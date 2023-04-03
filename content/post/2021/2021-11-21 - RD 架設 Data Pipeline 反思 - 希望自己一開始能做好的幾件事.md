---
title: 'RD 架設 Data Pipeline 反思 - 希望自己一開始能做好的幾件事'
description: 
date: '2021-11-21T01:21:40.869Z'
categories: ['資料庫']
keywords: ['Data Pipeline', 'BigQuery']
draft: true
---
近日跟同事從零開始建立公司的 Data Pipeline，同事有些經驗但我完全沒有，也不熟 Python 與資料運算的套件如 Pandas，所以在沒有太多經驗下只能且戰且走，這幾週花很多時間在學習、試錯，稍微沉澱一下，主要會集中在專案的成本 (人力為主)與工具的取捨，希望可以給大家不同面向的經驗

## 架構
![]()

## BI 工具
一開始 BI 選定了 [Metabase](https://www.metabase.com/) 開源的 BI 工具，以開源的角度它的功能已經很不錯了，可以解決
1. 圖形化操作：將 SQL 步驟用 GUI 包裝，讓對於 SQL 陌生的同事也能簡單拉報表
2. 圖表功能：有很多圖表功能，基本的折線圖、條狀圖、圓餅圖都有，而且有累積的功能不用自己用 SQL 刻
3. 變數與儀表板：可以用儀表板匯聚多個查詢，且支援 `變數`，可以改變時間區間、參數等動態查詢
4. 權限管理：針對不同的團隊開放不同的 Data Source 權限，雖然只能針對 Database (Schema) 全開或全關，但還算夠用

整體上，如果公司沒有專職的 Data Team，那 Metabase 會是一個蠻好的選擇，節省很大量 RD 開發與繪製報表的時間

## 為什麼需要 Data Pipeline
當初 PM 規劃的目的為
1. 匯聚外部資料：透過統一的儀錶板方便分析與閱讀，例如 FB Ads、Google Ads、GA 等外部資料
2. 自動偵測異常：透過時間區間內的標準差，分析當前指標是否異常

最一開始的資料儲存是 read only MySQL Replica，資料量整體也不大 (30 GB 上下) 還有很多可以調教或壓榨的效能空間，但最終還是決定將資料搬移到 BigQuery 上，主要考量
1. 查詢效能：要調教 MySQL 相對比較費時，BigQuery 儲存跟查詢效能都極佳，不容易遇上貧頸
2. 擴充性：BigQuery 生態很良好，SDK 也支援多種資料格式，寫入資料相當方便
3. SQL 彈性：目前資料庫還在 5.7，SQL 語法支援度很差

最後決定的第一版架構也很簡單，也就是自己用 ETL Job 搬移跟清理資料後寫入 BigQuery，ETL Job 先採用 EKS Cronjob 方式執行

## 資料彙整
第一步要先把原本的數據都彙整到資料倉儲，程式語言很快就選定 Python，一方面是資料處理的龍頭語言一方面也是團隊熟悉，後續的工具鏈就以 Python 為考量，因為資料量也不大所以就不考慮市面上的商用方案

ETL 我們一開始選用 [Singer](https://www.singer.io/)，說是 ETL 到比較像 EL 沒有 T，Singer 拆成兩部分 Tap / Target，也就是 `資料源->資料倉儲`，選擇原因是
1. Python 開發
2. 該支援的都有套件：FB / Google 廣告、GA、MySQL、BigQuery都有支援

後來基於這一套開發，以下稍微分享使用的過程
### Fulltable 與 Incremental
Fulltable 是指需要把資料倉儲的對應儲存移除並重新同步，Incremental 是持續新增紀錄

在很多 ETL 工具也都會看到類似的兩種模式，主要是因應`資料源的資料會不會被改動`，不會改動的資料如 log，寫入後就不會再去改動，資料源只會一直新增 (append) 紀錄，所以寫入資料倉儲時可以很放心的一直寫

但如果今天資料同步後還會被修改、甚至刪除，例如說 users 儲存使用者，今天用戶 11/20 註冊，11/21 修改名稱，通常我們會是直接在同一筆欄位中修改資料，這是很正常的 RD 開發操作，但對於資料 log 就很頭疼，因為 11/20 備份到資料倉儲 11/21 資料又被改變了

這部分可以拆成三種情況考量
#### 1. 資料不會改動
同步時，只需要紀錄當前同步的位置，下次就從這個點往後新增資料，可以用 Incremental
#### 2. 資料會被更新
假設用戶有上千萬筆，真正會改變的只有幾萬筆，每次都移除重新同步會非常浪費，可以透過 updated_at 搭配 Incremental，只同步有更新的資料，最後資料倉儲可以透過 View Table select row_number = 1 最新一筆資料排除重複，參考 [Retrieving the last record in each group](https://stackoverflow.com/questions/1313120/retrieving-the-last-record-in-each-group-mysql)
```sql
WITH ranked_messages AS (
  SELECT m.*, ROW_NUMBER() OVER (PARTITION BY name ORDER BY id DESC) AS rn
  FROM messages AS m
)
SELECT * FROM ranked_messages WHERE rn = 1;
```
#### 3. 資料會被刪除
如果是硬刪除 (欄位會消失)則只能用 Fulltable，每次都要砍掉 Table 然後重新建立，軟刪除可以視為 update

> 回歸 RD 本位，在設計資料庫時，要記得加上 created_at / 更新時調整 updated_at / 刪除盡量用軟刪除 對於後續的資料維護會方便很多，更勝者有 [Event Sourcing](https://docs.microsoft.com/zh-tw/azure/architecture/patterns/event-sourcing) 用事件的概念儲存

### 檢查原始碼
因為資料儲存比較敏感，加上不確定實作擔心會不會有記憶體等其他因素問題，所以有花一點時間掃過程式碼

資料源是從 MySQL，檢查了 [singer-mysql](https://github.com/singer-io/tap-mysql)，可以支援多個模式、透過 iterator 讀取欄位、設定讀取上限等

檢查時發現 [singer-bigquery 會額外送資料](https://github.com/RealSelf/target-bigquery/blob/a30ec3198081b97d820b33d10d8743e63b00ddea/target_bigquery.py#L286)，也沒有什麼機密只是送自己的版號，但是 http client 本身的資訊如 ip 等就會被蒐集，運行時還會卡住，最終 clone 一份移除這段程式碼

#### 缺點
Singer 缺點有
1. 需要額外的整合：singer-mysql 可以主動 scan DB schema，但是預設都是不選，需要額外挑選需要的欄位，如果大多數的欄位都需要就比較費時
2. 不容易整合：這邊是指 Singer 本身為 CLI 工具，所以沒有提供 Python module 的方式可以 import，包含讀取 config 也都是從指令參數取得而無法用 function 參數
3. 文件不足：很多 config 都沒有寫在 readme 上，需要看程式碼去推敲，所幸程式也不複雜
4. 維護度不高：看起來維護性跟社群熱度都不高，是另一個隱憂
5. `效能不好`：第一次要倒資料庫資料約 15 GB，跑了一個小時還沒跑

後來同事選用 [embulk](https://www.embulk.org/docs/index.html) 很快就倒完資料

### 小結
跟同事花了約 10 個工作天完成第一步的同步資料處理，把 FB / Google Ads / MySQL 資料同步到 BigQuery

Singer 還堪用，自己改還算改得動，如果單純倒資料可以參考 Embulk 效能好很多

------

## 資料架構
目前資料倉儲已經有最基本的原始資料，並開始篩選、彙整出具有商業價值的數據，建議這一階段先規劃出架構圖，確認每一層數據的目的與意義

通常來說都會面臨幾個需求
1. 基本數據：每小時、每日、每週的活躍用戶數，可能會再細部分群
2. 同時期的銷售比對：今天 11/20 11:00 ~ 12:00 比對 11/19 的同期，銷售狀況是否正常
#### 1. 獨立儲存紀錄
以活躍用戶為例，資料面可能是 Table users 中一個欄位 is_active 代表，好一點有另外的 user_active_logs 紀錄活躍與不活躍的時間，但這在後續要 aggregate 每小時的活躍用戶都非常痛苦，尤其是前者欄位修改後就無法歸因，所以會需要每小時掃描時就紀錄當時活躍的用戶

如果是用 BigQuery，我當初第一直覺是看到有 Array，那我用 Array 儲存同一時間的 user_ids 好像不錯，如
```bash
recorded_at, active_user_ids
12:00, [1, 2, 3,]......
```
但這問題會很多，例如今天 PM 要求一天內的不重複活躍用戶，Array 需要合併、去重相當麻煩，建議還是單筆儲存如
```bash
recorded_at, active_user_id
12:00, 1
12:00, 2
```
跟 SQL 整合也比較好

> 跟同事 V 大請教時，他有提到要`研究平台本身的特性`，如 BigQuery 的計價模式儲存成本很低，應該優先考量運算成本與維護性

#### 2. 用 Script 做 ETL 而不要用 BigQuery Scheduled Query
1. 如果任務有相依性
2. 如果資料要回補
3. 注意時區問題

#### 3. 嘗試用 ELT
ELT 是指先把資料寫到 BigQuery 再從 BigQuery 讀取資料做轉換，跟 ETL 相比的好處是 
1. BigQuery 效能好：先 Load 進去再重新做複雜讀取會比較快
2. BigQuery 支援 [INSERT SELECT](https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#insert_select_statement)：這真的很方便，先用 SQL Query 組合出需要的資料，接著加上 INSERT 就能寫入新的 Table 而且 Schema BigQuery 會搞定

## Workflow 管理
