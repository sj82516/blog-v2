---
title: '理解 Golang Scheduler'
description: Golang 可以併發 (concurrent) 數百萬的 goroutine 執行不同的任務，包含運算與 I/O，延續之前對 I/O 的理解，往 Golang 的 Scheduler 邁進，認識 scheduler 到底如何排程確保 fairness 與 performance
date: '2022-02-22T01:21:40.869Z'
categories: ['Golang']
keywords: ['scheduler']
draft: true
---
{{<youtube -K11rY57K7k>}}

goroutine 在邏輯上是一個`可運行的 thread`，更準確來說他是 user space thread，也會被叫做 green thread / coroutine；另一方面對於 CPU 而言真正的最小運行單元是 kernel thread

goroutine 當初在設計時有幾個目標
- 輕量，更準確的說是希望一個 process 能建立出百萬個 goroutine
- 可以平行處理 (parallel)並有良好的擴展性 (scalable)
- 最簡單的 API (只有建立 goroutine)
- 每個 goroutine 有無限的 stack
- 良好的處理 I/O、system call，不用 callback 的方式處理

基本範例如下
```go
resultChan = make(chan Result)
go func() {
    response := sendRequest()
    result := parseInt(response)
    resultChan <- result
}()
process(<-resultChan)
```

究竟 go scheduler 如何調整 goroutine 的排程、channel 的阻塞如何影響 goroutine 運行的方式，更具體的來說，需要釐清
1. goroutine 到底怎麼分辨是不是被 block 住
2. channel 如何知道哪些 goroutine 該被 block
3. goroutine 從 block 變成 runnable，是如何重新被 scheduler 排程

--------

#### thread per goroutine ?
1. memory 開銷過高，每個 thread 至少要 32K
2. 效能差，context switch 會涉及太多的 system call
3. stack 大小受到限制

#### thread pool ?
復用 thread 可以讓 goroutine 建立速度更快，但上面三個問題依然沒有解決

#### Simple scheduler

system call
=> 不知道何時會結束，只能等待 callback
=> 為了避免 deadlock，也不想被 block，建立新的 thread 執行其他的 goroutine，所以 thread > core

1. 輕量 goroutine
2. I/O system call
3. parallel

=> lock free
distributed run queue，每個 thread 有自己的 run queue
- scallable

work stilling，從別人的 runqueue 偷東西來做

=> 
如果被 system call block，會產生很多 thread 成常數增長
MPN，用 Processor 去控制 run queue，將 Processor 控制在 CPU core 數量

當 thread 發生 system call，Processor 會 handoff 到新的 thread 避免被 block

每個 Processor cache 對應到 CPU，增加 memory cache 效益

