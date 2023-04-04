---
title: 'Elasticsearch 操作： Golang Opensearch SDK 使用筆記'
description: 最近在用 Golang 做 Elasticsearch 相關的專案，在看文件到實際使用上有一段落差，寫個簡單的筆記補上 Golang 與 Elasticsearch 互動的方式
date: '2023-03-17T02:21:40.869Z'
categories: []
keywords: []
---
## 前言
Elasticsearch 是常用來做全文搜尋的 NoSQL Database，公司在使用上有自架也有用 AWS Opensearch 託管服務
要特別留意的是 Opensearch 是 AWS 自己 fork 維護，兩者不完全兼容，至少在 `client sdk 連線是不兼容的!` 原本使用 [Golang Elasticsearch 官方 SDK v7.17](https://github.com/elastic/go-elasticsearch) 要連線 Opensearch 回直接拋錯 
> error: the client noticed that the server is not a supported distribution of Elasticsearch

一些相關的文章 [\[Elasticsearch\] The Server Is Not A Supported Distribution Of Elasticsearch](https://towardsaws.com/elasticsearch-the-server-is-not-a-supported-distribution-of-elasticsearch-252abc1bd92)
> Since the AWS Elasticsearch Service has incompatible APIs with Elasticsearch itself, either by missing APIs or has incompatible format, we do not support it.

Beef 應該可以往前追溯幾年前 Elasticsearch 覺得 AWS 在白嫖開源社群進而更改授權，使得 AWS 決定自己維護 Opensearch (新聞 [AWS分叉Elasticsearch重新命名為OpenSearch](https://www.ithome.com.tw/news/143812))

但有趣的是我測試了一些場景，AWS Opensearch client SDK 可以連線 Elasticsearch (以下簡稱 ES) 與 Opensearch server，所以以下就用 [Opensearch cliend SDK](https://github.com/opensearch-project/opensearch-go) 操作 ES，後續不會針對 ES 本身有太多介紹，可以參考之前的幾篇文章 [Elasticsearch 教學 - API 操作](https://yuanchieh.page/posts/2020/2020-07-15_elasticsearch-%E6%95%99%E5%AD%B8-api-%E6%93%8D%E4%BD%9C/) 和 [Elasticsearch 系統介紹與評估](https://yuanchieh.page/posts/2020/2020-07-08_elasticsearch-%E4%BB%8B%E7%B4%B9%E8%88%87%E8%A9%95%E4%BC%B0/)

## Client SDK 使用
以下使用會覆蓋幾個場景
1. 建立 Client 連線
2. 建立 Index
3. 插入 Document
4. 搜尋 Document
5. 建立 Mapping
6. 刪除 Index  

完整原始碼參考 https://github.com/sj82516/elasticsearch-golang，或是參考 [Opensearch 官方文件](https://opensearch.org/docs/latest/clients/go/)

```go
func main() {
    // connect to elasticsearch
    client, _ := opensearch.NewClient(opensearch.Config{
        Addresses: []string{
            "http://localhost:9200",
        },
    })
    
    // create index
    res, _ := client.Indices.Create(index)
    fmt.Println(res)

    // create document
    createThenSearch(res, client)

    // refresh
    client.Indices.Refresh()
}

func createThenSearch(res *opensearchapi.Response, client *opensearch.Client) {
    // create document
    createDocument(res, client, `{"key": "key1", "title":"Test my first document", "number": 5}`)
    createDocument(res, client, `{"key": "key1.child", "title":"Test my first document", "number": 5}`)
    
    // refresh
    client.Indices.Refresh()
    
    // search document by text field
    r := search(res, client, "title", "document")
    fmt.Println("search by title:", r)
    
    r = search(res, client, "key", "key1")
    fmt.Println("search by key:", r)
    
    r = search(res, client, "key", "child")
    fmt.Println("search by key:", r)
}

func createDocument(res *opensearchapi.Response, client *opensearch.Client, document string) {
    req := opensearchapi.IndexRequest{
        Index: index,
        Body:  strings.NewReader(document),
    }
    res, _ = req.Do(context.Background(), client.Transport)
}

type searchResponse struct {
    Hits struct {
        Total struct {
            Value int `json:"value"`
        } `json:"total"`
        Hits []struct {
            Score  float64 `json:"_score"`
            Source struct {
                Key    string `json:"key"`
                Title  string `json:"title"`
                Number int    `json:"number"`
            } `json:"_source"`
        } `json:"hits"`
    } `json:"hits"`
}

func search(res *opensearchapi.Response, client *opensearch.Client, key string, value string) searchResponse {
    s := map[string]interface{}{
        "query": map[string]interface{}{
            "match": map[string]interface{}{
                key: value,
            },
        },
    }
    
    body, _ := json.Marshal(s)
    searchReq := opensearchapi.SearchRequest{
        Index: []string{index},
        Body:  bytes.NewReader(body),
    }
    
    res, _ = searchReq.Do(context.Background(), client.Transport)
    var r searchResponse
    json.NewDecoder(res.Body).Decode(&r)
    return r
}
```

以上是大致的 API 操作，呼叫起來不太麻煩，只是文件有點簡陋需要不停的查找，建議可以開著 Kibana 的後台對應查詢與回應，有 hint 蠻方便的
![](/post/2023/img/0319/kibana.png)

有兩個地方需要特別留意
1. 如果是本地端測試，記得在 create document 後 `client.Indices.Refresh()` 強制 refresh index，因為 ES 收到建立請求後需要一段時間處理才能夠查詢，所以要強制 refresh 才能直接查!  
2. 預設 ES 的 string 輸入都會是 `text 型別`，而 text 型別會經過 tokenize 、analyzer 加工後支援`全文搜尋`，這其中的處理包含了去除冗詞贅字、斷詞等等；  
所以像是我原本預期 `key` 這個欄位是完全匹配，也就是查詢時要完整的命中，但因為預設是全文搜尋，所以會把沒有完全匹配的結果也回傳，如圖下我查詢 "key"="key1"，結果連 "key1.child" 都回傳了
![](/posts/2023/img/0319/search_text.png)

如果要解決這個問題的話，需要在 Index 建立後增加 Mapping，Mapping 是指定 Index 每個欄位的處理方式，可以切換不同的型別、指定是否要被 indexing 等
```golang
func createMapping(res *opensearchapi.Response, client *opensearch.Client) *opensearchapi.Response {
    mapping := `{"properties":{"key":{"type":"keyword"}}}`
    res, _ = client.Indices.Create(index)
    req := opensearchapi.IndicesPutMappingRequest{
        Index: []string{index},
        Body:  bytes.NewReader([]byte(mapping)),
    }
    res, _ = req.Do(context.Background(), client.Transport)
    return res
}
```
需要特別留意 Mapping 必須要在 Index 為空的情況下才能生效，如果已經有 document 就不行，需要重新建立

以下查詢 "key"="key1" 成功回傳一筆資料
![](/posts/2023/img/0319/search_keyword.png)