---
title: "愛用 async await 而非 promise!"
description: 近期看不到少關於 async / await 的好文章，這裡特別摘錄兩篇總結
date: '2018-12-28T01:39:30.852Z'
categories: ['Javascript']
keywords: []

  
---

近期看不到少關於 async / await 的好文章，這裡特別摘錄兩篇總結

[**Asynchronous stack traces: why await beats Promise#then()** ](https://mathiasbynens.be/notes/async-stack-traces)

對比於直接使用 Promise Chain，使用 async / await 除了語法上更加友善，更重要的是 JS Engine 底層有優化，尤其是在 stack trace的時候。

`await X()` 跟 Promise 最大差別在於執行時會直接暫停 function 運作，直到 await 的 promise X結束後才繼續原本的 function；  
至於 promise.then(X) 則是把 X 放上 callback chain上，原 function 就結束了。

這點差異有著重大的改變，請看以下範例

```js
const a = () => {  
 b().then(() => c());  
};
```

function a 執行時，會直接呼叫 function b，而 b().then 則是將 `() => c()` 匿名 function 放上 callback chain，然後 a 就結束了，所以 function a 的 context 也跟著消失；

試想如果此時 b 或 c 拋出錯誤，理論上要除錯我們會希望看到完整的 call stack，但是 a 早就結束拋棄了 context，所以 V8 要額外將 a 的 context 傳給 promise b 跟 function c，這樣出錯才有辦法追本溯源，這些是額外的負擔。

改成 async / await 就不一樣了

```js
const a = async () => {  
 await b();  
 c();  
};
```
當 b 或 c 出錯時，因為還在 function a 的 context所以可以很快速追蹤，不需要額外的成本。

### 小結

很多 ES6語法都是 syntax sugar，但是 async / await 帶了更不一樣的改變，作者給兩點建議

1.  盡量用 async / await
2.  避免不必要的 transpile，透過 `babel-preset-env` 來避免

[**Deploying ES2015+ Code in Production Today**](https://philipwalton.com/articles/deploying-es2015-code-in-production-today/)

延伸剛才的小結第二點，JS Code 如果要跑在瀏覽器上不可避免要用 babel transpile 或是加上各種 polifill，但現在已經是 2018了！  
很多瀏覽器已經良好支援 ES 2015 +，所以 babel transpile 開始變得不是這麼必要，這篇文章深入探討 `如何平衡舊時代 babel transpile的 legacy js 與 modern js`。

這個議題的解法是 `<script type=”module”>` ，如果瀏覽器支援 ESM Module，那他就可以支援 `async / await` 、 `class`、 `arrow function` 、 `fetch` 等等

以下是 can i use 的支援程度分佈

[**Can I use... Support tables for HTML5, CSS3, etc**](https://caniuse.com/#feat=es6-module)

Chrome / Safari / Firefox / Edge 近兩、三個版本都良好支援，IE就算了…..

#### 開發重點

開發時使用 ES 2015+ 語法開發，透過打包工具(webpack 、 gulp等)來呼叫 babel 產生兩份程式碼： main.mjs、 main.es5.js

`.mjs` 是指支援 ES Module 的 js file 副檔名；而另一個就是 transpile 給過時瀏覽器使用的 ES5 語法。

babel config 可以參考作者在內文提供的，主要就是改 target 與 output 檔名
```md
**targets**:{    
   **browsers**:[    
      '> 1%',  
      'last 2 versions',  
      'Firefox ESR',  
   ],  
}
```

```md
**targets**:{    
   **browsers**:[    
      'Chrome >= 60',  
      'Safari >= 10.1',  
      'iOS >= 10.3',  
      'Firefox >= 54',  
      'Edge >= 15',  
   ],  
},
```

在 html page中，引用 js 改成

```html
<!-- Browsers with ES module support load this file. -->
<script type="module" src="main.mjs"></script>  

<!-- Older browsers load this file (and module-supporting -->
<!-- browsers know \*not\* to load this file). -->
<script nomodule src="main.es5.js"></script>
```

舊版瀏覽器看不懂 type=”module” 就會忽略，改成載入另一個 module；  
反之現代瀏覽器就載入 main.mjs。

#### 限制與注意事項

需注意以下幾點事項

1.  如果瀏覽器要使用 .mjs，記得 server response header 要加 `content-type:text/javascript` ，否則無法仔入
2.  ES Module 行為類似於 `<script defer>` ，也就是會等到 document parse 完成才會執行，如果有需要立即執行的需求，就要把 code 拆出來
3.  Module 是跑在 `strict mode` ，所以要語法等支援嚴格模式
4.  Module 行為與一般 script 略有不同，例如變數不會全局污染  
    例如說 `var a = 123` ，在 script 中可以用 window.a 來讀取，但是 Module 不會。
5.  注意 Safari 10 不支援 nomodule，所以要另外裝 polyfill
6.  如果 node_modules 有用到 ES2015+ module，記得 babel config 需要額外處理

### 補更

最近看到的好文章，你真的知道 Babel Transpile 過後的程式碼長怎樣嗎？

[**Avoiding Babel’s Production Bloat**](https://medium.com/@WebReflection/avoiding-babels-production-bloat-d53eea2e1cbf)

這篇文章提了幾個像 class / destructure / generator 等語法如何被 Babel 轉譯成 ES5的語法，整個程式碼的複雜度與體積都驚人的成長；  
如果網站主要在舊型瀏覽器，最好是考慮用舊的語法。

#### 好處

1.  Module Size  
    節省約 50%!
2.  Parse TIme  
    節省約 55%!
