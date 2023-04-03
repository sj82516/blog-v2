---
title: "Route53 Latency-Based Routing 機制 — DNS 如何評估延遲"
description: >-
  前陣子做全球不同地區 API Server 的部署，希望用戶基於延遲性選擇最靠近的 API Server，透過 Route53 + API Gateway 實作非常簡單。
date: '2019-04-29T00:18:14.937Z'
categories: ['雲端與系統架構']
keywords: []

---

前陣子做全球不同地區 API Server 的部署，希望用戶基於延遲性選擇最靠近的 API Server，透過 [Route53 + API Gateway](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-api-gateway.html) 實作非常簡單。

但量測延遲性，理論上只能由 Client 向多個 Server 發送，最後評比整段 Http Request 完成的時間；  
Route53 身為 DNS Server，如果是從 DNS Server 去打 Server，那量測的結果應當是 Route53 到 Server 的延遲，而不能代表 Client 到 Server；

好比說 User 在台灣，Route53 Server 在美國，Server1 在美西，Server2 在東京，那從 Route53 角度一定是美西的 Server1 比較近，但對 User 來說會是日本的 Server2 比較近才是；  
又如果說 Route53 是全球部署，那Route53 又如何決定 User 要連到哪個地區的 DNS Server ?   
又例如說 CDN，同樣會遇到要去哪個 Local CDN Server 比較快的問題？

以下是研究這個問題的過程。

### How Amazon Route 53 Uses EDNS0 to Estimate the Location of a User

參考[官方文件](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html#routing-policy-edns0)，Route53 支援 DNS protocol 額外擴充 EDNS0 中的edns-client-subnet。

DNS 技術發展於 1980 年代，當時 protocol 設計只有留 512 bytes 可以夾帶資訊，但隨著時間演進，人們希望加入更多的功能，例如說更多的 IPv6、[DNSSEC](https://medium.com

**edns-client-subnet** 主要是讓 client 再發起 DNS resolve 時可以在 query 中夾帶自己 IP 的 subnet，讓 DNS Server 可以知道 client 確切的 IP 來源而不會再 Recursive 解析過程中被置換，更詳細解釋於下一節；  
如果 client 不支援 edns-client-subnet，則 Route53 會拿 IP當作來源位置判斷。

> Route53 是透過 IP 判斷用戶的位置，並用此位置當作量測的基準，Geolocation / Latency based 都是如此；  
> 而 IP 位置來源優先使用 edns-client-subnet，其次用 source IP。

### edns-client-subnet (ECS)

摘要一些 RFC 內容

[**RFC 7871 - Client Subnet in DNS Queries**](https://tools.ietf.org/html/rfc7871)

DNS 查詢的方式是一層一層的，從最頂級的域名一路向下，例如說 hello.example.com，就會從 .com Nameserver → example.com Nameserver 逐步查詢。

Client 會透過 Stub Resolver (可理解一個 DNS Agent)，透過 Intermediate Nameserver 向 Authoritative Nameserver (握有 DNS zones 域名區域) 發起請求。

其中 Intermediate Nameserver 有兩種：

1.  Forwarding Resolver：不會遞迴解析，僅會傳遞給下一個 Recursive Resolver。
2.  Recursive Resolver：遞迴 domain chain 直到域名解析完成，會透過 cache 快速返回查詢。

目前來說，Recursive Resolver 使用日益增加，因為集中化管理有幾個優點 `cache 更多資訊` 、`審查用戶的 DNS查詢` ，但是傳統的 Recursive Resolver 在遞迴查詢時，會將 Source IP 改成自己的 IP而不是 Client 的 IP，但 Recursive Resolver 跟 Client 可能隔很遠(網路拓墣上的距離)；  
如果此時 Authoritative Nameserver 希望解析 Client IP 提供量身定做的 DNS Answer (Tailored Response)，就沒有辦法，因此制定 edns-subset-client 解決此問題。

#### Option Format
```md
+0 (MSB)                            +1 (LSB)  
      +---+---+---+---+---+---+---+---+---+---+---+---+---+  
   0: |                          OPTION-CODE              |  
      +---+---+---+---+---+---+---+---+---+---+---+---+---+  
   2: |                         OPTION-LENGTH             |  
      +---+---+---+---+---+---+---+---+---+---+---+---+---+  
   4: |                            FAMILY                 |  
      +---+---+---+---+---+---+---+---+---+---+---+---+---+  
   6: |     SOURCE PREFIX-LENGTH  |  SCOPE PREFIX-LENGTH  |  
      +---+---+---+---+---+---+---+---+---+---+---+---+---+  
   8: |                           ADDRESS...              |  
      +---+---+---+---+---+---+---+---+---+---+---+---+---+
```

edns-subset-client protocol 是基於 [EDNS0](https://tools.ietf.org/html/rfc6891) 制定，以下是他的 package 內容：

1.  OPTION-CODE  
    兩個八位元組，固定是 `0x00 0x08`
2.  OPTION-LENGTH  
    兩個八位元組，代表 payload 長度
3.  FAMILY  
    兩個八位元組，代表 address 的 family (IANA標準)，目前支援 IPv4跟 IPv6
4.  SOURCE PREFIX-LENGTH  
    Address 遮罩，Client 用來指定查詢的 IP 遮罩
5.  SCOPE PREFIX-LENGTH  
    同樣是 Address 遮罩，但是是由 Response 表示 Address 覆蓋範圍。

SOURCE PREFIX-LENGTH 跟 SCOPE PREFIX-LENGTH 這兩個參數相對比較重要

1.  當 Client 或 Stub Resolver 發起 name resolve 時，會指定 `Address` 與 `SOURCE PREFIX-LENGTH`，`SOURCE PREFIX-LENGTH` 算是希望`保留 Client IP 部分隱私，不見得要全部都送往 Nameserver`；  
    但 `SCOPE PREFIX-LENGTH` 必須設為 0 因為這是用在 Response 上
2.  當 Recursive Resolver 收到時，會透 `SOURCE PREFIX-LENGTH` 遮罩查詢 Cache，如果有則返回；沒有則繼續查詢，此時遞迴查詢的 `SOURCE PREFIX-LENGTH` 僅可小於等於來源查詢的 `SOURCE PREFIX-LENGTH`
3.  Authoritative Nameserver 如果回傳的 `SCOPE PREFIX-LENGTH` 小於 `SOURCE PREFIX-LENGTH`，代表不需用提供這麼多 bits；  
    反之 `SCOPE PREFIX-LENGTH` \> `SOURCE PREFIX-LENGTH`，則代表需要提供更多得 bits 才能得到更精準的 Answer。
4.  Authoritative Nameserver 處理 Cache 時要多加注意，不可以有 Prefix overlapping ，避免匹配到短的 prefix 回傳錯誤的 RRsets；  
    例如說原本的 cache 是 1.2.0/20 A，但此時多加了 1.2.3/24 B，就需要拆成 1.2.0/23, 1.2.2/24, 1.2.4/22, 1.2.8/21 A，1.2.3/24 B，避免疊合。

#### 資安風險

1.  生日攻擊  
    如果駭客向 Intermediate Nameserver 發送大量的假 DNS Answer，如果不小心被吻合到，Intermediate Nameserver 就會回傳被釣魚的IP，這個問題在原本的 DNS 就會出現。  
     → Intermediate Nameserver 必須對 DNS Answer 做欄位檢查，最好支援 DNSSEC 減輕問題發生機率
2.  Cache 污染  
    支援 ECS 後，Cache 機制變得更加複雜，會需要基於 FAMILY / SCOPE PREFIX-LENGTH / ADDRESS Cache，造成 Memory 用量大增；  
    如果駭客運用這一點，用洪水攻擊製造大量不容易命中 Cache 的查詢，對 DNS Nameserver 做 DDos 攻擊。  
     → Nameserver 必須自行做好評估

#### 示範案例

Spec 中有個示範案例

1\. Stub Resolver (SR)，IP位置是 2001:0db8:fd13:4231:2112:8a2e:c37b:7334，準備透過 Recursive Resolver (RNS) 查詢 [www.example.com](http://www.example.com)

2\. RNS 支援 ECS，查詢 [www.example.com](http://www.example.com) 是否在 cache中，沒有則開始查詢

3\. RNS 向 root Nameserver .com 查詢，向 root Nameserver 查詢不需要夾帶 ECS 選項

4\. 接著 RNS 準備去找 .example.com Authoritative Nameserver (ANS)

5\. RNS 要傳遞的封包，必須加入 ECS 選項  
   - OPTION-CODE: 8  
   - OPTION-LENGTH: 0x0b，固定 4 bytes + 7 bytes 的 Address  
   - FAMILY: 0x00 0x02，代表 IPv6  
   - SOURCE PREFIX-LENGTH: 0x38，遮罩代表 /56 bits  
   - SCOPE PREFIX-LENGTH: 0x00，這是 Answer 用的  
   - ADDRESS: 0x20 0x01 0x0d 0xb8 0xfd 0x13 0x42，也就是前 56 bits

6\. ANS 收到後，產生結果(Tailored Response)回傳，其餘內容相同  
   - SCOPE PREFIX-LENGTH: 0x30, 代表 /48

7\. RNS 收到後，比對 FAMILY, SOURCE PREFIX-LENGTH 和ADDRESS，如果不吻合則拋棄

8\. RNS 基於 ADDRESS, SCOPE PREFIX-LENGTH 和 FAMILY 做 cache

9\. RNS 回傳結果給 SR，此時不需要 ECS 選項

### 透過 dig 檢驗

dig 支援 edns-client-subnet 參數，藉此觀察 dns 回傳的 A record，指令為 `dig [@8](http://twitter.com/8 "Twitter profile for @8").8.8.8 {測試 domain name} +subnet={測試的 ip}` ，網路上很多資料是使用 `+client={測試 ip}` ，我實測是用 `+subnet` 才可以。

前面提到的 `SCOPE PREFIX-LENGTH` ，Route53 回傳 24，也就是最多提供 24 bits 的 Address 就可以取得最佳解。

測試的 domain 是公司內部透過 Route53 與 API Gateway 架設，不方便公開，但透過 VPN 取得不同區域的 ip，例如日本、印度、加拿大、阿根廷等地，放入 subnet 參數後，DNS 回傳的 ANSWER 確實跟著地區而改動；  
有點弔詭的是巴西不走國內反而是到法國 Frankfurt的伺服器，而阿根廷是到巴西 São Paulo的伺服器；  
GeoIP 查詢透過 [Maxmind](https://www.maxmind.com/en/geoip-demo)，他有每日查詢上線，是綁定 IP限制。