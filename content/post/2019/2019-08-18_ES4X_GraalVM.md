---
title: 讓 Node.js 跑得更快! ES4X 專案與Graal VM 介紹
description: 認識不同的 JS Engine，讓你的 NodeJS 專案有不同的可能性
date: '2019-08-18T11:31:29.945Z'
categories: ['應用開發']
keywords: []
---

文字版：[https://dev.to/pmlopes/javascript-on-graalvm-120f](https://dev.to/pmlopes/javascript-on-graalvm-120f)

身為一名工程師，想辦法讓自己的程式碼執行的更快，似乎是一種天性，當我們想要優化 Node.js Server 的執行速度時，第一印象應該都是如何寫出更好的程式碼、用更快的演算法，這些當然都是優化的一環，但如果拉遠一點想，有沒有辦法去`優化 Node.js Runtime本身`呢 ?!

作者提到在著名的 framework benchmark 中，JS 的執行效率排名很後面，如果用 FlameChart 分析，會發現絕大多數的時間是在底層也就是 V8 Engine 與 Libuv 上

![](/post/img/0__8pUeUi9pzwXJ9tkz.png)

![](https://blog.zenika.com/2011/04/10/nodejs/)

左圖：[https://blog.zenika.com/2011/04/10/nodejs/](https://blog.zenika.com/2011/04/10/nodejs/) 右圖：截自影片

所以我們再怎麼優化 JS code，就如同冰山一角般，是很難取得非常大幅度的效能提升，那該怎麼辦呢？

Paulo Lopes 設計了[ES4X](https://github.com/reactiverse/es4x) 專案，主要是用 `GraalVM 取代 V8` 與 `Vert.x 取代 Libuv` ，基本上就是將底層從 C/C++ 工具鍊換成了 JVM 為主的工具鍊，根據作者的 benchmark，在不同應用面可提升 120% ~ 700% 的效能

[**Run your JavaScript server 700% faster!**](https://www.jetdrone.xyz/2018/08/06/ES4X-JavaScript.html)

## Vert.x

Vertx 類似於 Libuv 的功能，提供 Event-Driven 與 Non-blocking 的框架，提供如 TCP / File 操作 / DNS / HTTP / Timer等 API支援，其核心概念是透過 Event Loop 方式達到事件驅動的開發方式，大概瞄過去跟 Javascript 的開發理念非常吻合，像是

### Callback Function

為每個事件註冊 Handler，等到事件完成後推進 Event Loop 等待執行， `Don't call us, we will call you.`

### Never block Event Loop

這點雷同於 Node.js，但是有一點不同是 Node.js 採用 Single Event Loop，但是Vertx 採用 Multiple Event Loop，主要是更有效運用 multi-core 的機器；  
雖然採用了 Multiple Event Loop，但是為了避免 Context Switch 與增進性能，如果 handler A 在 Event Loop1 執行，後續的 Callback 也都位在 Event Loop1 執行

### How to run blocking code

現實上不可避免還是會需要執行耗時的運算或是運行用 sync 設計的函式庫，這時可以用 executeBlocking，類似於 Promise的設計，但會運作到從 Worker Thread Pool 取得的 Thread 上，避免卡住 Event Loop

但文件描述到 executeBlocking 雖然是用於 blocking code execution，但建議超過 10s 的操作還是另外管理 Thread
``` java
vertx.executeBlocking(function (promise) {    
   // Call some blocking API that takes a significant amount of time to return_     
    var result = someAPI.blockingMethod("hello");  
    promise.complete(result);   
}, function (res, res_err) {     
   console.log("The result is: " + res);   
});
```

### Concurrent composition

非同步操作一大要解決的問題就是操作順序，Vertx 提供像 `CompositeFuture.all、CompositeFuture.any` 等 API，從 JS 角度應該都不陌生

直接使用 Vertx 的 JS 方案有一個很大的問題

> 目前是基於 Nashorn 這套 JS Engine，僅支援到 ES 5.1並不支援 ES6 以後的語法，如果 Library 用 ES6 以後語法寫也都不支援

這算是致命傷了吧，如果不能整合現在的 JS 生態系那應該很少人敢採用這套方案。

所以 ES4X 是一個全新基於 Vertx 開發的 `JS Runtime`，加入了 ES6+ 的支援更好與現在 JS生態系整合，所以 Promise / async-await 等等都可以採用，同時 Vertx 的語法也同時支援，作者提到下一版的 Vertx 會棄用現有的 Vertx JS 改用 ES4X。

> 題外話：  
> 作者人很好，在文章底下提問很多疑惑都在 24 hr 內得到解答，真的是很感謝

## GraalVM

GraalVm 是一個提供多語言的運行環境，透過 Graal Compiler 編譯成 Java Bytecode 並執行於 Java HotSpot VM上，所以可以兼容於 JVM-based 的語言如 Java/Scala/Kotlin等；  
透過 Truffer framework，可以兼容其他的程式語言，如JS/Python/R/Ruby等等

![](/post/img/0__pH1347fH__vCQeKkD.jpg)

許多程式語言都必須要有一個良好的運行環境 Runtime，但是要打造一個安全、高效的運行環境是非常困難且耗時的，例如說 JS的 V8 Engine 也是 Google多年的投入才有這麼好的成果，其他語言相較之下沒有這麼多資源，自然運行的速度就很慢；  
所以 GraalVM希望透過通用化虛擬化技術，讓不同的程式語言只要用 Java 透過[Truffle](https://github.com/oracle/graal/tree/master/truffle) Framework 實作該語言的 AST，後續的運行就交給 GraalVM，降低新語言開發的困難

除了讓原本的程式語言執行得更快，採用 GraalVM另一大好處是可以混合語言(Polyglot)開發，例如 JS內使用 R的套件，讓不同的語言發揮各自的長處，而且`效能不受到跨語言的影響`，因為不同的語言最後都是通過 Truffle Framework 生成 Graal Compiler 了解的AST，最後 Compile 出來的機器碼不會因為不同語言而有所差異

更多的細節可以參考這支影片

### 實作 — 用網頁顯示圖表 /採用 GraalVM 與 ES4X

簡單整合兩者的 Example Code，用 ES4X 執行一個 Web Server，並用 GraalVm 當作運行環境，採用 R繪製圖表。

#### 安裝

到 [https://github.com/oracle/graal/releases/tag/vm-19.1.1](https://github.com/oracle/graal/releases/tag/vm-19.1.1) 下載安裝檔，解壓縮後加入路徑

```bash
$ export PATH=<檔案位置>/graalvm-ce-19.1.1/Contents/Home/bin:$PATH  
$ export JAVA_HOME=<檔案位置>/Contents/Home
```

設定好之後，可以使用以下幾個 command，node 改成用 GraalVM執行，預設僅支援 Java/Javascript，如果需要其他語言則要 `$gu install python` 等

```bash
$ js   
runs a JavaScript console with GraalVM.

$ node  
replacement for Node.js, using GraalVM’s JavaScript engine.

$ lli   
is a high-performance LLVM bitcode interpreter integrated with GraalVM.

$ gu (GraalVM Updater)   
can be used to install language packs for Python, R, and Ruby.
```

簡單試一下跨語言的特性

```js
// 儲存成 test.js  
var array = Polyglot.eval("python", "[1,2,42,4]")  
console.log(array[2]);

$ node --polyglot --jvm test.js
```

使用 `Ployglot.eval` 可以執行其他指定語言的語法，

剛執行時會需要花比較多的時間 warn up，所以如果要當作 Command line tool 或其他生命週期短的應用程式，就建議繼續使用 Nodejs 即可；  
長時間運行的話，GraalVM 的效能與 V8 其實是差不多的，但如果多考量跨語言的特性，GraalVM 會是個不錯的選擇

## ES4X

先安裝初始化

```bash
$ npm install -g es4x-pm  
$ mkdir test  
$ npm init  
$ es4x init

// 安裝所需套件  
$ npm install @vertx/unit --save-dev  
$ npm install @vertx/core --save-prod  
$ npm install @vertx/web --save-prod  
$ npm install
```

index.js，接著用 `$npm run start` 執行

```js
/// <reference types="@vertx/core/runtime" />  
// @ts-check

vertx  
  .createHttpServer()  
  .requestHandler(async function (req) {  
    req.response().end("hello world.");  
   })  
   .listen(8080);
```

需注意，如果要達到最佳性能的提升需要使用它提供的 web framework `@vertx/web`，如果是使用像 Express.js底層的 System API Call 就不會走 Vertx，而是用當下 Runtime 環境的處理方式 (Node.js or GraalVM)，細節還需要更近一步理解專案才能解釋，不過從作者的描述現況是如此，所以舊專案要移植會重寫的門檻

另外目前不支援 GraalVM的 Polyglot，已回報給作者需要等他實作。

## 總結

跳脫框架，以前沒想過透過替換 JS Runtime 可以換取性能的提升，也不曾接觸過像 GraalVM這樣多語言支援的 Runtime，細節有蠻多關於 Compiler 相關的知識，自己很多都忘了，需要在加強才行

總結目前使用 GraalVM與 ES4X

1.  GraalVM 可以測試通過 npm 90%的 package，除了一些 native code 編寫的 library，其他不太需要擔心支援度問題；
2.  GraalVM 語法支援到最新的 ES2019/2020，這點還蠻不錯的
3.  GraalVM 性能對比與 V8不差多少，只是要一段 warm up 的時間，如果有跨語言整合需求，可以考慮看看
4.  ES4X 可以結合 Vert.x 與 GraalVM優點，得到大量的性能提升，但是專案還沒穩定，需要考量；  
    開發也必須用他的 Framework，使用 Express.js / Koa.js 等用戶無法無痛轉移