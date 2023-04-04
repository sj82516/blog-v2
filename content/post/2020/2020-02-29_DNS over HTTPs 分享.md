---
title: 'DNS over HTTPs 分享'
description: DNS 查詢可以基於 UDP 或 TCP 查詢域名的對應紀錄，但是目前沒有過多的保證與安全性，基於個人隱私與安全性考量，如今推出了 DNS over HTTPs，基於 HTTPS 安全性與隱密性保護 DNS 查詢
date: '2020-02-29T07:21:40.869Z'
categories: ['網路與協定']
keywords: ['DNS', 'Network']
---
會看到 DNS over HTTPs(DoH) 是因為閱讀到 [Firefox 在 2/26 於美國用戶推出預設採用 DoH 的文章](https://blog.mozilla.org/blog/2020/02/25/firefox-continues-push-to-bring-dns-over-https-by-default-for-us-users/)，早在 Firefox@62 時就已經內置這項設定，其餘地區用戶可以透過設定開啟；  
目前 [Chrome 於 78 之後預設開啟](https://www.ithome.com.tw/news/133004)，[Windows 10 也宣布即將整合 DoH](https://www.ithome.com.tw/news/134278)，公開 DNS 解析服務商也越來越多支援 DoH，早先 Firefox 與 Cloudflare 合作，後續 Google Public DNS / AdGuard 等也加入支援

DNS 是歷史悠久的網路通訊協定，基於 UDP/TCP 查詢域名對應的紀錄，但這一切在網路傳輸都是明文，沒有任何的隱密性與安全性，後來有了 `DNSSEC` 可以確保 DNS 紀錄沒有被竄改，但可惜在推廣上需要改 DNS Server，受到實作限制並沒有全面實施   

Mozilla 與 Google 於前陣子提出 `DNS over HTTPs`，將 DNS 查詢放在 HTTPs 當中，如此一來除了可以防止被惡意竄改等中間人攻擊外，更可以保護用戶隱私，ISP 等中間的網路設施提供商就`比較難追蹤用戶的網路瀏覽`  

這一篇文章會先大略技術介紹，接著整理網路上對於 DNS over HTTPs 的正反兩方討論，先說結論是
> 沒有所謂的 100% 安全，但我們能盡力做到最好

## 技術實作
DoH 其實就是透過 HTTPs 查詢 DNS 紀錄，一般 DNS 在查詢記錄時會需要反覆多次，從頂級域名開始一路查到子域名，在這過程中全部的服務商與網路中介設備都知道你在查詢哪個網站

DoH 希望改透過 Trusted Recursive Resolver(TRR) 去查詢，交由 TRR 做到解析域名這件事，這樣就無法回溯到使用者本身的 IP，達到保密性的效果；  
同時由 DNS 域名商提供的 TRR 服務時，會參考用戶的 IP 位置，避免一些透過 Geo DNS 的服務造成影響

## Spec 概覽：RFC-8484
[RFC8484](https://tools.ietf.org/html/rfc8484)，簡單抓出幾個有趣的地方
### MIME Type
DoH Client 可以用 `application/dns-message`，表明是要用 dns 格式查詢，也可以用 json 等方式，看 DoH Server 提供，如 [Cloudflare 有提供 json 格式](https://developers.cloudflare.com/1.1.1.1/dns-over-https/wireformat/)  
### HTTP Method
支援 GET / POST 兩種方式查詢  
例如說要查詢 www.example.com 長這樣
```md
:method = GET
:scheme = https
:authority = dnsserver.example.net
:path = /dns-query?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB
accept = application/dns-message
```
### 建議 HTTP2 為最低版本  
對比 DNS 採用的 UDP/TCP 來說，HTTP 開銷大很多，採用 HTTP2 有一些性能上優化的部分，例如重用連結、重整封包順序、Header 壓縮等，相比更舊的 HTTP 版本已儘可能減輕通訊上的負擔

## 實際使用與測試
要實際使用的方式有幾種，一種是在自己電腦裝上 DoH Client，接著將 DNS 查詢指向 DoH Client 經由他代理查詢，好處是透過代理不用擔心應用程式的支援問題，這部分可以安裝 cloudflare 提供的 [cloudflared](https://developers.cloudflare.com/1.1.1.1/dns-over-https/cloudflared-proxy/)  

但這次實驗只是要快速測試功能，與利用 Wireshark 實地看封包重送的過程，所以安裝另一個 command line 工具 [kdig](https://www.knot-dns.cz/docs/2.6/html/installation.html)，kdig 可以直接指定 DoH Client 查詢 dns 紀錄，比 dig 功能再多一些，安裝完成後比較兩個指令  
> $ kdig -d @1.1.1.1 +tls-ca +tls-host=cloudflare-dns.com yuanchieh.page
> vs
> kdig -d @1.1.1.1 yuanchieh.page

透過 Wireshark 擷取封包結果
![dns over DoH](/post/img/20200229/dns_doh.jpeg)
![dns](/post/img/20200229/dns.jpeg)
前者走一般 HTTPS 流程，後者走 DNS 流程，可以看到傳輸量與傳輸速度的差異

## 爭議之處
這篇新聞整理了許多專家對於 DoH 的反對意見：[DNS-over-HTTPS causes more problems than it solves, experts say](https://www.zdnet.com/article/dns-over-https-causes-more-problems-than-it-solves-experts-say/)，其中幾點蠻值得更深入探討
### DoH 不能防止 ISP 業者窺視用戶的瀏覽紀錄(可以解決)  
DoH 確實能夠防止 ISP 業者看到 DNS 查詢記錄，但如果用戶是用 HTTP，那走不走 DoH 他的網頁瀏覽紀錄還是會被發現；  
即使用戶走 HTTPS，基於現有的 HTTPS 缺失，不是每個 request 都是加密的，例如 `SNI` 跟 `OSCP`  

SNI 是 Client 先跟 Server 説他要連線的 hostname 是哪個，因為同個 IP 上可能有多個 Server (Virtual host) 需要回傳對應的憑證；  
OSCP 是 Client 收到 Server 回傳的憑證，並需再去 CA 驗證憑證的有效性；   
這兩個 Request 都是明文，所以都會被記錄到。

再者，ISP 業者還是會知道 Client 要送封包到哪個 IP，IP 位置不是很時常更動，透過反查就知道 Client 是在看什麼網站  

上述條件無關乎 DoH 的問題，但確實讓 DoH 毫無用武之地  

### 公司管理困擾
如果公司防火牆透過在 DNS 階段過濾，碰上 DoH 就會很頭疼，造成管理上的漏洞

### 過度集中於 DNS 解析商  
再發起 DoH 時，會需要指定 HTTPs 聯繫的對象，這通常是由 DNS 解析商所提供，這導致權利集中於幾間大公司手裡，例如 Firefox 瀏覽器內預設使用 Cloudflare / NextDNS，雖然也可以加入自定義，但如果一般的用戶不慎熟悉，這會導致 DNS 解析商反而有很大的影響   

專家建議是基於 DNS 本身機制外加加密方式，而不是把作法綁到幾間解析商手上。  

> 內文有提到「某些公司為了讓自己看起來很在意用戶隱私，才推出這種半殘的協定，是非常不負責任的」

## 結論... not the end!
DoH 看似解決了部分問題，又有 Firefox / Chrome / Windows / Google DNS / Cloudflare 等多家世界級產品與 DNS 服務商的推廣與背書，但確實反對者提出的質疑也很有說服力，只能說如果在意 DNS 有沒有被竄改，使用 DoH 或許可以，但不能期望 DoH 完全抹去個人的網頁瀏覽紀錄   

## TLS 1.3
TLS 1.3 改變了加密流程，由最一開始的 `Client 發出 ClientHello 就加密了`，此時加密的方式是從 DNS 紀錄拿到 Server 的 Public Key，並採用 Diffie-Hellman 交換金鑰方式，用「非對稱加密的公鑰」加密「對稱加密的金鑰」，用「對稱加密的金鑰」加密指定的 Server name   

目前僅剩唯一個問題 IP 位置，但如果 Server 是在 CDN 後面，讓 ISP 只能追蹤到 CDN，後面的就無法追蹤到  

此外 TLS 1.3 將握手機制減少一個 RTT 變成只要一個 RTT 就能完成交握，效率大幅提升  

## 結論
TLS 1.3 需要 DNS 支援，就可以從交握開始就全程加密；   
而為了避免 DNS 被攻擊或是竄改紀錄，記得要使用 DNSSEC；   
最後加上 DoH，讓 DNS 紀錄查詢這一段也不會被 ISP 追蹤   

整段補上後，就能增加用戶的隱私與安全性，可惜 AWS 的 Route53 跟 Cloudfront 不支援... :/   
看了一些文章，目前覺得 Cloudflare 在安全性這部分著墨很多，支援度也都很夠，或許該考慮看看

## 參考資料
[A cartoon intro to DNS over HTTPS](https://hacks.mozilla.org/2018/05/a-cartoon-intro-to-dns-over-https/): 非常仔細講解過程
[DNS over TLS / DNS over HTTPS - Is it the privacy magic bullet?](https://blog.sean-wright.com/dns-over-tls-dns-over-https-is-it-the-privacy-magic-bullet-2/)