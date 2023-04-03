---
title: 《How Javascript Works》讀後整理 上
description: >-
    Douglas 思考著 The Next Language 下一代的程式語言該具備的樣貌，延伸前作 《JavaScript- The Good Parts》，Douglas 頗析 JS的每一個環節，先解構 JS現有的存在，再重構出一門他覺得最接近下個世代程式語言的雛形
date: '2019-10-02T00:21:40.869Z'
categories: ['Javascript']
keywords: ['javascript', 'book review']
---

{{<youtube 8oGCyfautKo>}}

當初在 Youtube 看到 Douglas 為書籍做導讀的影片，重新介紹每個 JS 日常開發的部分，從型別開始 Number / Date / Function / Object / String / Array / Ｄㄍ；
延伸到 Promise / Exception / Generator / Async & Await；
最後寫一個自創的語言 Neo 解釋 Transpiler 的工作，Tokenizing / Parsing / Runtimes；

Javascript 是個神奇且矛盾的存在，它有許多錯誤與不好的設計，但避開這些坑他又是一門具備彈性、受到廣大熱愛的程式語言，再我讀來，Douglas 試著從前作《JavaScript: The Good Parts》描述如何避開 JS的坑擁抱正確的 JS編寫技巧，到這本《How JavaScript Works》，重新帶讀者認識 JS、如何讓 JS 變得更好 -> 如何寫出更好 JS Code，並試著傳遞出自己的`強烈`價值觀
> 下個世代程式語言的樣貌

是的，這本書雷同於前作，都表達了 Douglas 對於 JS 編程技藝的審美觀與價值觀，所以內容有些可能會與主流價值觀衝突，孰是孰非就見仁見智了；
但這本書帶給我的衝擊是`如何去思考一門程式語言的設計`，以往都在思考如何寫出更好的語法跟演算法，從沒想過程式語言的本身也是工具，自然就有被討論與改進的空間，跟個 Douglas 的腳步去思索，覺得是個蠻棒的思想試煉，這或許才是這本書最有價值的地方!
> 那你心中的程式語言又是怎樣的樣貌呢？

這本書適合對 JS 有一定認識的開發者，如果是新手就不建議閱讀。

## 前言
一般的工具書在前言通常是講一些 Terminology 、寫作緣由、適合誰閱讀等，這本書也不例外，但有趣的是 Douglas 補充了他對某些英文單字頗有微詞，例如說
`one`，這個單字開頭是 O，但也很像是 0，但其實他表達的是 1，而且發音 /wʌn/，文字外在意象跟實質意義不吻合，且與發音也不一樣，對 Douglas 來說這是個非常差的設計，所以他主張要改成 `wun`，而整本書的 one 都用 wun 取代，包含 wunce；
另一個單字 `through`，這個字有一半的字母沒有發音，所以他省略為 `thru`。

坦白說，一開始看到覺得有點無聊，想說這是沒事找碴的概念嗎 XD
但看完整本書後，覺得自己果然道行太淺，Douglas 想表達的是
> 正確命名就是寫好程式的第一步，不留給自己任何思維上的模糊地帶

任何有模糊解釋空間的地方，就會有誤解跟錯誤的產生，所以從源頭的命名開始就杜絕這種壞習慣，才是根本寫好程式的方法！
這樣的精神貫穿整本書籍，用最挑剔的方式重新檢視 JS 的語法與實作設計。

### How Names Work
在命名上，Douglas 認為程式語言應該要支援` `當作變數名稱的合法字元，但目前 JS 是不行的，所以他建議用小寫字母開頭並用 `_` 蛇行命名法切割多個單字的變數名稱；
至於 `$`、`_` 開頭則避免使用，這些應該被保留當作 code generator 、macro processor 使用。

在 JS 中，一大令人困惑的地方是 function 跟 constructor 無法區分，如果 function 用 `new` 呼叫就變成 constructor，所以 Douglas 建議 contructor 用大寫開頭作為區分，但可以的話連 `new` 都不要用，後續會在補充做法。

### How Numbers Work
這也是 JS 很常被詬病的誤解 0.1 + 0.2 !== 0.3，但其實 JS 是參照 IEEE 754 其中的雙精度浮點數規範，其餘如 Java 等採用同樣的規範也都會有一樣的問題，畢竟用有限的 bits 怎麼可能對應到無窮的有理數呢，所以在精度上的缺陷才會導致這樣的結果。

```md
要小心切換儲存的數值與實際表示的數字，這兩者會有數學公式的對應關係，但文字上容易產生誤解
```

JS 只支援單一種的數字型別就是 Number，這是個良好的設計，因為不需要涉及數字型別的轉換，例如 int 轉 float 或 double 等，在現在機器記憶體非常充足的情況下，程式語言以開發者友善的方式設計會比較適合

Number 以 64 bits 儲存，拆分成3個部分儲存，significand 是介於 0.5 ~ 1.0 的數值
> sign(1) + exponent(11) + significand(52)
轉成數值代表
> (-1) ^ sign * 1.significand * 2^(exponent - 0x3ff)

sign 是一個位元表示正負；
exponent 則是用 11個位元表示 2的次方倍，為了表示正區間到負區間所以預定有偏差值 (bias value 0x3ff)，也就是 exponent 0x000 代表的其實是 (-1 * 0x3ff)；
significand 用剩餘 52 bit 表示，但因為浮點數表示表達為 1.X * 2^n 次方，因為`1`固定會存在，所以就可以記在記憶體中，算是額外的 bonus bit，所以最大數值表示可以到 2^53 次方

幾個常見的數字對應 binary 表示
```md
-0: 8000 0000 0000 0000
+0: 8000 0000 0000 0000
1：3ff0 0000 0000 0000 => 2 ^ (0x3ff - 0x3ff) * 2^53 (別忘了 bonus bit) = 1
最大數： 7fef ffff ffff ffff => (2^54 -1) * 2^971 = 2 ^ (0x7fe - 0x3ff) * (2^54 - 1)

特殊字
無限大：0x7ff0 0000 0000 0000
NaN：0x7ff + 後面出現任意非0的bits，這也是為什麼 NaN !== NaN
```

須謹記只有在 Number.MAX_SAFE_INTEGER 到 Number.MIN_SAFE_INTEGER 之中的整數才是 1:1 mapping，也就是一個數字對應到一個真實的數值，在這個區間才保證數學運算的正確性，超過範圍的數值會喪失部分精準性，例如
```js
Number.MAX_SAFE_INTEGER + 1 === Number.MAX_SAFE_INTEGER + 2 // true
```

如果要檢查數字，請用 Number.{method}，例如 Number.isNaN、Number.isSafeInteger 等

### How Big Integers/Floating Point/Rationals Works
受限於 Number的精度，如果像銀行系統等不容許半點失真的數學運算，就必須自己額外處理，這部分 Douglas 分別寫了 Big Integers / Floating Point / Rationals 的處理，Rationals 是指用兩個 Big Integer 相除表示的數值，可以更精確表示某些 Floating Point，詳細可以看原始碼 [howjavascriptworks](https://github.com/douglascrockford/howjavascriptworks)，書中這三節都是拆解程式碼講解，但是排版看起來有點麻煩，不如螢幕拖拉看來得方便。

這邊 Douglas 拋出一個討論，他覺得大數運算不應該放進程式語言的原生支援，而是讓需要的用戶自行去採用 Library，JS 生態圈已經有良好現行的解法了，因為程式語言應該維持小而美，提供最核心的支援，其餘的應該是開放讓用戶自行選擇

但 [BigInt](https://developer.mozilla.org/zh-TW/docs/Web/JavaScript/Reference/Global_Objects/BigInt) 已經在 Firefox/Chrome 試行了 XD
我自己也是偏向 Douglas 的想法，為了少部分用戶，而讓 JS 從原本只有 Number 多加一個數字型別，覺得沒有這麼強烈的必要


### How Booleans Work
JS 支援 Boolean 型別，也就是 `typeof true / typeof false` 會回傳 `boolean`，但在條件表達式(if/for/&&/||等)中，JS 支援 boolish，也就是將其他型別轉換成 boolean 型別，尤其是一些彆扭的 falsy 值，例如 0 / "" / undefined / null / NaN等

良好的習慣是在條件表達式中只要 Boolean，而且判斷式用 `===` 而非 `==`

### How Array/Object Work
Array 是用來表達一個連續的記憶體區間，並以某 size 切分成若干等份的集合，Array 在 JS 中只是一個特殊的 Object，所以 `typeof array === 'object'`，要確實判斷是否為陣列請用 `Array.isArray` 

原生的 Array 提供很多方法，但要注意 sort/reverse 是 in place 發生，也就是他是改變原Array，理論上這兩個應該要是 pure function 才是，但可惜 ECMAScript 並沒有規範

關於 Object 可以利用 Object Literal 方式創建，Key 要採用 String，Value 可以其他型別包含 function等
```js
let my_obj = {
    ...
}
```
另外 Douglas 不建議在 Object 中儲存 undefined，因為這樣無法區分到底是 Object 不存在這個 Key 還是 Key存在但儲存 undefined

因為 JS 沒有繼承的概念，或是說透過 Prototype Chain 模擬繼承的方式，在使用上 Douglas 建議用 `let new_object = Object.create(null)`，因為 `null` 沒有 prototype，所以創建的新物件沒有多餘的 prototype 需要考量，整體上比較乾淨，運行上也比較有效率；
最好是再加上 `Object.freeze`，讓其他操作者無法任意更動 Object 屬性

Weakmap 有點類似於 Object，但好處是可以用拿 Object reference 當作 Key，如果有人要操作屬性就必須有 key 跟 weakmap，如

```js
function sealer_factory(){
    const weakmap = new WeakMap();
    return {
        sealer(object){
            const box = Object.freeze(Object.create(null));
            weakmap.set(box, object);
            return box;
        },
        unsealer(box){
            return weakmap.get(box);
        }
    }
}
```

可以將物件封裝載 weakmap 中，並回傳 Key Object reference box，只有拿 weakmap 跟 box 才能拿到當初封裝的東西。

### How Strings Work
String 在 JS 中是以 Immutable 的連續 16 bit 陣列，可以透過 String.fromCharCode 生成 String，數值範圍從 0 ~ 65535；
可以用 Array 的方法去操作 String，例如 my_string.indexOf(), my_string[0] 等

但世界語言何其多種，需要表示的字遠遠不止 65536 種，Unicode 編碼模式也因此而誕生，目前總共規範了U+0000到U+10FFFF(20bits)，共有1,112,064個碼位（code point），碼位代表儲存的位元表示方式，其一對一表示一個人類閱讀的字元；
接著以 65,536 為單位，將 1,112,064 切割成 16個平面，每個平面含 65536 個碼位；
其中第 0 碼位稱為 BMP，也就是基礎多語言平面，其他稱為輔助平面。

UTF-16 代表用 16bits 當作儲存的最小單位，為了要支援全部的 Unicode 語言平面，UTF-16改採用 2個單位來儲存一個碼位，將 20bits 切割上下兩個 10bits，高位元加上 0xD8，低位元加上 0xDC 組合

```md
U+1F4A9 => 0001 1111 0100 1010 0111
-----
前10位元： 0001 1111 01
後10位元： 00 1010 0111
-----
補足 16 bits 並加上對應的預設值
0001 1111 01 => 0000 0000 0111 1101 + 0xD8 = 0xD83D
00 1010 0111 => 0000 0000 1010 0111 + 0xDC = 0xDCA9
```

所以 U+1F4A9 在 UTF-16 儲存方式為 `0xD83D 0xDCA9`
UTF-16 只是 Unicode 實際儲存方式的一種實作，包含常見的 UTF-8 也是指實作方式

在 JS 中，要表達 Unicode 可以用
```js
"\uD83D\uDCA9" === "\u{1F4A9}"

//或是

String.formCharCode(55357, 56489) === String.fromCharCode(128169)
```

### How Generators Work
Douglas 認為 Generator 是個好東西，但是 JS 實作的太糟了，他認為原本的 JS 就可以用 Closure 實作 Generator，使用上用原本的 Function 表達可以更清楚；
而 JS 後來導入的 Generator 在命名上、用戶操作上都不慎理想，可以從言語中看出的他不屑與憤怒 XD 

這是我少數完全認同的章節，直接看程式碼比較快
以下是 JS 標準的 Generator
```js
function* counter(){
    let count = 0;
    while(true){
        count += 1;
        yield count;
    }
}

const gen = counter();
gen.next().value;
gen.next().value;
gen.next().value;
```

以下是 Douglas 認為不用 standard 編寫的 Generator
```js
function counter(){
    let count = 0;
    return function counter_generator(){
        count += 1;
        return count;
    }
}

const gen = counter();
gen()
gen()
gen()
```

從幾個地方去看出為什麼 Standard Generator 是糟糕的語言設計
1. 彆扭的命名
    在 JS 中，function 是 first class citizen，大家也都非常熟悉於 High order function，將 function 當作參數或回傳值使用；
    今天 Standard Generator 是在 function 後加入 `*` 標記，但其行為又跟 function 不同，例如 function 是用 return 回傳值，但是 Generator 是用 yeild
2. 偏向 OOP 設計而非 FP 
    當然要走 FP 或 OOP 比較像是個人偏好，但依據 Standard Generator，使用上必須宣告 while(true) 並搭配 yeild 實作，Douglas 認為應該要盡量減少 Loop 的使用
3. 回傳值的操作
   用 Standard Generator 初始化後，要呼叫下一個值必須用 `gen.next().value`
   回到類似第一點的設計錯誤，一個 Generator Function 沒有顯示 return 的值，居然是以一個物件的形式，呼叫其 next function，而且還要加上 .value，這表達的方式實在是很怪異，遠遠不如 `gen()` 來得直接明瞭。

Standard Generator 被批評的很徹底，但確實 Douglas 講得也很有道理，如果有人看過資料或有不同的意見，歡迎交流～ 我也很好奇其他人或是當初語言標準制定時是如何評量的

接著 Douglas 分享他一套 Generator 的組合技，還蠻厲害的，有興趣可以去書店翻閱，這部分程式碼沒有被放到 Github 上。

### How Exceptions Work
Exception 比較偏向指意外，但是在一般的系統設計常常會把錯誤( Error )與意外混為一談，例如說查詢檔案時如果檔案不存在，這應該是可以被預期的錯誤，應該要一般的流程處理，但我們還是會用 try catch 來傳遞這樣可被預期的錯誤

在 JS 中，錯誤拋出使用 `throw`，throw 可以搭配各種型別的值，使用上最簡單就用 String，有Error Object 但沒有太強使用的必要；
在 Compile 過程中，每個 function 都有一個 catchmap，如果發生錯誤，會依序從呼叫的 function 開始找 catch 機制，如果沒有則持續往上找 caller

使用 try catch 會有個安全風險是假使使用兩個外部的 module A/B，A 有網路存取的功能，而 B 用於內部的加解密運算，假使某天我們在調用是用 B 解密後再將值傳給 A 走網路傳輸，假使B 拋出錯誤 `throw private_key` 而 A 有註冊 catch 意外捕獲這個錯誤，那就會有資安疑慮的風險了

