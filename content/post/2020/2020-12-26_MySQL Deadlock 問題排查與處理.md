---
title: 'MySQL Deadlock 問題排查與處理'
description: 週末寫點簡單的 SQL 遇到了 Deadlock，才發現 foreign key 會有額外的 lock 效果導致 Deadlock，重新翻閱 MySQL 文件並分享排查過程
date: '2020-12-26T08:21:40.869Z'
categories: ['資料庫']
keywords: ['MySQL', 'Deadlock']
---

寫了一個簡單的購物流程 SQL，在一個 transaction 中執行
1. 讀取 product 資訊：`select * from product where id = 1`
2. 寫入新訂單 order 狀態: `insert into orders (product_id) values (1)`
3. 更新 product 販售狀態：`update product set sold=1 where id = 1`  
其中 order table 的 product_id 是引用 product table 的 id 當做 foriegn key，並在併發的情況下執行，開始偶然遇到 Deadlock   

```python
Error: update `products` set `sold` = 34 where `id` = '919' - Deadlock found when trying to get lock; try restarting transaction
```

當下覺得奇怪，第一印象中 Deadlock 只發生在兩個 Transaction 互相所需的欄位而無法釋放，如
1. T1: lock(r1) , wait(r2)
2. T2: lock(r2), wait(r1)  
但明明我就一種 SQL 併發執行，怎麼也會有 Deadlock  

以下開始排查原因
## MySQL Deadlock 說明
讓我們來看一下官方文件 [15.7.5 Deadlocks in InnoDB](https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks.html)

Deadlock 主要是多個 Transaction 手上握有對方需要的資源，在等待資源釋放的同時卻也不會釋放手上的資源，常發生在使用 update 卻順序剛好相反  
如果 Deadlock 數量很少不太需要擔心，應用程式記得 retry 就好，但如果發生很頻繁就要檢查 SQL 的狀況  

為了盡量減少 Deadlock 發生，可以檢查以下方式
1. 盡可能減少 Update / Delete 在單一 Transaction 中的數量
2. Lock 時請依照同樣的順序 (例如 select ... for update)
3. 降低 Lock 的層級，避免 lock tables 的操作
4. 警慎選擇 index，因為過多的 index 可能會造成 deadlock，後續會再展開描述
    > InnoDB uses automatic row-level locking. You can get `deadlocks even in the case of transactions that just insert or delete a single row`. That is because these operations are not really “atomic”; they automatically set `locks on the (possibly several) index records` of the row inserted or deleted.  
5. 考慮降低 isolation level，高層級的 `isolation level 會去改變 read 的操作`，例如 MySQL 中 `serializable 其實就是隱式把所有 select 都加上 lock for share`，引自於官方文件 [15.7.2.1 Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
   > This level is like REPEATABLE READ, but InnoDB implicitly converts all plain SELECT statements to SELECT ... FOR SHARE if autocommit is disabled.

Deadlock detection 預設是開啟，但如果在高流量下會有效能的影響，如果預期 Deadlock 狀況不多可以改透過 `innodb_deadlock_detect` 選項關閉，用 `innodb_lock_wait_timeout` 一直等不到 lock 發生 timeout 而觸發 rollback 取代  

MySQL 可以透過 SQL 指令 `> SHOW ENGINE INNODB STATUS` 看最後一筆發生 Deadlock 的原因，或是開啟 `innodb_print_all_deadlocks` 把每一次 Deadlock 原因都輸出到 error log 中   
開啟設定的 SQL 為 `> SET GLOBAL innodb_print_all_deadlocks=ON;`

## 具體的 Deadlock log
當在應用程式發現 deadlock 錯誤後，回到 MySQL 使用指令查看，得到以下原始 log
```md
=====================================
2020-12-26 00:10:16 0x7f9668490700 INNODB MONITOR OUTPUT
=====================================
Per second averages calculated from the last 29 seconds
-----------------
BACKGROUND THREAD
-----------------
....
----------
SEMAPHORES
----------
....
------------------------
LATEST DETECTED DEADLOCK
------------------------
2020-12-26 00:05:14 0x7f9657cf9700
*** (1) TRANSACTION:
TRANSACTION 14048, ACTIVE 1 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 11 lock struct(s), heap size 1136, 6 row lock(s), undo log entries 2
MySQL thread id 54, OS thread handle 140283242518272, query id 45840 172.22.0.1 api-server updating
update `products` set `sold` = 32 where `id` = '919'

*** (1) HOLDS THE LOCK(S):
RECORD LOCKS space id 3 page no 8 n bits 336 index PRIMARY of table `online-transaction`.`products` trx id 14048 lock mode S locks rec but not gap
Record lock, heap no 259 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 4; hex 00000397; asc     ;;
 1: len 6; hex 0000000036d7; asc     6 ;;
 2: len 7; hex 010000013f1e26; asc     ? &;;
 3: len 21; hex 50726163746963616c204672657368204d6f757365; asc Practical Fresh Mouse;;
 4: len 4; hex 800000b1; asc     ;;
 5: len 4; hex 800000fe; asc     ;;
 6: len 4; hex 80000020; asc     ;;


*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 3 page no 8 n bits 336 index PRIMARY of table `online-transaction`.`products` trx id 14048 lock_mode X locks rec but not gap waiting
Record lock, heap no 259 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 4; hex 00000397; asc     ;;
 1: len 6; hex 0000000036d7; asc     6 ;;
 2: len 7; hex 010000013f1e26; asc     ? &;;
 3: len 21; hex 50726163746963616c204672657368204d6f757365; asc Practical Fresh Mouse;;
 4: len 4; hex 800000b1; asc     ;;
 5: len 4; hex 800000fe; asc     ;;
 6: len 4; hex 80000020; asc     ;;


*** (2) TRANSACTION:
TRANSACTION 14052, ACTIVE 1 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 11 lock struct(s), heap size 1136, 6 row lock(s), undo log entries 2
MySQL thread id 57, OS thread handle 140283970258688, query id 45841 172.22.0.1 api-server updating
update `products` set `sold` = 34 where `id` = '919'

*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 3 page no 8 n bits 336 index PRIMARY of table `online-transaction`.`products` trx id 14052 lock mode S locks rec but not gap
Record lock, heap no 259 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 4; hex 00000397; asc     ;;
 1: len 6; hex 0000000036d7; asc     6 ;;
 2: len 7; hex 010000013f1e26; asc     ? &;;
 3: len 21; hex 50726163746963616c204672657368204d6f757365; asc Practical Fresh Mouse;;
 4: len 4; hex 800000b1; asc     ;;
 5: len 4; hex 800000fe; asc     ;;
 6: len 4; hex 80000020; asc     ;;


*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 3 page no 8 n bits 336 index PRIMARY of table `online-transaction`.`products` trx id 14052 lock_mode X locks rec but not gap waiting
Record lock, heap no 259 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 4; hex 00000397; asc     ;;
 1: len 6; hex 0000000036d7; asc     6 ;;
 2: len 7; hex 010000013f1e26; asc     ? &;;
 3: len 21; hex 50726163746963616c204672657368204d6f757365; asc Practical Fresh Mouse;;
 4: len 4; hex 800000b1; asc     ;;
 5: len 4; hex 800000fe; asc     ;;
 6: len 4; hex 80000020; asc     ;;

*** WE ROLL BACK TRANSACTION (2)
------------
TRANSACTIONS
------------
.....
--------
FILE I/O
--------
.....
-------------------------------------
INSERT BUFFER AND ADAPTIVE HASH INDEX
-------------------------------------
.....
---
LOG
---
.....
----------------------
BUFFER POOL AND MEMORY
----------------------
.....
--------------
ROW OPERATIONS
--------------
.....
----------------------------
END OF INNODB MONITOR OUTPUT
============================
```

挑出重點來看
1. `LATEST DETECTED DEADLOCK` 以下顯示最後一次發生的 Deadlock，有表述互相死鎖的兩筆 Transaction `*** (1) TRANSACTION:` 與 `*** (2) TRANSACTION:`
2. 接著看到兩筆 Transaction 手上握有的 Lock，看得出來他們都有同一行 product row 的 lock mode S locks 
```md
RECORD LOCKS space id 3 page no 8 n bits 336 index PRIMARY of table `online-transaction`.`products` trx id 14052 lock mode S locks rec but not gap
```
3. 接著他們在等待的鎖為
```md
`online-transaction`.`products` trx id 14052 lock_mode X locks rec but not gap waiting
```  

答案就此揭曉，因為兩個 Transaction 手上都握有 share lock，如果要取得 exclusive lock 則對方必須先釋放 share lock，因此造成 Deadlock，最終看到 Transaction 2 被 rollback 了
```bash
*** WE ROLL BACK TRANSACTION (2)
```

Debug 資訊乍看很多，但仔細看還蠻好理解的

### 找出問題根源 
知道是因為 shared lock 導致後面的 exclusive lock 死鎖的原因，回頭爬指令看哪裡有問題  

首先定位到 select from，根據官方文件，除非 isolation 是 serializable，否則一般的 select from 是沒有 lock 的，出處 [15.7.2.3 Consistent Nonlocking Reads](https://dev.mysql.com/doc/refman/8.0/en/innodb-consistent-read.html)
> Consistent read is the default mode in which InnoDB processes SELECT statements in READ COMMITTED and REPEATABLE READ isolation levels. `A consistent read does not set any locks` on the tables it accesses, and therefore other sessions are free to modify those tables at the same time a consistent read is being performed on the table.

既然不是 select 造成，嫌疑犯就變成 insert order 了，orders table 中的 product_id 是引用 product table 中的 id 當作 foreign key，果然找到相關的描述 [14.7.3 Locks Set by Different SQL Statements in InnoDB](https://dev.mysql.com/doc/refman/5.7/en/innodb-locks-set.html) 
> `If a FOREIGN KEY constraint is defined on a table, any insert, update, or delete that requires the constraint condition to be checked sets shared record-level locks` on the records that it looks at to check the constraint. InnoDB also sets these locks in the case where the constraint fails.

真相大白

### 如何解決  
在 SQL 最一開始，因為篤定會改變 product 欄位，直接使用 `select for update` 用 exclusive lock 鎖住，就解決問題了  
需注意設定成 `serializable` 還是有機會發生 Deadlock 喔，因為在 MySQL 中只是追加 select from 的鎖，而不是真的像 redis 一次只順序執行一道指令喔  

## 補充資料 - 關於 MySQL Lock
[解决死锁之路（终结篇） - 再见死锁](https://www.aneasystone.com/archives/2018/04/solving-dead-locks-four.html) 強力推薦這篇文章，後來與同事在工作上排查死鎖，發現 update 單筆資料竟然也有死鎖的狀況，才知道 lock 需要鎖定對應的 Index 並且在沒有命中時會使用區間鎖 (如果 isolation level 在 Repeatable Read 以上)，還是有機會造成死鎖

透過上述的參考資料，並重新翻閱 MySQL 文件，整理了另一篇 [【MySQL】Lock 與 Index 關係和 Deadlock 分析](https://yuanchieh.page/posts/2022/2022-04-25-mysqllock-%E8%88%87-index-%E9%97%9C%E4%BF%82%E5%92%8C-deadlock-%E5%88%86%E6%9E%90/)
