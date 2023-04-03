---
title: 'Infrusture as Code 挑戰賽 - Hashicorp 工具鏈全教學'
description: 
date: '2020-04-12T02:21:40.869Z'
categories: ['雲端與系統架構']
keywords: ['Infrastucure as Code', 'Hashicorp', '技術教學']
---

最近開始接觸 DevOps 與 Infrasture as Code 的概念，深深被用程式碼管理部署流程與架構設計感到著迷，對工程師來說最棒的文件莫過於結構清晰、沒有重複冗余的乾淨程式碼，尤其是把過往透過人工操作的不穩定性一切攤開在陽光下用 Code Review 方式檢視每一個環節，讓程式碼從出生到部署都可以完整地被檢視；  
再者在 Cloud-Native 時代，能夠跨區域部署、甚至混合雲部署能夠讓公司的性能與成本上獲得更大的彈性  

只是在學習過程中，被一堆技術工具轟炸，每個工具之間又有些重複又不怎麼相同的功能，又或是抽象畫層級不同 (Container vs VM)，像是 Chef / Ansible / Terraform / Kubernetes / Docker 等等，每次東學一些西學一些總是一個頭兩個大，最近看了來自 Hashicorp 的介紹影片以及一篇文章整理，覺得在觀念上更加的融會貫通，至少更清楚知道 `部署的流程` 與對應的工具應用    

{{<youtube wyRtz_tdJes>}}


[Why we use Terraform and not Chef, Puppet, Ansible, SaltStack, or CloudFormation](https://blog.gruntwork.io/why-we-use-terraform-and-not-chef-puppet-ansible-saltstack-or-cloudformation-7989dad2865c)  

簡單總結一下上面兩個參考資料的想法  
## Application Delivery with HashiCorp 
當在開發應用程式時，要正確地交付到用戶手中有一段路要走，主要分成幾個階段
### 1. Write 本地開發   
   在本地端開發時，開發者會需要有跟正式環境類似的配置，例如資料庫等，這時候可以用 `Vagrant` 建制開發環境
### 2. Test 測試  
   進行測試時也需要一個乾淨、獨立、與正式環境接近的配置，同樣能用 `Vagrant`
### 3. Package 打包應用程式
   當程式碼測試完，要準備部署時，還需要把設定檔、環境變數等一併打包變成一個可部署的最小單元，此時能用 `Packer` 依據不同環境(AWS/GCP...)打包出 Image
### 4. Provision (Day1/Day2+) 機器的環境設定  
   應用程式需要完整的架構設計，例如說 CDN / DNS / Networking / Firewall / Storage System 等等，這時候可以用 `Terraform` 配置 dev/stage/prod 環境  
### 5. Deploy 部署方式 (Orchestration)
   部署方式常見有 Canary / Blue-Green 等，又或是遇到流量起伏時的 Auto-Scaling，可以用 `Nomand`，將 Dev 跟 Ops 獨立拆分，Dev 只需要專注在需要的運算資源、部署流程的掌握，Ops 則負責底層的機器配置、數量管控、機器的安全性補丁等
### 6. Monitor 監控  
   Hashicorp 目前沒有直接相關的產品，但有提供 `Consul`，如果是採用 Microservice / SOA 架構，內部服務間如何發現彼此需要內部的 DNS處理 / 機器要怎麼管理 config 都是個問題，Consul 透過 Key/Store 儲存解決這類的問題
### 7. Security!
另一個不再流程中但開發者需時時牢記在心 `Security`，一般來說 key 會在打包階段被一並放進，但是這樣相對不太安全，`Vault` 提供key 自動 rotate / 中心化管理 credential / 中心化處理加解密過程，降低機器被攻陷後的影響與更快速彈性的替換 key，增加安全性保證  

以上工具都能夠整合 VM / Container based 的環境，也有許多不同的替代方案；  
例如 Docker 可以單獨吃掉 Write/Test/Package 的功能，K8S 則負責 Deploy 與 Monitoring，如果是託管於 Cloud 則由 Cloud 負責 部分Provision的功能(如 Load Balancer，但不會自動設定 Public DNS 或 S3 這類架構)   

其中 `Nomand` 跟 K8S 比較是互補的工具，Hashicorp 提到 K8s 上手學習曲線太高，很多時候我們不一定要這麼複雜但強大的工具，如果原本是 VM based 架構那用 Nomand 管理部署會輕鬆、直觀很多   

## Why we use Terraform and not Chef, Puppet, Ansible, SaltStack, or CloudFormation  
這篇的作者非常厲害，之前拜讀了全部的 Terraform 教學個人覺得比官網更實在，這一篇文章含金量一樣超高，從更高層級的角度看這類型的工具，**Chef, Puppet, Ansible, SaltStack** 主要是做 `Configuration management`，也就是一台乾淨的機器啟動後要做什麼配置，例如 API Server 需要安裝 program runtime 並部署程式碼 / DB server 要安裝 DB 並搭配安全性配置等等  

而 Terraform / CloudFormation 是 `Provision`，是配置整個架構，所以兩者的討論面向不同，雖然像 Ansible 也能做一些 Provision 工作，但相較就不適合  

接著是 `Mutable / Immutable` 的問題，Chef/Ansible 等工具在產生配置變化時會在同一台機器發生，也就是 Mutable，當累積的變化變多時可能會有配置衝突的問題；  
如果是用 Terrform 搭配 Packer/Docker 等，每次都會產生新的機器，所以是 Immutable，行為相對比較單純且可預測  

接著作者還從語法上、管理上、社群大小做了比對。  

技術層面上可以做不同混搭，例如 Terraform + Ansible，配置好架構後用 Ansible 管理每一台機器的設定； 
又或是 Terraform + Packer + Docker + Kubernetes，一樣架構配置好且機器的 Image 預設都裝有 Docker 與 K8s agent，後續用 K8s 管理部署的流程  

## 實作
看完對於整個部署流程與工具更加的理解了，此時當然要挑戰自己動手搭建整個環境，以 API Server + DB 的架構去挑戰 Hashicorp 全套工具鍊，希望用一個月左右時間完成，以下是完整的教學記錄，希望能夠幫助到大家  

[Vagrant 教學-一鍵啟動配置開發環境](https://yuanchieh.page/posts/2020-04-12_vagrant-%E6%95%99%E5%AD%B8-%E4%B8%80%E9%8D%B5%E5%95%9F%E5%8B%95%E9%85%8D%E7%BD%AE%E9%96%8B%E7%99%BC%E7%92%B0%E5%A2%83/)   
[Packer 教學- 打造 Image](https://yuanchieh.page/posts/2020-04-15_packer-%E6%95%99%E5%AD%B8-%E6%89%93%E9%80%A0-image-copy/)    
[Vault 教學-集中化管理機敏資料 (上)](https://yuanchieh.page/posts/2020-04-20_vault-%E6%95%99%E5%AD%B8-%E9%9B%86%E4%B8%AD%E5%8C%96%E7%AE%A1%E7%90%86%E6%A9%9F%E6%95%8F%E8%B3%87%E6%96%99-%E4%B8%8A/)
...待續


