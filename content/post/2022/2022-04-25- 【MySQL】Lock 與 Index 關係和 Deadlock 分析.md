---
title: '【MySQL】Lock 與 Index 關係和 Deadlock 分析'
description: 整理 MySQL 的 Lock 與 Index 關係，以及 Deadlock debug 過程
date: '2022-04-25T01:21:40.869Z'
categories: ['資料庫']
keywords: ['MySQL']
---
關於 MySQL Lock 來來回回寫了也有幾篇，每次看都有不同的發現，這次為了準備公司內部分享，重新再翻閱一次又找到一些新的有趣發現，以下將盡可能完整的解析 MySQL Lock 與 Index 的關係，怎樣的查詢會拿到怎樣的鎖，以及怎樣的查詢又可能互相 Deadlock

文章主要受啟發於 [解决死锁之路（终结篇） - 再见死锁](https://www.aneasystone.com/archives/2018/04/solving-dead-locks-four.html)，對應的實驗可以看程式碼 [sj82516/mysql-deadlock-test](https://github.com/sj82516/mysql-deadlock-test)，先說結論，`在 DML (更新、刪除、插入)的操作中，Lock 會與套用的 Index 有關`，在 MySQL 中 Index 有幾種
1. Clustered Index:   
通常是 Primary Key
2. Unique Secondary Index:  
如果沒有 Primary Key，則 Unique Secondary Index 會是 Clustered Index，行為與 Clustered Index 雷同，不額外贅述
3. Non Unique Secondary Index

以下將重點分析 Clustered Index / Non Unique Secondary Index 對於 MySQL 操作有什麼不同的影響，在 Read Committed 簡稱 RC) 與 Repeatable Read (簡稱 RR) 下又有怎樣的不同行為，實驗預設是 5.7 + Repeatable Read (MySQL 預設)

## Clustered Index
先來一題簡單的暖身題，以下兩個 Transaction 為什麼會 Deadlock
![](/post/2022/img/0425/01.png)
要滿足 Deadlock 需要有四個條件
- no preemption
- hold and wait
- mutual exclusion
- circular waiting  

在上面的案例中，MySQL 在 RR 下要 update 會先取得 exclusive lock，兩個 Transaction 手上都拿了對方想要的資源卻也不都會先放開手上的鎖，導致 Deadlock
![](/post/2022/img/0425/01_2.png)

直接從圖片很容易看出彼此 Deadlock，但正式環境中多筆 Transaction 交雜，該如何找出 Deadlock 呢？
### 1. 如何 Debug Deadlock
MySQL 有幾個相關參數
1. [innodb_deadlock_detect](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_deadlock_detect): 是否偵測 deadlock，預設開啟  
2. [innodb_lock_wait_timeout](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_lock_wait_timeout): 如果沒有開啟 Deadlock detect，建議設定較短的 wait timeout 否則會一直等到  
3. [innodb_print_all_deadlocks](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_print_all_deadlocks): 將所有 Deadlock 錯誤輸出至 error log

如果沒有輸出 Deadlock error，可以用 `> SHOW ENGINE INNODB STATUS` 輸出，其中有兩個區塊 deadlock 顯示最近一筆 deadlock 錯誤，transaction 則會顯示目前在等待 lock 的 transaction  

#### 1.1 實際閱讀 Deadlock
```md
LATEST DETECTED DEADLOCK
------------------------
2022-04-26 09:33:29 0x40de5bc700
*** (1) TRANSACTION:
TRANSACTION 9597, ACTIVE 3 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 3 lock struct(s), heap size 1136, 2 row lock(s), undo log entries 1
MySQL thread id 1034, OS thread handle 278338676480, query id 14980 172.17.0.1 root updating
`UPDATE teachers SET teachers.age = 10 WHERE teachers.id = 5`
*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 275 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9597 lock_mode X locks rec but not gap waiting
Record lock, heap no 3 PHYSICAL RECORD: n_fields 6; compact format; info bits 0
 0: len 8; hex 8000000000000005; asc         ;;
 1: len 6; hex 00000000257c; asc     %|;;
 2: len 7; hex 23000001c017d1; asc #      ;;
 3: len 1; hex 62; asc b;;
 4: len 4; hex 80000010; asc     ;;
 5: SQL NULL;

*** (2) TRANSACTION:
TRANSACTION 9596, ACTIVE 3 sec starting index read
mysql tables in use 1, locked 1
3 lock struct(s), heap size 1136, 2 row lock(s), undo log entries 1
MySQL thread id 1033, OS thread handle 278608463616, query id 14979 172.17.0.1 root updating
`UPDATE teachers SET teachers.age = 6 WHERE teachers.id = 1`
*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 275 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9596 lock_mode X locks rec but not gap
Record lock, heap no 3 PHYSICAL RECORD: n_fields 6; compact format; info bits 0
 0: len 8; hex 8000000000000005; asc         ;; -> index，用 16 進位表示，這邊是指 id: 5
 1: len 6; hex 00000000257c; asc     %|;;
 2: len 7; hex 23000001c017d1; asc #      ;;
 3: len 1; hex 62; asc b;;
 4: len 4; hex 80000010; asc     ;;
 5: SQL NULL;

*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 275 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9596 `lock_mode X locks rec but not gap waiting`  
Record lock, heap no 2 PHYSICAL RECORD: n_fields 6; compact format; info bits 0
 0: len 8; hex 8000000000000001; asc         ;;     
 1: len 6; hex 00000000257d; asc     %};;
 2: len 7; hex 22000001cc02e5; asc "      ;;
 3: len 1; hex 61; asc a;;
 4: len 4; hex 8000000f; asc     ;;
 5: SQL NULL;

*** WE ROLL BACK TRANSACTION (2)
------------
```
這部分內容參考 [MySQL死锁问题如何分析](https://juejin.cn/post/6844903943516979213)，重點看這一段
> RECORD LOCKS space id 275 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9596 lock_mode X locks rec but not gap waiting  `專指 row lock`  
Record lock, heap no 2 PHYSICAL RECORD: n_fields 6; compact format; info bits 0
 0: len 8; hex 8000000000000001; asc         ;;  `-> index，用 16 進位表示，這邊是指 id: 1`

，我們可以從 log 中看出操作 / 手上的 lock / 等待的 lock / `Lock 在哪一個 row`

### 2. 取得 Lock 的順序性
如果查詢的條件命中多筆，那 Lock 會怎麼取得呢？ 接著看以下案例
![](/post/2022/img/0425/02.png)

根據 [MySQL 文件](https://dev.mysql.com/doc/refman/5.7/en/update.html)，會根據 Order By 的指定條件與 Index 本身順序性一行一行鎖起來
> If an UPDATE statement includes an ORDER BY clause, the rows `are updated in the order specified by the clause`. This can be useful in certain situations that might otherwise result in an error. Suppose that a table t contains a column id that has a unique index. The following statement could fail with a duplicate-key error, depending on the order in which rows are updated

從 Deadlock Log 可以清楚看到 id 2 / id 5 被互相鎖住
```md
*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 278 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9676 lock_mode X waiting
Record lock, heap no 2 PHYSICAL RECORD: n_fields 6; compact format; info bits 0
 0: len 8; hex `8000000000000002`; asc         ;;
------
*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 278 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9675 lock_mode X waiting  
Record lock, heap no 3 PHYSICAL RECORD: n_fields 6; compact format; info bits 0
 0: len 8; hex `8000000000000005`; asc         ;;
```
#### 2.1 建立 Index 時決定順序
當[建立 MySQL Index](https://dev.mysql.com/doc/refman/5.7/en/create-index.html) 也可以指定順序，但需要注意 MySQL 5.7 會忽視 (全部都是 asc) 只有在 MySQL 8.0 以上才支援，所以以下案例只發生在 MySQL 8.0

我們可以透過 `USE INDEX()` 指定執行時的 Index
![](/post/2022/img/0425/02_01.png)

> (5.7 文件) A key_part specification can end with ASC or DESC. These keywords are permitted for future extensions for specifying ascending or descending index value storage. Currently, they `are parsed but ignored`; index values are always stored in ascending order.

#### 2.2 恰巧兩個 Index 順序相仿
2.1 案例中我們很刻意讓 Index 同一個欄位欄位但順序剛好相反，但如果是兩個不同 Index 而資料寫入時讓順序恰好相反呢？
在建立資料時，id 跟 name 的順序剛好相反，也就是
```md
id1 > id2 && name1 < name2，例如 (1, "zz") (2, "zx")
```
這樣也會發生 Deadlock!

![](/post/2022/img/0425/02_02.png)

### 3. 查詢沒有命中 : Gap Lock
如果查詢沒有命中，此時 MySQL 在 RR 情況下會取得 Gap Lock，所謂的 Gap 是在已存在欄位之間的縫隙，為了避免幻讀 MySQL 會鎖住 Gap 不讓其他 Transaction 插入資料

這邊特別介紹兩個鎖定區間的 Lock，分別是 Gap Lock / Insert Intention Lock
1. Insert Intention Lock 故名思義是是插入前會鎖定該區間
2. 這兩種 Lock 特別在於不會排擠自己人，例如 `Gap Lock 不會阻擋 Gap Lock` / `Insert Intention Lock 不會阻擋 Insert intention Lock`，但是 `Insert Intention Lock 跟 Gap Lock 互斥`，原因是區間可能很大，為了提升性能，在同一個區間可以同時插入新資料，如果真的有違反 Unique Key 則會有原本的重複性檢查阻擋，Update 也是

有一個場景是「我們希望更新某一筆資料，發現資料不在則寫入」，如以下範例則會造成 Deadlock
![](/post/2022/img/0425/03.png)

因為 id 6 / 10 在 update 時都取得了 Gap Lock，接著要 Insert 取得 Insert Intention Lock 卻因為雙方都還握有 Gap Lock 而無法寫入，讓我們看具體的 Deadlock 細節
```md
*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 279 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9700 `lock_mode X insert intention waiting`
Record lock, heap no 1 PHYSICAL RECORD: n_fields 1; compact format; info bits 0
 0: len 8; hex 73757072656d756d; asc `supremum`;;

*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 279 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9699 `lock_mode X`
Record lock, heap no 1 PHYSICAL RECORD: n_fields 1; compact format; info bits 0
 0: len 8; hex 73757072656d756d; asc `supremum`;;

*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 279 page no 3 n bits 72 index PRIMARY of table test.teachers trx id 9699 lock_mode X insert intention waiting
Record lock, heap no 1 PHYSICAL RECORD: n_fields 1; compact format; info bits 0
 0: len 8; hex 73757072656d756d; asc supremum;;
```

可以看到雙方都在等 `lock_mode X insert intention waiting`，指定的 row 是 `supermum` 這是代表最後一個區間，區間大致長以下這般
```md
(negative infinity, 第一筆]
(第一筆, 第二筆]
....
(最後一筆, positive infinity)
```

所以同樣的 query 只是原始資料改變落在不同區間，就不會有 Deadlock 如以下
![](/post/2022/img/0425/03_01.png)

### 4. 範圍查詢：鎖定找過的每筆資料即使條件不合
接下來看一個 RR 蠻嚇人的一個特性，參考文件 [15.7.2.1 Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
> "When using the default REPEATABLE READ isolation level, the first UPDATE acquires an x-lock on each row that it reads and `does not release any of them`

也就是說 where condition 假使是範圍搜尋，RR 會把搜尋到的範圍全部鎖死，直到 transaction 結束! 

讓我們看以下案例
![](/post/2022/img/0425/04.png)

Update 的條件沒有命中但是`全部都被 Lock`，要 update / insert 都不行，相對的
> RC 在檢查不符合條件就會 release，在做大規模的 Update / Delete 記得要用 RC 會比較好

## Non Unique Index
上面的範例都是 Clustered Index，MySQL 支援 Secondary Index，其中 Unique Secondary Index 與 Clustered Index 行為類似，就不另外贅述，但是 Non Unique Index 要稍微留意
### 1. 查詢命中：依然會 Gap Lock
在一開始的範例，如果 Clustered Index 查詢有命中只會鎖那一行 \(ex. update id = 1\)，但如果 Non Unique Index 即使完全命中，也會連同 Gap 一起鎖起來 (Next Key Lock)

![](/post/2022/img/0425/05.png)
這邊 Lock 比較多，需注意 Secondary Index 會被鎖之外，對應的 Clustered Index 也會被鎖，這邊 age 鎖定 10 以及前面的區間，所以要插入 age: 9 就會失敗；運用上面的技巧，age 切換到不同區間就可以成功插入


## Foreign Key：會有 Share Lock
> If a FOREIGN KEY constraint is defined on a table, any insert, update, or delete that requires the constraint condition to be checked sets shared record-level locks

更新欄位時 Foreign Key 也會被鎖住，之前有紀錄就不贅述 [MySQL Deadlock 問題排查與處理](https://yuanchieh.page/post/2020/2020-12-26_mysql-deadlock-%E5%95%8F%E9%A1%8C%E6%8E%92%E6%9F%A5%E8%88%87%E8%99%95%E7%90%86/)

## 總結與建議
幾點建議
1. 增加 Index 要仔細評估，Secondary Index 會造成寫入效能下降，體現於 lock 的使用
2. 如果是用 ORM，記得檢查 Query
3. 如果需要用 Secondary Index 改變欄位，建議可以用批次 (RoR 就是 find_in_batch)
4. 或是先篩選出 Primary Key (預設 select 不會有 lock)，再使用 Primary Key 當作修改條件避免 Gap Lock
5. `沒事就用 Read Committed`

## 進階：為什麼不要預設 Read Committed ?
既然 Repeatable Read 會有這麼多效能疑慮，更新時連 where 條件不符合的行都會鎖、還會有不預期的 Gap Lock，那為什麼預設不要改成 Read Committed ?

在 PostgreSQL 確實如此，[PQ 9.3. Read Committed Isolation Level](https://www.postgresql.org/docs/7.2/xact-read-committed.html)提到
> The partial transaction isolation provided by Read Committed level is adequate for many applications, and this level is fast and simple to use

我在查閱 MySQL 相關資料，也有查到 Percona 一篇文章提及 MySQL 預設應該要改成 Read Committed 比較好 [MySQL performance implications of InnoDB isolation modes](https://www.percona.com/blog/2015/01/14/mysql-performance-implications-of-innodb-isolation-modes/) 
> In general I think good practice is to use READ COMITTED isolation mode as default and change to REPEATABLE READ for those applications or transactions which require it.

那 MySQL 官方怎麼說，我找到一篇官方的 blog [Performance Impact of InnoDB Transaction Isolation Modes in MySQL 5.7](https://dev.mysql.com/blog-archive/performance-impact-of-innodb-transaction-isolation-modes-in-mysql-5-7/) 建議到
> - For short running queries and transactions, use the default level of REPEATABLE-READ.  
- For long running queries and transactions, use the level of READ-COMMITTED

裡面有另一篇文做了 Benchmark 非常有趣 [MySQL Performance : Impact of InnoDB Transaction Isolation Modes in MySQL 5.7](http://dimitrik.free.fr/blog/archives/2015/02/mysql-performance-impact-of-innodb-transaction-isolation-modes-in-mysql-57.html)，從 MySQL 內部的 Lock 數量與操做 QPS 衡量不同 isolation level，我本來以為 Read Committed 在增刪查改會碾壓 Repeatable Read，但發現盡然沒有，反而因為 Read Committed 在每次 Read 都會產生新的 MVCC 版本而有更多的內部 Lock，非常有趣

所以總結官方部落格建議，預設還是保留 RR 普遍效能反而更好，只有在長時間的 Job 再改成 RC 即可