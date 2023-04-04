---
title: >-
  Jonathan Martin: Async patterns to scale your multicore JavaScript elegantly
  總結與試驗
description: '利用Async Pattern 提升JS在多核心上的執行速度'
date: '2018-06-27T04:03:50.027Z'
categories: ['應用開發', 'Javascript']
keywords: []
---

今天看到一部不錯的影片，主題是「利用Async Pattern 提升JS在多核心上的執行速度」，細拆個三個小節  
1\. 用Async IIFE 解決任務間相依與並行的問題  
2\. 用High Order Function概念設計 Semaphore，控制同時並行的任務數  
3\. 透過Worker 讓任務跑在個別Thread上，增加多核心的效能利用。

## Concurrency vs Parallelism

Concurrency 並行是指 **多個Task執行時間有重疊**，也就是說Task1執行中時Task2也開始執行，算是一個概念性質上的定義，即使只有單一核心也可以透過Time Sharing 達到 Concurrency。

Parallelism 並發，強調的是多個Task被分配到多個實體CPU上，同時且獨立執行。

## Async IIFE

[**Cross Stitching: Elegant Concurrency Patterns for JavaScript**](https://www.bignerdranch.com/blog/cross-stitching-elegant-concurrency-patterns-for-javascript/)

最基本使用 async/await 就是一行一行寫，如

> await task1();  
> await task2();  
> await task3();…

但如果不同 task之間可能有相互依賴，如 task2 並須等到 task1結束才能進行/ 但也有些 task互相獨立可以並行，如果單純一行一行 async/await 會浪費等待的時間。

> 困難的點在於任務複雜，如何漂亮地表示任務間的先後順序相依，並讓並行最大化

所以作者提到可以用 async iife ，也就是 async function 立即執行函式，async function 不論何時都會回傳 Promise，即使失敗也是回傳 Promise.reject；

以下是我參考作者範例程式碼改寫的，主要比對原先的做法與async iife的差別，挑戰任務間相依的狀態如下

![](/post/img/1__v7aRZMMz__1__hTYVEGc4quQ.jpeg)

原本就有的寫法是描述Task橫向的並行，所以我們會用 Promise.all([])將 TaskB/TaskC並行處理，但是這種寫法可讀性差，而且架構的方向也是不好的，`因為 Task相依應該是垂直`  ，像是 TaskD明明就只要等 TaskC完成就可以開始執行，但因為寫法所以要等到 TaskB也執行完成後，TaskD與TaskE才並行處理。

所以使用 async iife 最大好處即是每個Task的相依性都被封裝的很直觀，主要是利用 Promise一宣告就執行的特性，像是 
```js
let taskA = (async ()=> { await timePromise(1000); console.log(“TaskA done”)})()
```
此時taskA已經開始執行了，但是後續的code因為 `await taskA`還是要等taskA結束才能繼續，所以一樣可以做到流程的控制；  
這也是為什麼 taskB/taskC這樣寫可以並行處理，接著taskD因為只相依taskC所以在範例中會比taskB更早結束，非常漂亮的寫法。

另外分享一個當初疑惑的點：taskC在 taskD / taskE被呼叫兩次，會不會就執行兩次?!   
答案是不會，因為taskC本身是Promise，執行完一次後就會轉成 Promise.fufilled(or rejected) ，如果後續要用 await taskC取值就會立即回傳結果。

## High Order Function

高階函式，定義是可接受函式當作參數的函式本身，如過往在數學上學到的 f(g(x))，在JS中結合closure 就可以有非常多的應用。

Semaphore 信號機，用來控制有限的資源量，作者利用信號機，設計限制最大並行數的機制

[**nybblr/semaphorejs**](https://github.com/nybblr/semaphorejs)

程式碼只有40行左右但蠻精妙的，使用上
：
```js
s = Semaphore(3)  
s(async _ => {console.log(“start”); await timePromise(3000); console.log(“done”)})  
s(async _ => {console.log(“start”); await timePromise(3000); console.log(“done”)})  
.....
```

對應程式碼，Semaphore(3) 將 task上限設為 3，接著回傳一個高階函式。  
仔細看這個高階函式的第一行`await acquire();`

```js
let dispatch = () => {      
      if (counter > 0 && tasks.length > 0) {        
             counter--;        
             tasks.shift()();      
      }    
};

let acquire = () =>   
     new Promise(resolve => {   
          tasks.push(resolve);   
          setImmediate(dispatch);   
     });
```

最有趣的地方莫過於作者用 acquire / dispatch 達到數量上的控制，acquire 將 Promise.resolve() 推上了 task陣列，接著觸發 dispatch，而dispatch只有在未達上限前可以執行 task.shift()的 function，這裡也就是Promise.resolve()，透過這個機制就可以去卡 `await acquire()` 。

## Web Worker and Multi Thread

JS本身執行於 Main Thread上，其餘非同步API是由底層瀏覽器的Web API或 Nodejs Libuv等支援，最後透過 event loop 將 callback 返回 Main Thread 執行；

但如果需要用JS執行費時的操作而沒有底層函式的支援(如自己編寫 Addon)，現在可以透過 Web Worker分開 Thread，避免阻擋 Main Thread。

程式碼請參考：[http://jsfiddle.net/sj82516/uqcFM/350/](http://jsfiddle.net/sj82516/uqcFM/350/)