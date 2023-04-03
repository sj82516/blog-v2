---
title: '[筆記] AWS s3 性能提升小撇步 — Amazon S3 Performance Tips & Tricks'
description: >-
  AWS S3
  用來做靜態資源管理，可以用來儲存非常大量的資料且有很高保持性(duribility:99.9999999%)的保證；在這篇官方的部落格中記載著S3內部的一些儲存機制以及優化的小技巧。
date: '2018-09-25T21:34:31.149Z'
categories: ['雲端與系統架構']
keywords: []

  
---

[**Amazon S3 Performance Tips & Tricks + Seattle S3 Hiring Event | Amazon Web Services**](https://aws.amazon.com/tw/blogs/aws/amazon-s3-performance-tips-tricks-seattle-hiring-event/)

AWS S3 用來做靜態資源管理，可以用來儲存非常大量的資料且有很高保持性(duribility:99.9999999%)的保證；  
在這篇官方的部落格中記載著S3內部的一些儲存機制以及優化的小技巧。

如果是每秒 API Request小於 50者，其實不太會有影響，S3 有自動的監控程序(Agent)，試著去平衡資源與增加系統的平均附載。

S3在內部維護了一張 Map，Map對應的Key 是 Bucket 中物件的名稱，S3會用物件的初始名稱當作 Key；  
實際物件的儲存會被分散到不同的 parition中，而 S3為了提供依照按字典順序排列的API， 在做 partitioning 的依據同樣是透過 Bucket的物件初始名稱；

所以如何取 `Bucket的物件名稱`就是影響性能的關鍵，在S3內部 Map的key  
`bucketname/keyname` ，S3會自動取前綴

有些人會習慣用 user ID / game ID/ 日期 / 遞增數字等，這些 Key的共通特性是前綴類似，這當作S3 Key會導致幾個問題  
1\. 傾向儲存在同一個 partition中  
2\. 所有的 partition 會有漸冷的效果，例如用日期儲存，通常越近的日期資料越容易存取，也就是partition 的使用量不平均

以下就是不好的示範
```md
2134857/gamedata/start.png  
2134857/gamedata/resource.rsrc  
2134857/gamedata/results.txt  
2134858/gamedata/start.png  
2134858/gamedata/resource.rsrc  
2134858/gamedata/results.txt  
2134859/gamedata/start.png  
2134859/gamedata/resource.rsrc  
2134859/gamedata/results.txt
```
有個非常簡單的方法可以做到，也就是在開頭加 hash，或是將日期字串反轉，總之要確保前兩到三位是不重複字串且寫入的物件數雷同
```md
7584312/gamedata/start.png  
7584312/gamedata/resource.rsrc  
7584312/gamedata/results.txt  
8584312/gamedata/start.png  
8584312/gamedata/resource.rsrc  
8584312/gamedata/results.txt  
9584312/gamedata/start.png  
9584312/gamedata/resource.rsrc  
9584312/gamedata/results.txt
```
S3會自動識別 prefix並分散到不同的 partition

/7  
/8  
/9

至於 prefix 真正到底如何取值文章並沒有說明，僅提到 prefix 理論上只有兩到三位即可，根據另一篇 AWS官方文章 [Request Rate and Performance Guidelines](https://docs.aws.amazon.com/AmazonS3/latest/dev/request-rate-perf-considerations.html)，應用程式存取S3的API限制為

> 3,500 PUT/POST/DELETE and 5,500 GET requests per second per `prefix` in a bucket

所以 hex hash 三位，最大讀取值可達 16 \* 16 \* 16 \* 5500 GET API Call /per second，這理論上可以滿足絕大多數的產品需求了；  
甚至大多數的產品還不需要 prefix的命名優化。