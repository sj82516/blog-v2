---
title: V8 Zero Stack Async Stack Trace 研究
description: >-
  這份是在 2018/11/20 由 V8 Team 釋出的文件，主要描述用一種新的Async 錯誤追蹤機制，此新機制僅適用於 async await
date: '2019-01-01T10:27:29.899Z'
categories: ['Javascript']
keywords: []

---

這份是在 2018/11/20 由 V8 Team 釋出的文件，主要描述用一種新的Async 錯誤追蹤機制，此新機制僅適用於 `async await` ，promise chain則沒有效果，目前需要透過 `--harmony-await-optimization`  flag 啟用這項功能。

以下內容與圖片摘錄於該文件。

### 緣由

參考下列程式碼

```js
async function foo(x) {  
  await bar(x);  
}

async function bar(x) {  
  await x;  
  throw new Error("Let's have a look...");  
}

foo(1).catch(e => console.log(e.stack));
```

如果運行在 V8 7.1 版本，會發現 error.stack 僅會印出部分錯誤資訊

```md
Error: Let's have a look...
at bar (<anonymous>:7:9)
```

而調用者 foo 則消失無蹤，這是因為從 JSVM角度，當 bar 因為 await x 而暫停執行，接著從 microtask queue 恢復執行後，在 stack 上已經沒有其他 function 了

目前可以開 Chrome Dev Inspector ( `> node --inspect`)，執行同樣的程式，可以看到完整的 error stack，但這會有很大的性能影響，所以只建議在開發中使用。

![](/posts/img/0__zUDoBxW4TG__IFqDF.jpg)

### 解法

目前的困境是發生錯誤時，因為非同步特性要追蹤完整的錯誤棧不容易。

正好 await 會停止目前的 function 運作，所以不但可以知道目前停在什麼地方，也可以知道是從哪裡被呼叫；  
這特性跟 promise chain相同，因為 promise 透過 .then 連結，所以能夠輕鬆反序重建出 function 呼叫相依。

#### 先行條件

我們必須運用 promise chain，才能有足夠的條件找出完整 stack trace；  
但如果 promise 是被另一個 promise resolved (在 fulfill 方法中 return 另一個promise)，這樣 promise chain 間就沒有直接的依據，必須等到下一個 tick `[PromiseResolveThenableJob](https://tc39.github.io/ecma262/#sec-promiseresolvethenablejob)` 執行時才知道這兩個 promise 是有相依的。

這是目前 ES2017 的規範所帶來 await 麻煩之處

```js
const _.promise_ = @createPromise();  
@resolvePromise(.promise, x);  
const _.throwaway_ = @createPromise();  
@performPromiseThen(_.promise_,  
  res => @resume(_.generator_object_, res),  
  err => @throw(_.generator_object_, err),  
  _.throwaway_);  
@yield(_.generator_object_, _.outer_promise_);
```

目前 await 都必須用另一個 promise `.promise` 重新包裝，即使 x 本身已經是promise，問題在於 `.generator_object` 與 `x` 沒有直接的關連；  
而是必須等到下個 tick [PromiseResolveThenableJob](https://tc39.github.io/ecma262/#sec-promiseresolvethenablejob) 將 `.promise ← → x` 與 `.promise ← → .generator_object` 才能關聯。

所以目前需要額外建立 `x ← → .promise 的關聯` 或是 查詢 microtask queue，兩者都需要開銷。

好在最近有提案要修改此部分，將多餘 .promise 刪除

const _.promise_ = @promiseResolve(x);  
const _.throwaway_ = @createPromise();  
@performPromiseThen(_.promise_,  
   res => @resume(_.generator_object_, res),  
   err => @throw(_.generator_object_, err),  
   _.throwaway_);  
@yield(_.generator_object_, _.outer_promise_);

最主要差別在 `const _.promise_ = @promiseResolve(x);` ，使用 `promiseResolve` 如果 x 本身是 native promise 就不會額外再包一層，可以在 V8 v7.2 `--harmony-await-optimization` 開啟此功能。

#### 概覽

接下來是 V8 內部的 await Promise實踐，透過上述的 Spec 修改後，達到 async stack trace 目標。

針對以下的程式碼，畫出實際 V8 的 Call Stack

```js
async function foo(x) {  
  await bar(x);  
}

async function bar(x) {  
  await x;  
  throw new Error("Let's have a look...");  
}

foo(1).catch(e => console.log(e.stack));
```

![](/posts/img/0__FZBjeD6zupannymv.jpg)

因為 bar(x) 中 await (1)，而 1 不是 promise 所以需要透過 Promise().resolve(1) 多包一層，所以在 Call stack 上 `bar` 被 `await fulfilled` 呼叫；  
「如果 async stack 功能開啟」，此時會去搜尋 “current microtask”找到 `包裝x的PromiseReactionJob` ，找到的話就會順勢找到 `generator object` ，這個 object 也就是 async function 所轉化而來的，同時包含 async function 的 promise reference。

#### 另一種做法

![](/posts/img/0__p4VtVwlDfBFbtUQq.jpg)

另一種做法則是 await 產生的內部 promise ( `.promise`)有辦法找到外部 promise (也就是 async function， `JSPromise`)，如果全部都是用 async await 串連，可以找到 `PromiseReaction` ，裡頭包含兩個特殊的閉包 `Await Rejected` 跟 `Await Fulfilled` ，兩者共同分享一個 Object `AwaitContext` ，這個AwaitContext 是另一個再等待 JSPromise 的`JSGenerator Object` ，也就是 function foo。

這部分內部實踐看得有點暈頭轉向，目前就是大致有個模糊概念。

#### Error.stack

目前 Error.stack 還不是官方標準，目前已經提案處於 stage-1 的草案

[**tc39/proposal-error-stacks**](https://github.com/tc39/proposal-error-stacks)

這部影片是文件的附屬 reference，主要分享 Nodejs 中如何使用async stack trace。

以下為測試程式碼

```js
function p(){  
        return new Promise((res, rej) => setTimeout(()=> res(1), 1000))  
}

async function one(){  
        await p();  
        throw new Error("err");  
}

async function two(){  
        await one();  
}

async function three(){  
        await two();  
}

async function four(){  
        await three();  
}

four().catch(error => console.log(error.stack));
```

使用目前的 Nodejs v11.5.0 執行，打印的結果是

```md
Error: err  
    at one (/Users/.../Desktop/test.js:7:8)
```

整個 call stack 只剩 function one 而已，這樣要 debug 相當困難。

此時可以開啟 inspector， `> node —inspect-brk=0.0.0.0:9229 test.js`

接著打開 chrome dev tool，記得打開 Discover network targets，點擊進去會跳出下方的 debug視窗，接著要打開 Pause on caught rejection 不然出錯就會結束了

![](/posts/img/1__Z2ZYMsG__OSWF9QF1UWBn3Q.jpeg)

如同上面所說，這種方法只適用於開發。

#### 新的 zero-cost async stack trace

目前需要 V8 v7.2 並透過 flag 才能開啟此功能，所以現在要先下載 v8-canary版的 Nodejs，平常都是用 nvm 管理多個 Nodejs 版本，可以用以下方式下載

```md
$  NVM_NODEJS_ORG_MIRROR=[https://nodejs.org/download/v8-canary](https://nodejs.org/download/v8-canary) nvm install node
```

可以透過 node的 REPL 環境執行 > process.versions 看 V8的版號。

接著執行

```md
$ node --async-stack-traces test.js
```

打印結果就會是

```js
Error: err  
    at one (/Users/zhengyuanjie/Desktop/test.js:7:8)  
    at async two (/Users/zhengyuanjie/Desktop/test.js:11:2)  
    at async three (/Users/zhengyuanjie/Desktop/test.js:15:9)  
    at async four (/Users/zhengyuanjie/Desktop/test.js:19:9)
```

### 結語

之後看來要花時間重新學 C/C++，這樣才能看懂 V8 與 JS Binding 等底層的 Nodejs 實作。