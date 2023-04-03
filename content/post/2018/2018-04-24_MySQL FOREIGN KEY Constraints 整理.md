---
title: MySQL FOREIGN KEY Constraints 整理
description: >-
  整理閱讀MySQL v5.7的FOREIGN KEY Constraints文件，並針對細節在DB Fiddle加上範例。
date: '2018-04-24T10:16:08.524Z'
categories: ['資料庫']
keywords: ['MySQL']
---

[MySQL :: MySQL 5.7 Reference Manual :: 13.1.18.6 Using FOREIGN KEY Constraints](https://dev.mysql.com/doc/refman/5.7/en/create-table-foreign-keys.html#foreign-keys-adding "https://dev.mysql.com/doc/refman/5.7/en/create-table-foreign-keys.html#foreign-keys-adding")

整理閱讀MySQL v5.7的FOREIGN KEY Constraints文件，並針對細節在DB Fiddle加上範例，後續FOREIGN KEY縮寫FK。

FK限制可保證資料關聯間的完整性，關係是建立child Table指定要與 parent Table的某欄位建立關聯，`FOREIGN KEY` 必須在 child Table中指定，child / parent需使用相同的DB引擎且不可為 TEMPORARY Table。

在宣告語法上，可以透過 [CONSTRAINT symbol ] 指定這筆關聯限制的名稱，但須注意名稱不可重複否則會出錯；  
如果擔心就不要宣告 CONSTRAINT讓 DB Engine自動產生

[DB Fiddle - SQL Database Playground](https://www.db-fiddle.com/f/ocxrUaBoXDVM6i1xAmyZH1/1 "https://www.db-fiddle.com/f/ocxrUaBoXDVM6i1xAmyZH1/1")

## FOREIGN KEY 資料型別

有趣的是，MySQL文件只說parent中的資料欄位與child FOREIGN KEY欄位的資料型別必須**類似**而非一致，又可細分成三類

1.  integer：  
    _Size & Sign必須相同，例如說 TINYINT / INT 就是不一樣的
2.  string：  
    長度不一定要相同，因為不論是parent長或是child長，FOREIGN KEY在插入時必須parent存在該筆資料；  
    所以在插入不可超過欄位長度與資料必須存在的兩個條件下，字串長度的限制就不是這麼必要
3.  對於非位元型別的字串，character set 和 collation必須相同

## FOREIGN KEY 限制

除了上述的資料型別限制外，MySQL為了搜尋上避免 full table scan

1.  parent 的欄位必須是「某Index中的第一欄位」，例如 index(id) / index(id, uid, ….)，因為MySQL的Index順序是由左至右，所以如果是多欄位Index只要該欄位是在第一順位也可以當作建立 FK的欄位。  
    假設不符合條件，會直接出錯無法建立child Table。
2.  child 的FK欄位必須是「某Index中的第一欄位」，如果沒有會自動創建。
3.  FK可以是多欄位，但同樣要符合「某Index中的前面順位」
4.  又因為FK必須建立Index，所以像 TEXT / BLOB 就不可能是 FK選項。

## 關聯操作

在定義FK時可以指定關聯操作，也就是如果 parent的對應FK欄位發生改變(UPDATE / DELETE)時 child FK欄位該怎麼應對，總共有幾種定義：

1.  CASCADE:  
    如果是 parent紀錄被刪除了，那對應FK的chlid紀錄也一併刪除；  
    如果是 parent FK更新了新值，則child 對應的FK會更新。
2.  SET NULL:  
    刪除更新 parent都會導致 child的 FK紀錄設為 Null，如果設定為 SET NULL 記得 「child FK 欄位不要加 NOT NULL 會衝突」。
3.  RESTRICT:  
    只要child中有包含該 FK值，完全不能刪除該筆parent或更新 parent的FK欄位。
4.  NO ACTION:   
    在MySQL等同於 `RESTRICT`。
5.  SET DEFAULT:  
    在MySQL InnoDB中不支援。

[**DB Fiddle - SQL Database Playground**](https://www.db-fiddle.com/f/acgvjzoA4B5sfy1RJb6Yyj/0)

## 增加或刪除FK

可以透過 `ALTER TABLE` 來增加FK，透過 `DROP TABLE` 指定刪除FK，但如果當初沒有使用 `CONSTRAINT` 宣告FK的名稱，可以用 `SHOW CREATE TABLE` 取得Table資料，即可得知系統自動創建的FK名稱。

## 暫時關閉 FK CONSTRAITS

當使用 `mysqldump` 時，為了方便重建資料MySQL會自動先關閉FK CONSTRAITS的限制

mysql> SET foreign_key_checks = 0;   
mysql> SOURCE _dump_file_name_;   
mysql> SET foreign_key_checks = 1;

但必須注意，即使關閉了在創建 FK時仍然不可以違背 FK資料型別的驗證，不然一樣會噴錯誤!

關閉限制後刪除/更新都不會檢查 parent是否存在對應資料，即使重新開啟限制檢查也不會回溯，所以務必小心。