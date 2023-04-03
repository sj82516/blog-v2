---
title: '【Refactoring Ruby Edition】(一) 體驗重構'
description: Refactoring Ruby Edition 系列第一篇，體驗重構的魅力
date: '2021-05-01T08:21:40.869Z'
categories: ['程式語言', 'Ruby', '重構']
keywords: []
---
工作了數年，可能是一開始寫動態語言的關係，鮮少注意到抽象化 / 封裝 / 物件導向的設計，導致程式碼越來越難以維護，深知這是自己技能上的弱點，開始去學習 TDD / 重構，希望可以寫出好懂 / 好維護 / 有測試保護的乾淨程式碼  

剛好最近換工作開始寫 Ruby，就順便買了這本 `【Refactoring Ruby Edition】`，原本是 Martin Fowler 大大用 Java 當作範例所編寫，這一本是由另外兩名作者與 Martin Fowler 掛名，採用 Ruby 當作範例並加入 Ruby 的語言特性，不影響對於重構的理解與實踐   

目前看了一半覺得很受用，整理很多 code smell，以及遇到時該如何有系統的重構成乾淨的程式碼，有一些原則可能會互斥 (抽類別或是把類別塞回去)，書中也有提及該如何判斷何者為佳

以下內容對應的是第一章 「Refactoring, a First Example」，程式碼於此 [sj82516/refactoring-ruby](https://github.com/sj82516/refactoring-ruby)，以下每個步驟都會對應到一個 commit

### 範例
這是一個租片服務，計算目前用戶租片的費用與回饋點數，影片有分三種類型

## 重構之前
一開始先觀察這段這段程式碼， Customer 中的 statement method 明顯很長一段，負責許多事情，包含計算與整理輸出規格  

從功能面上來看，這段程式碼運作符合預期，對於直譯器來說也不存在醜不醜的程式碼，但今天如果需求變更，需要人類的介入去修改程式碼，那可讀性就很重要了

例如說今天要增加一個輸出成 html 格式，目前的寫法只能 copy statement 並修改輸出格式，又如果之後要調整影片的計價方式，那很不幸兩個方法都要同步改動

> 當你發現要增加新功能很難改動時，`先重構`到你覺得很好加新功能後，再加上新功能
## 開始重構
以下按照書中建議，開始進行重構  
[init](https://github.com/sj82516/refactoring-ruby/commit/37ab1f1d4f998f0c49b7512489cf06b6606740c9)
### 1. 寫測試
如何確保在重構過程不把功能改壞？ `寫測試！` 透過寫測試可以明確表達我們預期的程式碼行為，在與 PM 溝通時透過具體的測試案例也可以避免有認知上的歧異  
[test: add unit test](https://github.com/sj82516/refactoring-ruby/commit/4a2efdcff4d2dc6654dd74590bbb59da85a257b6)
### 2. 拆解與重組 - Extact Method
首先拆解過於複雜的 statement 方法，要拆解首先找到邏輯上比較緊密的區塊，並拆分出獨立的方法，例如 case 就很適合

在拆分時要注意使用到的變數有沒有被修正，例如 rental 沒有被改動所以當作參數傳進去就沒事，但是 this_amount 有被改動，如果被改動只有一個變數，那就當做 function return 即可  

> 別忘記每改一小步都要跑測試，尤其是動態語言容易卡在變數名稱寫錯等小問題上

[refactor extract amount_for method](https://github.com/sj82516/refactoring-ruby/commit/c734e357cd146243da6bb1b29aa994be40c84589)
#### 2-2 重新命名幫助認知
在新的 amount_for method，改動一下變數名稱有助於含義的表達，少用太廣泛的含義例如 element / i 這類

> Any fool can write code that a computer can understand. Good programmers write code that humans can understand.

不得不推薦一下 RubyMine，一年訂閱要 $89 鎂但是有 Refactor 系列的輔助工具超方便，透過 `shift 鍵 * 2 叫出 action dialog 後輸入「refactor this」`，就會有一系列的重構方法讓你挑選 

[refactor: rename](https://github.com/sj82516/refactoring-ruby/commit/35abc2dd64937c7c77ee6e398b9c1f77376912e7)
### 3. 把邏輯放在正確的物件上 - Move Method 
仔細看一下 amount_for 方法中，運算邏輯的資料來源都從 Rental 這個物件而來，都沒有用上 Customer 物件上的資料，這時候可以合理的懷疑是不是把方法移到 Rental 會更加合適 

接著修正 Customer 的引用  
[refactor: move method to rental](https://github.com/sj82516/refactoring-ruby/commit/06622927d241160705a9947c7aadf24c040ea4b2)
#### 3-2. 移除不必要的區域變數 - Inline
這時候 this_amount 就有點多餘了，透過 inline 變數直接從 rental.charge 讀取  

或許會有人爭論：多次呼叫方法會降低效能，但是原則上`重構是為了簡潔，效能問題等到發生時在優化即可`，尤其是現在的運算資源往往很足夠，好維護上帶來的開發資源節省會比運算資源來得重要  

> 回過頭來看區域變數哪裡不好？  
試想我們剛剛在抽方法，需要擔心區域變數有沒有被其他人讀取或修改，而更糟糕的事會有人把區域變數重複 assign 於不同的用途，為了避免多餘的擔心與閱讀障礙，移除區域變數是會有幫助的   

[refactor: remove total_amount](https://github.com/sj82516/refactoring-ruby/commit/8e8668ac07c1aa7d32e369844a1f82673d35e427)

#### 3-3. 修改 frequent_renter_points
同樣的修改可以套用到 frequent_renter_points，不過 frequent_renter_points 本身是區域變數，而且是不斷地隨著 loop 而改變，這時候當作參數傳進去在用 return reassign 有點沒必要    
[refactor: extract and move frequent_renter_points method](https://github.com/sj82516/refactoring-ruby/commit/90c71babfeec7e5e05170e1b9aca81dd9f4d81c7)

### 4. 移除區域變數 Remove Temp
先前提到區域變數的缺點，接著移除 total_amount 與 frequent_renter_points，直接在使用的地方呼叫方法，同樣的，`呼叫方法的效能疑慮只有在真的有問題時再考慮`  

Ruby 比較妙的是方法呼叫可以省略()，所以看起來跟呼叫變數沒什麼兩樣  
[refactor: remove frequent_renter_points](https://github.com/sj82516/refactoring-ruby/commit/e8a02536a1258ed08e74ee0543e6094a4c113688)
### 5. 透過多型取代 case  
如果要使用 case，那記得 case 中的判斷依據應該是物件本身的資料  
目前在 Rental 的 charge 中，會依照 Movie 的 type 分不同的收費方式，這裡如果未來 Movie 要增加 type / 調整每種 type 的收費方式，一直來改 Rental 的 charge 呼叫端不太合適，所以將 charge 的邏輯歸類到 Movie 中    
[refactor: move charge logic to Movie](https://github.com/sj82516/refactoring-ruby/commit/3249902cc08268667286ba7ff0c2f43a7dec9eac)

相同的道理也套用於 frequent_renter_points 上  
[refactor: move frequent_renter_points logic to Movie](https://github.com/sj82516/refactoring-ruby/commit/dcf968a9e279c59321a7771ba3c5eab5626976db)
#### 5-2. 將 case 轉換成多型
Movie 中的 charge 依照不同的 type 收費，這聽起來就很像`繼承`可以處理的事情，可建立多個不同的 Sub Movie Class  
但這點並不適用於目前的場景，因為 Movie 的 type 會隨著時間而改變，並不是初始化後就不變的，所以更適合用 `State/Strategy Pattern`  

> State/Strategy Pattern 最大差異在於 State 表達的是狀態的改變，而 Strategy 代表的是計算時的演算法改變，兩者看起來蠻像的，主要在於命名如何表達設計者的意圖

這邊比較適合用 State Pattern，因為 Movie 的 type 比較是一種 state，會持續一段時間而非當下計算完就結束  

這邊第一步先在 price_code= 方法中初始化狀態，先暫時用 case 頂替等等會換掉
[refactor: add state pattern to extract charge logic](https://github.com/sj82516/refactoring-ruby/commit/4e99642cc80c190f48f5f29c9bf7ccf05c208c66)  

#### 5-3. 抽換 frequent_render_points
frequent_render_points 也可以用類似的方式，但注意到只有 New Release 的計算方式不同，這邊可以用 Module 的方式設定預設方法，在 New Release Sub Class 中在複寫  
[refactor: update frequent_renter_points](https://github.com/sj82516/refactoring-ruby/commit/a227f668b68059cc27e6f1acc80ab63e5d7d34aa)

#### 5-4. 移除 price_code=  
最後讓呼叫者將初始化的 price class 傳入，就可以省去 price_code= 中的 case 使用  

導入 State Pattern 花了幾個步驟，主要是在未來增加新的計價模式，舊的 Code 都不會受到影響，只要新增就好，符合 `Open Close 原則`  
[refactor: change Movie initialize](https://github.com/sj82516/refactoring-ruby/commit/d100a3353e16f45017f507190e68c192b93110ad)  

## 結語  
重構有趣的地方在於一步一步調整程式碼到有彈性的方式，所以不用一開始就追求完美的設計，避免了 over design 的問題，因為只要有重構的習慣就不會讓程式碼僵硬到無法維護  

之前工作常常遇到大家會說 Legacy Code 多到無法維護而需要「重寫」，但回過頭來看如果用一樣的邏輯跟開發方式，重寫幾百次最後都面臨同樣的困境，學習重構逐步優化，並調整對於物件導向、設計模式的認知，這才是長久之計
