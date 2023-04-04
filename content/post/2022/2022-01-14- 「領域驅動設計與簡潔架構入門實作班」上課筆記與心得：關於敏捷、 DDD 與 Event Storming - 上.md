---
title: '「領域驅動設計與簡潔架構入門實作班」上課筆記與心得：關於敏捷、 DDD 與 Event Storming - 上'
description: 結論 - 要學 DDD 直接報名 Teddy 的課程絕對是投資報酬率最高的方式
date: '2022-01-14T01:21:40.869Z'
categories: ['架構', 'DDD']
keywords: []
---
在 2022 年一開始就上到如此扎實、有收穫的課程真的是太讚了，之前在同事的介紹下認識了 Event Storming 並接觸到一些 DDD 的名詞，開始在網路上透過影音課程 [Domain-Driven Design Fundamentals](https://www.pluralsight.com/courses/fundamentals-domain-driven-design)、鐵人賽系列文章學習，在上課前也大概翻了一下 DDD 藍皮書，以上的教材都很不錯，也把名詞解釋跟 DDD 流程大致梳理一遍，但是蓋上書本、關掉網頁，`我要怎麼導入？`

例如說 DDD 提到開發人員要找領域專家一起找出 Domain Model，並將 Domain 劃分出適合的 Bounded Context，但什麼是適合？我該怎樣知道不適合？當我找到適合的"感覺" A-ha Moment 是怎樣會發生？

在翻閱《Clean Architecture》一書也有同感，文章寫得非常清楚，也透過 Uncle Bob 的文筆重新認識了軟體架構，但`然後呢？我該怎麼實作？`

在 DDD 一書闡述了軟體的建立需要攜手 Domain Expert 定義 Domain Model，並確保程式實作要跟 Model 保持一致，在圖表中拆分了 Entity / Value Object 等，以及提供很多元件間溝通的 Patten，但沒有說實作起來會怎樣 (講白了書本中沒有太多的程式碼)    
在 《Clean Architecture》 中描述的 SOLID / 分層原則 / 依賴性原則，但沒有說元件所謂的`職責怎麼劃分`，有很多實作的細節跟取捨並沒有太多案例

Teddy 將兩者結合，用自己設計的 Kanban 系統，帶著學員跑過一次 DDD 建模的過程，並透過《Clean Architecture》實作，他說他很接近理想的軟體 
> 改動的成本只跟需求範圍有關，跟系統存在的時間無關

透過一個階段一個階段的討論與檢討，先試錯再回頭解釋名詞，這樣的學習方式我覺得比看書、看影片還要好很多，以下我將用時間軸分享 Teddy 上課的內容以及我們小組討論的演進，會有大量錯誤然後被糾正 ~打臉~ 的案例 XD   
內容有點細，不會完整介紹 DDD 跟 Event Storming，只會分享在實作上錯誤與老師的糾正

推個課程頁面 [領域驅動設計與簡潔架構入門實作班](https://teddysoft.tw/courses/clean-architecture/)，實際參與小組討論會清晰很多

## Domain Driven Design
### DDD 基本介紹
#### 1. 什麼是 Domain
Domain 可以被拆分為 `Problem Domain` 以及 `Solution Domain`，Problem Domain 是指實際發生在世界上的問題，也就是公司所面臨的商業問題，例如外出想要叫車、肚子餓想要點外賣等，但是世界上的問題太多了，不會每一個都關注，所以總合來說 
> 利害關係人所在乎的實際問題就是你的 Domain 

Uber 在乎用戶外出的通勤問題 / Food Panda 在乎用戶肚子餓想點外賣果腹的問題，各自有各自的 Problem Domain，並對此提出各自的解法 Solution Domain，之後討論將 Solution Domain 限縮在軟體設計上

回歸開發的根本，為什麼我們需要一直跟 PM / 利害關係人 (後續以`領域專家`代稱) 不斷釐清問題，因為問題才是驅動一切的本質，如果今天不用寫一行程式碼就能解決問題，那何必動手，`釐清問題是開發的第一步`

#### 2. 什麼是 Domain Model
有了 Problem Domain，過往的習慣是直接進入開發設計，也就是對應到 Solution Domain，但這兩個 Domain 間有一個很大的鴻溝 (附圖路徑 A)，開發人員以為自己聽懂了需求就開始實作，而領域專家也以為開發人員真的懂了，最後等系統驗收時才發現根本做錯了

DDD 提倡領域專家與開發人員應該要先達成共識，將 Domain 建立出對應的模型 Model，讓雙方將共識轉換為圖形，並在過程中建立 `Ubiquitous Language` 共同語言，等確認後開發人員才去實作 (附圖路徑 B) 

![](/posts/2022/img/0114/domain-model.png)

比對路徑 A 、B，看似 B 繞了點遠路，但先透過 Domain Model 闡述 Solution 的長相並抽離實作，才能用最小的成本，讓領域專家及早確認解法的方向正不正確
> Q: 是不是所有問題都要建 Domain Model?   
> A: 不是，只有當商業邏輯足夠複雜才需要，單純的 CRUD、報表系統是不需要的

Event Storming 是一個建立 Domain Model 的方法，從 High Level 到 Low Level 持續演化的過程
#### 3. Domain Model 要越真越好嗎
所謂的「真」是指實際世界的真實性，Teddy 上課舉例：「樣品屋是不是越像真的實體屋越好？」  
答案是「不一定!」，重新思考 Domain Model 是 Solution Domain 的一環，所以真正的重點是源頭的 Problem Domain，今天建商蓋樣品屋是希望用戶購買實體屋，但如果今天建商蓋完就銷售一空，那根本連樣品屋都不用蓋

只要 Model 能夠剛好解決問題就好，over design 或 under design 都是不好的，這點在後續的實際操作會再補充

## Event Storming
以 Kanban 系統 [ezKanban](https://ssl-ezscrum.csie.ntut.edu.tw/ezKanban-stable)，Teddy 擔任領域專家 (兼任開發人員XD) 帶大家跑過 Event Storming，以下介紹 Kanban 的核心商業邏輯
- Visualize：視覺化表達
- Limit WIP：每一個工作階段的進行中工作 (WIP) 有數量限制
- Manage Flow：管理工作流程
建模工具使用 [Miro](https://miro.com/app/dashboard/)

進行順序按照階層從 Big Picture 開始與領域專家討論核心的用戶行為，接著到 Process Modeling 補充更多的規則、行動，最後才是 Software Design
![](/posts/2022/img/0114/event-storming-level.png)

### 1. Big Picture: 找出 Domain Event
先拉出一條箭頭表達時間軸，先後順序，將 User Story 中的關鍵事件 (Domain Event) 先條列出來，所謂的`事件是會改變系統狀態`，例如電商系統用戶加購物車、結帳等，反之`讀取不是事件，因為不會改變系統狀態`，不管 Data 讀取幾次都不會有變化

事件是代表發生過的事情，所以都會用過去式表達，例如看板系統中的
- Workflow Created
- Workflow Deleted
- Stage WIP set
等等

在討論過程中，務必記得
- 不要出現技術用語，例如資料庫怎麼儲存、實作要套什麼 Design Patten 
- 不要被 UI 綁架了!
![](/posts/2022/img/0114/domain-model-impl.png)
因為我們是看著 Teddy 已經實作好的 ezKanban，所以 Domain Event 很多，實務上看各自系統規模，而且 `Event Storming 是持續演進，不用求一步到位`

上圖是我們小組建立 Domain Event，其中有三點錯誤
#### a. 時間軸順序性
我們一開始把 User Created / User Logined 放在同一列上，同一列在 Event Storming 代表這兩個事件是在差不多時間點發生，但理論上 User Create 必然在 User Logined 之前，所以不該放在同一列上
#### b. 不要被 UI 綁架
這是一個非常有趣的案例，在 ezKanban 中你必須在畫面上點擊「Layout Edit」才能編輯工作流程的框架，所以我們組內討論很直覺的想這個事件很重要，所以就補了一個 「Layout Mode Entered」，但老師說不對!! `被 UI 綁架了`，這只是一個實作細節，我今天可以換一個按鈕或 UI 流程做到同一件事，這屬於應用層面的邏輯

Domain Event 又可細分成兩種 Core Domain Event / Application Domain Event，前者是滿足核心商業邏輯的事件、後者是應用程式執行時需要的事件，今天以看板系統，用戶哪會關心什麼 Layout Mode，那是你`實作的事情`，所以不該把這個 Event 放在上面

我自己後來在反思這件事情，我嘗試用這樣的邏輯去釐清  
> - 我能不能用不同的 UI Flow 取代當前的事件？ 例如在 Board 頁面就區分出「版位調整」/「工作調整」，如果可以的話，那就是應用事件
> - 今天我實作在多平台 Web / App / Server 都需要這個事件嗎？如果要那有可能是核心，如果只有 Web 要實作其他平台不用，那肯定是應用事件

這麼在意是不是 Core Domain Event 的用意是讓 Domain Model 保持簡潔，太多細節參雜會混淆討論
#### c. 不要被 DB 綁架 - 任務驅動而非指令驅動
在條列 Domain Model 時，我與組員都有一個疑問 `「一個 Stage 有 10 個屬性都能夠 CRUD，那我要全部列出來嗎？例如 Stage 的標題、說明欄等，那我是要寫一個 Stage Updated 就好還是要寫 Stage Name Updated？」`  

除了不要被 UI 綁架外，也不要被資料庫綁架了! 今天用戶才不管你怎麼 CRUD，他真正在意是`能不能完成他手中的任務`，例如說今天我去 ATM 領錢，系統顯示
1. 說法 A: 您已提領 1000 元
2. 說法 B: 已更新您的帳戶餘額為原餘額減去1000 元
   
相信你提款後看到說法 B 應該會傻眼，請以「用戶想要完成什麼任務」的角度描述 Domain Event

#### d. 用說故事的方式去釐清 Model 表達力
我在操作 ezKanban 先跑了建立工作流程，最後才發現 ezKanban 有 Team 的概念，Team 可以邀請其他 User 當作 Member 共享 Project，因為我比較晚看到所以 Team 相關的事件放在時間軸後面

最後 Teddy 問說：「這樣的 Model 表達了什麼含意？」Model 的意義在於`圖形化我們想要解決的問題與發生順序`，也就是用戶的使用歷程與每一個使用案例，今天用說故事的方式會像
1. 故事 A:「用戶今天想要使用看板系統，他先註冊了帳號並登入，接著建立專案，並開始設定自己的工作流程...... 最後他邀請他的成員加入，大家一起操作看板」
2. 故事 B: 「用戶今天想要使用看板系統，他先註冊了帳號並登入，接著建立團隊，邀請他的成員加入，大家一起操作看板，接著建立專案，並開始設定團隊的工作流程......」

兩個故事都說得通，但 Teddy 覺得故事 B 更符合他的使用場景，團隊的建立會在工作流程之前，所以調整後的 Domain Event 大致長這樣
![](/posts/2022/img/0114/domain-model-impl-r.png)

### 2. Big Picture - 劃分 Bounded Context
洋洋灑灑列出 Domain Event 後，接下來要來分群，想像成是買房畫隔間，設計圖應該要能清楚辨識出這是一個商務辦公室還是一個小家庭自住用，透過隔間去表達系統的意圖
![](/posts/2022/img/0114/room.png)
*附圖從 Google 搜尋，不用懂室內設計但也大致能看出左右兩張圖的不同

我們小組一開始思考方式是「不然就每個物件一間，Workflow 一間 / Board 一間等」，如圖示
![](/posts/2022/img/0114/bound-wrong.png)

Teddy 看到我們如此設計，他反問說「你們的隔間有反應出 "看板系統" 這個意圖嗎？如果從外部使用者的角度，他看到 Workflow / Board / Stage 這麼多細節對嗎？」  

正確的隔間應該是
![](/posts/2022/img/0114/bound-right.png)
區分成三塊：
- Core Domain：Kanban 是我們的核心領域，`千萬不要外包`
- Generic Domain：User / Team 屬於通用性功能
- Support Domain：圖上沒有，如金流、外部通知系統，這種的找外包即可，不一定要自己開發

如何知道自己的隔間是否正確？回到商業邏輯與說故事的方式，劃分 Bounded Context 後是否能正確拆解出公司的核心與非核心商業邏輯  

> 大家最關心的微服務，通常是一個 Bounded Context 一個部署的元件
### 3. Big Picture - 加入 Role / Externel System
加入觸發的角色 / 外部系統，這一步驟相對單純，角色是系統中動作的執行者
![](/posts/2022/img/0114/role.png)
HotSpot 是當討論過程卡住、發生意見不同、命名不同時可以貼著註記，避免討論被卡住，最後可以看哪一個區塊是大家最沒有共識的

### 4. Process Modeling - 加入 Command / Read Model
這一步相對單純
- Command 是觸發 Domain Event 的動作，基本上就是把完成式改成現在式表達
- Read Model 則是完成 Command 所需的參數
![](/posts/2022/img/0114/command.png)
#### a. 建立事件是否要傳入 id
有趣的小細節是 Create Board 時我們把 board_id 也寫出來，小組討論時會覺得 DB 會自動產生 id 所以不用寫到 read model，但 Teddy 說 `「錯，我哪管你 id 是 DB 產生還是前端用 UUID 產生，這是實作細節，Board 就是需要 id 識別」`，再次強調，不要陷入 UI/DB 的細節
### 5. Process Modeling - 加入Policy
Policy/Rule/Process 是指 `事件完成後觸發的流程`，千萬不要跟動作需要完成的驗證搞混，例如說
- 輸入 Email 註冊時，Email 必須符合格式 => 這是驗證
- 密碼輸錯三次後，需要封鎖帳號 => 這是 Policy

驗證是實作細節在 Event Storming 中不表達，Policy 才是我們現階段要關注的，以下是舉例「全家推出領取包裹後，可以八折買拿鐵」
![](/posts/2022/img/0114/policy.png)  

這邊偷夾帶一張白色的便利貼，Teddy 說他確實也遇到有些驗證是重要的商業邏輯，他自己變形增加了白色便利貼，表示 Command 的驗證規則

> 到這一步我們可以發現 Event Storming 很好的描述了一個故事
「User want receive package, we have to check his id card, after user have received package, he can purchase latte 20% off」  
這就是 Event Storming 的魅力

### 6. Software Design - 加入 Model
接下來進入實作細節，Model 可以想做是物件，比對 Command 應該是哪一個物件負責，條列後最終把 Model 的大致關係也描繪，大致如下
![](/posts/2022/img/0114/model-wrong.png)
因為 Stage / Swimlane 一者是橫向一者是直向，兩者可以互相包含，所以圖表有點複雜，圖表複雜代表程式碼實作一定也不好寫，該怎麼優化呢？

![](/posts/2022/img/0114/model-right.png)
- 抽一個 Lane 代表 Stage / Swimlane，這樣關係就單純很多
- 更精準表達商業邏輯，另外一個重點是 `Workflow 與 Stage 關聯而不是 Lane`，因為 Workflow 預設第一層必須是 Stage，透過圖表表示出核心的設計邏輯

#### a. Model 拆分很看商業邏輯
同學在課堂上詢問：「如果我有多個支付，我是不是要把每個 CreditCardPay / ApplePay 都寫成一個 Model？」    
Teddy 反問：「為什麼需要？如果 Pay 只是一個付款手段，如果沒有很大的差異，一個 Pay 表達實作時再拆分就好」  
我接著提問：「那為什麼 Stage / Swimlane 要拆分？他們也只是一個橫的一個直的」

Teddy 表示 `因為在看板的 Domain 中，直的代表工作階段 / 橫的代表工作流程是截然不同的，這是非常核心的商業邏輯`，所以 Model 要拆到多細，要不要真的把每個實作的物件都表達，完全看領域專家與開發人員是否很重視每個元件的獨立性與表達性

### 7. Software Design - 找出 Aggregate
最後一步! 也是很抽象的一步，將 Model 分群，有些 Model 明顯是其他 Model 的附庸 ，例如說訂單細項 Order Item 是訂單 Order 的附庸，每次 Order Item 的改動會影響 Order 的計算，會進階影響例如折價券等計算，所以 Order Item 最好不要直接調整，由 Order 統一調整才能確保資料的`一致性` 

要不要把 Model Aggregate 成一塊有兩個作用力
- 資料一致性
- 併發操作

Teddy 帶我們思考的方式是
> 今天我改動 Model A，那我可不可以同時改動 Model B ? 我在 Workflow name 的時候，可以同時操作 Board 嗎？

切記不要用 Database Relation 思考，例如 User 刪除 Order 也要跟著被刪除，這樣 Aggregate 永遠切不開，更直觀地說 `要包 Transaction 操作的都就放在同一個 Aggregate`  
![](/posts/2022/img/0114/aggregate-right.png)

找出 Aggregate 後，需要找一個 Model 當作 Root，往後 Aggregate 內的 Model 都由他來控制，`外人不可直接操作內部 Model`，任何跨 Aggregate 操作只能保證最終一致性

### 延伸變體：還是很想把讀取也放入 Event Storming 可以嗎？
Teddy 上課一直強調讀取隨便寫就好，怎麼髒都沒關係因為 Command 才會影響系統狀態 XD Query 效能問題等又是 DB 細節，本身也不是 Event Storming 該關注的層級  

但協作上大家還是想把 UI 放到討論中 / Read Model 如果有前端可能也希望在寫得細一點，這些都可以自己延伸，Teddy 也分享有些流程 UI 可以幫助說明的話他也會放進去，例如 Command 後回傳另一張 Read Model / UI 圖示放在 Read Model 旁邊等
![](/posts/2022/img/0114/ui.png)

### 延伸問題：開發只要這一份文件就好了嗎？
文件的維護也是我課前很想了解的部分，在 DDD 藍皮書中不斷強調 `Domain Model 跟程式碼實作要高度一致`並持續演進，但工作多年有良好維護文件習慣的人還真的是少數，尤其是文件越多份維護的成本就更高，所以我課後就問 Teddy 他們團隊開發是不是只有這一份文件，他說基本上是，資料庫部分因為他是走 Event Sourcing 所以不用另外的 Schema 設計文件，如果不是頂多再一份 DB Schema 文件就足夠了

## DDD - Tacticle Design & Strategic Design
跑過一次 Event Storming 再回來看 DDD 廣為人知的兩張圖就比較能理解了，這邊只額外補充兩件事
#### 1. Entity 與 Value Object 區分
前者是具有 id 在 Conext 下有唯一識別性的物件，後者是內容重要但是不是同一個物件不太關心，例如說紙鈔，大多系統下我們只關心紙鈔的面額，甭管你是左邊的 100 元還是右邊的 100 元，所以是 Value Object / 但如果是印鈔系統，同樣是 100 元還是要用 id 區分不同的紙鈔，這時就是 Entity 了

#### 2. 如果有驗證需求，可以考慮用 Value Object
一個實作的小細節，如果以往都是用欄位儲存一個基礎型別，例如 string email，要增加驗證就會很瑣碎，封裝一個 Email 物件並在 constructor 統一驗證會比較簡潔

## 結語
重點小整理：
- 以商業核心為出發
- 用說故事的方式跑 Event Storming
- 不要落入實作細節
- 如果有需要，可以自己變體適應組織


上完課自己重新覆盤，沒想到花這麼多時間才整理完，DDD 用靜態的學習方式真的很抽象，大腦一直轉不過去，上完 Teddy 的課才覺得那扇門被打開了一個縫，看到理想軟體開發的光明 XD  

這一篇主要整理 DDD，下一篇預計整理 Clean Architecture 與如何跟 DDD 結合，希望這些紀錄對大家有幫助，最後在幫 Teddy 老師推廣一下他的[課程](https://teddysoft.tw/courses/clean-architecture/)，只有實際跑過一次Event Storming 才能真正學會，如果有什麼建議或糾錯再麻煩留言