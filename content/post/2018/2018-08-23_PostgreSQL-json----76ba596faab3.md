---
title: PostgreSQL json 操作
description: Postgresql 可以用欄位 jsonb型別儲存 json格式的資料，並提供不少內建的函式可以協助查詢，以下稍微整理一些常用的情景。
date: '2018-08-23T08:36:20.503Z'
categories: ['資料庫']
keywords: ['PostgreSQL']
---

Postgresql 可以用欄位 jsonb 型別儲存 json 格式的資料，並提供不少內建的函式可以協助查詢，以下稍微整理一些常用的情景。

### 示範資料庫

[**DB Fiddle - SQL Database Playground**](https://www.db-fiddle.com/f/vk8sCioCh1RstjSWXsZnWr/4)

基本就是是 Orders / Products 兩張表，Orders 中資料用 data jsonb 格式存儲，Products 則是常規的欄位定義。

Orders 資料大約長這樣

```json
{
  "id": 1,
  "cost": 200,
  "products": [{"id": 1, "nums": 5}, {"id": 2, "nums": 3}],
  "details": {"title": "memo"}
}
```

#### 操作 JSON

如果是要做 json 的欄位索取，可以用 `->` ，如果要回傳字串結果用 `->>`

例如說 `data->’details’->>’title’` 就會回傳 `“memo”`

陣列也可以指定哪個位置，例如 `data->’product’->0->’id’`

使用上如果是 key 用 `` ` `` 單引號括著，如果是陣列位置才不需要，不然會一直回傳 null

另外要特別注意的是`->>` 都是回傳字串，所以如果要跟其他類型做比對，需要自己做格式轉換，例如 `Cast( data->>”id” as int ) = id` 拿 data.id 跟 int 型別的自增主鍵做比對

#### 陣列長度

如果是想要知道陣列的長度是多少，可以用 jsonb_array_elements

例如 `jsonb_array_length(data->’products’) > 2` ，這會直接回傳 int

#### Key 是否存在

有三種用法，`?’比對key’ ?|[’比對key1’, ’比對key2’] ?&[’比對key1’, ’比對key2’]` ，結果回傳 boolean

例如找出 data 中包含\`detail\`欄位的資料  
 `select * from Orders where data?’detail’;`

?| 則是後者陣列中只要命中一個就為 true，?& 則是要陣列中所有的元素都存在才是 true。

#### 攤平陣列

算是做第一正規化，我希望透過 Join Products 計算每筆訂單的總額，但因為 Orders 中的 data->product 是陣列，所以需要 `jsonb_array_elements` ，`jsonb_array_elements` 會直接回傳 set

`select jsonb_array_elements(data->’products’) as product_item from Orders;` 這樣就可以做到第一正規化

接著蠻神奇的是可以直接將 Order 與 `jsonb_array_elements` 做 CROSS JOIN
```sql
select Orders.id,  
Sum(Cast(product_item->>'nums' as int) \* Products.price) from Orders,  
 jsonb_array_elements(data->'products') as product_item  
 left join Products on Cast(product_item->>'id' as int) = Products.id  
 group by Orders.id;
```

但結果竟然不是預期的笛卡爾積 N\*M，而是會自動幫你把屬於該訂單的 product 對應好，到現在還想不透怎麼會這樣。

#### json vs jsonb

Postgresql 支援兩種合法 json 可插入的格式 `json` `jsonb` ，但兩者有些微的差異

1.  json  
    以純文字型態插入，包含空白、換行，同時保持原本的鍵值順序
2.  jsonb  
    以二進制方式儲存，會把重複的鍵值去除(後者覆蓋前者)

jsonb 支援 index，在插入時需要較長的時間，但是查詢速度較快，是比較通用的選擇格式。

但如果有需要保持原本鍵值順序、或是單純想保留原本的 json 格式才使用 `json` 格式

參考資料  
[https://my.oschina.net/swingcoder/blog/489769](https://my.oschina.net/swingcoder/blog/489769)、[https://stackoverflow.com/questions/22654170/explanation-of-jsonb-introduced-by-postgresql](https://stackoverflow.com/questions/22654170/explanation-of-jsonb-introduced-by-postgresql)

### 結語

有看到一些實驗是把 Postgresql 當作 NoSQL 使用，但個人覺得還是偏玩票性質，關聯式資料庫還是遵守正規化設計，僅把 json 當作額外的彈性就好
