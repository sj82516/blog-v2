---
title: V8 如何優化 async / await
description: JS 基於事件驅動，大量的 Promise 充斥在應用程式中，其後在 ES2017 加入了 async/ await 語法糖後，讓非同步代碼更加簡潔與直覺
date: '2018-12-25T13:06:04.006Z'
categories: ['Javascript']
keywords: []

---

JS 基於事件驅動，大量的 Promise 充斥在應用程式中，其後在 ES2017 加入了 async/ await 語法糖後，讓非同步代碼更加簡潔與直覺；

但是 async / await 不單單是語法糖，從一開始會有不小的 overhead，v8 team 不斷的優化到今日與原生的 Promise chain 效能不相上下，甚至使用 async / await 效能更優於 Promise chain 了!

以下內容整理自

[https://v8.dev/blog/fast-async#fn2](https://v8.dev/blog/fast-async#fn2)

![圖片來自 v8 官網](/post/img/1__YyZo6l5__VFtYWyILzqHCnQ.jpeg)
圖片來自 v8 官網

V8 在執行 async await時，會通過一個轉換，流程大概是

1.  先將 await 轉成 promise
2.  加上 Handlers
3.  停止 function 運作並回傳 implicit_promise

其中的參數 promise 目的是 `async function 會等到 await 完成才會下一步` ；  
而 throwaway promise 則另有他用，稍後會解釋

所以整體上一個 aysnc / await 會造成 `2個額外的 JSPromise 以及 3個額外的 Mircorticks!`

### 優化

#### 取消對 await function 多包一層 Promise

大多數 await 後面接的都是 promise，那為什麼要在多浪費一個 Promise 呢？  
直接改用 promiseResolve()，如果原本是 Promise 就直接回傳，如果不是在多包一層 Promise，如此就可能優化掉一個 Promise 還兩個 MicroTasks！

![](/post/img/1__VZ6rECQaskS2v__wQ3LEgKQ.jpeg)

直接回傳Promise 跟多包一層 Promise 有什麼差別呢？

參考github issue 討論的其中一個案例

[**Normative: Reduce the number of ticks in async/await by MayaLekova](https://github.com/tc39/ecma262/pull/1250 )

```js
async function f() {  
  let promise = Promise.resolve(1);  
  promise.then = function(...args) {  
    console.log('then called');  
    return Promise.prototype.then.apply(this, args);  
  };  
  let result = await promise;  
  return result;  
}

f().then(v => console.log(v));
```

可以試著在 Chrome 71 跟 73(現為 Canary版)執行，會發現 73 優化過後不會再印 `then called` ，因為少了用 Promise 多包一層，已經 resolved 的 promise 就會直接回傳而不會在 call 一次 then function。

這部分會影響對 Promise 做 Monkey Patch 的用戶，所以在 github issue 下有不同的討論，可以看到維護者對於語言功能上與一致性上的取捨，大致上就是`不鼓勵對 Promise.then 做 Monkey Patch的操作`。

### 去掉 internal promise ：throwaway

![](/post/img/1__IvdP7Fh9NYfmsxIKu7V21A.jpeg)

在文章中提到 throwaway 之所以存在是為了滿足 Spec 對於performPromiseThen API的操作   
(only there to satisfy the API constraints of the internal `performPromiseThen` operation in the spec.)

後來到 Twitter 發問，作者回覆說「It’s still there only when async hooks are enabled (in Node.js) — they attach some internal data on it.」

所以在 Nodejs還會使用，但是在 Browser 就不會了，這部分看來不用太在意。

### Nodejs v8 的小Bug

Nodejs 在 version 8 有偷做優化，也就是第一步省掉，如果發現是 await 接promise 就不會多包一層，可以用 v8 / v10 對比跑下列程式

```js
const p = Promise.resolve();

(async () => {  
  await p; console.log('after:await');  
})();

p.then(() => console.log('tick:a'))  
 .then(() => console.log('tick:b'));
```

會發現 version 8 的打印結果是 `after:await -> tick:a -> tick:b` ，而 version 10 則是符合目前 Spec的 `tick:a -> tick:b -> after:await` 。

version 8 因為 p 已經是 resolved promise會執行執行；version 10 多包一層 Promise 就會等到下一次 microtask queue 執行時期才會執行。

### 開發重點

請使用原生 JS Engine 提供的 Promise，而不是其他 JS Library 的 Promise或非 Promise 類型的函示，這樣在底層會有更好的效能優化 ( 省了兩個 Microtask與一個多餘的 Promise )