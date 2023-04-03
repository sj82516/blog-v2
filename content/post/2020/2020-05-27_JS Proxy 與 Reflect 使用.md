---
title: 'JS Proxy / Reflect 實戰 - 實作 API 自動 retry 機制'
description: 介紹 ES6 推出的 Proxy 與 Reflect，並分享使用場景 - console log 於正式環境複寫功能與API 自動 retry 機制
date: '2020-05-27T08:21:40.869Z'
categories: ['應用開發', 'Javascript']
keywords: ['JS']
---

之前在閱讀 ES6 相關教學時，有提及 `Proxy` / `Reflect` 這兩個新的內建物件型別，Proxy 主要是作為指定物件的代理，可以改寫、偵聽物件的存取與操作 / Reflect 則是用靜態方法操作物件，完善 Proxy handler 的實作；   
當初有看沒有懂，也想不到應用的場景，直到最近在開發應用程式時，遇到要包裝 API 自動 retry 機制


>針對不同的 API 錯誤集中化處理，可能是單純 retry 或是呼叫其他 API 換新的 token 之類的


如果要每次 api call 時去 catch error 並處理是一件非常頭疼且難以管理的事情，臨機一動想到 `Proxy` 這個好幫手，目前用起來蠻順利的，以下分享 Proxy / Reflect 基本介紹，以及如何應用在 API retry 機制的實作

文章內容大多參考自 [javascript.info: Proxy and Reflect](https://javascript.info/proxy)，個人覺得寫得比 MDN 詳盡且易懂

## Proxy
當我們在調用 Proxy 時，會這樣宣告
```js
var p = new Proxy(target, handler);
```
1. `target`  
要被 Proxy 代理的物件對象，只要是 Object 型態都可以，包含 Array / Function 等，如果不是 Object 宣告時會收到錯誤
```js
Uncaught TypeError: Cannot create proxy with a non-object as target or handler
```
2. `handler`  
選擇要指定觸發的時機，Proxy 會產生所謂的 `trap`，也就是攔截物件操作的方法，如果未定義則直接呼叫原 Target  

在物件的操作上，都會有對應的內部呼叫方法(internal methods)，例如說 `new A()` 代表呼叫了 `A 物件的 [[Contructor]]` 方法，常用的 get / set 如 `a.prop / a.prop = 'hello world'` 則分別呼叫了 `[[Get]] / [[Set]]` 等方法，而 handler 則是對應這些方法產生攔截的定義   

另外有些物件會有內部的儲存資料格式，稱為 internal slot，例如 Map 的內部資料格式是 `[[Mapdata]]` 而不是透過 `[[Get]]/[[Set]]`，這類型就不能透過 Proxy 代理

#### 基本案例 - 改寫 get 設定預設值
我們希望在取得陣列時，遇到超出範圍則回傳預設值 0
```js
let numbers = [0, 1, 2];

numbers = new Proxy(numbers, {
  get(target, prop, receiver) {
    if (prop in target) {
      return target[prop];
    } else {
      return 0; // default value
    }
  }
});

console.log(a[1]) // 1
console.log(a[-1]) // 0
```
在 handler 中定義 get 可以攔截 `[[Get]]` 呼叫，會收到三個參數 target / prop / receiver    
1. target    
目標物件，也就是 number 本身  
2. prop  
呼叫的屬性名稱  
3. receiver:  
`執行 target[prop]` 時的 this 代表值，通常是 Proxy 本身，但如果是有繼承等實作會不太一樣，後續會補充

另外方法呼叫也會觸發 get喔，例如 a.method()

#### 第二個案例 - 改寫 set 統一驗證方式
在寫入表單時，可能會用一個物件暫存用戶的輸入，但此時都需要欄位的驗證，例如手機號碼 / 地址格式等等  
如果要將邏輯散落在每一個輸入後的 function 有點麻煩  

```js
let numbers = [];

numbers = new Proxy(numbers, { // (*)
  set(target, prop, val, receiver) { // to intercept property writing
    if (typeof val == 'number') {
      target[prop] = val;
      return true;
    } else {
      return false;
    }
  }
});

numbers.push(1); // added successfully
numbers.push(2); // added successfully
alert("Length is: " + numbers.length); // 2

numbers.push("test"); // TypeError ('set' on proxy returned false)
```

> set 會收到四個參數，並注意需要回傳 `boolean` 表示 set 是否成功  

其餘像是 construct / getPrototypeOf / ownKeys 等等的方法

#### 實際使用 - 正式環境複寫 console 行為  
在開發時，為了 debug 方便回留下很多 console 呼叫的方法，但如果上到正式機忘記關閉就會很尷尬；  
同時像 error / warning 會需要用其他的方式送回 server 紀錄錯誤 log，避免正式機除錯不易，此時用 Proxy 去包 console 就是一個蠻方便的做法   

```js
window.console = new Proxy(window.console, {
    get: function(target, prop, receive){
        if(prop === 'log' || prop === 'debug'){
            alert("你看不見我");
            return ()=>{};
        }
        return target[prop]
    }
})

console.log() // 彈出 alert
console.error("123") // 照常顯示
```

當然也可以自定義 Log Class 達到一樣的效果，但會覺得用 console.log 是個很直覺的做法，如果能用 Proxy 去改寫達到一樣的效果比較方便 (懶

#### receiver 應用
剛才提到 get 第三個參數 receiver 指的是函式執行 this 所代表的物件
```js
let user = {
  _name: "Guest",
  get name() {
    return this._name;
  }
};

let userProxy = new Proxy(user, {
  get(target, prop, receiver) {
    if(prop === Symbol.iterator || prop === Symbol.toStringTag || prop === Symbol.for('nodejs.util.inspect.custom')){
	return;
    }
    console.log({
      target, prop, receiver
    })
    return target[prop]; // (*) target = user
  }
});

let admin = {
  __proto__: userProxy,
  _name: "Admin"
};

console.log(userProxy.name) // outputs: Guest
console.log(admin.name);// Expected: Admin but outputs: Guest (?!?)
```
宣告一個 user 物件，並用 userProxy 代理，最後 admin 用 `__proto__` 方式繼承 userProxy，透過 userProxy get 可以看出 `target 都指向 user`，但是 receiver 就不一樣，兩者都指向呼叫的自身 (Proxy / Admin)  
但因為最後執行是透過 `target[prop]`，所以 this 指向的都是 user  

如果希望 admin.name 最後印出 "Admin"，也就是需要讓執行時 this 指向 admin，就需要 Reflect 協助

> 記得要避免在 proxy handler get 中直接呼叫 receiver[prop]，因為會不斷透過 [[GET]] -> Proxy get -> [[GET]] -> Proxy get 輪迴  

> 這一段是用 node.js 執行，需加入 if condition 避免不斷的遞迴呼叫，因為在 console.log 時會主動去 iterate 物件並呼叫 toString，這些也會觸發 [[GET]]

## Reflect
Reflect 是 ES6 新增的類別，不能透過 new 建構新的 instance，只能呼叫靜態方法，主要是針對物件操作的方法，例如
```js
const a = {b: 123}
a.b // 123
Reflect.get(a, "b") // 123


const object1 = {
  property1: 42
};

delete object1.property1
Reflect.deleteProperty(object1, 'property1');
```
基本上都有一對一的方法可以調用

剛才提到，getter 時第三個參數 receiver 可以變成 target 呼叫時的 this 指向，例如
```js
let a = {c: 123, get d(){ console.log(this); return this.c}}
let b = {c: 456}

Reflect.get(a, "d") // 123
Reflect.get(a, "d", b) // 456
```

所以當我們希望指定 getter 實際操作的物件，可以用 `Reflect.get 去取代 target[propd]`，這是一種最安全的做法，結合 function call 用以下方式最為保險
```js
new Proxy(user, {
  get(target, prop, receiver) {
    let value = Reflect.get(...arguments);
    return typeof value == 'function' ? value.bind(target) : value;
  }
});
```

在某些時候，用 Reflect.get 可以避免不預期錯誤，例如說 `Map`，Map 在讀寫參數時是透過 `this.[[MapData]]` 而不是 `this.[[Get]]/this.[[Set]]`，所以如果沒有指定 receiver 則預設 this 指向 Proxy 就會拋出錯誤，要改用 Reflect.get 將 this 替換成 Map 本身才不會有問題

```js
let map = new Map();

let proxy = new Proxy(map, {});

proxy.get('test');  // 錯誤: Uncaught TypeError: Method Map.prototype.get called on incompatible receiver

/// 正確方法
let map = new Map();

let proxy = new Proxy(map, {
  get(target, prop, receiver) {
    let value = Reflect.get(...arguments);
    return typeof value == 'function' ? value.bind(target) : value;
  }
});

proxy.get('test')
```

#### API retry 機制
個人還是蠻喜歡用 axios 的而不是用原生的 fetch，可能是因為 axios 更像一個物件，可以透過 create 創建 instance 蠻方便的

接著用 Proxy 代理 function 的呼叫，並回傳一個 async function，在裡頭就能自定義錯誤處理機制，例如說收到 403 就去換新的 token 之類的
```js
const APIInstace =  axios.create({
    baseURL: 'https://httpstat.us'
})

const APIProxy = new Proxy(APIInstace, {
    get(target, prop, receiver){
        let fn = Reflect.get(...arguments);
        return async function(){
            try{
                const result = await fn(...arguments);
                return result;
            }catch(error){
                if(error?.response?.status === 403){
                      const result = await APIInstace.get("https://www.mocky.io/v2/5ed11b963500005b00ffa29a");
                      return result;
                }
                
                throw "OhNo"
            }
        }
    }
})

console.log(await APIProxy.get("/403")); // 沒有錯誤
await APIProxy.get("/404"); // 拋出 OhNo 錯誤
```