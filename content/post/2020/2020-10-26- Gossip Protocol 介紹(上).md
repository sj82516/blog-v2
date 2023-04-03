---
title: 'Gossip Protocol 介紹 (上) - 從 Cassandra 內部實作認識 Gossip Protocol 的使用'
description: 在學習 Consul 與 Redis Cluster 過程中，都提及使用 Gossip Protocol 同步集群中節點的狀態，究竟機器之間怎麼談茶水間八卦實在令人好奇，透過 Cassandra 內部實作理解 Gossip 的原理
date: '2020-10-26T08:21:40.869Z'
categories: ['資料庫','系統架構']
keywords: ['Redis', 'Consul']
---

Gossip Protocol 是一種通訊機制，應用於同一網路內機器與機器間交換訊息，原理類似於辦公室傳謠言一樣，一個傳一個，最終每一個機器都擁有相同的資訊，又稱 `Epidemic Protocol`

實務上有幾個好處  
1. 去中心化:  
機器與機器間直接溝通 (peer to peer)
2. 容錯率高:   
即便節點與節點之間無法直接相連，只有有其他 節點 可以傳遞狀態，也可以維持一致的狀態
3. 效率高且可靠  

Gossip Protocol 被廣泛採納，如Cassandra / Redis Cluster / Consul 等集群架構，以下將從 Cassandra 的實作來理解 Gossip Protocol

## Apple Inc.: Cassandra Internals — Understanding Gossip
{{<youtube FuP1Fvrv6ZQ>}}

先從實務面來看，Gossip Protocol 在 Cassandra 中主要用於同步 節點 的 Metadata，包含
1. cluster membership
2. heartbeat
3. node status   
同時每個節點都會保存一份其他節點狀態的 Mapping Table  

更具體來看節點狀態所保存的資料格式
1. HeartbeatState:  
每一個節點會有一個 HeartbeatState，紀錄 generation / version，`generation` 是節點啟動時的 timestamp，用來區分機器是否重新啟動過；`version` 則是遞增數值，每次 ApplicationState 有值更新時就會遞增  
> 所以同一個節點內的 ApplicationState version 不會重複，且 version 比較大一定代表這個鍵值比較新  

2. ApplicationState: 一個由`{enum_name, value, version}`建立的 tuple，enum_name 代表固定的 key 名稱，version 則表示 value 的版本號碼，號碼大者則代表資料較新
3. EndpointState:  紀錄某一個節點下所有的 ApplicationState
4. EndpointStateMapping: 一個節點會有一張針對已知的節點所紀錄的 EndpointState，同時會包含自己的狀態

如下圖
```bash
EndPointState 10.0.0.1
  HeartBeatState: generation 1259909635, version 325
  ApplicationState "load-information": 5.2, generation 1259909635, version 45
  ApplicationState "bootstrapping": bxLpassF3XD8Kyks, generation 1259909635, version 56
  ApplicationState "normal": bxLpassF3XD8Kyks, generation 1259909635, version 87
EndPointState 10.0.0.2
  HeartBeatState: generation 1259911052, version 61
  ApplicationState "load-information": 2.7, generation 1259911052, version 2
  ApplicationState "bootstrapping": AujDMftpyUvebtnn, generation 1259911052, version 31
.....
```
這邊可以看到節點 10.0.0.1 所保存的 `EndPointStateMap` 有兩筆 EndPointState，其中 10.0.0.1 的 HeartBeatState 是 `generation 1259909635, version 325`，這代表 10.0.0.1 是在 1259909635 時啟動的，並且他目前保存欄位中最新的版本是 325；  
接著看 `ApplicationState "load-information": 5.2, generation 1259909635, version 45`，這代表節點內 "load-information" 這個 Key 對應的值是 5.2 以及當時收到的 generation 與 version，後兩者用來決定 `這個 key 收到訊息後要不要更新的依據`  

### Gossip Messaging 
接著來看每次 Gossip 的實作流程，每個節點會在每一秒啟動一個新的 gossip 回合   
1. 挑出 `1~3` 的節點，優先選擇 live 狀態的節點，接著會機率性選擇 Seed 節點 / 先前判定已經離綫的節點
2. 傳遞訊息的流程是 SYN / ACK / ACK2 (類似於 TCP 的3次交握)  

假設現在是節點 A 要傳訊息給 節點 B 關於節點 C 的 Gossip
1. **GossipDigestSynMessage** :  
節點 A 要發送的 SYN 訊息包含 `{ipAddr, generation, heartbeat}`，需注意此時只要送 HeartbeatState，而沒有送詳細的 ApplicationState，避免多餘的資料傳輸  
2. **GossipDigestAckMessage** :  
節點 B 收到後，會去比對他自己暫存節點 C 的狀態，運算兩者差異    
    a. 節點 A 的資料比較新，則節點 B 會準備跟節點 A 要新的資料  
    b. 節點 B 的資料比較新，打包要更新的 ApplicationState 回傳 `ACK` 通知節點 A
3. **GossipDigestAck2Message** :  
節點 A 收到 ACK 後，更新自己暫存的資料，並且根據 (2.a) 中節點 B 所需要的 ApplicationState，回傳 `ACK2`  

會多一個 `ACK2` 是為了讓通訊更穩定，達到更快收斂的作用，但這邊如果 節點 B 沒收到 ACK2 是否會重試等如同 TCP 作法就沒有提及  

> 總結來看傳送訊息的過程，在 Cluster 沒有節點狀態異動下，傳送的訊息量是固定的，不會有 `Gossip Storm` 網路封包突然爆量的情況；    
除非是有節點 新加入，多個節點 希望同步資訊才有可能   

來看實際案例，假設
目前有節點A (10.0.0.1)
```bash
EndPointState 10.0.0.1
  HeartBeatState: generation 1259909635, version 325
  ApplicationState "load-information": 5.2, generation 1259909635, version 45
  ApplicationState "bootstrapping": bxLpassF3XD8Kyks, generation 1259909635, version 56
  ApplicationState "normal": bxLpassF3XD8Kyks, generation 1259909635, version 87
EndPointState 10.0.0.2
  HeartBeatState: generation 1259911052, version 61
  ApplicationState "load-information": 2.7, generation 1259911052, version 2
  ApplicationState "bootstrapping": AujDMftpyUvebtnn, generation 1259911052, version 31
EndPointState 10.0.0.3
  HeartBeatState: generation 1259912238, version 5
  ApplicationState "load-information": 12.0, generation 1259912238, version 3
EndPointState 10.0.0.4
  HeartBeatState: generation 1259912942, version 18
  ApplicationState "load-information": 6.7, generation 1259912942, version 3
  ApplicationState "normal": bj05IVc0lvRXw2xH, generation 1259912942, version 7
```
以及節點B (10.0.0.2)
```bash
EndPointState 10.0.0.1
  HeartBeatState: generation 1259909635, version 324
  ApplicationState "load-information": 5.2, generation 1259909635, version 45
  ApplicationState "bootstrapping": bxLpassF3XD8Kyks, generation 1259909635, version 56
  ApplicationState "normal": bxLpassF3XD8Kyks, generation 1259909635, version 87
EndPointState 10.0.0.2
  HeartBeatState: generation 1259911052, version 63
  ApplicationState "load-information": 2.7, generation 1259911052, version 2
  ApplicationState "bootstrapping": AujDMftpyUvebtnn, generation 1259911052, version 31
  ApplicationState "normal": AujDMftpyUvebtnn, generation 1259911052, version 62
EndPointState 10.0.0.3
  HeartBeatState: generation 1259812143, version 2142
  ApplicationState "load-information": 16.0, generation 1259812143, version 1803
  ApplicationState "normal": W2U1XYUC3wMppcY7, generation 1259812143, version 6 
```
#### 節點A 決定向節點B 發起 Gossip 
產生的 GossipDigestSynMessage 會是類似於 `10.0.0.1:1259909635:325 10.0.0.2:1259911052:61 10.0.0.3:1259912238:5 10.0.0.4:1259912942:18`，主要是傳送 `Node IP:generation:version`

#### 節點B 收到 GossipDigestSynMessage 
會有以下流程  
1. 跟自己的狀態比較，從差異最多的遞減排序，這意味著優先處理差異最多的節點資訊
2. 接著檢驗每一個節點的資料
-節點A 所保存的 `10.0.0.1:1259909635:325` 會大於節點B 所保存的`10.0.0.1:1259909635:324`，generation 一樣所以略過，但是 version 325 > 324，則代表節點B 需要向節點 A 索取 10.0.0.1 在 ApplicationState 在版本 324 之後的資料  
    - `10.0.0.2:1259911052:61` 比節點B 保存的版本還要小，所以到時候會打包資料給節點A
    - `10.0.0.3:1259912238:5` 部分節點B generation 比較小，這意味著 10.0.0.3 有 reboot 過，所以節點B 需要更新全部的資料
    - `10.0.0.4:1259912942:18`節點B 根本沒有 10.0.0.4 的資料，所以需要全部的資料

組合以上結果 GossipDigestAckMessage的內容會是
```bash
10.0.0.1:1259909635:324
10.0.0.3:1259912238:0
10.0.0.4:1259912942:0
10.0.0.2:[ApplicationState "normal": AujDMftpyUvebtnn, generation 1259911052, version 62], [HeartBeatState, generation 1259911052, version 63]
```
這代表著 
- 請給我 10.0.0.1 在 generation 1259909635 中 version 324 以後的更新資料
- 請給我 10.0.0.3 在 generation 1259912238 全部資料 (version:0)
- 10.0.0.4 同上
- 這是你需要更新關於 10.0.0.2 的 ApplicationState 資料  

#### 節點A 回覆 GossipDigestAck2Message
節點A 收到後，更新完 10.0.0.2 的資訊後，接著回覆節點B 所要的資料
```bash
10.0.0.1:[ApplicationState "load-information": 5.2, generation 1259909635, version 45], [ApplicationState "bootstrapping": bxLpassF3XD8Kyks, generation 1259909635, version 56], [ApplicationState "normal": bxLpassF3XD8Kyks, generation 1259909635, version 87], [HeartBeatState, generation 1259909635, version 325]
10.0.0.3:[ApplicationState "load-information": 12.0, generation 1259912238, version 3], [HeartBeatState, generation 1259912238, version 3]
10.0.0.4:[ApplicationState "load-information": 6.7, generation 1259912942, version 3], [ApplicationState "normal": bj05IVc0lvRXw2xH, generation 1259912942, version 7], [HeartBeatState: generation 1259912942, version 18]
```

這樣就完成一輪的 Gossip 了
> 可以看出為什麼 HeartbeatState 的 version 會與 ApplicationState 共享，這邊的共享指的是在`同一個節點下 ApplicationState 的 version 必須是獨一無二且遞增`，這樣才能在 SYN 時只傳送 HeartbeatState 直接判斷有哪些欄位需要更新  

以上範例整理自 [ArchitectureGossip](https://cwiki.apache.org/confluence/display/CASSANDRA2/ArchitectureGossip)

## 其他集群上的管理
集群管理上，除了透過 Gossip Protocol 同步資訊外，還有幾個問題要解決
1. 誰在 Cluster 當中
2. 如何決定節點的狀態是 Up / Down，這又會帶來什麼影響
3. 何時要終止跟某節點的通訊
4. 應該要偏好與哪個節點通訓
5. 增加/移除/刪除/取代節點時如何實作

### 誰在 Cluster 當中  
當一個新的節點要啟動時，他必須要知道集群中有哪些節點去 Gossip，在 Cassandra 的設定檔中可以指定 `Seed`，有不同的作法可以指定，常見是寫死某一些節點的 ip addr，節點啟動後就跟 Seed 節點溝通，後續就透過 Gossip Protocol 取得所有節點的狀態與 IP  
> 在 Consul 中，會自己透過廣播在 LAN 裡面自動發現有沒有其他節點，在 EC2 上還可以指定 EC2 Tag 去找出其他節點  

### Failure Detection: 決定節點是 Up 或 Down  
在 Cassandra 中，錯誤偵測是該節點在本地端決定某節點的狀態，而這個狀態不會隨著 Gossip 所傳送
> ex.節點A 覺得節點B 是 Down，當節點A 跟節點C Gossip 時，節點C 不會因為節點A 而把節點B 判斷成 Down，節點 C 會自行判斷  

偵測的方式透過 Heartbeat，Heartbeat 可以是節點跟節點直接用 Gossip 通訊，也可以是從其他節點間接取得 Gossip；  
節點會計算每次 Heartbeat 的間隔，當超過 `phi_convict_threshold` 則判定為 Down，系統需要因應硬體狀態/網路環境去調整閥值，避免太敏感誤判或是太遲鈍而反應不及等狀況    

在節點斷線的時候，其他節點部分的寫入可能因此沒有收到 ACK 回覆，此時會暫存在本地當作 Hint，如果節點在一定時間內恢復，則會透過 Hint 重新傳送寫入，修復掉資料的可能  

如果節點重新恢復時，其他節點會定期重送 Gossip 給 Offline 節點，屆時就能把 Down 調整回 Up  

### 節點偏好
除了錯誤偵測外，Cassandra 內部有模組 Dynamic Snitch 專門做節點間的通訊品質偵測，每 100 ms計算與其他節點的延遲，藉此找出表現較好的節點；  
為了避免一時網路波動，每 10 分鐘就會重新計算  

其餘的節點管理就暫時略過，對於理解 Gossip Protocol 不大
## 結語  
在分散式系統中，節點的狀態同步十分基礎且重要，而 Gossip Protocol 目前是被廣泛應用的解法，模擬人類傳送八卦的方式，想不到在機器也一樣適用   
整體最有趣的設計應該在於 `generation / version` 的實作，透過 generation 可以知道機器重啟過後要不要重新要資料；透過 version 可以快速 diff 僅有哪些資料要更新，避免額外的傳輸浪費，下一篇將從理論上去分析 Gossip Protocol