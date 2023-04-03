---
title: 'Sketch Data Structure - Bloom Filter 介紹與實作'
description: 犧牲部分準確性，Bloom Filter 用少量的記憶體與 O(1) 的查詢時間回答「某值是否曾經出現過」的問題
date: '2020-11-17T08:21:40.869Z'
categories: ['Algorithm']
---

在系統設計中，我們常常需要檢視某一個值是否出現過，例如遊戲中用戶 ID 是否已經註冊過等等，如果把每個 ID 都存成一張表每次去檢視，會需要很大量的記憶體 ( ID 大小 * ID 數量)，如果是像 Google 這類有上億的用戶，光是帳號重複檢查可能就需要 1,20 GB 的記憶體空間；  

以下將介紹，Bloom Filter 為什麼可以犧牲一點準確性就能節省大量的空間 

## 原理
Bloom Filter 原理其實很簡單，產生一個陣列，用 bit 代表該元素是否出現過，透過 Hash function 將輸入專換成陣列位置，藉此標記與查詢是否元素出現過  

因為 Hash 會有碰撞問題，所以會有 `False Positive 但不會有 False Negative `
> 意即 Bloom Filter 回答元素已存在但實際上沒有存在， Bloom Filter 回答不存在則一定不存在  

原理很好懂，但複雜的是`陣列要多大? 要選幾種 Hash` 才能平衡記憶體用量以及避免 False Positive 的錯，這一個部落格用數學證明 [Bloom Filters - the math](http://pages.cs.wisc.edu/~cao/papers/summary-cache/node8.html)   

1. 假設我們決定用一個長度為 m 的陣列，陣列的元素是一個 bit 表示該鍵值已出現過
2. 當今天增加鍵值時，經過 Hash 會隨機分配陣列中的一個位置給該鍵值，換句話說陣列的某個位置被插入的可能性是 `1/m` 
3. 今天假設插入了一個鍵值，那第二個鍵值與第一個鍵值碰撞的機率是 `1/m` (好死不死分配到同一個陣列)，也就代表不會碰撞的機率是 `1 - 1/m`
4. 今天假設插入了兩個鍵值，那第三個鍵值不會碰撞的機率是 `(1 - 1/m)^2`，如果插入了 n 個鍵值，那第 n + 1 個不會碰撞的機率是 `(1 - 1/m)^n`

以上是 Hash 數量為 1 的情況，接下來考量獨立 Hash 為 k 的情況  
1. 因為 Hash 數量為 k ，所以每一輪陣列會有至多 k 個位置被標記成 1，需注意 Hash 之間也可能標記到同一個位置，所以在機率上是獨立事件，所以是某位置在插入後不會被選中的機率是 `(1-1/m)^k`，也就是每次 Hash 後的值都沒有選到他  
2. 所以插入 n 個鍵值後，第 n + 1 個不會產生碰撞的機率是 `(1-1/m)^(k*n)`   
3. 換算一下，會產生 False Positive 的機率是 `(1 - (1-1/m)^(k*n))^k`，也就是第 n + 1 個鍵值與任一一次 Hash 後產生碰撞的機率，簡化後可以變成 `(1 - e ^ (-k*n/m))^k`  

從這個公式可以看出
> `m 越大，False Positive 的機率就越小`，這也蠻直觀的，因為 Hash 後產生的碰撞機率自然就變小；  
但是 k 的值就比較沒這麼直觀，不是越大越好，也不是越小越好，而是在 m,n 在對應的比例下，會有一個最剛好的值   

我們可以用 [Bloom Filter Calculator](https://hur.st/bloomfilter/) 手動調整參數，去評估預期的 False Positive 機率與所需要耗費的記憶體空間 (m 的大小)  

基本上，如果 m 是 n 的 10 倍，在選擇 4 個 Hash function 下 False Positive 機率約為 1.2 %，如果選擇 5 個 Hash function 則機率降為 0.9 %    

一開始在思考時，會想說明明增加 Hash function 的數量應該會增加碰撞機率才對，後來才想到前提是 `m >> n` 的時候，有足夠的多餘空間讓多個 Hash function 的整體碰撞機率更小

### 變形 - 增刪鍵值
如果今天要刪除鍵值時順便更新 Bloom Filter，就不能用 boolean 儲存，而是要用 unsigned integer，增加時 + 1 移除時 - 1，那 integer 需要 4 bit / 8 bit 還是多少個 bit 才足夠呢 ?!  

同一篇部落格文中，同樣有數學推導，但因為不太了解就先略過，最後的結論如果 Hash function 足夠隨機的話 4 bit 應該已經足夠，但需要小心如果非常非常不幸 4 個 bit 不夠儲存，會產生 `False Negative`，也就是 Bloom Filter 回答不再但實際上還是存在的狀況

## 實作
實作部分，可以拆成兩個步驟
1. 如何產生 k 個獨立的 Hash Function
2. 實作插入與查詢的 bitwise 操作

### 如何產生 k 個獨立的 Hash Function  
如何產生一個運算快速、足夠隨機且 Universal 的 Hash function 是非常關鍵的一步，影響後續的錯誤率，選擇用 non-cryptographic hash function 即可，強度不高但是性能夠好，差別在於 hash 後被逆推的可能性(沒有強抗碰撞與弱抗碰撞的保證)，可能會遭遇 HashDos，被發現碰撞後就不斷嘗試導致性能變差  

回歸正題，爬了一些 Bloom Filter 的實作，有發現使用 xxHash、MurMurHash 等已知的 hash function library，這一個實作蠻有趣 [bloomfilter.js](https://github.com/jasondavies/bloomfilter.js)，Hash function 是實作 [Fowler–Noll–Vo(FNV) hash function](http://isthe.com/chongo/tech/comp/fnv/)，程式碼如下
```js
  function fnv_1a(v, seed) {
    var a = 2166136261 ^ (seed || 0);
    for (var i = 0, n = v.length; i < n; ++i) {
      var c = v.charCodeAt(i),
          d = c & 0xff00;
      if (d) a = fnv_multiply(a ^ d >> 8);
      a = fnv_multiply(a ^ c & 0xff);
    }
    return fnv_mix(a);
  }

  // a * 16777619 mod 2**32
  function fnv_multiply(a) {
    return a + (a << 1) + (a << 4) + (a << 7) + (a << 8) + (a << 24);
  }

  // See https://web.archive.org/web/20131019013225/http://home.comcast.net/~bretm/hash/6.html
  function fnv_mix(a) {
    a += a << 13;
    a ^= a >>> 7;
    a += a << 3;
    a ^= a >>> 17;
    a += a << 5;
    return a & 0xffffffff;
  }
```
在 Stack Exchange 看到有趣的問答 [Which hashing algorithm is best for uniqueness and speed?](https://softwareengineering.stackexchange.com/questions/49550/which-hashing-algorithm-is-best-for-uniqueness-and-speed)，有強者比較多種 Hash Function 的效能以及碰撞機率，FNV-1a 表現還不錯，但作者比較推薦 Murmur2  

接著，有另一篇論文 [Building a Better Bloom Filter](https://www.eecs.harvard.edu/~michaelm/postscripts/tr-02-05.pdf) 證明如果要產生多個 Hash function 應用在 Bloom filter 上，只需要產生兩個 Hash function 再加上係數的組合出其他的 Hash function 即可
```js
gi(x) = h1(x)+ ih2(x) mod p // p 是質數
```

## 總結
如果原本的鍵值很長，再容忍一定的 False Positive 下使用 Bloom Filter 可以節省非常大量的儲存空間，但需注意 Hash 運算會多一些 CPU 資源