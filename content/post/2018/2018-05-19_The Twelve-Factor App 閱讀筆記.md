---
title: The Twelve-Factor App 閱讀筆記
description: >-
  The Twelve-Factor App 是由一群有豐富經驗的工程師，整理開發一個Web應用程式(或是所謂的SAAS
  software-as-a-service)開發方針
date: '2018-05-19T07:02:08.523Z'
categories: ['系統架構']
keywords: []
---

[**The Twelve-Factor App**](https://12factor.net) 是由一群有豐富經驗的工程師，整理開發一個Web應用程式(或是所謂的SAAS software-as-a-service)開發方針，基於以下幾個方向

1.  設定明確，降低新人加入專案的上手成本
2.  最大化可移植性
3.  適合部署到雲端平台
4.  降低開發與部署的差異性，增加持續部署的敏捷
5.  容易擴展(scale up)

基於上述幾個要點，整理成12項要素，而符合這 12要素的應用程式則稱為**twelve-factor app (後文會採用此名詞)**，瀏覽過後蠻有趣的，稍微摘要並提出自己在實踐上的想法(主要是Nodejs，作者看來比較愛用Python當範例)。

為避免歧義或英文水準不佳，有些關鍵字會中英夾雜，或是直接顯示英文單字。

## 1\. Codebase

#### 用版本控制工具管理一份Codebase，但可以有多份部署 (One codebase tracked in revision control, many deploys)

原始碼必須使用版本控制工具，如 [Git](http://git-scm.com/) / [Subversion](http://subversion.apache.org/) / [Mercurial](https://www.mercurial-scm.org/)，每份APP只能有一個Code Repo，但可以有一份Code Repo可以執行多份且版本不一樣的部署 Deploy；

## 2\. Dependencies

#### 命確定義與隔離相依(Explicitly declare and isolate dependencies)

許多語言程式都有對應的函式庫(library)管理工具，例如Ruby有Rubygems、Perl有CPAN、NodeJS有NPM(或Yarn)，在安裝上有系統層級或是被侷限於專案目錄下(又稱 bundling / Vendoring)

一個正確的應用程式「不應該依賴系統層級的函式庫」，應該要在宣告文件明確的宣告所有依賴的函式庫；  
並確保函式庫不會影響全域環境，並維持隔離。例如NPM在專案目錄下的 `package.json` ，預設安裝也是在該專案目錄下的 `node_modules` 中。

明確定義的好處是對新人友善，只要瀏覽宣告文件就可以得知所有相依的函式庫，而且通常函式庫管理工具都有自動安裝的指令，如 `npm install`

另外專案也不隱式依賴系統工具，例如 `curl` 、`ImageMagick` 等，因爲即便這些工具在大多系統都存在，但不能保證應用程式運行的環境有安裝；  
如果需要，則考慮將系統工具也打包進應用程式中。

## 3\. Config

#### 將設定儲存於環境中(Store config in the environment)

config是那些會依據部署環境而有所不同的資料，例如資料庫連線資料/ AmazonS3等外部服務的機敏資料 / hostname等，所以也不會放入版本控制工具追蹤。

必須注意，程式碼與設定檔「**必須嚴格分離」，**程式碼是所有部署都同一份，並且不應該包含任何機敏資料。

許多程式語言本身有偏好的設定文件格式，如 xml / yml / json 等，為了方便最好是使用儲存於環境變數中。

此外，環境變數應該是每個環境獨立於彼此，所以不需要像 Rails用 “production” / “test”/ “development” 在細拆定義環境變數。

\>> 但這裏比較tricky的是公司專案 stage / prod都是跑在同一台機器上，沒辦法用環境變數，都是採用 config.js 當作設定文件

## 4\. Backing services

#### 將支援服務當作附加的資源(Treat backing services as attached resources)

這裡的Backing services泛指應用程式相依的外部服務，例如資料庫、寄信服務商、快取資料庫等

**twelve-factor app** 應該是可以在抽換外部支援服務而不需要更動程式碼，只需要改變設定檔並重啟而已；  
例如說將資料庫從本機端的MySQL替換成雲端 Amazon RDS。

## 5\. Build, release, run

#### 嚴格區分建制與執行步驟(Strictly separate build and run stages)

當原始碼要轉換成部署的程序時，會經過三個步驟  
1\. 建置 build：  
 將程式碼轉換成可執行的包裹(Bundle)，這步驟會抓取外部相依的函式庫並編譯二進制檔案等。  
2\. 發布 release：  
將build好的可執行包裹，並結合該部署環境的設定檔  
3\. 執行 run：  
執行release階段打包好的程式。

每份release都必須有特定的編號，不論是日期格式 `2011–04–06–20:32:17` 抑或是遞增版好 `v100` ，方便後續有問題可以回滾。  
此外當發布release後不能有任何更動，只能透過發布新的release。

`建置階段`通常是當工程師覺得有新的程式碼更動需要部署，則主動觸發的，所以在建置階段可以執行相對複雜的指令與操作，當發生錯誤時還可以有工程師手動修復；  
但相對在`執行階段`，可能是自動化執行如應用崩潰後自動重啟，所以在執行階段應該要越簡潔越好。

## 6\. Processes

#### 執行無狀態的單執行緒或多執行緒(Execute the app as one or more stateless processes)

一個應用程式可能有單個或多個執行緒，**twelve-factor app** 應該是`stateless`且 `share-nothing` ，需要長期保存的資料可以放在外部服務如資料庫或CDN中

程序的記憶體或是檔案系統只能當作暫時的操作空間，例如下載檔案、操作、接著將結果儲存於資料庫中，應用程式應該確保被暫存在快取與檔案系統的資料在未來不會被用上；  
因為在多執行緒下，未知的請求可能被不同的執行緒所執行，即使是單執行緒程式當系統崩潰時快取跟檔案系統的資料都可能消失。

有些應用程式會採用 `sticky-session` 確保同一個用戶被同一個執行緒所服務，這是違反規範的。  
有時效性的暫存狀態資料(如session)可以放在像Redis / Memcached這類的資料庫中。

## 7\. Port binding

#### 透過綁定埠口對外開放服務(Export services via port binding)

應用程式有些時候被執行在其他容器中，例如 PHP服務可能執行於 [Apache HTTPD](http://httpd.apache.org/) / Java服務 執行於 [Tomcat](http://tomcat.apache.org/)下，但是 **twelve-factor app** 應該是服務直接綁定埠口並處理請求。

這通常都有函示庫可以支援，例如 python的 [Tornado](http://www.tornadoweb.org/) / Ruby 的 [Thin](http://code.macournoyer.com/thin/) 等，這使得整份應用程式都是在 user-space執行，且全部包含在原始碼中。

HTTP只是其中一個可以綁定埠口的協定，其他像是 XMPP / Redis Protocol 等服務都需參照此規範。

## 8\. Concurrency

#### 透過執行緒模型擴展(Scale out via the process model)

應用程式在執行緒管理上有多種方式，例如 Apache 會在收到請求時開一隻新的子執行緒(Process)跑 php應用，而Java則是透過JVM先保留一大塊CPU/Memory資源接著透過內部分配線程(Thread)達到並行效果。

在 **twelve-factor app** 中，執行緒是第一公民，開發者可以決定由哪一個執行緒跑任務，例如 HTTP請求執行在 Web執行緒上 / 背景服務則跑在 Worker執行緒上

看說明作者舉 [Foreman](http://blog.daviddollar.org/2011/05/06/introducing-foreman.html) 當做例子(下圖輔助說明)，這樣的好處是重要的任務可以分配較多的資源

![](/post/img/0__jvIkj4Cf__DgPZRRt.png)

但這並不排除執行緒內部多工處理、VM內部處理線程分配、又或是像 非同步/事件觸發的NodeJS，但是單一VM能夠容量有限，應用程式須可拓展多個執行緒到多台實體主機上。

這樣的設計在需要水平擴展時會大放異彩，share-nothing / 可水平拆分的執行緒在增加更多並行(Concurrency)時十分地簡單。  
在 `pm2` 同樣可以做到同樣的事情。

最後一段提到，**twelve-factor app** [should never daemonize](http://dustin.github.com/2010/02/28/running-processes.html) or write PID files. Instead, rely on the operating system’s process manager (such as [systemd](https://www.freedesktop.org/wiki/Software/systemd/), a distributed process manager on a cloud platform, or a tool like [Foreman](http://blog.daviddollar.org/2011/05/06/introducing-foreman.html) in development)

技術名詞太多直接貼原文，追蹤完相關內文連結大致上想要說明「應用程式應該管好開發應用程式就好，其餘的執行交給工具即可」  
也就是 `KISS(Keep it simple, stupid)` 的設計理念。

daemon是處於背景、不予用戶互動的執行程式，其父進程為 init (在 linux 中為系統啟動後第一個進程，PID編號為1)，init會一直存在到電腦關機為止；  
當有任何父進程先行關閉而子進程仍然執行時，init會轉為這些子進程的父進程，所以常見啟動daemon作法也都是在父進程 fork出子進程後退出，此時子進程就是daemon process了。

參考 Nodejs Daemon 函式庫就是此作法，用 child_process.spawn 關閉 stdin 並重導 stdout / stderr 與其他設定，另開新的進程。

[**indexzero/daemon.node**](https://github.com/indexzero/daemon.node/blob/master/index.js)

## 9\. Disposability

#### 快速啟動+優雅關閉=>增強程式可靠性 (Maximize robustness with fast startup and graceful shutdown)

應用程式應該盡可能降低啟動時間，這樣才可以在快速擴展 / 修改設定時快速啟用服務；  
當應用程式收到[**SIGTERM**](http://en.wikipedia.org/wiki/SIGTERM)訊號時，應當優雅的關閉，也就是停止處理新的請求並將現有的請求處理完成才退出。

應用程式需要處理非預警的關閉，例如硬體壞掉等，這時候最好有可靠的queueing backend 例如Beanstalkd，當應用程式終止或超時可以自動將任務重新返回 queue中。

## 10\. Dev/prod parity

#### 盡可能保持環境一致 (Keep development, staging, and production as similar as possible)

因為一些歷史緣由，開發環境與正式環境可能有幾種差異存在  
1\. 時間：開發環境可能持續開發了數天到數個月才同步到正式環境  
2\. 人：開發工程師負責開發，而維運工程師部署到正式環境  
3\. 工具：本地端可能用SQLite 而 正式環境則用 MySQL

**twelve-factor app** 則是要縮短上面的差距  
1\. 縮短時間：開發到部署在數小時甚至數分鐘之間  
2\. 人：開發者應該緊密的參與正式環境部署  
3\. 工具：盡可能用同樣的工具鍊

環境宣告工具如 [Chef](http://www.opscode.com/chef/) / [Puppet](http://docs.puppetlabs.com/) 結合輕量的虛擬化環境工具如 [Docker](https://www.docker.com/) / [Vagrant](http://vagrantup.com/) 可以大幅同步開發與正式環境。

## 11\. Logs

#### 用串流處理Log( Treat logs as event streams)

**twelve-factor app** 本身不應該去管理或煩惱 Log應該要儲存在哪裡，執行中的程式應當直接輸出到 `stdout` ，在本地開發上工程師可以直接在終端機介面看到所有的打印訊息；  
而在正式環境上，Log應該被執行環境處理，彙整所有的Log到不同的地方儲存或是到[Hadoop/Hive](http://hive.apache.org/) 做更進一步的資料處理，有開源工具可以使用如 [Logplex](https://github.com/heroku/logplex) / [Fluentd](https://github.com/fluent/fluentd)，值得注意是應用程式本身不知道Log其他設定。

在Nodejs開發中，`pm2` 有提供基本的Log，但如果要更進階的處理就還是要用 `bunyan` / `winston` Log 函式庫，但這就會違反原則，因為變成是應用程式要自己處理Log的部分。  
除非自己另外開發一套直接接 stdout / stderr 的串流工具(好像可以試試看?!)。

## 12\. Admin processes

#### 執行一次性管理任務 (Run admin/management tasks as one-off processes)

一次性的管理任務如 資料庫Schema更動 / 特定任務腳本 / 使用REPL執行任意的程式碼等，這些一次性的管理任務應當一同放入版本控制，並與應用程式使用相同的工具鍊與設定檔。

==========

以上只是個人的濃縮總結，有興趣可以看原資料網站。