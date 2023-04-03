---
title: '從 Nodejs 到 Golang: Concurrency 實作比較'
description: Golang / Nodejs 試著透過有效率地使用 Kernel Thread 方式增加 Concurrency 處理能力，但兩者在實作上有不同的方式，以下將比較核心實作差異與語法上使用的不同
date: '2021-03-07T08:21:40.869Z'
categories: ['程式語言', 'Golang']
keywords: []
---

在一兩年前 Golang 很火紅時有學了一下，但當時沒有深入的理解 Golang 相對於其他語言的特色與魅力，只停留在表層的語法學習，時隔多年因為換工作的需求，重學 Golang 發現有蠻多有趣的地方，拿來與 Nodejs 相比有許多類似但不同的實作差異，尤其在非同步這一塊，特此筆記並分享如何從 Nodejs 跳槽到 Golang

本篇將著重於介紹 Golang 上手的教學資源，以及對比 Nodejs (Javascript)，Golang 的特色在什麼地方

## Golang 與 Nodejs 異同之處 - 以非同步為例  
Golang 與 Nodejs 在非同步設計上有些雷同之處，相較於傳統的每一個 IO 事件就開一個 thread 讓 OS 去排程，`Nodejs 與 Golang 都盡可能減少 kernel thread 的產生，而是透過 Non blocking system call 或是 user thread 與 scheduler 方式，降低 OS Context Switch 就能更有效率使用 kernel thread`   
### Nodejs 內部非同步處理
透過 runtime 底層 `libuv` 呼叫 non-blocking system call，向 system 註冊有興趣的事件並加入 event loop ，event loop 中又細分成多個 phase 檢查不同的任務如 timer / io / check 等，等到 main thread 執行完後檢查 event loop 上 IO 事件是否完成，如果完成則觸發 callback 到 main thread 執行   

但需要注意 Nodejs core library 有些是沒有 non blocking system call，例如 fs / crypto / dns.lookup 查詢，這些是從 Worker Pool 另外開 thread 執行，會受限於環境變數 UV_THREADPOOL_SIZE 控制整體 kernel thread 數量，所以再次提醒 `Nodejs runtime 是 multi thread，只是 js 跟 event loop callback 都跑在同一個 main thread 上`，具體可以參考
1.  [The Node.js Event Loop: Not So Single Threaded](https://www.youtube.com/watch?v=zphcsoSJMvM)   
2.  [Node's Event Loop From the Inside Out by Sam Roberts, IBM](https://www.youtube.com/watch?v=P9csgxBgaZ8)
3.  [Basics of libuv](http://docs.libuv.org/en/v1.x/guide/basics.html)

> Instead, the application can request the operating system to watch the socket and put an event notification in the queue. The application can inspect the events at its convenience

如果是 core library 沒有支援的 non blocking 任務，就必須自己透過 worker_threads / child_process / cluster 等方式才不會 block main thread，這也是新手搞混的問題 `是不是用 Promise 包成非同步就不會 blocking (X)`

### Golang 的 goroutine 與 scheduler
內容摘錄自這幾篇優良的內容：   
[GopherCon 2018: Kavya Joshi - The Scheduler Saga](https://www.youtube.com/watch?v=YHRO5WQGh0k) / [Go: Goroutine, OS Thread and CPU Management](https://medium.com/a-journey-with-go/go-goroutine-os-thread-and-cpu-management-2f5a5eaf518a) / [Scheduling In Go : Part II - Go Scheduler](https://www.ardanlabs.com/blog/2018/08/scheduling-in-go-part2.html)

> 前情提要，processor 只能執行 kernel thread 任務，每個 kernel thread 在記憶體佔用與 context switcth 花費都不小 (8KB / 1 ms)  
> 而 Golang 本身建立 user thread (goroutine)，開銷相對只要 (2KB/10 ns)
> 透過 Schedule 安排 user thread -> kernel thread -> processor 實際運行程式，盡可能讓 kernel thread 持續保持 running 減少 context switch

Golang 本身有 Scheduler 負責排程，透過 `go func()`啟動 goroutine  (user thread)，此 user thread 將由 Scheduler 排程   
![來自參考文件](https://www.ardanlabs.com/images/goinggo/94_figure11.png)   
(來自參考文件)  

1. Scheduler 預設為啟動一個 Processor P1，這裡會對應到硬體上可獨立執行 thread 的運算單元
> 不一定等於 CPU core 數量，因為像 intel Hyper-Threading 功能，一個 physical core 可運行兩個 thread
2. Processor P1 上運行一個 Kernel Thread M1，並將 goroutine G1 排程到 M1 中執行
3. 如果有新的 goroutine G2 誕生，且目前的 Processor P1還在跑，則建立新的 kernel thread M2與 Processor P2，並執行 goroutine G2
4. 如果 kernel thread 啟動數量達到上限 `GOMAXPROCS`，則會放到 FIFO queue 當中，簡稱 `runq`，每個 Processor 都有對應自己的 local runq
5. Processor 如果把 local run queue 都處理完，可以去偷其他 processor 的 runq (`work stealing`)，達到工作 balance 
6. 除了 local runq，還有一個 global runq 放被中斷的長時間佔用 goroutine，kernel thread 會用比較低的頻率去執行，還有像垃圾回收等任務
>```golang
>runtime.schedule() {
>    // only 1/61 of the time, check the global runnable queue for a G.
>    // if not found, check the local queue.
>    // if not found,
>    //     try to steal from other Ps.
>    //     if not, check the global runnable queue.
>    //     if not found, poll network.
>} 
>```   
7. 遇到 system call，會有兩種反應  
   - 如果是 `blocking system call`，則該 kernel thread 會暫停 (parking) 並移出 processor，把 process 讓給其他人 (handoff)，此時 thread 不會佔用總體上限
   - 如果是 `non blocking system call` 例如 network 相關，則不需要移出 thread，而是把 goroutine 放到 `network poll`，processor 會在有空的時候去 network poll 找出完成 system call且 runnable 的 goroutine

這樣每個 process 都盡可能綁定一個 kernel thread，且此 kernel thread 就持續在 running 狀態而沒有切換，透過 Go Scheduler 替換 user thread 排程工作  

Scheduler 本身會在以下情況處理排程
- `go` keyword
- 垃圾回收：垃圾回收有獨立的 goroutine
- system call
- sync 相關呼叫: atomic / mutex / channel 相關操作，會導致 goroutine 堵塞

goroutine 可以針對 function level 啟動併發，也有豐富的同步語法，例如 sync.Mutex 保護 critical section / sync.WaitGroup 等待 goroutine 完成 / channel 在 goroutine 當中傳遞資料與控制執行

### 範例一：透過 http request 讀取 users list 並再次透過 http request 取得 10 位 user 的詳細資料，算最後的性別加總  
範例只是要稍微品嚐一下兩個語法的差異，錯誤處理等就先不要太在意
  
<script src="https://gist.github.com/sj82516/6e10f70a62a1d717c78485077ff5a15d.js"></script>

這部分寫起來用 Nodejs 就蠻方便的

### 範例二：計算 1000 * 1000 數字矩陣加總，併發四個 thread 執行最後加總
  
<script src="https://gist.github.com/sj82516/df8e34f1ba7952817d3da2607c3eda35.js"></script>


Nodejs 在 child_process 或是 worker thread 我自己都覺得有點不太方便，不能針對某一個 function 起新的 thread，傳遞資料上也不是太方便，不如 Golang 直接 `go func()` 搭配 channel 來的簡便

接著回過頭來看，分享從 Nodejs 跳槽到 Golang 的學習方式
## Golang 教學資源推薦
影片付費資源：[Go Core Language](https://app.pluralsight.com/paths/skills/go-core-language) ，自己本身蠻喜歡影片式教學，可以快速過一遍，Pluralsight 的課程品質還不錯，而且還有 Skill 可以測試自己的能力，把上面 Go 核心課程看完大概就花個 5個小時左右，覺得入門來說頗划算

## 為什麼要用 Golang
除了本身是靜態強型別的編譯式語言，Golang 相比於 Nodejs 語言本身有幾大特色讓我十分喜歡
### 1. `非常工程導向/簡潔`：  
Golang 從一開始推出就是為了解決 Google 所遇到的大型軟體系統設計難題，所以從一開始設計就非常工程、團隊合作導向，例如
1. 只有 for loop 沒有 while / do while 等，讓寫法有統一的方式，不會每個人都有各自的實作  
2. package 中大寫代表 public / 小寫代表 private
3. test function 必須是以 Test 開頭  
Golang 只有 25 個 keywords，且在許多地方都有明確的限制，而不是給予空泛的自由，這讓團隊有明確的 coding style 可以遵守
### 2. `語言核心包含常用的功能，例如 CLI / Testing` 
在 Nodejs 中，我們常需要各種 npm package 完成任務，小至 http request 都要安裝 node-fetch / axios / request 等，因為核心 library 提供的 api 不好用； 
但是 Golang 中沒有這樣的問題，如果是要寫 CLI 工具，處理參數 / 產生 -help 文件等核心 library 都處理妥當；http request 用原生的 net/http 就很方便，甚至 api server 也都可以不用社群的 framework 就能夠快速實作
### 3. `跨平台編譯出單一可執行的 Binary 檔`  
雖然有 Docker 提供跨平台部署的一致性保證，但是 Golang 可以直接編譯出對應平台可執行的 Binary 檔還是很方便，在寫 Dockerfile 也不用擔心太多環境設定是否正確 / 安裝過多套件是否有安全漏洞等等 
### 4. `官方文件齊全且詳盡`   
Golang 官網中的 [Frequently Asked Questions (FAQ)](https://golang.org/doc/faq) 與 [The Go Blog](https://blog.golang.org/)就有解答我許多疑惑，包含
> 為什麼 Golang 要把型別宣告放在後面 [Why are declarations backwards?](https://golang.org/doc/faq#different_syntax)
> 因為用口語念程式碼更直覺表達出意圖

> 為什麼要用 Go [Two recent Go articles](https://blog.golang.org/two-recent-go-articles)   
> 因為目前熱門的語言都是在網路/多核心時代前的產物，如C/C++/Java，像是thread 功能都是在語言誕生很久之後才設計的；另外現今系統的規模 / 協作人員等數量都完全不同，所以需要有新型態的語言來支援；  
Go 具備`快速編譯/跨平台支援/垃圾回收機制/goroutine 併發設計`，讓設計現代軟體更加簡便   

官方就有豐富的資源可以讓開發者更深度的理解 Golang 設計精髓與奧妙

## 結語 
關於底層的 runtime 種種還有許多未解之謎，就等未來慢慢填坑，看著不同語言的發展與設計理念，覺得實在是有趣  

回歸工作，如果是一些簡單的任務，寫 Nodejs 還是蠻順手的；只是在大型軟體開發上，Golang 的設計理念 / 語言特性都讓他成為熱門的選擇，不愧是 Docker / K8s 等工具選擇的開發語言
