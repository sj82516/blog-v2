---
title: 'Vector DB 初探與 Weaviate DB 教學'
description: 兩週前看到 Fireship 介紹 Vector DB，用來儲存與高效查詢向量 vector，搭配 AI embedded 可以做出許多 AI empower 的功能，包含文字、圖片、影片等多媒體的相似查詢
date: '2023-04-24T00:21:40.869Z'
categories: ['DB']
keywords: ['Database']
---
{{<youtube klTvEwg3oJ4>}}

當我們希望打造一個基於語意相似的文字搜尋時，一般的作法是將文字透過 AI model 轉成 embeddeding vector，透過計算 vector distance (cosine distancing) 找出距離最相近的文字 kNN (k nearest neighbors)，例如 [OpenAI 的 demo code：Semantic_text_search_using_embeddings](https://github.com/openai/openai-cookbook/blob/main/examples/Semantic_text_search_using_embeddings.ipynb)

當資料量小的時候，這樣做不會有什麼問題，但仔細看目前的比對方式是把輸入跟資料集的資料每一筆 vector 都做 distance 計算，所以複雜度會是 `O(N)，N 是資料集數量`，如果資料量一大，這勢必會是造成瓶頸

Vector DB 就是要解決這樣的問題，主要透過
- 改用 ANN (approximate nearest neighbors) 取代 kNN，用相似度查詢換取執行速度
- 提供 database 功能，包含持久化保存、水平擴展 (sharding)、高可用性、API 封裝等功能

![](/post/2023/img/0424/vector_db.png)

目前搜尋市面上有幾個常見的選擇
- [Pinecone](https://www.pinecone.io/)：閉源專案，就先略過不用
- [Milvus](https://milvus.io/)：純 vector DB，看起來在基礎建設 (scaling、availability) 等做得比較完整
- [Weaviate](https://github.com/weaviate/weaviate)：有 module 可以支援 AI model 整合，也支援純 vector DB 使用
- [Chroma](https://docs.trychroma.com/)：Fireship demo 用

這次 Demo 選擇用 Weaviate，主要是有支援 module 直接整合 AI model，這樣我就不用另外想 embedding vector 該如何產生

![](/post/2023/img/0424/weaviate-module-diagram.svg)

## Weaviate DB 基本介紹
Weaviate DB 有以下幾個特色
- 便利性：  
module 支援常見的 AI model，包含 transformer、openai 等，透過參數可以直接調整，但有些 AI model 部分需要自己架設 server，Weaviate DB 核心並不包含 AI model，只是會直接透過 interface 調用
![](https://weaviate.io/assets/images/weaviate-module-apis-3a56351def9cd3a66f6cd0186875d2c4.svg)
- 搜尋與過濾：  
除了 vector 搜尋外，在文字上會結合 inverted index 增加搜尋的精準度與效率，並提供 `filter 可以透過屬性篩選`
- API 接口支援 REST 與 GraphQL
- 擴充性：    
會提供 Sharding 與 High Availability (後者還在開發中)

### 儲存概念
以 `Class` 為管理單位，可以理解成 table 或 collection 的概念，每個 class 有自己 vectorize 的機制、sharding 設定等，例如
```json
{
  "class": "string",                        // The name of the class in string format
  "description": "string",                  // A description for your reference
  "vectorIndexType": "hnsw",                // Defaults to hnsw, can be omitted in schema definition since this is the only available type for now
  "vectorIndexConfig": {
    ...                                     // Vector index type specific settings, including distance metric
  },
  "vectorizer": "text2vec-contextionary",   // Vectorizer to use for data objects added to this class
  "moduleConfig": {
    "text2vec-contextionary": {
      "vectorizeClassName": true            // Include the class name in vector calculation (default true)
    }
  },
  "properties": [                           // An array of the properties you are adding, same as a Property Object
    {
      "name": "string",                     // The name of the property
      "description": "string",              // A description for your reference
      "dataType": [                         // The data type of the object as described above. When creating cross-references, a property can have multiple data types, hence the array syntax.
        "string"
      ],
      "moduleConfig": {                     // Module-specific settings
        "text2vec-contextionary": {
          "skip": true,                     // If true, the whole property will NOT be included in vectorization. Default is false, meaning that the object will be NOT be skipped.
          "vectorizePropertyName": true,    // Whether the name of the property is used in the calculation for the vector position of data objects. Default false.
        }
      },
      "indexInverted": true                 // Optional, default is true. By default each property is fully indexed both for full-text, as well as vector search. You can ignore properties in searches by explicitly setting index to false.
    }
  ],
  "invertedIndexConfig": { 
    ... 
  },
  "shardingConfig": {
    ...                                     // Optional, controls behavior of class in a multi-node setting, see section below
  }
}
```

每個 Class 內包含多個 Object 以 json 格式儲存，Object 內的屬性 (Property) 支援[多種格式](https://weaviate.io/developers/weaviate/config-refs/datatypes)，額外有提供地理位置、日期、電話號碼(有點不解?!)，其中地理位置在查詢上還支援方圓內的篩選

Class schema 是靜態的，如果要增減欄位需要透過 API 修改，而不像某些 NoSQL 是動態寫入的

### 物理儲存以 Shard 為單位
一個 Class 在物理儲存上有多個 [Shard](https://weaviate.io/developers/weaviate/concepts/storage)，每個 Shard 會包含 vector index / object store / inverted index，其中 vecotr index 目前是用 HNSW，其餘兩個是用 LSMTree 儲存

## Demo - 打造簡易的文字查詢
程式碼在 [sj82516/weaviate-db-demo](https://github.com/sj82516/weaviate-db-demo)，在本地端啟動 Weaviate DB 並做簡易的文字查詢
### 透過 docker-compose 啟動
這邊我們只做文字搜尋的部分，選用 transformer 當作 AI model，可以查看[不同的 modules](https://weaviate.io/developers/weaviate/modules)
```yml
version: '3.4'
services:
  weaviate:
    image: cr.weaviate.io/semitechnologies/weaviate:1.18.3
    ports:
      - "8080:8080"
    environment:
      QUERY_DEFAULTS_LIMIT: 20
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: "./data"
      DEFAULT_VECTORIZER_MODULE: text2vec-transformers
      ENABLE_MODULES: text2vec-transformers
      TRANSFORMERS_INFERENCE_API: http://t2v-transformers:8080
      CLUSTER_HOSTNAME: 'node1'
  t2v-transformers:
    image: semitechnologies/transformers-inference:sentence-transformers-multi-qa-MiniLM-L6-cos-v1
    environment:
      ENABLE_CUDA: 0 # set to 1 to enable
      # NVIDIA_VISIBLE_DEVICES: all # enable if running with CUDA
```
### 建立 Class 與匯入資料
Class schema 可以主動宣告，或是讓 Weaviate DB 自動幫忙建立 (有點像 Elasticsearch)，這邊建立了一個 Class 並指定 module 用 text-transformer
```golang
client.Schema().ClassCreator().WithClass(&models.Class{
  Class:       className,
  Description: "all books I have",
  Vectorizer:  "text2vec-transformers",
  ModuleConfig: map[string]interface{}{
    "text2vec-transformers": map[string]interface{}{},
  },
  Properties: []*models.Property{
    {
      Name:     "title",
      DataType: []string{"text"},
    },
  },
})
```
匯入資料可以批次匯入
```golang
objects := []*models.Object{
  {
    Class: className,
    Properties: map[string]interface{}{
      "title": "Hello World Blue",
      "type":  "program",
    },
  },
  {
    Class: className,
    Properties: map[string]interface{}{
      "title": "Hello World Red",
      "type":  "program",
    },
  }, {
    Class: className,
    Properties: map[string]interface{}{
      "title": "Hello World Yellow",
      "type":  "science",
    },
  },
}

client.Batch().ObjectsBatcher().
  WithObjects(objects...).
  WithConsistencyLevel(replication.ConsistencyLevel.ALL).
  Do(context.Background())
```

### 搜尋與篩選
完整查詢有三個部分 搜尋 + 篩選 + 欄位過濾
```golang
// 文字搜尋
nearText := client.GraphQL().NearTextArgBuilder().
  // 搜尋的關鍵字
  WithConcepts(concepts).
  // 讓向量往某個方向靠近
  WithMoveTo(&graphql.MoveParameters{
    Force: 0.5,
    Concepts: []string{
      "Yellow",
    },
  })

// 篩選機制
where := filters.Where().
  WithPath([]string{"type"}).
  WithOperator(filters.Equal).
  WithValueText("program")

// 選擇欄位回傳
fields := []graphql.Field{
  {Name: "title"},
  // 額外的欄位，算是 metadata
  {Name: "_additional", Fields: []graphql.Field{
    {Name: "id"},
    {Name: "distance"},
  }},
}

// GraphQL Request
result, err := client.GraphQL().Get().
  WithClassName(className).
  WithNearText(nearText).
  WithWhere(where).
  WithFields(fields...).
  Do(context.Background())

if result.Errors != nil {
  for _, err := range result.Errors {
    fmt.Println(err.Message)
  }
  return
}

r := result.Data["Get"].(map[string]interface{})[className].([]interface{})

jsonbody, err := json.Marshal(r)
if err != nil {
  // do error check
  fmt.Println(err)
  return
}

books := []Book{}
if err := json.Unmarshal(jsonbody, &books); err != nil {
  // do error check
  fmt.Println(err)
  return
}

for _, book := range books {
  fmt.Println(book)
}
```

在 searching 搜尋中，如果是 text Weaviate DB 會用 inverted index 與 vector 搜尋 `WithNearText`，找出的結果會給出對應的 distance
```golang
nearText := client.GraphQL().NearTextArgBuilder().
  WithConcepts(concepts).
  WithMoveTo(&graphql.MoveParameters{
      Force: 0.5,
      Concepts: []string{
          "Yellow",
      },
  })
```
- concepts 搜尋的文字陣列
- WithMoveTo 額外指定搜尋要特別接近哪些關鍵字  
參數可參考 [Vector search parameters](https://weaviate.io/developers/weaviate/api/graphql/vector-search-parameters)

也可以針對屬性做篩選，例如我只要 object 中 type = program 的資料
```golang
where := filters.Where().
  WithPath([]string{"type"}).
  WithOperator(filters.Equal).
  WithValueText("program")
```

搜尋的結果大概是 (Yellow 被篩選掉)
> {Hello World Blue  {b9f93a34-6cbd-45b3-afc3-f82e9d1d0da8 0.54240143}}  
{Hello World Red  {6575290e-53cc-4ab9-8d39-330e5a47b0d1 0.55338395}}

## ANN 演算法：HNSW 介紹
![](https://d33wubrfki0l68.cloudfront.net/00e2d0033d5802e0016a442757bb9ee603e02d2b/caebb/images/hnsw-2.jpg)
HNSW (Hierarchical Navigable Small World) 是一種 ANN 演算法，主要是借鏡 借鏡 probability skip list，透過分層查詢，先從最上層最稀疏的 layer 開始找最相近的鄰居，接著往下一層找該鄰居的最相近鄰居，一直到最底層 (layer 0)  
> 查詢複雜度降至 log (N)

這部分有兩個參數可以注意
- efConstruction: 決定每次查詢回傳的鄰居數量，數量越多查詢越精準，但是效率越差
- maxConnections: 決定每個 point 可以連接的 edge 數量，同樣是數量越多越精準

### 如何決定 point 要插入哪一層
這部分便是透過機率所決定，越上層機率越低
![](https://d33wubrfki0l68.cloudfront.net/a93d856af84ab39170d4a056a5a05ff63bf23552/8e259/images/hnsw-8.jpg)


## 結語
快速瞭解了一下 Vector DB，未來如果有需要做向量查詢使用上應該會蠻方便的，之後有機會在評估一下 [Milvus](https://milvus.io/docs/overview.md)，看起來基礎建設比 Weaviate DB 更完善、Github 上熱度也更高、也支援更多的 ANN 演算法  

另外 Elasticsearch 在 8.0 也有支援 vector search，如果以經有在用 ES 也可以直接當作 Vector DB 使用