---
title: 'AWS Aurora 架構研究以及與自駕 MySQL 的差異'
description: AWS Aurora 是 AWS 託管的兼容於 MySQL/PostgreSQL 的雲端關聯式資料庫，我一直誤以為他就是個託管服務與管理跨區域 Replica，但為了因應雲端與效能改善，底層儲存架構與自駕的 MySQL 截然不同
date: '2021-07-02T01:21:40.869Z'
categories: ['架構', '資料庫']
keywords: ['Aurora', 'MySQL']
---
公司使用 MySQL，近日遇到一些讀取的瓶頸，有了使用 AWS Aurora 的討論，剛好上一週看到 [Exploring performance differences between Amazon Aurora and vanilla MySQL](https://plaid.com/blog/exploring-performance-differences-between-amazon-aurora-and-vanilla-mysql) 才赫然發現 AWS Aurora 底層儲存架構會影響使用場景，跟預期的自駕 MySQL 搭配 Replica 有不同的效果  

以下這篇將探討
1. MySQL 儲存的基本原理
2. Aurora 的儲存架構

資料源自於
1. [Exploring performance differences between Amazon Aurora and vanilla MySQL](https://plaid.com/blog/exploring-performance-differences-between-amazon-aurora-and-vanilla-mysql)
2. [Amazon Aurora: Design Considerations for High Throughput Cloud-native Relational Databases](https://www.amazon.science/publications/amazon-aurora-design-considerations-for-high-throughput-cloud-native-relational-databases)

## MySQL 儲存的基本原理
關聯式資料庫最基本要保障 ACID，其中 Durability 是最基本的核心功能，保證寫入成功的資料不會因為系統 crash 等問題而遺失，在 MySQL 寫入的流程大概是
1. 將更新寫入 Redo Log buffer (WAL)，等待 commit 確定就刷新到硬碟保存紀錄避免遺失資料
2. 如果資料有被讀取到 memory 中，則更新 Page 內容並標記為 dirty
3. 背景運行的程序在 checkpoint 時機觸發時將 dirty page 與 redo log 的內容更新於硬碟上的 data file

其中有幾個目的
1. 減少 disk I/O 並保障連續性寫入：  
如果每一筆資料進來就馬上更新硬碟上的儲存，這會拖垮 DB 效能，所以 MySQL 讀寫時是以 `page` 為單位，如果發現更新的 page 在記憶體中會標記為 dirty page，後續再 checkpoint 統一更新到硬碟中
2. Redo Log 避免系統 Crash 而資料遺失：  
為了避免資料遺失，所以會先寫入 Redo Log，所以又稱作 Write Ahead Log 先寫入 log 再操作，Redo Log 是一個順序性持續寫入的 Log，所以寫入效能比隨機性更新還要好，當系統 crash 後，會來檢查 Redo Log 中是否存在沒有更新到資料庫硬碟的資料；  
具體寫入硬碟時機看 `innodb_flush_log_at_trx_commit`，預設 1 為每一筆都及時寫入硬碟中
3. 定期同步到硬碟中：  
每個操作都有先寫入 Redo Log，但這是為了災難復原而用，資料庫的資料會以 Page 形式儲存於硬碟中，所以定期到 checkpoint 會把 dirty page 從記憶體更新到硬碟中

### Binlog
Binlog 適用於系統異地恢復/建立 Replica，Binlog 不像 Redo Log 會保存所有的操作，只會保存對於資料有異動的行為，例如 update / delete 等  

寫入時機在 commit 完成時，會在 commit 結束前 / lock 釋放前寫入硬碟，避免資料異常，具體的寫入頻率要看 `sync_binlog`，預設為 1 代表每一筆 commit 就寫一次，可以設定為 n 代表 n 筆 commit 才寫入但就會有遺失資料的風險

### Undo log
如果 isolation level 開到 repeatable read，則 MySQL 採用 MVCC，讓每個 transaction 只會讀取到自己 transaction 開始前的最新資料，而不被並行的 transaction 所影響  

之所以需要 undo log 是當 transaction rollback 時，需要知道自己要回滾的狀態，所以 undo log 必須保存到 transaction 執行完畢才可以刪除，長度會是 `執行最久的 transaction`

## Aurora 架構
Aurora 是 AWS 基於雲端建構的關聯式資料庫服務，兼容於 MySQL / PostgreSQL，主要想解決幾個問題
1. 容錯能力：  
硬碟可能會壞 / 主機可能會有問題 / 甚至 Data Center 都會出意外，尤其是在雲端分散式系統中，機器數增加帶來更高的出錯機會，Aurora 每一個 replica 都會對應 3 個 AZ 各 2 個 node 總共 6 個 node 儲存資料，大幅增加容錯能力
2. 擴展性：  
傳統的資料庫架設於單一主機上，讀取會受限於 Disk I/O 的貧頸，Aurora 將 Compute / Storage 分離，可以針對需求獨立升級，並增加跨區域、跨 AZ 的 Read Replica

但有這麼多好處卻不用受到太多的性能影響，聽起來有點美好的不切實際，例如備份到多個儲存 node 就需要擔心資料一致性/效能的問題，除了原本的 Disk I/O 又多了一段 Network I/O，Aurora 在不同的地方作出了對應的調整

## 2. DURABILITY AT SCALE
### 2.1 Replication and Correlated Failures
Aurora 跟很多分散式儲存的服務很像，採用多數讀寫的機制，只要確保
1. Vw + Vr > V
2. Vw > V / 2  

V 代表節點數量，如果 Vw 寫入節點數量超過 1/2 節點都成功才成功，且 Vr 讀取數量是讀取多數則

最基本的數量會取 3，則 Vw / Vr 只要有 2 個 node 存活則可以繼續運作，容錯率是 33%，但文件中說到 Aurora 選擇 6 個 node分散在 3 個 AZ，這樣可以預防一個 AZ 以及一個額外錯誤下讀取還不會中斷
### 2.2 Segmented Storage
為了降低同時機器故障而導致破壞多數的可能，要盡可能降低 MTTF(平均錯誤時間)與 MTTR(平均復原時間)，Aurora 以 10GB 當作一個區段，產生 6 個備份並分散到 3 個 AZ 稱之為 PG(Protection Group)，一個 Storage Volume 就是由多個 PG 所組成，實體上就是由 EC2 加上一群分割的 SSD 組成，最大可支援到 64TB  

Segment 是最小獨立單位 (也就是會壞掉是獨立一個 Segment 壞)，AWS 會負責持續監控與復原，目前復原一個 Segment 約 10秒鐘 (網路帶寬為 10Gbps 下)，所以出現破壞多數的場景：兩個 node 在 10秒鐘內同時壞掉且一個 AZ 掛掉又不包含同時壞掉的 node 機率就微乎其微 

> 小結：這邊談的是 AWS 在持久性上的優化，將最小的儲存單位定在 10GB，讓復原速度變快 / 產生 6 組備份增加容錯

## THE LOG IS THE DATABASE
### 3.1 The Burden of Amplified Writes
![](/post/2021/img/0702/mysql-old.png)
先看第一版 Aurora 嘗試的架構 - 傳統的鏡像同步架構，一台 Primary Instance 負責寫入儲存於 EBS 並同時備份到另一份 EBS 中，有一台 Replica Instance 同步 Primary 的寫入並儲存於兩份 EBS 中，可以看到一個 MySQL 寫入最多會觸發五個 I/O binlog / redo log / frm(metadata) / double-write，要等到全部寫入結束才算是操作成功，這會拉長回應時間，更糟糕的是圖片中步驟 1,3,5 (為什麼有5?) 是同步且順序寫入

### 3.2 Offloading Redo Processing to Storage
![](/post/2021/img/0702/aurora.png)
相反的 Aurora 透過 Redo Log 同步，讓 Storage level 負責 Redo Log 寫入與更新 Data file，同時分送給 Replica 更新記憶體中 page 的資料；  
不像過往 MySQL 需要在 Checkpoint / background / cache 空間不足時刷新資料到硬碟中，全部由 Storage Service 負責，大幅降低了 Network I/O  

![](/post/2021/img/0702/perf.png)
從 Benchmark 可以看到，每筆 Transaction 所需的 I/O 從 7.4 變成 0.9，完成的 Transaction 數也提升了 35 倍

這同時也降低了復原的時間，傳統 DB 需要從 Redo Log 上一次的 checkpoint 開始逐條執行，但 Aurora 的復原是從 Storage level 向其他備份拉 Segment，復原速度可以在一分鐘以內

### 3.3 Storage Service Design Points
Storage Service 核心設計要降低寫入請求的延遲，所以把大部分的儲存工作都移至背景執行，尤其是更好地利用 CPU 去換取 Disk 寫入時間，例如舊的 Page 要垃圾回收可以在背景用 CPU 執行而不要延遲前景在處理寫入請求，所以 Aurora 的背景運作不會影響前景，不同於傳統 DB 如果背景在 Checkpoint 刷新硬碟則會造成前景寫入的延遲

![](/post/2021/img/0702/storage.png)
Storage Service 收到請求會執行
1. 放入 Memory 中
2. 寫入硬碟，寫入請求成功
3. 排序，並確認寫入紀錄是否有遺漏
4. 透過 gossip 跟其他節點要遺漏的紀錄
5. 更新到 page 中
6. 定期同步到 s3
7. 定期清除舊的 page
8. 定期檢查 page 的驗證碼

除了步驟 1, 2 會影響前景寫入，其餘步驟都可以非同步且於背景執行

## 4. THE LOG MARCHES FORWARD
接著要確保 rumtime、replica 都保持一致性，究竟是如何不使用昂貴的 2pc 卻又能保持一致性
### 4.1 Solution sketch: Asynchronous Processing 
前面提過 Aurora 是透過 redo log 同步，每一筆 log 都有 持續遞增的 LCN (Log Sequence Number)，因為寫入成功只要多數的 node 同意即可，所以有些 node 可能會缺少幾個 log，可以透過 LCN 去跟其他 node 索取遺失的 log  

考量到多 transaction 的情況，每個 transaction 執行順序有所不同，在過程會陸續把 commit 送到 storage service 儲存 (到 complete) 階段，但如果發生了系統故障時，重新恢復後需要把沒有 commit 的 transaction 都 rollback，假設 DB 目前最高完成寫入的 LCN 稱為 VCL (Volume Complete LSN))，在復原中任何 LCN 高於 VCL 都會被遺棄，因為代表沒有被 complete  

更進階這些高於 VCL 的 LCN 會被標記成 CPL (Consistency Point LSNs)，接著定義出 VDL 為那些在低於 VCL 中最高的 CPL，例如 CPL 有 900,1000, 1100 但是 VCL 為 1007，則 VDL 為 1000，這代表 storage service complete 到 1007 但是持久化儲存到 1000 
> 這一整段沒有到非常理解，待之後慢慢思考

### 4.2 Normal Operation
Aurora 會同時處理大量的寫入請求，每一筆 redo log 都會產生一個大於 VDL(被持久化保存的 LCN)的 LCN，但為了不要讓 LCN 的遞增遠大於 Storage Service 所能保存的速度，LSN Allocation Limit (LAL) 預設為 10萬筆，意即 Aurora 最多並行 10 萬筆進行中的 transaction 避免寫入速度跟不上

每一個 PG 中的每一個 Segment 只會保存部分的 redo log，但會有一個 link 指向上一份 log 所在的 PG，這用來追蹤目前所完成最大的 LCN，並且在與其他 node gossip 時可以知道缺漏的 log

#### Read
如同大多數的 DB，Aurora 會在 buffer 中 cache page ，如果 cache miss 則從 disk 讀取，此時傳統 DB 會優先移除 dirty page 並寫回硬碟中；但 Aurora 並不需要刷新 dirty page (因為 storage service 已經獨立更新)，相反的是把 page LCN 大於等於 VDL 的 page 移除並讀取最新被持久化的page

前面提到 Aurora 透過多數讀取確保一致性，但大多數時機並不需要，Aurora 會在 Page 讀取時紀錄 Page LCN 當作 read point，接著只要讀取的 storage node VDL 確定在 read point 之後，就代表該 node 有該 page 完整最新的資料，而且因為每個 segment 都有紀錄 LCN 與 link，所以能很快知道資料要到哪一個 segment 讀取

同時每個 PG 會維護一份目前最低的 Protection Group Min Read Point LSN (PGMRPL)，這代表低於此數字的 LCN 的 page 都不會再被讀取，這樣垃圾回收就能移除過舊的 log

### Replica
一個 write node 可以搭配 16 個 read replica 並共用相同的 storage service，writer 會把 redo log 也同步給 reader，如果 log 有在 cache 中則更新，否則就直接丟棄

因為 reader 跟 storage service 的 redo log 更新是錯開，所以 reader 在更新 log 時要確保 LCN 是小於等於 VDL / 如果 log 是 mini-transaction 的一部分則更新，確保跟所有的 database 看到相同內容

預期 reader 的延遲會在 20ms 以內

### 4.3 Recovery
傳統 DB 在災難復原時，會去讀取 redo log 中還沒被 checkpoint 執行的 log，搭配 undo log 將失敗的 transaction rollback，但這執行過程蠻花時間，而 Aurora 沒有這方面困擾

首先會檢查每一個 PG，找出讀取多數中可以確保已經完成的寫入多數紀錄 VDL，高於 VDL 的 LCN 全部捨棄，接著一樣需要透過 undo log 去 rollback，整個過程約 10秒以內

## 5. PUTTING IT ALL TOGETHER
接著看完整的架構圖
![](/post/2021/img/0702/architech.png)
社群版的 MySQL InnoDB 引擎在寫入操作時會修改 buffer 中的 page 與寫入 WAL redo log buffer，等到 commit 時再把 redo log buffer 寫入硬碟中；而被修改的 page 要則透過 double-write buffer 避免只更新部分 page，page 寫入會發生在背景 / checkpoint / cache 移除時；
此外還有一些 B+Tree 操作與相關的 mini trasaction (MTR) 如拆分、合併 B+Tree page 需要是原子性操作

在 Aurora 版本中，redo log record 就代表每一個 MTR 操作，最新的一筆 log 被標記成 consistency point；Aurora 提供相同的 isolation level

其餘就是架構的說明，以及各方面的性能表現，就不贅述了

----------
## Aurora 對比 MySQL 有什麼隱憂
因為 Aurora 如果 primary 跟 read replica 在同一個 region 下，則會共用 storage service，這也就代表 undo log 會是同一份，如果今天 read replica 有一筆執行非常久的 transaction，則 undo log 也會跟變大導致 primary 效能下降  

這個在傳統 MySQL 不會發生，因為如 3.1 提到 MySQL 是透過 binlog 同步各自的 MySQL 維護各自的 redo log / undo log 所以 read replica 不會有任何影響 primary 的時候  

最後作者指出有幾個解法
1. 調整 read replica 預設 isolation level 為 read commited，就不會用到 undo log(需注意預設為 repeatable read)
2. Aurora 選擇 binlog relica，就跟傳統的 mysql 一樣
3. 拿在 S3 的備份資料，用其他大數據工具分析
4. Aurora 支援 clone，備份一組新的設定

## 結語
翻整個 Aurora 架構有很多生硬的地方沒有完全搞懂，但是看到這種解 bug 追根究底到底層架構還是覺得很過癮，之後會持續的優化文章內容，如果有哪裡有建議跟指教再麻煩留言～