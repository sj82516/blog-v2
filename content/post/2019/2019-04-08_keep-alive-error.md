---
title: Http persistent connection 研究與 proxy — server keep-alive timeout 不一致的 502 錯誤
description: >-
  架構上使用 elb 當作 load balancer proxy，後端接 nodejs api server，但是偶爾拋出 502 錯誤，後來發現是 proxy 與 server 間 keep-alive 差異所造成
date: '2019-04-08T23:46:01.643Z'
categories: ['雲端與系統架構']
keywords: []

  
---

架構上使用 elb 當作 load balancer proxy，後端接 nodejs api server，但是偶爾拋出 502 錯誤，elb log 顯示該次連線沒有進到 api server，麻煩的是機器 health check 正常，絕大多數的 api 測試也都正確，錯誤不太好復現，直到後來才發現是 proxy 與 api server 在 persistent connection 的 time-out 機制有所不同。

以下是研究 http 1.0 / 1.1 keep-alive / persistent connection 機制，並重新復現與解決問題。

### persistent connection 簡介

![](/posts/img/1__TCGmEtiKtghxQ6yG28J2Sg.png)

[https://en.wikipedia.org/wiki/HTTP_persistent_connection#/media/File:HTTP_persistent_connection.svg](https://en.wikipedia.org/wiki/HTTP_persistent_connection#/media/File:HTTP_persistent_connection.svg)

參考自[維基百科](https://en.wikipedia.org/wiki/HTTP_persistent_connection)，persistent connection 主要是希望在短時間內有多個 http request 時，可以重新利用 tcp connection，而不是每次都重新建立 tcp連線，降低 tcp handshaking 時間等開銷。

在 **http 1.0** 並沒有正式支援且默認關閉，但是蠻大多數的 http agent 都有支援，在 header 註明 `Connection: keep-alive` ，如果 server 也支援會把 header Connection 再次回傳；  
直到 client 或 server 決定斷線才會發送 `Connection: close` 斷開連線。

在 **http 1.1** 默認開啟，如果關閉 persistent connection 則必須主動在 http request 夾帶 `Connection: close` 。

在 reverse proxy 中或是 application server 都可以設置 keep-alive timeout，決定 server 在閒置多少秒數後沒有收到新的 http request 就主動斷開連線，以下透過 wireshark 實際觀察 persistent connection。

server.js 的程式碼很簡單
```js
const http = require('http');

const server = http.createServer((req, res) => {  
   res.end();  
});

server.listen(3000);
```

### http 1.0 ： client ← → server

如果直接使用 nodejs http module或是其他二次開發的模組，預設是採用 http 1.1 且不能修改，此時必須使用更底層的 net 模組發送 http 1.0 request

![](/posts/img/1____VxpaLipngwfWOh74Ye__CA.jpeg)

Server 很明確知道此次 connection 沒有要復用所以就可以直接斷開連結。

### http 1.1: client ← → server

http 1.1 request 預設會使用 persistent connection，程式碼把上面的 `Http/1.0` 改成 `Http/1.1` 即可，觀察 wireshark server 的回應就有所不同

![](/posts/img/1__4g8eFUFSBgKKQZjqSVsBkA.jpeg)

觀察到 http 1.1 預設支援 persistent connection，所以 server 會等到 keep-alive timeout (nodejs 8.0 後預設 5秒)才會斷開連結，從封包顯示是由 client 斷開連結。

為什麼 client 會主動關閉而沒有走 persistent connection 呢？

### http 1.1: keep-alive

在 nodejs中，http request 如果要使用 keep-alive，`必須透過 http agent 發送`，http agent 會生成 socket pool 並控制 socket 的復用與關閉時機；  
如果不使用 http agent，即使 header 或預設支援 keep-alive，每個 request 結束後client都會主動發送 [FIN,ACK] 斷開連結。

![](/posts/img/1__HPu__O06NHGGpqpfwTg__pYg.jpeg)

觀察到 tcp 少了一次完整的交握 (建立與結束)，省了 9 個 tcp packets 來回的時間。

### http 1.1: keep-alive timeout

預設 server 是五秒，那如果 client 第二個 request 超過五秒發送會發生什麼事？

![](/posts/img/1__FcolIW8__fD4jCIwMu6oWyw.jpeg)

根據觀察結果，在第一個 request 完成後，每隔一秒(秒數可調整)會從 client 發送 [[ TCP Keep-Alive ]](http://www.tldp.org/HOWTO/html_single/TCP-Keepalive-HOWTO/#whatis) 封包，五秒到 server 主動斷開連線；  
下一個 http request 就必須重新建立 tcp 連線。

> 小結：  
> 沒有走 persistent connection，通常是由 server close connection，因為 server 決定 response 的長度；  
> 但是 persistent connection 下，可能由 client 或 server 任一者 close connection，不過新的 request 還是由 client 發起。

現在加入 Nginx Reverse Proxy，模擬幾種情況

### Nginx Proxy — 不使用 KeepAlive

從最基本的設定檔開始，最單純轉發的動作

接著用 docker 執行

docker run -v /Users/zhengyuanjie/Desktop/Nodejs/persistent-connection/ka_nginx.conf:/etc/nginx/nginx.conf -it -p 8080:80  nginx

目前分成兩段 `client <---> nginx <---> nodejs server`

分別查看 wireshark 封包

![](/posts/img/1__fcMFyqRZQpyVIH3F2iBIQg.jpeg)
![左圖為 client ← → nginx / 右圖為 nginx ← → server](/posts/img/1__F9tpw9gqLudFmq65vjZ6zA.jpeg)
左圖為 client ← → nginx / 右圖為 nginx ← → server

因為 nginx keep-alive 設置 timeout 為 65秒，所以 `client <---> nginx` 處於 persistent connection；  
但是 `nginx <---> server` 這段是每次 request 都重新建立，預設到 server 這段 nginx 不會建立 persistent connection。

### Nginx Proxy — 開啟KeepAlive 且 timeout 大於 nodejs server

簡單修改一下 nginx conf，讓 `nginx <---> server` 這段也走 persistent connection

![](/posts/img/1__BAM9__7LQjtNIRDSBLn0SOQ.jpeg)
![](/posts/img/1__8pTNIDN7hnuI6uFToEdVZg.jpeg)

觀察到一個現象是 client ← → nginx 已經由 client 主動斷開連線，但是 nginx 到 server 卻要等到其中一者 timeout 才會斷開連線，雙方都不會主動發送 `Connection:close`；

多個 client 發送，n 個 client 會建立 n 個到 nginx connection，但是 nginx ← → server 會用同一條 connection 。

### 偶發的502 錯誤 — Keep-Alive Race Condition

[**Tuning NGINX behind Google Cloud Platform HTTP(S) Load Balancer**](https://blog.percy.io/tuning-nginx-behind-google-cloud-platform-http-s-load-balancer-305982ddb340)

[** 解决 AWS ELB 偶发的 502 Bad Gateway 错误_ - Timon Wong**](http://theo.im/blog/2017/10/14/suspicious-502-error-from-elb/)

> The NGINX timeout might be reached _at the same time_ the load balancer tries to re-use the connection for another HTTP request, which breaks the connection and results in a **502 Bad Gateway** response from the load balancer.

看到幾篇相關的問題，主要都是發生 race condition，某一方在剛好收到 [FIN, ACK] 後又收到下一個 request，導致了 tcp connection error 回傳 [RST]；  
解決方法通常是拉長 api server 端的 keep-alive timeout，讓 load balancer 自己斷開 connection。

#### TCP Close Connection

[**Transmission Control Protocol - Wikipedia** ](https://en.wikipedia.org/wiki/Transmission_Control_Protocol)

當 TCP 決定要關閉連線時，需要四次交握，主要是 client → server 與 server ← client 兩個方向都有一組的 FIN , ACK 交換，才能確保說關閉連線後對方不會再送資料；

假設目前是 A , B 在通信

1.  A 送出了 [FIN] 表示即將關閉 A → B 的 Connection
2.  B 回 [ACK]，表示收到，A → B 就關閉了
3.  但這時候 B → A 還是可以繼續傳送資料，直到 B 送出 [FIN] A 回傳 [ACK]，tcp connection 才真正關閉。

這個狀態是 `half-open`  ，某一個方向關閉但另一向還是通的。

在某些系統(Linux)的實作上僅支援 `half-duplex`，當要關閉某一向的 connection 時會連讀取都一併關閉，如果還沒處理完所有的資料，此時 host 會回傳 RST，另一方視此次 request 失敗。

### Nginx 優化

[**nginx优化--包括https、keepalive等**](https://lanjingling.github.io/2016/06/11/nginx-https-keepalived-youhua/)

keep-alive 有幾個相關的參數，可以依據服務內容而調整，簡單筆記幾個重點

1.  keepalive_requests  
    一個 persistent connection 最大的服務 request 數量，超過則強迫關閉
2.  keepalive_timeout  
    connection idle 超過時間就會被強迫關閉
3.  keepalive  
    最大同時 connection idle 數量，如果超過則 idle connection 會被回收

### 結語

keep-alive 優點在於重複利用 tcp connection，但必須注意

1.  client library 的實踐，確認是否有主動發送 connection: close 機制，否則 server 都會等到 timeout 才斷開連線，會造成太多不必要的 idle。
2.  nginx ← → server 這段的長連接 timeout 雙方都可以拉長，如果 QPS (query per second) 很高的話，多個 client connection 也會利用同一條 nginx ← → server 的 persistent connection。
3.  如果有使用 GCP / AWS load balancer 偶發 502錯誤，且 api server 端沒有收到任何連線紀錄，多半是 keep-alive timeout 問題。
4.  讓 client timeout 大於 server timeout，因為 request 是由 client 發起，就能有效避免 keep-alive race condition。