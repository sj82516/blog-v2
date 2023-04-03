---
title: 'Expressjs Middleware 如何在 Response 結束觸發'
description: 因為 express.js 設計因素，如果要自行設計一個 Middleware 在 response 結束時才觸發會比較麻煩些，透過研究紀錄 response time 相關的 middleware 參考他人怎麼實作的
date: '2020-02-06T22:21:40.869Z'
categories: ['應用開發']
keywords: ['Backend', 'Js']
---

在使用 express.js 當作 Nodejs server 框架時，時常會需要寫一些 Middleware 處理 Token 驗證、用戶權限檢查等等，也會套用很多第三方的模組去建構程式  
但突然某天在思考`如何自己寫一個紀錄response time`的 Middleware，發現自己沒辦法用一個 Middleware 註冊就完成這件事，因為 express.js 不像是 Koa 的 middleware 是用 promise based 實作，所以當某個環節是非同步，執行的順序就會錯亂  

後來查看了 `morgan` 被大量使用的 express log middleware，才發現其中設計的小巧思，以下是整理的內容

## Expressjs Middleware 設計
先來看最基本的 Middleware 設計

```js
const express = require("express");

const app = express();

app.use(function(req, res, next){
    console.log("middleware 1 start");
    next();
    console.log("middleware 1 end");
});

app.use(function(req, res, next){
    console.log("middleware 2 start");
    next();
    console.log("middleware 2 end");
});

app.get("/", async function(req, res){
    console.log("request started")
    await delay();
    console.log("request finished")
    res.send();
});

async function delay(){
    return new Promise((res)=>{
        setTimeout(()=>{
            res()
        }, 1000)
    })
}

app.listen(3000);
```

目前的 log 會變成
```md
middleware 1 start
middleware 2 start
request started
middleware 2 end
middleware 1 end
request finished
```

如果我們希望在 Request 進來先紀錄開始時間，接著在 Response 結束時紀錄結束時間，就必須仰賴其他的實作方式  

## on-headers / on-finished
爬過 `morgan` 程式碼後，發現是透過這兩個模組去實作功能的  
[on-headers](https://github.com/jshttp/on-headers)：註冊事件，當 header 被寫入時會觸發  
[on-finished](https://github.com/jshttp/on-finished)：註冊事件，當 request/response 結束時觸發  
這兩個模組可以針對 Nodejs 原生的 http server 搭配使用，express.js 也是繼承原生的 http server 

在 `morgan` module 中，在 middleware 進入一開始標記 request 開始時間，在 on-headers 時紀錄 request 結束時間，在 on-finished 將訊息印出，pseudo code 大致如下
```js
app.use(function (req, res, next) {
    res._startTime = new Date().getTime();

    onHeader(res, function () {
        res._endTime = new Date().getTime();
    })

    onFinished(res, function () {
        console.log(`req process time: ${res._endTime - res._startTime} ms`)
    })
    next()
})
```
log 結果是
```md
request started
request finished
req process time: 1010 ms
```

### on-headers 實作
將原本的 response 中的 writeHead 複寫，只是多包一層觸發事件的機制
```js
function createWriteHead (prevWriteHead, listener) {
  var fired = false

  // return function with core name and argument list
  return function writeHead (statusCode) {
    // set headers from arguments
    var args = setWriteHeadHeaders.apply(this, arguments)

    // fire listener
    if (!fired) {
      fired = true
      listener.call(this)

      ....
    }

    return prevWriteHead.apply(this, args)
  }
}

function onHeaders (res, listener) {
  if (!res) {
    throw new TypeError('argument res is required')
  }

  if (typeof listener !== 'function') {
    throw new TypeError('argument listener must be a function')
  }

  res.writeHead = createWriteHead(res.writeHead, listener)
}
```

### on-finished 實作
這邊的實作就比較有趣，如何正確的判讀 http request/response 結束了呢？
```js
function isFinished (msg) {
  var socket = msg.socket

  if (typeof msg.finished === 'boolean') {
    // OutgoingMessage
    return Boolean(msg.finished || (socket && !socket.writable))
  }

  if (typeof msg.complete === 'boolean') {
    // IncomingMessage
    return Boolean(msg.upgrade || !socket || !socket.readable || (msg.complete && !msg.readable))
  }

  // don't know
  return undefined
}
```
如果是套用在 response，需注意根據官方文件 [response.finished](https://nodejs.org/api/http.html#http_request_finished) 是指說 `res.end()` 被呼叫後設定為 true，不代表 response 中的資料完全傳輸到網路上  

這些討論可以看 PR [response is only finished if socket is detached #31](https://github.com/jshttp/on-finished/pull/31)，提交者修改成
```js
if (stream && typeof stream.closed === 'boolean') {
    // Http2ServerRequest
    // Http2ServerResponse
    return stream.closed
}

if (typeof msg.finished === 'boolean') {
    // OutgoingMessage
    return (
        msg.finished &&
        msg.outputSize === 0 &&
        (!socket || socket.writableLength === 0)
    ) || (socket && !socket.writable)
}
```
增加 http2 的檢查，以及確保 `outputSize === 0` 所有 queued 住的資料都確實送出 socket

知道如何判斷 response 是否結束，最後看事件的註冊
```js
function attachFinishedListener (msg, callback) {
  var eeMsg
  var eeSocket
  var finished = false

  function onFinish (error) {
    eeMsg.cancel()
    eeSocket.cancel()

    finished = true
    callback(error)
  }

  // finished on first message event
  eeMsg = eeSocket = first([[msg, 'end', 'finish']], onFinish)

  function onSocket (socket) {
    // remove listener
    msg.removeListener('socket', onSocket)

    ....

    eeSocket = first([[socket, 'error', 'close']], onFinish)
  }

  if (msg.socket) {
    // socket already assigned
    onSocket(msg.socket)
    return
  }

  // wait for socket to be assigned
  msg.on('socket', onSocket)
  ....
}
```
在 response 與 response.socket 分別註冊事件，當結束或錯誤事件觸發後，檢查 response 是否真的結束，最後觸發用戶註冊的事件