---
title: Express 與 Koa 如何處理錯誤
description: >-
  以前只注重把功能寫出來而已，慢慢地開始維護後發現一開始的系統規劃很重要，包含基本的 Loggin / Debugging / Error
  Handling，以及是否能將每個物件函式乾淨拆分避免過多副作用無法編寫測試(詳見另一篇網誌)
date: '2018-08-27T07:20:36.575Z'
categories: ['應用開發', 'Javascript']
keywords: []

  
---

以前只注重把功能寫出來而已，慢慢地開始維護後發現一開始的系統規劃很重要，包含基本的 Loggin / Debugging / Error Handling，以及是否能將每個物件函式乾淨拆分[避免過多副作用無法編寫測試](https://medium.com

此次主要研究 Express 與 Koa 框架下編寫如何做錯誤處理。

### 原本的寫法

在最一開始使用Promise時，都習慣個別Promise.catch 處理錯誤；  
之後用上了 async / await ，也都習慣用 try{}catch(){} 個別處理；
```js
function handle(req, res) {   
   Promise1().then(data => ....).catch(err => handleError(err))  
}

async function handle(ctx){  
   try{  
       await Promise1()  
   }catch(err){  
       hanleError(err)  
   }  
}
```
這樣的寫法缺點在於每個函式都必須重複一樣的事情(不斷 try catch)，此外回傳 http status code / error message 很多都會重複，也是此次想要改變的問題，希望改以`統一拋出錯誤並註冊一個Middleware專門處理錯誤`。

### 改善寫法

#### Koa

先來看Koa如何實作，以下是一般使用方式
```js
const Koa = require('koa');  
const app = new Koa();

app.use(async (ctx, next){...});

app.listen(3000);
```
當我們創建一個 Koa 的 instance app後，接著就會用 `app.use` 註冊所有的 Middleware，最後就是 `app.listen` 啟動

在 Koa 原始碼當中， new Koa()中重要的一段原始碼是

`return fnMiddleware(ctx).then(handleResponse).catch(onerror);`

Koa 處理的順序是 `fnMiddleware將 app.use()註冊的全部Middleware轉成 Promise chain` -> `hanldeResponse(呼叫 res.end送出 http respond)` / `onerror (處理錯誤)`

Promise chain(自定義的) 是指當 Koa Middleware 呼叫 next() 會遞迴呼叫下一個 Middleware，有興趣可以看我另一篇文章 [Koa2 源碼解析 — 簡潔美麗的框架](http://sj82516-blog.logdown.com/posts/4720279)

這部分的錯誤處理又可拆成兩塊，一個是 app層級 一個是 ctx 層級；  
在原始碼中 /koa/application.js，有預設基本的 onerror的錯誤處理，基本上就是打印出來，這部分是透過 `app本身繼承 Event Emitter屬性並註冊 app.on(“error”) 事件後處理`

另一方面當 Server 發生錯誤 Client 都會收到 `Internal Server Error` 回應，是在 `ctx.onerror 處理`，並 `app.emit(“error”)`，定義於 /koa/context.js 中；  
對應不同的Http Status Code 有不同的回應，這是基於`statuses` 模組定義的。

這裡比較混亂的是 app.onerror 與 ctx.onerror 呼叫時間是交錯的

1.  `fnMiddleware(ctx).then(handleResponse).catch(onerror);` 的 onerror 是 `(error) => ctx.onerror(error)`
2.  `ctx.onerror` 會 respond 預設的錯誤處理與 `app.emit(“error”)`
3.  `app.emit(“error”)` 是由 `app.onerror` 去接收，這部分可以自訂 `app.on(“error”, ()=>{自行處理})`

![](/posts/img/1__9GhLVsWnNyqmW__0yDv6wPg.jpeg)

官方文件有寫到錯誤處理，用戶可註冊 error 事件就會改由用戶自己處理

app.on("error", (err, ctx) => {....})

BUT!! 這邊的 ctx 是拿來看 context 資訊，如果是希望客製化回傳的錯誤是沒辦法的喔！  
因為錯誤的狀態碼與內文 Reponse 是在 ctx.onerror 就處理掉。

所以如果要自己處理整個錯誤，必須改用 Middleware ，記得`第一個`就註冊錯誤處理才可以捕獲所有的錯誤，如以下

#### Express

Express 對比 Koa 是個比較全面的框架，內含了基本的 Middleware / Router，發送Response 方式也不像 Koa 是最後框架幫你發送；  
而是必須自己用 `res.send()` 之類的語法自行發送。

#### Routing 機制

詳請請參考 [**express源码分析之Router**](https://cnodejs.org/topic/5746cdcf991011691ef17b88)

在Express 實例化之後有一個 Router Instance，接著每個路由會對映一個 Route，一個路由中可能有多個Middleware 稱為 Layer，資料結構就是陣列儲存。

當一個 Request 近來會流過依照 Route 中的註冊順序流過 Layer ，每個Layer 判斷是否 Match URL，如果 Match 則處理，發生錯誤則走錯誤處理

特別注意 正常處理與錯誤處理路徑是分開
```js
app.use((err, req, res, next)=>{}) 對應是 Layer.handle_error  
app.use((req, res, next)=>{}) 對應是 Layer.handle_request
```
當發現有 Middleware 呼叫了 next(err)後，就開始走錯誤處理，也就是後面的 Layer 都是呼叫 Layer.handle_error !

在錯誤處理Express 採用 `next(err)` 在Middleware 間傳遞錯誤，所以當 Middleware 或是 Routing 中有錯誤不能直接拋出或不處理，必須要用 `try{..}catch(error){next(error)}` 處理；  
但這樣就會很麻煩，因為都必須用 try catch 包起來，同理像是原生的 Nodejs module 如 fs 都沒有 Promise版，所以都要自己再 Promisify 後呼叫一樣的道理(麻煩)。  
([Using Async Await in Express with Node 9](https://medium.com/@Abazhenov/using-async-await-in-express-with-node-8-b8af872c0016) 有提及)

後來看到一個蠻 Hacking 的方式，[express-async-errors](https://github.com/davidbanham/express-async-errors)，他會複寫Express/Layer.handle 方法，把每個 Routing Function 的錯誤統一用 `next(error)` 傳遞

他處理的方式也是很妙，簡化後可以這樣示意
```js
let pE = async () => {throw new Error("error")}  
let fn = pE.call()  
if(fn && fn.catch) fn.catch(err => console.log(err))
```
也就是如果發現註冊在Layer中的Function 是 Async Function，Async Function 執行後會回傳 Promise，接著就是用 `fn && fn.catch` 判斷是否為 Promise，如果是則幫忙補上 `.catch((err) => next(err))` ，蠻聰明的作法。

根據 Express Routing 機制，ErrorHandling 在 Express 必須宣告在最後面

### 結語

就個人觀點，Koa 相比 Express 確實是個更進步的框架，最主要是在 Middleware 構建與執行上，Koa 是先轉成類似 Promise Chain，並預設有做 Error Handling；  
這比較符合現在以 Promise 為基礎構建的應用程式，也使得 Middleware 設計與錯誤處理直觀很多。

而Express 必須很彆扭的使用 next(err)傳遞，對比就有點像 callback hell 的 error 放在 function 第一位的傳統寫法；  
另外我也是現在才知道 `app.use((err,req,res,next)=>{…})` /`app.use((req,res,next)=>{…})` 差一個參數在 Express 中呼叫時機完全不同，整個錯誤處理弄的有點不太直觀。  
看到Github Issue 討論有提到 Express@5 會加入更好的 async /await 支援，到時再來看看原始碼的更動。