---
title: AWS-CDK教學 — Infrastructore As Code 用程式碼管理架構
description: '最近陸陸續續在看 AWS re:invent 2018 的影片，主要專注於 CI/CD這一部分，以下內容主要出自於，不得不說看完真的是非常振奮人心啊！'
date: '2019-01-27T03:29:50.283Z'
categories: ['雲端與系統架構']
keywords: []

  
---

最近陸陸續續在看 AWS re:invent 2018 的影片，主要專注於 CI/CD部分，不得不說看完真的是非常振奮人心啊！

以往在做架構設計，可能是先畫個架構圖，接著打開網頁登入 AWS Console，看要開幾台 EC2 、VPC 架構、 ALB 設定、CDN 設定、開 S3 Bucket 等等，基本上大多的事情都是透過網頁完成，或是使用 Command Line Tool 完成；  
但這樣的缺點是如果公司突然想要重建一份同樣的架構當作 staging 環境，又或是往後需要改動架構，此時必須自己同步文件、修改架構圖等等，在管理上有相當多不方便的地方。

## 為什麼不用程式碼來管理

這也就是這篇要分享的方法，使用 AWS-CDK，AWS-CDK 是一個 nodejs 的 package，安裝後當作 cli tool 使用；  
在 AWS-CDK 下提供各個 AWS 既有服務的套件(如 lambda 、 S3 等)，目前提供 C#、Javascript、Typescript、Java，開發時引入這些套件就可以使用了。

透過程式碼管理，我覺得有幾個好處

1.  更好的封裝與結構  
    如果是用網頁做設定，基本上行為只能透過文件來溝通，如果是用 shell script 或許也可以做到一部分的自動化，但整體理解上還有蠻多不方便之處，更別說維護的人寫法可能不同，造成維護的困難；  
    使用 AWS-CDK，他本身是用 OO 的概念封裝既有的 AWS 服務，官方也有提供工具幫助初始專案，也給予一定的程式碼架構建議，後人接手一定會好理解非常多
2.  版本控制  
    隨著公司發展，可能會更動架構，透過代碼管理工具可以協助良好管理架構的演進，Rollback 也可以有依據 (例如費用爆掉的時候…)
3.  跨區域部署  
    如果你想要跨區域部署同樣的架構，用網頁操作應該會非常頭痛，而且容易出現人工錯誤；  
    用程式碼就是多一行指定區域， DONE!

AWS-CDK 底層其實是將程式碼轉成 Cloud Formation，AWS 自定義的服務定義語法，可以理解成 AWS服務的 Assembly Code。

> ＊WARNING：目前發文時間 2019/01/27 還**不建議使用於正式環境**，但因為他底層是轉成 Cloud Formation，理論上轉換不出錯應該就蠻穩的，目前測試尚未遇到 Bug

在開始 Coding之前，建議使用 AWS-CDK 之前要先熟悉 AWS 服務，例如你想串 Lambda 建議先至少看過文件、用網頁版完整操作過一次，因為有很多參數實際用過才知道怎麼填寫，目前官方網站有良好的文件，但這些文件僅限於參數說明，如果沒實際用過不會知道參數設定後的實質意義與用途；  
另外目前我查了一下沒有太多實戰分享，只有一些基本的串接與操作，所以在服務間的串接蠻多是 Try-And-Error 玩出來的，也是我想寫這篇文章的目的，幫助大家上手。

本篇比較適合已經在使用 AWS 服務一段時間，希望可以用更好方式管理架構的工程師；  
後續會使用 Typescript 當作範例，不過概念都是一樣的。

最後再次提醒，因為還在 pre-release 階段，如果你發現以下程式碼有誤或無法執行，煩請留言。

### 安裝 AWS-CDK 與專案初始化

[**cdkworkshop.com**](https://cdkworkshop.com/15-prerequisites.html)

在開始之前，請確保完成官網的 prerequest 步驟

1.  安裝了 aws-cli
2.  完成 iam role 設定，實驗性質先開 admin 權限比較方便
3.  完成 aws configure
4.  安裝 Nodejs v8.12 以上
5.  安裝 aws-cdk， `npm install -g aws-cdk@0.22.0`

aws-cdk 主要提供幾個指令

```bash
// 用於初始化專案，可以指定語言  
$ cdk init 

// 查看目前所有的 stack (後續介紹什麼是 stack)  
$ cdk ls

// 查看目前程式碼轉換的 cloud formation  
$ cdk synth

// 查看目前架構的變動  
$ cdk diff

// 部署  
$ cdk deploy

// 初始化環境  
$ cdk bootstrap
```

目前我習慣使用 Typescript 開發，搭配 VSCode 有連好的自動提示非常方便。

### 實戰：部署 Scheduled Event 觸發 Lambda

Let’s write some code~   
這次做一個部署到多個區域，定期 2 分鐘去打 [https://www.president.gov.tw/](https://www.president.gov.tw/) 看台灣總統府頁面在全球的網頁回應速度，接著發訊息到 slack 頻道。

到專案目錄下，執行 `> cdk init app — language=typescript`

接著同個目錄下，我們需要開兩個 shell，一個 shell 執行 `> npm run watch` ，主要是為了自動轉譯 typescript 成 javascript 才可以讓 nodejs 執行；  
另一個 shell 用來執行後續的 cmd。

在目錄下會有常見的 nodejs 專案檔案，有兩個資料夾比較重要 /bin 、 /lib；

`/lib` 主要是放架構定義，初始化之後會有一個 aws-cdk-stack.ts，在 AWS-CDK中， `stack` 代表的就是一個架構的 class，例如說目前要設計的架構就是 (scheduled event + lambda)，這就是一個小型的架構；  
後續可以讓小架構組合成大架構，就看需求決定如何封裝。

`/bin` 主要是放 `app`，也就是最終架構的檔案，主要是整合Stack 初始化與部屬的方式，定義在 aws-cdk.ts 之中。

#### aws-cdk-stack.ts

是不是比想像中的清晰簡單啊，載入對應模組宣告即可，而且 lambda 可以參照本地端的資料夾，自動幫忙打包與部署超方便的；  
另外 aws-cdk 文件一個好處是都有把對應的參數文件對照好，所以查起來蠻快的，但是參數量非常大 …..

Stack 在初始化需要綁定是在哪個 app下，以及獨立的 ID，這後續會再網頁中看到。

#### aws-cdk.ts

基本上就是初始化 Stack 並定義部署的區域，另外的 lambda 與 slack 就看 git repo 參考，不再贅述。

程式碼完成後，執行以下步驟

1.  檢查  
     `> cdk list` 查看App下的所有 Stack，接著針對各個 stack 下 `> cdk synth AwsCdkStack2` ，大概檢查有沒有 error 與 cloud formation 定義。
2.  部署  
     `> cdk deploy`   
    如果是第一次部署，他可能會跳出需要執行 `>cdk bootstrap {專案id/region}` 的錯誤，其他的話就等他慢慢部署；

cdk 部署時有良好的打印訊息，最棒的是 cdk 會自動處理 aws 服務 iam role 的權限，如果有處理過權限設定就知道這非常的頭痛 XD   
因為 AWS 服務切太細了，好處是可設定的非常精準，但缺點就是查找起來很頭痛，通常都要跑個幾次看錯誤log 補權限。

以下是網頁與 Slack 回應的截圖

lambda

![](/post/img/1__mn7RZtoPWTy33Xo9S1TdJg.jpeg)

Slack 訊息，看來歐洲回應時間最長，東北亞最快，結果是也不太意外 XD

![](/post/img/1__JQxsYZQ2OaTEoMSo3tbhMA.jpeg)

最後附上完整專案的 github

[**sj82516/aws-cdk-demo**](https://github.com/sj82516/aws-cdk-demo)

## 刪除 Stack

假設我想要移除美西的部署，**_不要直接從程式碼刪除Stack 重新 deploy_** ，我實測的結果這樣是不會幫你把東西刪掉的，要改用以下步驟

1.  `> cdk destroy AwsCdkStack`
2.  接著才從程式碼刪除

## 結語

在雲端服務中，AWS 不得不說是這個行業的領頭羊，而且就技術上個人覺得領先 GCP 不少，基礎服務不好說，但是在跨服務的整合上，AWS 做得非常良好，這或許才是企業用乎所在乎的未來，整套 solution 而不是單個單個服務還要自己慢慢整。

有了 AWS-CDK 要分享、重用架構就極度方便，之後再來做一系列基於 AWS-CDK 的 AWS 架構研究與分享。