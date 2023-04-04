---
title: MySQL Explain分析與Index設定查詢優化
description: >-
  資料庫日積月累資料量逐步攀升，MySQL在一般查詢是透過全表搜尋，所以大量的資料會導致查詢等方式越來越慢
date: '2018-07-30T10:14:40.633Z'
categories: ['資料庫']
keywords: ['MySQL']

  
---

資料庫日積月累資料量逐步攀升，MySQL在一般查詢是透過全表搜尋，所以大量的資料會導致查詢等方式越來越慢；  
MySQL提供索引建置，一般的索引透過 B+ Tree，在記憶體中快速查找資料所在位置，將搜尋從 O(n) 約\*降至O(log n)，索引支援Where / Order by / Range中的條件判斷。

以下產生User / Order兩張百萬筆資料的Table  
1\. 並試著用Explain 分析SQL語法  
2\. 透過索引設定比較前後的查詢速度優化

### Table
```sql
CREATE TABLE 'users' (  
  'id' int(11) NOT NULL AUTO_INCREMENT,  
  'uuid' char(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,  
  'age' int(11) DEFAULT NULL,  
  'firstName' varchar(255) DEFAULT NULL,  
  'lastName' varchar(255) DEFAULT NULL,  
  'createdAt' datetime NOT NULL,  
  'updatedAt' datetime NOT NULL,  
  PRIMARY KEY ('id'),  
) ENGINE=InnoDB AUTO_INCREMENT=1000001 DEFAULT CHARSET=utf8mb4;

CREATE TABLE 'orders' (  
  'id' int(11) NOT NULL AUTO_INCREMENT,  
  'uuid' char(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,  
  'cost' int(11) DEFAULT NULL,  
  'user_id' int(11) DEFAULT NULL,  
  'user_uuid' varchar(255) DEFAULT NULL,  
  'tradeNo' varchar(255) DEFAULT NULL,  
  'createdAt' datetime NOT NULL,  
  'updatedAt' datetime NOT NULL,  
  PRIMARY KEY ('id')  
) ENGINE=InnoDB AUTO_INCREMENT=750001 DEFAULT CHARSET=utf8mb4;
```

### Explain

Explain可以用於分析 SELECT / DELETE / UPDATE / INSERT / REPLACE 語句，條列出執行SQL語句時會使用到的 Table與欄位資訊，實際回傳的欄位有

1.  select_type:   
    SELECT查詢的狀態，常見有幾種型別  
    * SIMPLE：簡單查詢  
    * PRIMARY：主查詢，相對於子查詢Subquery  
    * UNION：在UNION語句中的非首個SELECT  
    * SUBQUERY：子查詢  
    如果非SELECT則為其他動詞如DELETE
2.  table:   
    也就是使用的Table名稱
3.  partitions:  
    如果有使用 partition功能才會顯示
4.  type:   
    `type` 參數非常重要，這會決定此次SQL語句使用索引狀況，由優至劣順序介紹  
    **const / system**  
    查詢用上primary / unique key，也就是條件剛好匹配一個行，因為只讀取一行所以速度最快；  
    system是特殊類的const，用於查詢 system相關的表，如  
    `explain select * from 'proxies_priv' where user=’root’`
    **eq_ref** :用於多表 join下，如果在條件判斷 = 上用了`PRIMARY KEY` 或`UNIQUE NOT NULL`也就是條件剛好匹配一個行  
    此範例的 join select就是用上[`eq_ref`](https://dev.mysql.com/doc/refman/8.0/en/explain-output.html#jointype_eq_ref)因為 user.id是 primary key  
    `explain select * from orders left join users on users.id = orders.user_id where orders.cost > 100;`  
    **ref**  
    用於多表 join下，如果是用leftmost prefix key或是非 `[eq_ref](https://dev.mysql.com/doc/refman/8.0/en/explain-output.html#jointype_eq_ref)` 條件中的key，也就是可能會匹配多行   
    * index_merge：  
    如果查詢用上多個key，例如  
    `explain select id from users where id = 2 or id=100 or uuid=’21d9dadb-038f-427d-8ef1-c2b3aa0994e6';`  
    (id / uuid 都是 index)  
5. range
  將key用於範圍查詢，如 
    * [=](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_equal)
    * [<>](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_not-equal)
    * [>](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_greater-than)
    * [>=](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_greater-than-or-equal)`, 
    * [<](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_less-than)
    * [<=](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_less-than-or-equal),
    * [IS NULL](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_is-null)
    * [<=>](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_equal-to)
    * [BETWEEN](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_between),
    * [LIKE](https://dev.mysql.com/doc/refman/8.0/en/string-comparison-functions.html#operator_like) 
    * [IN()](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#function_in)`  
  * index：  
    全表索引檢索，常用於索引可覆蓋查詢欄位，所以不需要到磁碟讀取資料  
    ALL：  
    最差的查詢方式，全表搜尋
6.  possible_keys：  
    可能會用上的key
7. key：  
    實際用上的key
8.  key_len：  
    實際key使用的比對長度
9.  ref：  
    用在與索引比對的常數或欄位，如  
    `explain delete from users where id=1;` ref值為 const，因為是1；  
    如果比對的是欄位則會出現欄位名，如 `index_search.orders.user_id`
10.  rows：  
    MySQL預計要讀取的行數
11.  filtered：  
    MySQL根據條件預計會篩選掉的比例，以百分比顯示，所以最大值為100，也就是每個 rows都用上
12.  Extra：  
    額外補充，有幾個值需要留意  
    ＊Using filesort：  
    MySQL在排序上需要做額外的處理，會耗費大量的性能。  
    \* Using Where：  
    有加入條件判斷，如果不是要刻意掃全表，理論上都會出現這個值；  
    如果Extra沒有出現Using Where 且 type為 ALL/ index，小心就落入了全表掃描。  
    \* Using index：  
    索引搜尋且覆蓋索引，就不用再額外讀取實際的row 資料。

### 實際使用

我透過 nodejs塞入百萬筆假資料，可以參考連結取得

#### RIGHT JOIN 和 LEFT JOIN差異

users / orders Table目前只有 id是 primary key，比對以下兩個語句，兩者執行速度天差地遠

`explain select * from users left join orders on orders.user_id = users.id;`

`explain select * from users right join orders on orders.user_id = users.id;`

[MySQL內部會把RIGTH JOIN轉換成LEFT JOIN](https://dev.mysql.com/doc/refman/8.0/en/outer-join-simplification.html)，所以其實就是比較先執行 users 還是 orders，在內部 [JOIN是多層 for loop查找](https://dev.mysql.com/doc/refman/8.0/en/nested-join-optimization.html)並比對 on 的條件判斷；  
在這個案例中， 後者的執行速度會遠快於前者因為後者先loop orders，接著拿 orders.user_id去 users中比對users.id，而 user.id是 primary key所以速度非常快；  
反之 orders.user_id沒有索引，只能全表掃描。

![`explain select * from users right join orders on orders.user_id = users.id;`](/post/img/1__vXNThgMlQU72iv7kH3dXiw.png)

`explain select * from users right join orders on orders.user_id = users.id;`

![`explain select * from users right join orders on orders.user_id = users.id;`](/post/img/1__fp99dWZ32mfR0yvRKL2Xfw.jpeg)

`explain select * from users right join orders on orders.user_id = users.id;`

#### 子查詢

如果我想要條列所有訂單數超過兩筆的用戶，並同時顯示{用戶所有資料，訂單數}，可能有幾種做法

1.  從users , temp table取資料，temp table 是暫存 訂單數超過2的 table，兩者做 INNER JOIN   
    `select users.*, temp.order_count from (select user_id, count(distinct orders.id) as order_count from orders group by orders.user_id having order_count > 2) temp INNER JOIN users on users.id = temp.user_id;`
2.  orders 先INNER JOIN users，接著才計算訂單數  
    `select users.*, count(distinct orders.id) as order_count from orders INNER JOIN users on users.id = orders.user_id group by orders.user_id having order_count > 2;`

第一點的問題是在子查詢 `(select user_id, count(distinct orders.id) as order_count` 不可避免的要跑一次全表搜尋，但是暫存成 temp Table做INNER JOIN 又會在跑一次，等同於全表搜尋 orders兩次

![1](/post/img/1__Jeto7u4zaq9XDJ3fwSppRw.jpeg)
1

為了避免多一次無謂的全表搜尋，先JOIN在 GROUP BY 效率就好很多。

![2](/post/img/1__yMDa4b2rpLrDLnY26N19ZQ.jpeg)
2