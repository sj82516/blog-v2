---
title: '「領域驅動設計與簡潔架構入門實作班」上課筆記與心得：關於敏捷、 DDD、 Event Storming 與 Clean Architecture - 下'
description: 結論 - 要學 DDD 直接報名 Teddy 的課程絕對是投資報酬率最高的方式
date: '2022-01-14T01:21:40.869Z'
categories: ['架構', 'DDD']
keywords: []
draft: true
---
## Clean Architecture
1. 什麼是軟體架構？
   
重點三個
- 分層原則
- 相依性原則
- 跨層原則
為什麼不能一個 Entity 傳到尾？假性重複

1. 一個 Use Case 有幾個 Repo ?
一個 Aggregate Root 就一個 Repo，不管實作對應幾張 Table
2. 使用 Bridge Patten 讓雙方都可以擴充
- 違反跨層原則 (Entity 丟給 Repo) 也沒關係
- 延遲 DB 決策，用 collection 代替
3. AggregateRoot 發 Event，如果遇到 for loop 會先把事件先儲存最後一次發，避免狀態改變一半後失敗，前面的事件都發出去了
- 事件

## Big Picture
1. Event Storming (部分做完就開工)
2. TDD 開發
   1. 寫 Use Case 的測試案例
   2. Aggregate Root 很重要的邏輯分開測
3. 寫 RESTful Controller，做 E2E 測試 (by Postman)
4. 前端串接
5. 一個 production shippable 的 User Story 就完成了，也好量進度

#### Adapter
- class adapter: 用繼承的
- object adapter：用組合的方式 (成員之一/參數)


Use Case 可以互相呼叫
## 結語
