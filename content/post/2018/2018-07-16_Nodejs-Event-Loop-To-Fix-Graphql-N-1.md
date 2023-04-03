---
title: 為什麼要理解 Nodejs Event Loop：Dataloader 源碼解讀與分析如何解決 Graphql N+1問題
description: >-
  Nodejs底層是事件驅動，透過 Event Loop處理非同步(non-blocking)操作，讓費時的I/O操作可以交由libuv去呼叫系統事件驅動的
  system api或是用 multi thread方式處理，而Main thread則持續處理request或其他運算。
date: '2018-07-16T12:35:50.102Z'
categories: ['Javascript']
keywords: []
---

Nodejs底層是事件驅動，透過 Event Loop處理非同步(non-blocking)操作，讓費時的I/O操作可以交由libuv去呼叫系統事件驅動的 system api或是用 multi thread方式處理，而Main thread則持續處理request或其他運算。

```md
// copy from nodejs 官網   ┌───────────────────────────┐┌─>│           timers          ││  └─────────────┬─────────────┘│  ┌─────────────┴─────────────┐│  │     pending callbacks     ││  └─────────────┬─────────────┘│  ┌─────────────┴─────────────┐│  │       idle, prepare       │   (internal use)│  └─────────────┬─────────────┘      ┌───────────────┐│  ┌─────────────┴─────────────┐      │   incoming:   ││  │           poll            │<─────┤  connections, ││  └─────────────┬─────────────┘      │   data, etc.  ││  ┌─────────────┴─────────────┐      └───────────────┘│  │           check           ││  └─────────────┬─────────────┘│  ┌─────────────┴─────────────┐└──┤      close callbacks      │   └───────────────────────────┘
```

簡而言之，Event Loop有許多不同的階段(phase)，每個phase 是個陣列，當完成非同步操作後，會對應將 callback task push到 phase中；  
Nodejs會不斷的輪詢 Event Loop並`同步執行callback task`，直到 Event Loop上都沒有 task且 Main thread也都執行完成，就會退出。

Nodejs一些非同步操作對應的 phase如下  
1.`setTimeout` 屬於 timers   
2\. `pending callbacks`主要處理系統錯誤 callback  
3\. poll 階段則是向系統取得 IO事件  
4.`setImmediate` 屬於 check  
5.`關閉事件如 socket.on(‘close’, …)` 則屬於 close

`process.nextTick` 是在每個phase結束前執行， `Promise` 屬於 microtask，同樣執行於每個phase結束之前，且在 process.nextTick之前；  
所以要小心，不能要遞迴呼叫process.nextTick，會導致整個Event Loop卡住，因為每個process.nextTick都會在phase結束前執行。

以上大致介紹，實際運作複雜許多，附註參考資料：  
1\. [https://www.eebreakdown.com/2016/09/nodejs-eventemitter.html](https://www.eebreakdown.com/2016/09/nodejs-eventemitter.html)  
2\. [https://nodejs.org/en/docs/guides/event-loop-timers-and-nexttick/](https://nodejs.org/en/docs/guides/event-loop-timers-and-nexttick/)  
3\. [https://jakearchibald.com/2015/tasks-microtasks-queues-and-schedules/](https://jakearchibald.com/2015/tasks-microtasks-queues-and-schedules/)  
4\. 在瀏覽器中狀況跟Nodejs執行環境不太相同 [https://github.com/kaola-fed/blog/issues/234#code-analysis-b-a](https://github.com/kaola-fed/blog/issues/234#code-analysis-b-a)

但我看這個有什麼用? 只要我知道怎麼寫非同步程式碼，了解底層 Event Loop執行順序有什麼意義嗎?

雖然說學習不該帶有太強烈的功利性，追根究底本身就是個樂趣，但這個問題著實困擾我頗久，在這兩天看到了 `dataloader` 驚為天人的 Library，以下正文開始。

## dataloader的用途

dataloader主要用於解決Graphql的N+1問題，稍微簡單介紹一下  
Graphql是 FB提出的技術，用來當作新一代的前後端API交互介面，主要是將搜尋的能力交還給前端控制，後端就被動配合；  
改善以往 RESTful API在 GET上麻煩的地方，以下為示範


假設有 User / Post / Comment，  
User 1 <-> m Post，User可以創建多個Post  
User 1 <-> n Comment m <-> 1 Post，User可以在Post下發布 Comment

假設今天我們要顯示某用戶的所有貼文，以REST來講可能是  
/user/:userId/post  
如果要某用戶下所有貼文帶評論  
/user/:userId/post/comment  
如果是某用戶某貼文的所有評論  
/user/:userId/post/:postId/comment  
......

所以在查詢上，前端多一個需求後端就要多一隻API，有點麻煩  
如果要省著用同一個API外加query來判斷，就變成資料層或邏輯層一樣要處理

\--------------------------------------  
而Graphql 則漂亮很多，前端定義好需要的資料格式，後端就會對照回傳(套件輔助)  
```graphql
{    
   User {   
      name,  
      id,  
      Post {  
         title,  
         Comment {  
             content,  
             User .......  
}
```

不論是要取得 User，User -> Post， User -> Post -> Comment無限遞迴，都是非常簡單的一件事

後端則是對應好資料擷取，Graphql在後端會過濾把前端需要的欄位回傳，大幅降低網路 payload，非常的簡潔有力。

如果是有大量查詢的應用程式，或是有跨裝置應用，可以考慮導入 Graphql，現在來說方案都已經非常成熟了。

### Graphql N+1問題

但是在讀取巢狀資料的過程中，Graphql會發生N+1問題，例如取得所有用戶下的所有文章`{User{Post}}` ，這時候因為架構設計的關係，Graphql會先讀取所有的User，接著再針對個別User去讀取Post；  
所以資料庫讀取會變成 1 次讀取全部 User + N次個別User讀取Post，例如

```md
SELECT \* FROM User; --> 回傳了 [1,2,3,4]  
SELECT \* FROM Post WHERE user_id = 1;  
SELECT \* FROM Post WHERE user_id = 2;  
....

\---> 較為理想情況  
SELECT \* FROM User; --> 回傳了 [1,2,3,4]  
SELECT \* FROM Post WHERE user_id in (1,2,3,4);

\---> 最理想  
SELECT \* FROM User LEFT JOIN Post on Post.userId = User.id;
```

而dataloader提供的解法相當美妙，在應用層稍作改變，不影響原本graphql / 不干涉資料庫操作，將 N+1進化成第二優化的查詢條件。

### dataloader 介紹

dataloader作者

[dataloader](https://github.com/facebook/dataloader) 主要做兩件事 `batch` & `cache` ，因為在處理 http request上，為了上資料不過期，大多不會用上 cache，所以這裡僅介紹 batch。  
dataloader提供的解法是將異步操作合併，並在Event Loop的一個phase結束後用 process.nextTick 執行。

先看dataloader說明範例

```js
var DataLoader = require('dataloader')
var userLoader = new DataLoader(keys => myBatchGetUsers(keys));

/*  
myBatchGetUsers是自訂的函式，接收被dataloader batch起來的keys，回傳等同keys長度的Promise  
*/

userLoader.load(1)
    .then(user => userLoader.load(user.invitedByID))
    .then(invitedBy => console.log(`User 1 was invited by ${invitedBy}`));

// Elsewhere in your application  

userLoader.load(2)
    .then(user => userLoader.load(user.lastInvitedID))
    .then(lastInvited => console.log(`
            User 2 last invited $ {
                lastInvited
            }
            `));

/*
userLoader.load(1) 代表要載入，這會被 dataloader batch起來，最後再keys => myBatchGetUsers(keys)一併處理  
*/


// 接著來看程式碼，總共324行，大概有100行是註解… 非常精簡巧妙的設計

load(key: K): Promise < V > {

    var promise = new Promise((resolve, reject) => {
        // Enqueue this Promise to be dispatched.  
        this._queue.push({
            key,
            resolve,
            reject
        });

        // 在queue 重新填裝時觸發  
        if (this._queue.length === 1) {
            if (shouldBatch) {
                // If batching, schedule a task to dispatch the queue.  
                enqueuePostPromiseJob(() => dispatchQueue(this));
            } else {
                // Otherwise dispatch the (queue of one) immediately.  
                dispatchQueue(this);
            }
        }
    });

    return promise;

}
```

load()執行後是回傳一個Promise，注意關鍵的一行 `this._queue.push({...})` ，這個回傳的Promise resolve方法是被push到 _queue上，而_queue是 dataloader一開始創建時建立的空陣列。

#### enqueuePostPromiseJob
```js
var enqueuePostPromiseJob =  
    typeof process === 'object' && typeof process.nextTick === 'function' ?  
    function(fn) {  
        if (!resolvedPromise) {  
            resolvedPromise = Promise.resolve();  
        }  
        resolvedPromise.then(() => process.nextTick(fn));  
    } :  
    setImmediate || setTimeout;

// Private: cached resolved Promise instance  
var resolvedPromise;
```

resolvedPromise就是用來暫存的 Promise.resolve()，用來執行`resolvedPromise.then(() => process.nextTick(fn))` ，fn 是剛才的 `() => dispatchQueue(this)` ；  
如果環境有 process.nextTick則用，不然用 setImmediate / setTimeout 也可以!

這裡作者打上了25行的註解，大意是說：  
ECMAScript 運用 Job / Job Queue描述當下執行結束後的工作順序安排；  
(對照Nodejs也就是Event Loop的實作)，Nodejs用 process.nextTick實作 Job的概念，當呼叫了 Promise.then 則會在 global Jobsqueue中加入 PromiseJobs這樣的一個 Job。

dataloader會打包同一個執行的幀(frame) 中的操作，包含在處理PromiseJobs queues 之間的 load也會被一併打包。  
這也是為什麼要用`resolvedPromise.then(() => process.nextTick(fn))` ，確保在所有的 PromiseJobs之後執行 (\*備註一)；

這一段主要是因應cache處理，如果有開啟cache，執行過後一次dataloader會以 Promise.resolve儲存結果，也就是後續不管調用幾次都是立刻回覆結果；  
所以下列結果 1 / 5 /6 會被batch在同一個phase執行，而4會到下一個loop去

```js
testLoader.load(1).then(t => console.log("1 got ", t))
Promise.resolve().then(() => {
    testLoader.load(5)
}).then(() => {
    testLoader.load(6)
})

setTimeout(() => {
    testLoader.load(4)
})
```

而瀏覽器沒有向Nodejs中提供 microtask(process.nextTick)，只能用 macrotask(setImmediate / setTimeout)取代，但會有性能上的影響。

### dispatchQueueBatch
```js
var keys = queue.map(({ key }) => key);  
var batchPromise = batchLoadFn(keys);

batchPromise.then(values => {  
    queue.forEach(({  
        resolve,  
        reject  
    }, index) => {  
        var value = values[index];  
        if (value instanceof Error) {  
            reject(value);  
        } else {  
            resolve(value);  
        }  
    });  
})
```

`dispatchQueue` 多做一些判斷，最後呼叫dispatchQueueBatch；  
在此處取出所有佔存在queue上的keys，並呼叫batchLoadFn，也就是在 new `Dataloader((keys)=>{…})` 所定義的，執行後就對應queue上的 resolve，也就是把值回傳給 `userLoader.load(k).then(value => ….)` 做後續的處理。

總結一下，要使用時先建立 dataloader，並決定對應的 batch loader該如何處理，通常就是放資料庫 batch處理 `new Dataloader((keys) => customBatchLoader(keys))` ；  
接著定義操作， `loader.load(key).then(value => {})` ；  
dataloader內部透過 `enqueuePostPromiseJob` 機制，將一個執行幀內定義的操作都匯集起來，並在 Event Loop phase最後執行；  
最後內部呼叫 `dispatchQueueBatch` ，也就是實際調用 `customBatchLoader` 的地方，最後 resolve 當初宣告的 `loader.load()` 。

#### dataloader簡單範例

打印結果，注意 setTimeout會在下一個loop執行，而Promise.resolve()則在同一個 phase被處理掉。

```md
batched by dataloader: [ 1, 2, 3, 5 ]  
content: [ 1, 2, 3, 5 ]  
1 got 2  
[2,3] got [ 3, 4 ]  
batched by dataloader: [ 4 ]  
content: [ 4 ]
```

對應我們要解決的N+1問題，因為Graphql怎麼處理底層呼叫算是個黑盒子，以下是大概示意

1\. 原本Graphql的 N + 1問題 
```js 
let userList = await db.getUsers()  
let post1 = await db.getPostByUserId(userList[0].id)  
let post2 = await db.getPostByUserId(userList[1].id) 
```
......

2\. 如果用dataloader轉換  
```js
let userList = await db.getUsers() 

// post請求集中成  
let postLoader = new Dataloader((keys) => {  
    let res = await db.getPostListByUserId(keys)   
    return Promise.all(res.map(r => Promise.resolve(r)))  
}) 

// 照舊一個一個定義還是可以  
let post1 = await postLoader.load(userList[0].id)  
let post2 = await postLoader.load(userList[1].id)
```

## 結語

原本以為 N+1問題要解決必須深入到改寫資料庫的SQL，例如轉成 SELECT IN，但沒想到有個如此簡潔又漂亮的解法，而且不限定用什麼資料庫，真的是太棒了。

深入底層理解原理，抽象又費時，但我想這樣的投資是值得的，不禁再次感嘆這個Library的精妙，I dont know JS OTZ。

### 備註

篇幅有點長，所以把一些細節放在這裡

#### 確保在所有的 PromiseJobs之後執行

這部分要深入了解 Nodejs 執行 microtask與macrotask的順序

Promise.resolve ().then (() => {  
   console.log (2);  
}).then (() => {  
   console.log (9);  
   process.nextTick (() => {  
      console.log (7);  
   });

   Promise.resolve ().then (() => {  
      console.log (8);  
   });  
});

process.nextTick (() => {  
    console.log (1);  
});

Promise.resolve ().then (() => {  
     console.log (3);  
}).then (() => {  
     console.log (6);  
});

setImmediate (() => {  
    console.log (5);  
});

setTimeout (() => {  
   console.log (4);  
});

////// 打印結果  
1  
2  
3  
9  
6  
8  
7 --> 等同於 dataloader 第一次 batch觸發的時機  
4  
5

這部分蠻有趣的，一開始Event Loop會先從 nextTick queue開始，所以1會先打印；  
接著處理 Promise.resolve()的 promise queue，也就是2 3；  
接著 2 3分別又繼續往後resolve 9 6；  
8之所以在7之前是因為 Nodejs此時再處理 promise queue，所以會優先處理promise，處理完成後才會再處理 nexttick；  
等 microtask都處理完，才會進到其他timer phase與後續的phase處理。

這也是為什麼`enqueuePostPromiseJob` 要用 `promise.resolve(()=>process.nextTick(()=>dispatchQueue(this)))` ，對應如果 Promise.resolve().then().then() 中的 Promise都是 resolve了就會自動在同一個 batch處理，對印也就是打印 `7` 的位置。  
如果開啟了 dataloader cache，dataloader 是直接儲存 resolved promise，性能會有顯著的提升。