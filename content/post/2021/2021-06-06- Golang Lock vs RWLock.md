---
title: 'Golang 併發處理 Mutex / RWMutex / SingleFlight'
description: 研究 Mutex , RWMutex 性能對比，以及併發下用 SingleFlight 避免擊穿問題
date: '2021-06-06T01:21:40.869Z'
categories: ['Golang']
keywords: ['golang']
---
在與公司前輩請教時，有聊到 Mutex , RWMutex 性能對比，以及併發下用 SingleFlight 避免擊穿問題，所以就花點時間看實作與練習，發現這系列寫得太好了 [6.2 同步原语与锁](https://draveness.me/golang/docs/part3-runtime/ch06-concurrency/golang-sync-primitives/)，拜讀過後整理以下的提問

### Mutex 實作
分成兩種模式：一般模式與飢餓模式
取得 Lock 時
1. 沒有人佔用則直接取得
2. 有人占用時，如果判斷是否能進入自旋模式，所謂的自旋是透過消耗 CPU cylcles 的 buzy waiting，降低 context switch 的花費
3. 重新嘗試取得鎖，如果沒有取得鎖，等到時間超過 1ms 則進入飢餓模式，並等待信號 (runtime_SemacquireMutex)


### RWMutex 會產生 Write Starvation 嗎？
RWMutex 採用寫入優先，如果在取得 RWMutex 寫鎖時，發現目前有多個讀鎖
1. 先將 readerCount 變成負數，讓後續讀鎖都無法取得
2. 等到信號 writerSem 喚醒

讀鎖在取得時
1. 檢查 readerCount 是否為負數，如果是代表有寫鎖
2. 如果有寫鎖，則偵聽 readerSem 信號喚醒執行

在解除寫鎖 / 讀鎖，會分別去出發信號，讓等待的讀鎖 / 寫鎖開始執行

### RWMutex 跟 Mutex 效能比較
實際測試的結果，設定一個寫入比率，單純比較取鎖/釋放鎖，跑一百萬次兩者差異不大
```md
BenchmarkMutexTest-8            10000000                 0.04064 ns/op
BenchmarkRWMutexTest
BenchmarkRWMutexTest-8          10000000                 0.04699 ns/op
BenchmarkFakeWrite
```

加入了讀取跟寫入，有些測試會用 time.Sleep ，但我實驗因為同時跑 goroutine 關係，如果全部 goroutine 都在 sleep 會出錯，所以改用簡單的計數從零數到一百萬當作讀取，而寫入則是五倍的讀取時間

寫入比例抓 0.2 的話，RWMutex 用起來有優勢很多
```md
BenchmarkMutexTest
BenchmarkMutexTest-8               10000             58176 ns/op
BenchmarkRWMutexTest
BenchmarkRWMutexTest-8             10000             37176 ns/op
```

測試的程式碼在此 [go-rwmutex-benchmark](https://github.com/sj82516/go-rwmutex-benchmark)

總結
> RWMutex 測試起來效能蠻好的，在考量到讀取比較多的情況表現會比 Mutex 還要好

## Singleflight
當 Server 在處理併發時，會避免大量重複的查詢操作進入 DB 中，這尤其會發生在 Cache 失效的當下，最理想狀況是`所有同樣的查詢只要進 DB 查一次，其他查詢等待返回相同的結果`  
這樣的情境可以使用 [Singleflight](https://medium.com/@vCabbage/go-avoid-duplicate-requests-with-sync-singleflight-311601b3068b)，提供阻塞其餘查詢，只讓一個查詢發生的機制，並對外開放三個方法
- Do: 使用者指定 Key 與受保護的方法，同一時間只有一個保護方法會被執行，其餘進來的呼叫會等待
- DoChan: 同於 Do，但返回 channel，可以搭配 timeout 使用
- Forget: 有時候會希望主動讓 Key 不再保護，例如過了數秒為了避免讀取太舊的值，可以主動刪除 Key 讓下一個保護方法可以執行 (即使前者尚未返回)

更詳細內容可參考此篇 [Go: Avoid duplicate requests with sync/singleflight](https://medium.com/@vCabbage/go-avoid-duplicate-requests-with-sync-singleflight-311601b3068b)，自己寫了一個簡單的範例 [go playground](https://play.golang.org/p/_uGNGjyMJ5f)

Singleflight 的實作也十分精練，用一個 map 保存 key 對應 struct，struct 裡面放 mutext 避免同步操作 / wg 讓其他呼叫發現有人在執行就乖乖等待 ，可參考 [golang防缓存击穿利器--singleflight](https://segmentfault.com/a/1190000018464029)

### typescript 實作
後來覺得頗有趣就自己實作一個 typescript 版本：[sj82516/go-singleflight](https://github.com/sj82516/go-singleflight)，原本想要多一個儲存的 adpter 支援 redis，但卡在 Object / Error 要如何 serialize / deserialize 就先中止了

## Go Assembler
往下追 `"sync/atomic"` 發現沒有相關的 CompareAndSwapInt32 的程式碼，這是因為這些部分是在 runtime 產生，atomic 指令必須由 CPU 提供才能保證執行時的原子性，而指令則是各平台限定，如 x86 / x64 / arm 32 / arm 64 / powerpc 等等，這在編譯的時候可以透過 `GOARCH / GOOS` 指定編譯的平台  

補充資料可以參考
1. 高階語言如何變成機器可執行的位元檔：[Compiling, assembling, and linking](https://www.youtube.com/watch?v=N2y6csonII4)
2. [GopherCon 2016: Rob Pike - The Design of the Go Assembler](https://www.youtube.com/watch?v=KINIAgRpkDA) / 文字說明 [Go Tools: The Compiler — Part 1 Assembly Language and Go](https://medium.com/martinomburajr/go-tools-the-compiler-part-1-assembly-language-and-go-ffc42cbf579d)  

Rob Pike 說明一開始 Go 的原始碼有使用 C/Yaac 完成編譯的方式，但因為難管理後來在 Go 1.3 開始汰換成 Go 實作  

這邊實作有趣的地方在於 Rob Pike 表示雖然每個平台的指令/暫存器名稱都不同，但是基本的使用可以被抽象化，所以 Go Compiler 會編譯出 semi pseudo code，接著依照指定的平台轉換成對應的 assembly code，這部分實作了 `obj` library  

這樣的好處是對於 Compiler 來說產生 semi pseudo code 就是單純的文字轉換

在影片中的範例
```golang
ADDW AX, BX

-----

&obj.Prod{
    As: arch.Instructions["ADDW"],
    From: obj.Addr{Reg: arch.Register["AX"]},
    To: obj.Addr{Reg: arch.Register["BX"]}
}
```
最後提到他們在開發工具，直接讀 PDF 產生各平台對應的 instruction set
![]()

在思考的過程中，開始想 assembly 夾在 source code / machine code 的地位，這一篇 SO 給出了回答 [Why do we even need assembler when we have compiler?](https://stackoverflow.com/questions/51780158/why-do-we-even-need-assembler-when-we-have-compiler)  
正如同夾在中間的地位，machine code 人類無法讀，source code 又太 high level，如果要確認 compiler 是否編譯出有效的 machine code，那查看 assembly 看實際人類可讀的指令是最好的

Go 編譯過程可參考 [Go 语言设计与实现 ](https://draveness.me/golang/docs/part1-prerequisite/ch02-compile/golang-compile-intro/)

存參個在 SO 上被扣分的發問 [Why assembly is unportable](https://stackoverflow.com/questions/67855719/why-assembly-is-unportable?noredirect=1#comment119941280_67855719)，comment 有很多解釋之後慢慢細讀再補充