---
title: MySQL 關於地理位置的儲存與運算
description: 最近突然好奇如何做LBS服務，最基本的應用場景就是找出某經緯度位置內方圓距離多少內的所有資料，所以就來研究一下MySQL如何處理地理位置。
date: '2018-06-21T22:15:22.655Z'
categories: ['資料庫']
keywords: ['MySQL']
---

最近突然好奇如何做LBS服務，最基本的應用場景就是找出某經緯度位置內方圓距離多少內的所有資料，所以就來研究一下MySQL如何處理地理位置。

## Spatial Reference Systems(SRSs) 空間參考系統

[**Spatial Reference Systems in MySQL 8.0**](https://mysqlserverteam.com/spatial-reference-systems-in-mysql-8-0/)

所有的幾何物件如點/線/面，都必須定義在同一個座標系統，例如說在XY軸平面上有一點(1,2)，但是座標系統可能是一個足球場/或是一台筆電螢幕，足球場上的座標(1,2)跟螢幕上的座標(1,2)是截然不同且無從比較起的。

所以在定義幾何物件時，必須要同時宣告該物件所屬的座標系統，也就是 SRID(spatial reference system identifier)，MySQL和其他的DBMS都必須在相同的SRID下才能夠進行幾何運算。

在MySQL 8.0中支援超過5000種SRSs，常見的有兩種：

1.  SRID 3857：  
    將地球表面投影至平面上，屬於笛卡爾座標系( [Cartesian 2D CS](https://epsg.io/4499-cs))，也就是XY軸相互垂直且單位長度一致。  
    常用於網頁上的地圖系統，如Google Map / Open Street Map等
2.  SRID 4326：  
    屬於真實空間座標系統，將地球視為橢圓體，也就是轉換成經緯度，座標軸彼此不是垂直的，經度最後都在南北極彙整。  
    常用於GPS

## 語法使用

[**DB Fiddle - SQL Database Playground**](https://www.db-fiddle.com/f/bcr9MQnzYG9Acu9SUqyXRV/1)

創建欄位上，可以定義 GEOMETRY型別，欄位可以指定 SRID，需要索引可加上 SPATIAL INDEX(g)，InnoDB/MyISAM都支援。

在插入欄位有兩種做法，一種是直接使用幾何形別，一種是透過 ST_GeomFromText 從字串轉換，目前只有看到後者可以指定 SRID  
`Insert into geom VALUES(Point(1,1), “word”);`   
`Insert into geom2 VALUES(ST_GeomFromText(‘POINT(1 1)’, 4326), “hello”);` 
`Insert into geom2 VALUES(ST_GeomFromText(‘POLYGON((0 0, 0 2, 2 2, 2 0, 0 0))’, 4326), “zip”);  `

MySQL支援多種幾何形別，例如Point / Line / Polygon等。

運算上[MySQL 8.0支援多種函式](https://dev.mysql.com/doc/refman/8.0/en/spatial-relation-functions-object-shapes.html#function_st-contains)，函式皆已 ST_開頭，例如  
算兩點距離  
`SELECT ST_Distance((SELECT g from geom2 where name=’hello’), ST_GeomFromText(‘POINT(0 0)’, 4326)) AS distance;`

判斷是否在某範圍內 (hello是 point 型別，zip 是 polygon型別，判斷)  
`SELECT ST_Within((SELECT g from geom2 where name=’hello’), (SELECT g from geom2 where name=’zip’))`

### 補：經緯度距離換算

在SRID 4326中，地球是偏橢圓狀，人們為了方便透過經緯度用網格做劃分，分辨地理位置的判別，所以要將經緯度換算回實際的距離需要有公式的轉換。

[**Learn How Far It Is From One Latitude Line to the Next**](https://www.thoughtco.com/degree-of-latitude-and-longitude-distance-4070616)

### 經度換算

經度差會隨著往南北極而遞減至零，在赤道大約是 111.321km，而南北緯 40度則為 85 km。

### 緯度換算

緯度間基本上是平行，所以每單位緯度差之間都是相近的，只是因為地球偏橢圓所以高緯度距離越長。  
像是在赤道每一度緯度差實際距離是 110.567 km，在回歸線附近則是 110.948km，如果是在南北極則是 111.169 km，平均大約可以取 111 km。

所以如果要用經緯度差換算實際距離，可以用 haversine 公式，詳細內容可以參考 Wiki  
目前也存在多種換算公式，不同的運算複雜度帶來不同的運算準確度，可以再多加研究。

[**Haversine formula - Wikipedia**](https://en.wikipedia.org/wiki/Haversine_formula)

在MySQL 5.7中支援度上沒有這麼好，所以球型距離轉換公式需要自行換算，詳細可以參考此篇 [https://mysqlserverteam.com/mysql-5-7-and-gis-an-example/](https://mysqlserverteam.com/mysql-5-7-and-gis-an-example/)