---
title: 'Elasticsearch 教學 - API 操作'
description: 主要針對 Elasticsearch 的實作與 API 操作
date: '2020-07-15T08:21:40.869Z'
categories: ['資料庫']
keywords: ['Elasticsearch']
---

以下內容包含基本的 CRUD 操作，Elasticsearch 提供良好的 REST API 呼叫介面，以下模擬情境為書店，旗下有 amazon / eslite 多家書店，每一書店儲存書本相關的資料，如書名、頁數、簡介等  

另外還有一些系統配置與進階功能，看到 Alias 功能覺得十分有趣，讓維運有更多的彈性跟方法去調整資料儲存與硬體架構

如果想之前架構層面，可以參考 [Elasticsearch 系統介紹與評估](https://yuanchieh.page/posts/2020/2020-07-08_elasticsearch-%E4%BB%8B%E7%B4%B9%E8%88%87%E8%A9%95%E4%BC%B0/)

> 基本名詞解釋，Index = MongoDB 的 Collection / MySQL 的 Table；
> Document = MongoDB Document / MySQL Row

## 基本操作 CRUD
### 常見的回傳值
不論請求是否成功，通常會返回 _index / _type / _id / _version / _shard 等資訊  
`_version` 是用來追蹤 document 被改動的次數；  
`_found` 代表文件是否存在
### 建立 
1. 如果系統已經有規劃 _id 
```bash
$ curl -XPUT http://localhost:9200/amazon/book/1?op_type=create
```
2. 如果沒有 _id 則由 Elasticsearch 生成，預設生成的 `_id 是 22字元長 + Base64 編碼 + URL 合法的字串`
```bash
$ curl -XPOST http://localhost:9200/amazon/book
```
### 刪除
```bash
$ curl -XDELETE http://localhost:9200/amazon/book/1
```
可以看到回傳值 _version 也會被增加
### 更新 / 部分更新
```shell
$ curl -XPUT http://localhost:9200/amazon/book/1

// 部分更新
$ curl -XPOST http://localhost:9200/amazon/book/1/_update
```
對 Elasticsearch 來說，所有的資料都是不可變的，所以更新其實是建立新的文檔並刪除舊的

另外有個動詞是 `Indexing`，也就是建立與更新合在一起，沒有文檔時建立、存在時就更新

#### scripting
有時候我們會希望基於現有的 document 欄位進行更新，例如說瀏覽次數 +1 等等的功能，可以透過 scripting 語法  
如
```bash
curl -XPOST curl http://localhost:9200/amazon/book/iVKeNXMBpRlP8dKifEma/_update -H 'Content-Type: application/json' \
-d '{ "script": "ctx._source.page_num += 1" }'
```
在 Body 中夾帶 `script`，並指定欄位與操作即可，像這邊我是將書籍的頁面 +1
#### upsert
有時候欄位要更新時可能不存在，可以透過 upsert 指定欄位不存在時的行為
```bash
'{ "script": "ctx._source.page_num += 1", "upsert": { "page_num": 100 } }'
```

### 樂觀鎖與 _version
當每次有寫的操作，document 的 _version 都會被 +1，這是為了實踐樂觀鎖提供在併發狀況下的保護，在所有的操作中可以加入 querystring `?version=` 確保版號
例如我要查找 id="iVKeNXMBpRlP8dKifEma" 的書籍且確保是 version 1
```bash
curl http://localhost:9200/amazon/book/iVKeNXMBpRlP8dKifEma?version=1
```
如果有其他人已經更動過書籍導致 version 不再是 1，此操作會拋出 `409` 錯誤
```bash
"reason":"[iVKeNXMBpRlP8dKifEma]: version conflict, current version [4] is different than the one provided [1]","index_uuid":"gSaILK3KSH6UCpOeYBGKcQ","shard":"0","index":"amazon"},"status":409
```

> Warning：樂觀鎖僅適用於單文檔更新，Elasticsearch 沒有 Transaction 概念，所以沒有多文檔更新的一致性保證
### 查詢
```bash
$ curl -XGET http://localhost:9200/amazon/book/1
```
如果想要針對多筆 document 查詢
需指定多筆的 index/type/id，如果某一個檔案不存在回傳值得 _found 就會是 false
```bash
跨 index 查詢
$ curl http://localhost:9200/_mget -H 'Content-Type: application/json' \
-d '{ "docs": [ { "_index": "amazon", "_type": "book", "_id": 5 }, { "_index": "amazon", "_type": "book", "_id": "iVKeNXMBpRlP8dKifEma" } ]  }

也可以在同一個 index/type 底下查詢，只要標注 id 就好
$ curl http://localhost:9200/amazon/book/_mget -H 'Content-Type: application/json' \
-d '{ "ids": [ 1, "iVKeNXMBpRlP8dKifEma" ]  }
```
### 批次寫入操作
如果我們想要一次建立多個檔案，或是刪除等，甚至是混雜各種查詢一次性呼叫，可以使用 batch  
Elasticsearch 執行 Batch 時會同時`獨立處理，結果也需要去對應的 Response 查詢`，如果有 Shard 就會分散到對應的 Shard 最後再把結果合併
如果操作是 create/index/update 的話，下一行是放 document 內容  
```bash
curl http://localhost:9200/_bulk -H 'Content-Type: application/json' \
-d $'{ "create": {"_index":"amazon", "_type":"book", "_id": 2 }\n {"name":"....","page_num":991,"publish_date":"2017/05/16","intro": "...."}\n{"delete": { "_index": "amazon", "_type": "book", "_id": 5 } }\n
```  
需注意 Body 中是以 `\n` 當作新的指令開始，且`最後一筆紀錄也要以 \n 結尾`  

> 為什麼 Elasticsearch 不用 JSON Array 當作 Body 呢？  
這是因為如果是 Array 的話，Node 接收到之後還要去拆解 Array，接著決定哪些 Query 是屬於哪個 Shard 在包一層 Array；
直接使用 JSON Object 加上 \n 可以不用額外的記憶體空間，用換行字符拆解 Query 就好，節省許多不必要開銷

## 搜尋
Elasticsearch 在搜尋上彈性很大，可以跨 index / 跨 type 搜尋  
```bash
curl http://localhost:9200/_search
```
指定條件部分，可以用 querystring 或是 Body 夾帶，推薦後者因為彈性與可維護性更高
#### 指定某欄位的條件搜尋
```bash
curl http://localhost:9200/amazon/book/_search?q=name:Elasticsearch 
```
用 `q=${欄位名稱}:${條件}`，如果有多筆則用`+`連結  
#### 某文檔任一欄位符合條件搜尋
在 Elasticsearch 中，每個文件都有一個特出欄位 `_all`，也就是把文件中所有的字串格式欄位都拼接起來
```bash
curl http://localhost:9200/amazon/book/_search?q=Elasticsearch 
```
### Mapping
為了更好的支援搜尋，Elasticsearch 在寫入文件時會有建立 Schema，可以透過以下指令查詢
```bash
curl http://localhost:9200/amazon/_mapping
```

型別有分成 text / number 系列(int, long) / date / boolean / object / geo_point 等等 [非常多種](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html)  
如果欄位是 Array，則以第一個元素的型別為主，且同一 Array 中元素必須都是同型別

```json
{
    "amazon": {
        "mappings": {
            "properties": {
                "intro": {
                    "type": "text",
                    "fields": {
                        "keyword": {
                            "type": "keyword",
                            "ignore_above": 256
                        }
                    }
                },
                "page_num": {
                    "type": "long"
                },
                "publish_date": {
                    "type": "date",
                    "format": "yyyy/MM/dd HH:mm:ss||yyyy/MM/dd||epoch_millis"
                },
				...
            }
        }
    }
}
```

也可以主動針對 Index 設定 Schema 與調整型別設定，例如說索引的深度與數量等，預設 Elasticsearch 會把每個欄位都建立索引，所以記憶體消耗非常驚人

> Warning: 型別設定後只能新增欄位，不能更動既有的型別或 Indexing，最好是一開始就設定好，不然要 ReIndex ，詳見後續

### 建立 Mapping
先刪除 amazon Index，重新建立 Index 與 Mapping  
假設我希望 page_num 欄位是 Integer 且不要建立索引
```bash
$ curl -XPUT http://localhost:9200/amazon/_mapping -H 'Content-Type: application/json' \
	--data '{ "properties": { "page_num": { "type": "integer", "index": false }  }  }'
```
重新將資料寫入後，其餘的欄位 Elasticsearch 會幫忙補上型別，page_num 因為已經存在則不會改變    
需要注意如果 `index指定false` 則使用 `/_search?q` 會無法搜尋  

### Analyzer  
如果只能針對條件做篩選，這一般的資料庫也做得到，真正讓 Elasticsearch 區別於一般資料庫的地方在於 Analyzer  
每個文檔的欄位除了型別定義與索引外，還可以指定該欄位如何被分析，例如說最基本的`斷詞` "中華民國" 要拆成 "中"、"華"、"民"、"國" 還是 "中華"、"民國"等有多種方式，決定如何斷詞會影響查詢   
另外像`語意分析`，如果我們想搜尋「Quick fox jumps」，我們不單希望字面上完全符合，而是找到類似下者的文檔 `A quick brown fox jumps over the lazy dog`

所以 Analyzer 主要分成三個部分
1. `character filter`   
決定字元如何處理，像是轉換數字格式 / 去除 HTML tag 等  
2. `tokenizer`  
決定字元如何組合成字串，英文預設是用空白，每個 Analyzer 一定也只能有一個 tokenizer
3. `token filter`  
將字串做處理，例如全部轉小寫 / 過濾同義詞等

#### 測試 Analyzer 
如果不知道要怎麼選擇 Analyzer，可以看文件找出[內建的 Analyzer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-analyzers.html)並透過 API 去測試，指定不同的 Analyzer 與測試字串
```bash
$ curl http://localhost:9200/_analyze -H 'Content-Type: application/json' \
	--data '{ "analyzer": "standard", "text":"this is a test" }' 

$ curl http://localhost:9200/_analyze -H 'Content-Type: application/json' \ 
	--data '{ "filter": ["lowercase"], "char_filter" : ["html_strip"], "tokenizer": "whitespace",  "text":"this <a>iS</a> A Test" }' 
```
可以看到回傳值是 Analyzer 會如何 parse 字串並產生索引的 keyword，更多的參數可以參考文件 [Analyze API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-analyze.html)    
如果需要支援中文，則需要另外安裝 plugin   
#### 調整欄位的 Analyzer  
可以在 Index 下建立客製化的 Analyzer，例如我建立一個 `my_intro_analyzer`
```bash
$ curl -XPUT http://localhost:9200/amazon/_settings -H 'Content-Type: application/json' --data \
	'{ "analysis": { "analyzer": { "my_intro_analyzer": { "filter": ["lowercase"], "char_filter" : ["html_strip"], "tokenizer": "whitespace" } } } }'
```

透過 Mapping API 去更改欄位的 Analyzer，同樣是不能更改既有的 Index，且只能指定 Analyzer 而不能在欄位中自訂 tokenizer 等
```bash
$ curl -XPUT http://localhost:9200/amazon -H 'Content-Type: application/json' --data \ 
	'{ "mappings": { "properties": { "intro": { "type": "text", "analyzer": "my_intro_analyzer"  } }  }, "settings": { "analysis": { "analyzer": { "my_intro_analyzer": { "filter": ["lowercase"], "char_filter" : ["html_strip"], "tokenizer": "whitespace" } } } } }'
```

> 看起來 Indexing 深度與 Analyzer 分析的 Token 數都需要設定上限，否則預設值會變成記憶體怪獸!

## DSL
前面提到搜尋時可以用 querystring 加上條件，但為了設定更複雜且彈性的查詢語法，可以使用 Elasticsearch 自訂的查詢語言  
### Query
如果今天想要找欄位中是否有相近的值，可以用 `match`
```bash
$ curl http://localhost:9200/amazon/_search -H 'Content-Type: application/json' --data \
 '{ "query": { "match": { "name": "Distributed" }  }  }'
```
### Filter
如果今天想要找欄位中完全一模一樣值，可以用 `term` 接篩選條件
```bash
$ curl http://localhost:9200/amazon/_search -H 'Content-Type: application/json' --data \
 '{ "query": { "term": { "name": "Elasticsearch: The Definitive Guide: A Distributed Real-Time Search and Analytics Engine 1st Edition, Kindle Edition" }  }  }'
```
### 組合多種條件
如果今天要搜尋的條件比較複雜，例如說我希望`名稱一定要包含 Distributed`，頁數`最好`在200至500頁或是出版年份在今年(但兩者必須至少符合一項)  
可以用 `bool` 搭配 `must` 必須符合 + `should` 應該符合，搭配 `minimum_should_match` 可以決定條件的符合程度
```bash
curl http://localhost:9200/amazon/_search -H 'Content-Type: application/json' --data \
'{ "query": { "bool": { "must": { "match": { "name": "Distributed" } }, "minimum_should_match": 1, "should": [ { "range": { "page_num": { "gt": 200, "lt": 500 } } }, { "range": {"publish_date": { "gt": "2020/01/01" } } } ] } } }'
```

## 系統配置與設定
### Sharding 相關
#### 1. 設定 Index 的 sharding 與 replica 數量
有兩種方式，一種是建立 Index 時就指定，第二種是建立 Index 後續調整
```bash
1. 建立 Index 指定
curl -XPUT http://localhost:9200/amazon -H 'Content-Type: application/json' --data \
'{ "index": { "number_of_shards": 2, "number_of_replicas": 0 }  }'

2. 後續動態調整
curl -XPUT http://localhost:9200/amazon/_settings -H 'Content-Type: application/json' --data \
'{ "index": { "number_of_replicas": 0 }  }'
```
需注意 sharding number 最好一開始就設定好，可以配置稍微多一點 Primary shard 方便後續 scale out  
後續如果要動態調整很麻煩，要把 Index 設成 read-only 並透過 Split API 修改 / 或是用 Reindex 方式重建新的 Index 

#### 2. 指定 Index 使用的機型
有時候我們會希望某些熱門的 Index 使用較好的硬體，其他冷門的使用差一點的硬體，Elasticsearch 在機器運作時可以打上標記 `--node.box_type`
```bash
$ ./bin/elasticsearch --node.box_type strong
```
指定 Index 要存放的機型
```bash
$ POST /logs_2014-09-30/_settings
{
  "index.routing.allocation.include.box_type" : "strong"
}
```
結合後續的 Alias 可以配置出更符合實際應用的設定

#### Index template  
當建立新的 Index 時，可以指定 template 套用設定，就不用每次都要打設定，Elasticsearch 在 7.8 版本中，可以指定 component template 與 index template；  
component template 是小單位可以被用來組合的；而 index template 則是 Index 直接套用的

```bash
// Component template
PUT _component_template/other_component_template
{
  "template": {
    "mappings": {
      "properties": {
        "ip_address": {
          "type": "ip"
        }
      }
    }
  }
}

// Index template，只要 Index 開頭是 bar 就會套用
PUT _index_template/template_1
{
  "index_patterns": ["bar*"],
  "template": {
    "settings": {
      "number_of_shards": 1
    },
    "mappings": {
      "_source": {
        "enabled": false
      },
      "properties": {
        "host_name": {
          "type": "keyword"
        },
        "created_at": {
          "type": "date",
          "format": "EEE MMM dd HH:mm:ss Z yyyy"
        }
      }
    },
    "aliases": {
      "mydata": { }
    }
  },
  "priority": 10,
  "composed_of": ["component_template1", ....],
  "version": 3,
  "_meta": {
    "description": "my custom"
  }
}
```

### Reindex 與 Alias
先介紹 `Alias`，看到這個功能讓我覺得十分驚豔，可以將維運與開發拆分的更加獨立  
今天假設因為資料的格式問題 / Sharding 重新分配等問題需要`Index 需要重建`，Alias 就能派上用場  

他的概念就好像檔案連結，可以取一個連結名稱，但同時對應到多個實際的檔案路徑，例如說我有兩個 Index 想要分開儲存 /amazon + /eslite  
但我希望查詢時可以有一個共同的 endpoint 取名叫 /bookstore，就可以用 Alias 連結 /amazon 與 /eslite
```bash
$ curl -XPUT http://localhost:9200/eslite/_alias/bookstore
$ curl -XPUT http://localhost:9200/amazon/_alias/bookstore

$ curl http://localhost:9200/boostore/_search
// 同時返回 amazon / eslite 底下的文檔 

$ curl http://localhost:9200/*/_alias/bookstore
// 查詢哪些 Index 有設定 alias 為 bookstore 

$ curl -X DELETE http://localhost:9200/amazon/_alias/bookstore
// 刪除 alias 
```
雖然搜尋的時候也可以直接指定多個 Index 如 `curl http://localhost:9200/amazon,eslite/_search`，但如果要增減 Index 項目就需要改程式碼，十分不乾淨  

另外更大的好處在於同一個 Index 要升級時，實際儲存可以用版號如 index_name_v1，用 alias 指定 index_name；  
接著在建立新的 index_name_v2 換成新的 Index，完成後在切換 index_name 的指向就能 zero downtime 切換 index 了  

> 查詢時指定 alias 就可 / 寫入時如果 alias 下只有一個 index 就不用指定；超過一個必須指定寫入的 index 

### 拆分 Index 與 Alias 應用
假設今天我們拿 Elasticsearch 當作 Logging Service，通常是越近期的資料越熱門，時間久之後舊資料可能要移除或轉出保存  
在系統設計上，我們要考量幾個點
> 1. 儲存時區分新資料與舊資料
2. 搜尋時希望新資料與部分舊資料都可以被查詢
3. 舊資料的定期刪除與冷保存  

書中建議，Log 依照時間區間建立新的 Index，例如每個依照每個月份儲存 `2020-05` 就單放五月份的 Log   
建立新的 Index 時可以透過 template 綁定預設值，就不用每次都要手動預先建立 Index 了  
假設查詢時會希望搜尋近期 3 個月的資料，與其每次都指定 3 個 Index，可以透過 `Alias` 簡化查詢語法

拆分多個 Index 好處是調整非常彈性，例如說舊的 Index 可以`取消 Replica / 移到較差的硬體 / 單獨備份 / 整個砍掉(效率遠比砍 document 好)`

## 總結
礙於篇幅，其他還有處理自然語言 / 地理位置資料 / 實際上線的注意事項等等進階議題，只能等之後真的有用上再來分享  