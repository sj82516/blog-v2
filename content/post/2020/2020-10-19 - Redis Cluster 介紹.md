---
title: 'Redis Cluster 介紹'
description: 參考文件摘要 Redis Cluster 使用與架構
date: '2020-10-19T08:21:40.869Z'
categories: ['資料庫']
keywords: ['Redis']
---

雖然 Redis Cluster 推出已久，但公司最近才準備從 Sentinel 轉成 Cluster，架構上有不少的調整，以下閱讀文件 [Redis Cluster Specification](https://redis.io/topics/cluster-spec)並摘要

## Overview
可以由一至多個 replica 組成，每一個 replica 分配固定的 slot，透過 CRC 將 key 做 hash 後分配至固定的 replica，slot 總數固定在 `16358` 個
1. 動態增加、刪除 replica，可以透過 Migrate 指令重新分配 slot
2. 任何一個 Node 都能夠接收 request，但沒有 proxy 功能，會透過 MOVED 回傳 client 正確的 Node
3. `可用性`，遭遇網路分割時多數群體可以活下來，條件是 replica 至少有任一 Master 存在 (從 Slave Promote 成 Master 也可以)

所有的單一key 指令支援 Cluster，如果是 multi-key 指令例如 set union 等，Redis 會產生 hash tag 強迫所有的 multi-key 分配到同一個 Node 上

### Node  
每個 Node 彼此互相透過 tcp 連接，稱為 Redis Cluster Bus，透過 gossip protocol 發現新的 node /ping 彼此 / 發送 cluster message 等  

每個 Node 都會有 `160 bit亂數 ID`，即使 Cluster ip 位置改變，ID 也不會改變，除非是 config 檔被刪除或是 admin 強制替換
Node 之間是走 TCP 並透過 16739 port，Node 會與其他 Cluster 內的所有 Node 相連行程 `full mesh (N-1 connection)`  

Clusert Node 會接受任意的連線，並回應任意的ping，但其他訊息只有`被視為 cluster 一部分的 Node` 才會處理，否則直接丟棄
要加入 cluster 的驗證有兩種方式
1. admin 使用 `CLUSTER MEET ip port` 加入
2. 已經互相驗證過的 Node 口耳相傳，例如 A -> B 驗證過，B<->C驗證過，則 B 會推薦 C 給 A，則 A<->C 也能成功建立連線；
所以 Node 與任一被驗證的 Node 許可後，後續其他 Node 就能自動發現  

整體的 Cluster Node 數量上限建議在 `1000` 以內  

### 寫入遺失  
因為是非同步副本，所以有小概率已經回傳成功給 client 的 write 會被覆蓋，Redis 採取 last failover wins，也就是最新的一個 Master 會覆寫其他副本的結果，所以會有一段空窗期遺失資料，空窗期長短要看發生網路分隔時 client 是連到多數還是少數群  

Master 寫入後，還來不及複製到 Slave 就死掉了，如果沒有在一定時間 ( NODE_TIMEOUT )內恢復，Slave 被 promote 成 Master 那寫入的結果就掉了；
而 Master 被 partition 隔開，在一段時間後 Master 發現自己連不到多數Master 就會停止接受寫入請求  

### 可用性
例如說目前有 N 個 Master ，且對應搭配 N 個 Slave (1對1)，假設有任一個 Node 掛掉，目前為 `2N - 1`  

此時如果剛好殘存的 replica 那一個 Node 死去，整個 Cluster 才算掛掉，反之就能繼續運作，因為會有一部分的 slot 沒有 Node 負責  
所以 `avalaibility 是 1 / (2N-1)`

### 效能  
因為 Node 沒有 Proxy 功能，所以只會跟 client 說正確的 Node 在哪，接著 client 要再發起一次 request 才能完成操作，最終 client 會知道所有的操作該去哪個 Node；  
基本上不太需要擔心效能問題，假設 Cluster 有 N 個 Master，負載能力基本上可以視為單機 * N，雖然有上述在第一次要多查一次的問題，但因為 Client 對於每個 Cluster Master 都保持 TCP 長連結，所以不至於太擔心  

### 分散式模型
redis 將 key space 切割成 16384 等分 `HASH_SLOT = CRC16(key) mod 16384`，分配後會固定，該 slot 就會由同一個 Node 負責，直到有 reconfig 的指令； 

hash tag 是一個分散的例外，主要是為了支援 `multi-key` 可以分配到同一個 hash slot 上，如果 key 包含 {} ，則 hash key 產生是key 裡面第一組 {…} 中間的值 (沒有包含 {})
```c++
unsigned int HASH_SLOT(char *key, int keylen) {
    int s, e;
    for (s = 0; s < keylen; s++)
        if (key[s] == '{') break;
    
    /* 沒有找到 {，則 hash 整個字串 */
    if (s == keylen) return crc16(key,keylen) & 16383;
    
    /* 找到 { */
    for (e = s+1; e < keylen; e++)
        if (key[e] == '}') break;
    /* 沒有找到 }，hash 整個字串 */
    if (e == keylen || e == s+1) return crc16(key,keylen) & 16383;
    
    /* 如果有 {} 配對，則 key 取 {...} 之間的字串 */
    return crc16(key+s+1,e-s-1) & 16383;
}
```

## Resharding
Redis Cluster 在管理上以及使用上都有相當大的彈性，Cluster 可以任意增減 Node 數量以及調整 Slot 對應的 Node；而 Redis Client 可以與任意的 Node 連線  

如果 Node 收到 Client request 後
1. 如果該資料屬於他的 slot，則直接處理
2. 反之則找出哪個 Node 應該負責，回傳 Moved 錯誤給 Client `-MOVED 3999 127.0.0.1:6381`，這代表 key 在 slot 3999，正確的 Node 是 127.0.0.1:6381  

Client 在每次收到 MOVED 後都應該去記住哪一個 slot 對應哪一個 Node，這樣可以增加效率；  
又直接拉下整張 mapping，用 `$cluster nodes` 找出所以的 node，並結合 `$cluster slots` 直接查看 cluster 完整對照表，就可以完整知道 node 對應的 slot 以及 node ip 位置與 id  

### Rebalance
Cluster 可以在運行中增減 Node，並且會自動搬移資料並更新 slot mapping，有幾個 command 可以動態影響 Node 與 Slot
1. `addslot` : 指定 Node 增加 slot
2. `delslot` : 移除 slot，原本負責的 Node 會遺忘這個 slot
3. `setslot` : 轉移 slot  

轉移的部分比較複雜，會需要先去調整 Node 狀態，例如說希望將 slot 8從 Node A 轉到 Node B  
1. 在 Node B 上指定資料會從 Node A 過來: `$CLUSTER SETSLOT 8 IMPORTING A`  
2. 在 Node A 上指定要把 slot 8 轉移到 Node B 上: `$CLUSTER SETSLOT 8 MIGRATING B`  
3. 之後有一個背景程式 `redis-trib` 會主動將 slot 逐步搬移

也可以手動轉移  
1. 列出該 slot 一定數量的 hash key: `$CLUSTER GETKEYSINSLOT slot count`
2. 將這些 key 轉移: `$MIGRATE target_host target_port key target_database id timeout`，Migrate 會在轉移成功後才移除 Node B 的紀錄    

過程可參考此問答 [Redis cluster live reshard failure](https://stackoverflow.com/questions/53080371/redis-cluster-live-reshard-failure)  

### 轉移過程
在轉移過程中，client 針對搬移中與搬入中的 Node 發出 Request 反應會有所不同
1. 搬出中的 Node :     
    a. 如果 key 還在 Node中 則直接處理     
    b. 不再則回傳 `ASK` 錯誤，Client 接著必先向新的 Node 發出  `ASKING`，接著才傳送 Request  
2. 搬入中的 Node : 只處理有先傳送 ASKING 的請求，其餘回傳 MOVED 錯誤  

這樣的目的是為了方便轉移過程，`New Key 一定是在搬入中 Node產生`，Migrate 則只需要處理 Old Key  

> 已經有 MOVED 錯誤碼仍然需要 ASK 的原因是 ASK 是一次性請求，我們會希望在搬移過程，假設 Client 如果有 slot 8 的請求，應該先去問 A 再去問 B，如果 A 沒有會用 ASK 轉去 B；  
MOVED 代表的是往後的永久性所有針對 slot 8 的請求都去 Node B，但顯然還在 migrate 的話會有大量的 key 還沒搬移，所以用 ASK 一次性的查詢當作過度

如果是 multi-key 操作，假設 key 分散在兩個 node 之間，則會收到 `TRYAGAIN` 錯誤  

## Fault Tolerance  
Node 會發送 `ping / pong` 去確認其他 Node 是否還存活，兩者合併又稱 `heartbeat`，除了 ping 會觸發 pong 回復外，如果 Node 有 config 檔更新，也會主動發送 pong 給其他 Node  

在半個 `NODE_TIMEOUT` 時間內，Node 會送 ping 給其他所有的 Node 確保存活，在 NODE_TIMEOUT 時間點到前，Node 還會重新與其他 Node 建立 TCP 連線，確保ping 沒收到不是剛好這一次的 TCP 連線有問題  

> 所以 packet 交換數量與 Node 數量和 NODE_TIMEOUT 時間有關，例如 100 Node + 60 sec 的 timeout，則每一個 Node 30 sec 內會送 99 個ping 給其他 Node，換算後整個 cluster 是每秒 330ping  

heartbeat 封包共用 Header 大致如下
1. NodeID: 160 bit 識別碼
2. currentEpoch: 遞增數字，用來表示訊息的先後順序
3. flag: 是 Master 還是 Slave
4. bitmap: 用來表示負責的 slot
5. sender 的 tcp port
6. sender 認為 Cluter 是否還在運行
7. 如果是 Slave 則需要包含 Master NodeID


### Fault Detection
在 Cluster 中，一個 Node 被判定錯誤是經由多數的 Node 所決定；  
而如果發生錯誤的是 Master，且沒有 Slave 被成功升級成 Master，則此時 Cluster 進入錯誤狀態，停止 Client 的請求  

Node 在時間內會隨機對數個 Node 發送ping 請求，此時如果超過 `NODE_TIMEOUT` 都沒收到 pong，則會標記該 Node 為 `PFAIL`，此時的 PFAIL 並不會觸發任何機制；  
當 Node 在回覆 pong 時，會把自己所維護的`hash slot map`也一並發送，所以每個 Node 在一定的時間內都會知道其他 Node 所維護的標記狀態清單  

假設 Node A 標記 Node B 為 PFAIL，接著 Node A 收到來自其他 Master Node 對於 Node B 的標記，如果在 ` NODE_TIMEOUT * FAIL_REPORT_VALIDITY_MULT` 等待時間內，大多數的 Master 也都標記 Node B 為 PFAIL 或是 FAIL，則 Node A 轉標記 Node B 為 `FAIL`  

被標記成 FAIL 幾乎是不可逆，除了下述情況
1. Node 是 Slave 且可以被連上
2. Node 是 Master 且可以被連上，同時沒有分配到任何 slot，此時會等待被加入 Cluster
3. Node 是 Master 且可以被連上，同時 Cluster 過很長一段時間都沒有 Slave 被 Promote 成功，則可以考慮重新加入 Cluster 

透過這樣的設計，最終 Cluster 中每一個節點的狀態都會是被同步的

## Configuration handling, propagation, and failovers
這一章節主要談 Slave promotion 的過程  
### Cluster current epoch  
在分散式系統中，必須有個方式決定重複或是衝突的事件該選擇哪一個，Redis Cluster 中採用 `epoch` (對比 Raft 中的 term) 是一個 64 bit unsigned int，初始化 Master / Slave 都是 0，在發送訊息時加 1，在收到訊息時如果對方的 epoch 高於自己，則更新 epoch 並加 1；  
遇到有衝突，則選擇 epoch 較高的那一則訊息  

Master 在發送 ping 時會夾帶 configEpoch 且在回 pong 時會夾帶所屬的 slot mapping

### Promotion 過程
如果符合以下條件
1. Master Node 失敗
2. Master 有負責 slot
3. Slave 並沒有與 Master 失聯超過一定時間，這個判定是為了避免 Slave 的資料太舊  

則 Slave 會準備提起 Promotion，此時會增加 configEpoch 值，並希望取得多數 Master 的同意，發送 `FAILOVER_AUTH_REQUEST` 給 Master Nodes，接著 Slave 會等待 2 * NODE_TIMEOUT  

此時 Master 如果同意，則回覆 `FAILOVER_AUTH_ACK`，此時 Master 在接下來的 2 * NODE_TIMEOUT 不可以回覆其他 Slave Node FAILOVER_AUTH_ACK 訊息，避免多個 Slave 同時投票  

如果 Slave 在 2 * NODE_TIMEOUT 內收到多數 Master 同意，則選舉通過；  
反之如果失敗，則 4 * NODE_TIMEOUT 後開始下一次選舉  

### Hash Slot 維護
先前提到 Master 在送 pong 時會把自己管理的 slot 也一併更新，此時的 slot 會夾帶目前 Master 的 epoch 資訊，例如以下
1. Cluster 初始化，此時 Slot 都沒有對應的 Master，需要 `CLUSTER ADDSLOTS` 分配
```bash
0 -> NULL
1 -> NULL
2 -> NULL
...
16383 -> NULL
```
2. 假設分配部分給 A，A 會順便標記 epoch，假設此時值為 3
```bash
0 -> NULL
1 -> A [3]
2 -> A [3]
...
16383 -> NULL
```
3. 產生 Failover，B 上來頂替 A，此時會把 `epoch + 1`
```bash
0 -> NULL
1 -> B [4]
2 -> B [4]
...
16383 -> NULL
```
這也就是 `last failover wins` 策略，假使 A 此時網路連線回來要宣稱自己是 Master 也會被擋下來，因為 A 的 epoch 比較小

#### 實際案例
假設 Master 已經掛了，此時有 A,B,C 三個 Slave
1. A 競選成功變成了 Master
2. 網路區隔關係，A 被視為錯誤
3. B 因此競選而成 Master
4. 接著換 B 被網路區隔
5. 此時 A 成功連線回來

此時 B 失聯，A 以為自己還是 Master，此時 C 因為 B 失聯會想要去競選 Master
1. 此時 C 會成功，因為其他的 Master 知道 C 的 Master(B) 已經失敗
2. A 無法宣稱自己是 Master ，因為 hash slot 已經被更新成 B 的 epoch （第三步)，且 B 的 epoch 高於 A 的 epoch
3. 接著 C 會更新 hash slot 的 epoch，Cluster 持續運作

## 結論
整個看過 Redis Cluster Spec 會對於實際操作比較有信心，下一篇來自己實際架設看看    

有一些細節比較瑣碎就跳過，有些章節讀起來比較不通順，自己重新理解後編排一下 (OS. 可能會變得更難理解 ?! 

