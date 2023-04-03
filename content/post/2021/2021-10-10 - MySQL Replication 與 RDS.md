---
title: 'MySQL Replication 與 RDS'
description: 與同事某一天看到 RDS MySQL read replica 盡然可以 writable，覺得這也太神奇了，花了點時間理解 MySQL Replication，並實驗怎樣的更改會導致 replication 中斷
date: '2021-10-10T01:21:40.869Z'
categories: ['資料庫']
keywords: ['replication']
---
公司目前主要資料庫是 MySQL，為了資料分析有開啟新的 Read Replica 避免影響到正式環境，因為一些分析工具 (Metabase) 的限制，所以與同事在思考 `Read Replica 如果只同步指定的資料表，同時保留寫入其他資料表的彈性該有多好 ?!`，查了一下 RDS 發現這是可以的 [How can I perform write operations to my Amazon RDS for MariaDB or MySQL DB instance read replica?](https://aws.amazon.com/premiumsupport/knowledge-center/rds-read-replica/)，當時覺得十分的衝突，為什麼 "Read" Replica 可以 Write，也借此回到源頭理解 MySQL Replication 設定與機制，才發現這一切都是很合乎情理的

以下都是以 MySQL v5.7 為主
## MySQL Replication
閱讀過 [Chapter 16 Replication](https://dev.mysql.com/doc/refman/5.7/en/replication.html)，簡單整理幾個重點
1. Source DB / Replica DB 都要指定 server_id
2. Source DB 必須開啟 binlog，有三種格式可以選，後續補充
3. Replica DB 可以透過 `replication_do_table` 指定資料表同步
4. Replica DB 可以指定多個 Source DB
5. GTIDs 建議開啟，主要是幫助 binlog 的每一個操作都打上 id，方便確認同步進度；不開啟則是用 file 同步，需要紀錄同步的檔案名稱與位置，相對複雜些

binlog 會紀錄在 master 上的所有操作，而 replica 很單純就是拿到 binlog 把同樣的操作套用在自己身上，用這個角度思考，就可以理解為什麼 replica 同時保留寫入的功能很正常，只要不影響 master binlog 上的操作即可

### binlog format
#### 1. statement
binlog 直接紀錄 master 上 SQL 語句，所以 binlog 本身非常容易閱讀，在做系統操作檢查時，也可以很清楚看到每一個 SQL 操作 (audit)，好處是相對資料量小、好閱讀；缺點是有些 statement 是 undeterminsitic，也就是在 replica 上重新執行會有不同的結果，例如 UUID() / USER() 等一系列操作，有趣的是 RAND() / NOW() 這些看起來就是會有問題的反而不會有問題

#### 2. row
不紀錄每一個 SQL，而是把 SQL 會影響到的欄位以 Row 的格式紀錄，例如 UPDATE 更新了 10 筆欄位就紀錄 10 筆，好處是重新執行保證結果一致 / 壞處是資料量很大、格式不易閱讀需要工具 decode、沒辦法看到原始的 SQL

#### 3. mixed
結合 statement / row 的優點，只有遇上 undeterministic 的 statement 才會用 row 紀錄，這也是 RDS 預設的格式

## 實驗
完整實驗可以參考我的 Repo [play-with-mysql-replication](https://github.com/sj82516/play-with-mysql-replication)，主要驗證了
1. 不要在同步的資料庫新增資料，否則會終止同步
2. 在非同步的資料庫做任合操作都沒問題
3. 在同步的資料庫，增加 Index、增加新的欄位、`UPDATE 已經同步的資料`都沒問題
4. 如果是修改同步的資料庫欄位格式，例如 varchar(255) => varchar(200)，在不超過欄位尺寸下，statement 同步正常、row 不能同步

RDS 上行為類似，差別在預設就不能有 Multi Source 的功能

## 結語
使用託管服務如 RDS 代為管理 MySQL 蠻有趣的，大幅降低了管理的麻煩，但如果有什麼功能面的問題，回歸工具本身去探索反而可以看得更全面；  
不過 RDS 還有而外跟 Aurora 做結合，可以製作 Aurora Read Replica，不確定有沒有別的行為差異，之後有機會再來研究