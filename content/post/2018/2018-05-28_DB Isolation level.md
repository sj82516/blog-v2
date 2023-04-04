---
title: 資料庫 Isolation level 與實際應用情境處理
description: Transaction 交易機制，可以讓單一或多筆操作聚合為單一的原子性操作，一次性成功寫入或失敗回滾，避免資料庫出現資料不一致的狀況。
date: '2018-05-28T09:29:27.191Z'
categories: ['資料庫']
keywords: ['MySQL']
---

Transaction 交易機制，可以讓單一或多筆操作聚合為單一的原子性操作，一次性成功寫入或失敗回滾，避免資料庫出現資料不一致的狀況。

Isolation，關聯式資料庫的基本要素之一，描述當同時有多筆請求要讀寫同一筆資料時的處理狀況。

以下參考 《Designing Data-Intensive Application》第七章與

[**透過 Payment Service 與 DB Isolation Level 成為莫逆之交**](https://medium.com/@mz026/%E9%80%8F%E9%81%8E-payment-service-%E8%88%87-db-isolation-level-%E6%88%90%E7%82%BA%E8%8E%AB%E9%80%86%E4%B9%8B%E4%BA%A4-a2d035049038)

越高層級的Isolation提升資料的一致性，但也帶來效能上的損耗，以下整理實際應用邏輯與對應適合的 Isolation設計。

### Dirty Write

複寫其他尚未commit 的 transaction 更新。

### Dirty Read

讀取到其他Transaction 更新但尚未 commit 的值。

### Read Skew (Non Repeatable Read)

在同一個 transaction中，讀取的值會受到其他commit的 transaction 更新影響。

### Phantom Read

當其他transaction 插入或刪除資料，會影響同一 transaction中先後的讀取。

### Lost Update

![](/post/img/1__itWWv776OilCVdD0NghGUg.jpeg)

兩個Transaction都是走 `先讀取某值 -> 基於某值運算 -> 更新原資料` ，例如說購票流程，必須先檢查票種的剩餘票券，如果有剩就建立訂單並扣除名額。

這狀況如同 票券剛好剩一張，T1 / T2 同時讀取發現票券剛好為一，兩者都以為彼此可以買票，接著 T1 / T2 先後將票券數量改為零，雖然最後票券為零但 T1/T2卻分別消耗了兩次。

#### 解法

1.  將語法改成 `compare-and-set`，將原先讀取到的值帶回更新時的判斷式中合併成單一SQL，如 `Update ticket where ticket.num = 1` ，這樣較晚更新的 transaction就會更新不到失敗 rollback。
2.  在MySQL中使用 `select … for update` ，這是 exclusive row lock，當取得鎖後其他 transaction 如果要 `select lock in share mode` / `select ... for update` / `update` / `delete`都不能取得鎖，直到 commit；  
    從而避免並行讀取的錯誤。  
    (對比可以並行讀取的是 `select … for share` ，但同樣會排斥寫鎖)

使用 `select for update` 就可以避免 t2 在不知道 t1更新的情況下更新，因為 t2 的 `select for update` 必須等到 t1更新後才能讀取，解決 Lost update 問題

### Write Skew And Phantom

Write Skew是 Lost Update更廣泛地集合，同樣是讀取後修改，但Write Skew讀取與修改的對象可以是不同的(若相同則為 Lost Update)。

例如說：  
有張 會議室的表，上面記錄哪些會議室被佔用的時間紀錄如 (id1, from 12:00 to 13:00)，當 T1 / T2 同時想要預約同一間會議室同一個時段，在掃過兩者都以為沒有被佔用就插入新紀錄，結果就發生兩筆預約衝突。

又或是 遊戲暱稱不可重複，T1/T2掃過全部用戶名稱沒有發生重複，插入後才發現 T1/T2的值是重複的。

上面兩個範例是無法透過 Lost Update提供的解法，因為沒有一個特定的 row 可以去 lock。

整體上發生Write Skew的條件是  
1\. Select 某些資料  
2\. 依據上一步的資料做判斷  
3\. Update / Delete 一些資料  
Write Skew 就是發生於 2,3 步之間在重複第一動會發現Select結果是不一樣的，也就是phantom read 的出現。

#### 解法：

1.  使用 serializable isolation。  
    在MySQL Inno DB serializable中 ，select是用表級共享鎖，也就是 select 後其他 select還是可以用，但是全表不能插入更新等
2.  Materializing conflicts 具象化衝突  
    Write Skew是Lost Update的超集合，換言之如果可以將 Write Skew 問題降維成 Lost Update，就可以從 range lock 降為 row lock提升性能。

> 會產生 Write Skew 在於插入/刪除時沒有特定的鎖可以預先鎖住該行，換言之如果可以預先鎖到就可以避免問題。

例如說會議室資料，假設我們先將所有的會議室與時間表全部插入資料庫中，這樣當有 transaction 要預約會議室，就可以用 `select for update` 某行資料，就不會有其他人ˋ並行預約同一間同一個時段的會議室。  
但這不是萬用解，有些狀況不能預先窮舉所有可能。

這點在文章中，有個範例有用上Serializable， 退費使用ChargeRefund 一張表紀錄，而Order在另一張表，每次要產生退費時就必須先 讀取訂單相關的所有Refund計算額度，如果訂單還有足夠餘額才會創建新的 ChargeRefund 這時候符合Write Skew發生要素，所以他們是用 Serializable 去解；

我們網站是會將目前訂單退費餘額紀錄在Order上，所以只要透過select for udpate 去鎖該筆訂單就好，不需要用到 Serializable。

3\. 加入判別條件  
利用 Consistence 特性 同樣在會議室問題，如果創建個 unique cluster index (room_id, startAt, endAt) 或許就可以用關連式資料庫本身特性去解決，但同樣不是萬用解

有趣的是，Serializable 在 MySQL中不是真正的序列化執行 Transaction，他還是可以並行處理的，文件中有提到   
「This level is like [REPEATABLE READ](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html#isolevel_repeatable-read), but InnoDB implicitly converts all plain [SELECT](https://l.facebook.com/l.php?u=https%3A%2F%2Fdev.mysql.com%2Fdoc%2Frefman%2F8.0%2Fen%2Fselect.html&h=ATOC4ffs6BKSHXBCJcrGevajNQd1g1s7qYsAzfsfTGRFoGXhpjXyzEyFHF19205nddtzOVldg9awOjZll47FXPJlnfY7PURwsQuhbtePwESQX3OagGbirEKa8zgg8CavRkrBQ0g8N8w) statements to [SELECT … FOR SHARE](https://l.facebook.com/l.php?u=https%3A%2F%2Fdev.mysql.com%2Fdoc%2Frefman%2F8.0%2Fen%2Fselect.html&h=ATNwi30GW1C8dJO6U-XEOj-Q557fHQWkGXKkDFZ6yWph7SMPBiVlJ0QKCFJ29k47XhsMI_UQyWDc9YPC-q95T1rMQEkMjkSA9EZnnTc6xuDMa1103rYbhLpEvN-_hGHDjL0735wh6luiAV2wdsIyY4kW) if [autocommit](https://l.facebook.com/l.php?u=https%3A%2F%2Fdev.mysql.com%2Fdoc%2Frefman%2F8.0%2Fen%2Fserver-system-variables.html%23sysvar_autocommit&h=ATMitbTaqVv4e7wb_690adrkhYA2FCc7KajjshqR_sU4mUUhp3xQ_Zwsxt8-cUaYdtUB-DW4y2HCSubCiiyJ-vSsiscL6D20NMmi3DmIfjWj_KijnMrUmkCJKRVHWId1NBHX7I81MIo) is disabled.」

所以要避免 Write Skew，還是要去思考要鎖多少區間，或是鎖整張表，單單改成 Serializable是沒辦法解決問題的

在 MySQL InnoDB中，select for update / select lock in share mode 在 Repeatable Read下，會加上 Next Key Lock，Next Key Lock等同於 row lock 加上 gap lock，gap則是根據 index 拆分區段，進而可以分區鎖定，阻擋幻讀的發生； 而select for update 在沒有 where 條件下基本上就等同於table lock。

在研究過程中，有文章提到 SQL Standard 對於 isolation level定義模糊，各家資料庫的實作也略有差異，所以相對於採用預設的 isolation level，實際了解 locking 機制比較實在。

### 總結：

在書中有提到 SQL標準對於 isolation level的定義是不太明確的，導致各個資料庫都會定義各自的isolation level，而且都會有些微的差異；

所以與其盲目的去使用常見的四種 isolation level，更重要的事針對業務邏輯去分析到底 concurrency 發生的狀況以及如何防止 race condition。