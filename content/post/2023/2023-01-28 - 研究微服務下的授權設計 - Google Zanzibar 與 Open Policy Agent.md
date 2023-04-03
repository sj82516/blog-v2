---
title: '研究微服務下的授權設計 - Google Zanzibar 與 Open Policy Agent'
description: 授權是保護用戶隱私的核心，也是長年在 OWASP 網站漏洞的榜單上，在微服務架構下授權的設計又更加的困難，閱讀 Google Zanzibar 與 Open Policy Agent (OPA) 如何實作與設計
date: '2023-01-28T01:21:40.869Z'
categories: []
keywords: []
---
上一篇 [驗證與授權的差別，淺談 OAuth 2.0 與 OpenID Connect](https://yuanchieh.page/posts/2023/2023-01-20-%E9%A9%97%E8%AD%89%E8%88%87%E6%8E%88%E6%AC%8A%E7%9A%84%E5%B7%AE%E5%88%A5%E6%B7%BA%E8%AB%87-oauth2.0-%E8%88%87-openid-connect/) 淺談到 OAuth 2.0 與 OIDC 的差異，我們是以 Client 的角度去理解如果像第三方取得驗證與授權，但如果今天我們要 Google 一樣自己處理授權的設計，思考的方式就會有所不同  

參考以下的文章，分享這幾天研究微服務下該如何設計驗證的機制
- [Best Practices for Authorization in Microservices](https://www.osohq.com/post/microservices-authorization-patterns)
- [Zanzibar: Google’s Consistent, Global Authorization System](https://research.google/pubs/pub48190/)
- [How Netflix Is Solving Authorization Across Their Cloud \[I\] - Manish Mehta & Torin Sandall, Netflix](https://youtu.be/R6tUNpRpdnY)
- [Open Policy Agent](https://www.openpolicyagent.org/)

看到網路上有時會縮寫 (Authentication -> `AuthN` / Authorization -> `AuthZ`)，以下也會用此縮寫

## 一. 所謂的授權驗證 Authorization
具體來說，授權設定主要是判斷 
> {某人} 是否可以針對 {某資源} 執行 {某操作}

現今有三種主流管理授權的方式
1. RBAC
2. ABAC
3. ReBAC

#### 1. RBAC
制定 Role 並綁定對應的權限，例如 AWS IAM，案例如 “如果用戶是 Admin 權限才可以瀏覽此頁面“  
但是權限就直接綁死 Role，如果同個 Role 下突然想要在拆分更細的控制，就要增加新的 Role

#### 2. ABAC
透過 Attribute 綁定對應的權限，例如 “如果用戶是 10 月以前註冊，可以享有 xxx 優惠“，Attribute 制定相對就彈性許多，[AWS IAM 也可以用 ABAC 設定](https://docs.aws.amazon.com/zh_tw/IAM/latest/UserGuide/introduction_attribute-based-access-control.html)

#### 3. ReBAC
當角色或資源是有層狀的繼承關係時，可以透過描述 Relation 方式來制定權限，例如 “Group A 包含 Group B，小明是 Group B 成員，某個檔案是 Group A 所有成員都可以讀取，則小明也應該要可以讀取“

## 二. 微服務下的驗證架構
在 monolithic 架構下，因為 DB 都在一塊，所以 authorization 可以直接 query 檢查即可，例如
```ruby
# 如果用戶是 admin 
if user.is_admin
    // xxxx
end

# 如果用戶是資源擁有者
if user.id == document.onwer_id
    // xxxx
end
```
驗證變成是商業邏輯的一部分

但如果今天是在 microservice 情況下，該如何判斷用戶是否有權限可以操作呢？ 大致有以下三種方法
### 1. 將資料放在原位，透過 API 呼叫
假設今天獨立一個 document service，每個 document 隸屬於某個組織 org 下，而 org 管理是屬於 user service 的範疇
則 user service 可以開一條 API 專門查詢 user 所隸屬的 org
![](/posts/2023/img/0128/service_api.png)
這是最簡單且有效的方式，但如果服務越變越多，則會有幾個問題
- 服務間判端可能有重複呼叫 (例如 document 往上多一層 folder，變成要判斷 user 是否有權限操作 document 與 folder)
- API 呼叫會有延遲
- 如果驗證方式改變，多個 service 也要跟著改動 (例如 service A / service B 都是用 org 驗證，但之後突然變成要用 user 本身驗證)

### 2. 在 Gateway 注入授權驗證所需的資料
![](/posts/2023/img/0128/gateway.png)
既然服務都需要 user org 這個資訊，那我們在 request 近來時就透過 gateway 把 user 資訊塞好塞滿，好處有
- 減少多餘 request，所有下游的 service 都能讀取到 user org 參數
- 如果授權的參數很有限，例如只有切分幾種 role，那 gateway 會是最方便的

缺點是 Gateway 會需要知道所有 service 需要的資料，如果今天驗證方式改變 Gateway 也要跟著改變

### 3. 獨立的授權驗證服務
![](/posts/2023/img/0128/authz_service.png)
有一個獨立的 AuthZ service，其他 service 收到 request 都直接向 AuthZ service 驗證授權，將`驗證與商業邏輯拆開並集中管理授權邏輯`   
特別適用於微服務眾多且需要互相溝通的情況 / 有第三方廠商要分享資料時，例如 Google / Airbnb / Netflix

缺點是
- AuthZ service 與其餘 Service 的內容耦合，因為 AuthZ service 並須知道所有的 resource，才能對應設定權限，例如 document / folder 等
- 多一組服務要維護

大部分的公司應該都不需要如此複雜，通常也沒有獨立的團隊在維護驗證授權，但可以借鏡 Google 設計的 Zanzibar 與 CNCF 的開源專案 Open Policy Agent (OPA) 來看大型軟體採用的授權檢查方法

## 三. Google 中心化 AuthZ 服務 - Zanzibar
Zanzibar 是中心化的 AuthZ 服務，提供統一的 data model 與 config language (描述 ReBAC 的規則)，他有以下的表現
- 效能：延遲 p95 < 10ms
- 規模：數十億的規則 / 每秒百萬等級 request，囊括 Calendar, Cloud, Drive, Maps, Doc 等
- 可用性：99.999%

實際設定可能像以下圖示 (非 google 官方，參考自 [zanzibar.academy](https://zanzibar.academy/))
![](/posts/2023/img/0128/demo.png)

### 為什麼需要中心化的 AuthZ 服務
1. 提供統一的語意和用戶體驗
2. 當多個應用程式互交相錯時，更容易實作
> 例如發送 Gmail 時會幫你檢查附件中的 Google Doc 收件人是否有權限讀取

### Tuple: 描述「物件與物件的關係」或「物件與用戶的關係」
Zanzinbar 有自己一套描述規則的語言，每條規則稱為一個 tuple，可以描述
1. user U has relation R to object O
2. set of users S has relation R to object O

以下是論文的案例
> `doc:readme#owner@10` User 10 is an owner of doc:readme    
`group:eng#member@11` User 11 is a member of group:eng   
`doc:readme#viewer@group:eng#member` Members of group:eng are viewers of doc:readme   
`doc:readme#parent@folder:A#...` doc:readme is in folder:A

後續 Client 就可以透過 check API 指定 user + operation + object 請求驗證

### 一些實作的困難與克服方式
通篇論文主要在講設計 Zanzibar 的挑戰，因為驗證服務需要滿足 
- Flexibility 讓多種服務都能設計自己的驗證規則
- Correctness 驗證是核心的用戶隱私保護所以判斷結果一定要正確
- Low Latency 因為大多數的 Request 都需要驗證
- Scale 因為 Request 會非常頻繁 (請求每秒百萬且橫跨整個地球)
- High Availability 因為每個服務都會依賴驗證服務

以下提幾點比較有趣的困難與克服方式
#### 1. 設定的最終一致性
當 ACL (Access Control List) 發生改變時，操作的順序必須嚴格遵守，否則會不小心把舊的 ACL 套用到新的物件上 / 舊 ACL 影響到新的內容 (同物件)，否則會有以下錯誤
- ex1. Alice 移除 Bob 權限 (1)，此時新增物件 O (2) 繼承上層權限，則 Bob 不應該擁有 O 的權限 (3) 
  - 如果 2 比 1 先套用，則 Bob 就不小心有了 O 的權限 (2 > 1)
- ex2. Alice 移除 Bob 權限 (1)，此時物件 O 新增內容 (2)，則 Bob 不應該看到新的內容 (3)
  - 如果 2 比 1 先套用，且 Bob 在 1 之前讀取到新的內容 (套用順序：2 > 3 > 1)，但理論上他不應該看到新的內容

以上問題稱為 `new enemy problem`，Zanzibar 透過 external consistency 與 snapshot reads with bounded staleness 解決此問題
- external consistency  
當操作 Tx 在操作 Ty 之前，則當 T 時看到 Ty 生效時，則 Tx 必定生效，Zanzibar 是透過 Google Spanner 儲存，仰賴 data storage 的特性保證
- snapshot reads with bounded staleness  
當物件更新時 (ex2-2)，當下版本會對應一個稱為 zookie token 並記錄當下的時間；之後 client request 都必須帶上 zookie，只要讀取的時候比對 zookie 時間小於等於儲存層更新的時間 (ex2-3)，則代表更新先前的 ACL (ex2-1)都已經被套用

#### 2. Leopard Indexing
因為權限判定可能是嵌套很多層 (Group A 包含 Group B 包含 Group C ....)，這樣在判斷上會有需要 traverse 很多節點 (圖學問題)，Zanzibar 設計 Leopard Indexing，將 group 層級攤平並儲存在 memory 中，這樣降低了搜尋的複雜度

#### 3. 把較慢的請求發給不同的 server (Request Hedging)
Zanzibar 會有一個閥值，當發現請求比較慢時，會發送給其他回應速度比較快的 server，優化特別慢的請求 (通常也代表特別複雜)

----------
其他還包含一些 Cache 設計 / 整體架構 / 對外開放 API 等，這邊就先不贅述，來看一下第三方提供的 Zanzibar like 雲端服務，部落格跟教學寫得都很好
- [authzed-A managed permissions database for everyone](https://authzed.com/)
- [auth0](https://auth0.com/blog/auth0-fine-grained-authorization-developer-community-preview-release)，還在 preview 階段，但他們的教學不錯
- [oso](https://www.osohq.com/)

## 四. 針對 cloud native 的 solution - Open Policy Agent
當我們把目光從應用程式移開，整個系統架構處處都需要驗證的服務
- 某個網域的流量是否可以進來 / 出去
- 某台機器開發者是不是可以 ssh
- DB 是不是可以被第三方廠商 access

Open Policy Agent (簡稱 OPA) 針對 cloud native 架構設計驗證規則的解法，`中心化管理驗證規則與其他邏輯解耦，整個架構統一一套驗證規則語言`，支援 Kubernetes / Envoy / Terraform (決定用戶是否能用 tf 調整某種資源) / Kafka 等，也開放 HTTP API 所以應用程式層也可以使用，另外也有提供 Golang Libary 與 WASM 可以整合

流程大概是
![](/posts/2023/img/0128/opa-service.svg)
1. Client 發出請求
2. OPA agent 根據請求找到對應的 policy (用 rego 語言撰寫)，結合 data 判斷 client 是否有足夠權限

實際的 policy 制定如
```python
package httpapi.authz

# bob is alice's manager, and betty is charlie's.
subordinates := {"alice": [], "charlie": [], "bob": ["alice"], "betty": ["charlie"]}

default allow := false

# Allow users to get their own salaries.
allow {
    input.method == "GET"
    input.path == ["finance", "salary", input.user]
}

# Allow managers to get their subordinates' salaries.
allow {
    some username
    input.method == "GET"
    input.path = ["finance", "salary", username]
    subordinates[input.user][_] == username
}
```
請求類似於
```py
input_dict = {  # create input to hand to OPA
    "input": {
        "user": http_api_user,
        "path": http_api_path_list, # Ex: ["finance", "salary", "alice"]
        "method": request.method  # HTTP verb, e.g. GET, POST, PUT, ...
    }
}
# ask OPA for a policy decision
# (in reality OPA URL would be constructed from environment)
rsp = requests.post("http://127.0.0.1:8181/v1/data/httpapi/authz", json=input_dict)
if rsp.json()["allow"]:
```

data 部份不一定要寫死，而是可以從外部的 DB 撈取或是擷取 request 中的 jwt token，參考 [External Data](https://www.openpolicyagent.org/docs/latest/external-data/)，算是蠻有彈性的

以上的機制是聽到 Netflix 的分享 [How Netflix Is Solving Authorization Across Their Cloud [I] - Manish Mehta & Torin Sandall, Netflix](https://www.youtube.com/watch?v=R6tUNpRpdnY&list=WL&index=18)

## 總結
驗證比我想像中的複雜許多，Google 設計了 Zanzibar / Netflix 部分採用的 Open Policy Agent 機制，前者針對負責的巢狀規則與極大規模的驗證需求、後者則針對 Cloud Native 環境統一了架構層的驗證規則