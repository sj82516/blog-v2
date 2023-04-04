---
title: HTTPS不代表安全：Cloudflare SSL 研究從Server到Cloudflare
description: >-
  網頁瀏覽時出現HTTPS的綠色鎖看了令人放心，這似乎代表著我們在網站瀏覽的資料有受到「完整的加密保護」，不用擔心資料被偷窺與被調包等等MitM中間人攻擊的風險，但事實當然沒有這麼簡單。
date: '2018-07-11T01:37:07.542Z'
categories: ['系統架構']
keywords: []
---

網頁瀏覽時出現HTTPS的綠色鎖看了令人放心，這似乎代表著我們在網站瀏覽的資料有受到「完整的加密保護」，不用擔心資料被偷窺與被調包等等MitM中間人攻擊的風險，但事實當然沒有這麼簡單。

在申請SSL憑證時是綁定域名申請，理論上 DNS解析域名後直接指向Server所在IP，也就是Client透過HTTPS在索取憑證、驗證憑證、與 Server共同生成對稱加密金鑰後，實際將資料加密傳輸到Server的整段網路過程是受到完整的保護。

但是現在很多網站為了效能上與安全性上的考量，採用了向 Cloudflare這樣的 DNS代管 / CDN服務；  
`Client ← → Cloudflare ← → Server`

Cloudflare在全球各大洲部署多個資料中心，會自動將DNS / Cached資料散佈到多節點上，並提供多項優質服務，如

1.  從地理位置最近的節點回覆 Client所需資料，之前曾看過實測多家DNS/CDN服務商的資料，Cloudflare回應速度是最好的；
2.  在Cloudflare後台觀察到網站有近八成的流量是命中Cache從 Cloudflare直接回覆 Client，降低Server 負擔與流量，再Server以流量計費的主機託管下節省很大的成本。
3.  DDos防護與白/黑ip名單建立

但是採用 Cloudflare有些資安上的疑慮，也是此次筆記的內容  
主要紀錄  
1\. 採用Cloudflare風險在哪  
2\. 修正問題與實測

### 採用Cloudflare風險在哪

#### Client ←→ Cloudflare

先前提到Cloudflare會擋在 Client與 Server之間，如果`啟用CDN服務為了解析緩存資料`，Cloudflare 會需要在他這層直接解密，所以如果是用免費版 Cloudflare會提供 Universal (shared)的憑證，這是簽發於 Cloudflare機構底下；  
如果要用自己域名簽發的憑證，必須`透過Cloudflare購買`或是`上傳自己購買的憑證與私鑰` ，這兩項都必須採用付費方案；

但這樣看來 Cloudflare 就是渾然天成的 MitM中的中間人，但是我們選擇相信他，有看到一些謠言是說 Cloudflare背後有美國的 NSA國家安全局把持，所以資料可能有洩漏的疑慮，畢竟 Cloudflare可以看到所有解密後的資料。  
看到一些討論是半信半疑，技術性上也不是所有的流量都會導向美國的服務器，但還是有必要留個心眼，畢竟先前也是有 FBI要求 Apple 解鎖Iphone的經歷，國家機器再處理這種法律、資安、個資等議題確實蠻掙扎的。

[**Tim Cook says Apple's refusal to unlock iPhone for FBI is a 'civil liberties' issue**](https://www.theguardian.com/technology/2016/feb/22/tim-cook-apple-refusal-unlock-iphone-fbi-civil-liberties)

(雖然Apple 在中國也服軟了 :/)

所以如果要有緩存機制且非常在意 Client → Server 必須全程走HTTPS且使用自家憑證不被任何人在中途解密資料，就適合自建Cache Server 不適合用Cloudflare。

#### Cloudflare ←→ Server

從Cloudflare到Server這段有不同層級的設定，可以於後台設定

![](/post/img/1__by4l7dHy5wi__pWEzz0cl9w.jpeg)

1.  Off：  
    全部走HTTP
2.  Flexible：  
    Client → Cloudflare 走HTTPS，而Cloudflare → Server 走HTTP
3.  Full：  
    Cloudflare → Server 走HTTPS，但是 Cloudflare不會驗證憑證。  
    Server需要開啟443 port 才能處理。
4.  Full(strict)：  
    呈上，但是Cloudflare會向CA驗證憑證的正確性，這部分需要搭配設定 `Origin Certificates` ，可以由 Cloudflare 產生或是自己產生後上傳。  
    Cloudflare本身也是合格的CA，所以往好處想是上傳憑證是可以被信任的，但同樣的雞蛋都在同一個籃子裡本身就是個風險，算是一體兩面。

### 修正問題與實測

所以除了Client要有HTTPS保護，在Server這段也建議要開啟 Full以上的防護措施，Server部分用 Let’s Encrypt 免費簽署，並同時開啟 80 / 443 port，來調整對應Cloudflare的SSL保護措施。

#### 1\. 僅開啟 Cloudflare DNS：

這時候打 [https://domain.com](https://domain.com) 會出現自己簽發的憑證，像我是用 Let’s Encrypt 簽署的憑證

#### 2\. 開啟 Cloudflare CDN服務：

這時候同樣的 [https://domain.com](https://domain.com) 會自動變成 Cloudflare Universal 憑證

![](/post/img/1__DhAfWG__CN45Me0tMhpyb9Q.png)

以上是 Client <--> Cloudflare這段

以下用 `> sudo tcpdump -nn -i eth0 'tcp and (not port 22)'` 查看封包，排除port 22 主要是避免 ssh 封包干擾觀察

#### 3\. SSL 設為 Flexible

![](/post/img/1__Rg8Jz3FZZx8adrfbYt0heA.png)

從 Cloudflare(用 whois 172.68.47.149查詢後確認) 到 Server是走 80 port

#### 4\. SSL 設為 Full / Full (strict)

![](/post/img/1__5MvJS8IszULHOhDNeGlKbw.png)

後台設定切換後等個三、五秒就立即改走 port 443

#### 5\. 測試憑證檢查

Full (strict)差別在於會檢查憑證是否為公開的第三方CA頒布的合法憑證，那就來確認一下檢查的機制是否OK。

a. 在 Full 狀態下改用其他網域的SSL憑證 => 可以!  
b. 在 Full (strict) 狀態下改用其他網域的SSL憑證 => 不行，會檢查

![](/post/img/1__6JOG8bEc9kDeqexWERRBbA.jpeg)

如果是自簽憑證，記得要上傳 CSR到Cloudflare，不然一樣會出錯。

### 結論

1.  僅使用 Cloudflare DNS服務，Client會看到自家提供的憑證
2.  開啟 Cloudflare CDN服務，免費版轉為 Cloudflare Universal SSL憑證；  
    如要替換為自己Domain簽署的憑證，需要付費方案
3.  開啟 Cloudflare CDN，會讓 Cloudflare成為中間人，資料有被外露的疑慮
4.  記得開啟 SSL 為 Full(strict)，保護 Cloudflare 到 Server這段