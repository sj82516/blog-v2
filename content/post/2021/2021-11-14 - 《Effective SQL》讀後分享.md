---
title: '《Effective SQL》讀後分享'
description: 《Effective SQL》分享 61 個優化 SQL Database 相關的技巧，有些關於資料表的設計與複雜的關聯式查詢有很多不錯的點子，是本很實用的工具書
date: '2021-11-14T01:21:40.869Z'
categories: ['資料庫']
keywords: ['SQL']
---
![](https://cf-assets2.tenlong.com.tw/products/images/000/107/662/webp/ACL049900.webp?1525539256)
[天瓏購買連結](https://www.tenlong.com.tw/products/9789864764358?list_name=lv)

最近在幫公司處理 Data Pipeline，將資料送往 BigQuery 儲存，並開始了 SQL 煉獄，必須說平常開發寫的 Query 複雜度都不太高，比較注重資料表的設計與效能，而報表相關則需要更大量的關聯、去重、查詢效能等，所以特別買了《Effective SQL》拜讀一番，裡頭提供很多寫 SQL 的優化，以及關聯後各種的 Edge Case，如果你對於寫的 SQL 沒有足夠自信，那很推薦入手

以下將整理幾點我覺得特別有啟發性的
## 關聯運算
在關聯運算中，包含了八種運算
1. 選擇：透過 where / having 過濾
2. 投影：透過 select / group by 選擇回傳欄位
3. 連接：透過 join 連接多張資料表
4. 交集：透過 interset 找出兩個集合的重疊 (MySQL 不支援)，也可以用 INNER JOIN，例如「找到同時買過 bike 與 sakteboard 的客戶」
5. 笛卡爾積：兩個集合的所有組合列舉，使用 CROSS JOIN
6. 聯集：合併兩個欄位相同的集合，透過 UNION
7. 除法：被除數集合中帶有全部除數集合的列，例如「某應徵者符合所以的工作條件」
8. 差集：一個集合減去另一個集合，可以透過 EXCEPT (MySQL 不支援)，但可以用 OUTER JOIN 再去檢查 null 值模擬

### 作法 23: 找出不相符或不存在的紀錄
https://www.db-fiddle.com/f/4WX7yN4GWRrA1wX7zb8AXv/2  
主要可以使用 3 種方式
1. 使用 In
2. 使用 Exists
3. 使用 Left Join 並用 Where

前兩種搭配 subquery，exists 通常性能比 in 好因為只要 subquery 至少存在一列就能 return

### 作法 24: 使用 Case 解決問題的時機
https://www.db-fiddle.com/f/knMFW8pMRiVa6yg22i59DB/0  
紀錄一下 Case 中 when 可以使用 subquery，這讓可能性增大很多，例如標記商品的熱銷程度，可以在 when 中加入 subquery 查詢販賣總數而不用先 outer join 再 select 一次

### 作法 25: 解決多條件問題的技巧
當資料表需要關聯後再用多種條件篩選，要小心下條件的位置避免篩選錯誤，例如「要找出買過 skateboard 又同時買過 helmet / knee pad 的用戶」，需要使用多次 INNER JOIN 才能夠篩選出同時滿足多條件的查詢，要小心不能直接用 IN 會變成 "OR" 的條件
```sql
-- 這只會找到有買過任一商品的用戶
select users.id from users 
where users.id in (
  select orders.user_id from orders
  inner join products on products.id = orders.product_id
  where products.name in ('skateboard', 'helmet', 'knee pad')
);
```

可以適時用 function 簡化重複的 SQL
https://www.db-fiddle.com/f/vpB9hZgNGhnFPZo2FQrLhn/0

### 作法 26: 需要完全符合時使用除法 
https://www.db-fiddle.com/f/sA2VfuFSxW9Lr4krdcUg29/1
假設是一個求職網站，用戶需要找「滿足特定技能組合的職缺」，就需要用到除法的概念，可以用兩種方式
#### 1. 雙重否定：
先看最內層 - 找出用戶所有的與所需技能樹相符合的技能，第一個否定式是找出所需技能樹中用戶有哪些不足的 (not exists)，第二層否定式 `用戶沒有 (所需技能樹中不再(用戶所需的技能樹))`
```sql
select * from users
where not exists (
  select * from prefered_skills
  where not exists (
  	select * from users as u2
    inner join user_skills on user_skills.user_id = u2.id
    where u2.id = users.id and user_skills.skill_id = prefered_skills.skill_id
  )
)
```
邏輯上有點繞，假設所需技能樹需要 js / aws，而 user 只會 rails / aws，第一層會先篩選出 aws (rails 不再所需技能樹內)；第二步會篩選出 js (因為用戶沒有該技能)，第三步計算出 (用戶有缺少所需技能樹) 所以被過濾掉；  
不過以上除了邏輯比較繞，還有一個缺點是 `如果所需技能樹為空，則會回傳所有的行，因為第一層否定會是 all true`

#### 2. 使用 group by 與 having：
這個方法比想像中簡單，透過 LEFT JOIN 找出 user 目前與 prefered_skills 有幾個重複技能，最後直接比 count 是否相同就知道
```sql
select users.id, count(prefered_skills.skill_id) as prefered_skill_count 
from users
    inner join user_skills on user_skills.user_id = users.id
    left join prefered_skills on prefered_skills.skill_id = user_skills.skill_id
group by users.id
having (select count(*) from prefered_skills) = prefered_skill_count;
```

### 作法 33: 不用 GROUP BY 找出最大或最小值
https://www.db-fiddle.com/f/8TMwJykwSRc4Li4J9hbdyb/0
這個提議很有趣也很實用，通常看到 MIN/MAX 很直覺就是用 GROUP BY 找出，但是 GROUP BY 後只會保留聚集的欄位而其他欄位資訊都會消失 (除非用 primary 當作 GROUP BY 條件但通常不會這麼用)，這邊作者給出另一個很棒的替代方案，`使用 LEFT JOIN 找出極值`

例如說今天有一個酒單 \[類別, 產地國家, 酒精濃度\]，我們希望「找出同一類別中最烈的酒同時顯示產地國家」
第一種是錯誤示範，會出現`ER_WRONG_FIELD_WITH_GROUP` 的錯誤 
```sql
select max(alcohol), category, country from beers
group by category;
```

可以用 LEFT JOIN 方式，找到同一個種類中比當前欄位更高的酒精濃度，如果找不到 (where .. is null) 代表當前欄位就是最烈的啤酒 
```sql
select * from beers
left join beers as beers2 on beers.category = beers2.category and beers.alcohol < beers2.alcohol
where beers2.category is null;
```

> Subquery vs JOIN：
> 可以看到 Subquery 在很多時候可以與 JOIN 互相替換，不論是在篩選所關聯的資料表、計算加總等，那究竟兩者誰比較好？
> 網路上普遍說 JOIN 比較好，因為 DBMS 執行時比較容易優化，且 Subquery 每次都會執行；
> 但在這本書中卻沒有明講，有時候 Subquery 涉及的欄位少、可以透過索引加速時 (ex. 基於索引的 COUNT) 反而有可能會更快，最後看來還是要實際跑跑看用 EXPLAIN 才知道

### 窗口函式
早期 SQL 沒有相鄰列的概念，只能用 GROUP BY 做彙整，而窗口函式提供了以當前行計算的類似加總方法，例如在某條件下該行的加總(SUM)、排行 (RANK)、前一筆 (LEAD) 等，可以做到以往很難實踐的功能例如同月跨年的營收成長比例

透過 partition by month 讓窗口依照 month 分類，同時用 year 當作排序，取 lag 也就是前一筆的 revenue 就可以得到「去年同月」的資料
```sql
select year, month, 
	revenue - lag(revenue, 1) over (partition by month order by year asc) as increase
from revenues;
```

常用的還有 ROW_NUMBER / ROW_NUMBER 是單純的行數， RANK 則是按照順序排名，兩者的概念很接近，只有在有重複數值時 RANK 會出現相同的排名；但是當 RANK 相同排名出現後會斷層，如果希望是連續排名可以用 DENSE_RANK 

另外還有 RANGE，可以取前後一個範圍區間做動態彙整

## 總結
SQL 寫起來也頗有挑戰性，要想辦法兼顧簡潔與性能需要一定的時間學習，還有一些進階的議題如階層化顯示等就先略過