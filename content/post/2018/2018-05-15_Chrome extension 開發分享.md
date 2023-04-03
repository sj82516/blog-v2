---
title: Chrome extension 開發分享
description: >-
  基本的 Chrome 插件開發分享，擴充網頁滑鼠控制的功能
date: '2018-05-15T09:56:14.414Z'
categories: ['應用開發']
keywords: []
---

昨天在 Android 手機上用 Youtube 分享影片到 LINE 聊天室給朋友，突然靈機一動覺得 APP 有這麼方便的分享機制，那我是不是可以在 Chrome 用 Extension 方式整合社群分享，按一個按鈕就可以把當前頁面的連結或文字快速分享；  
正好之前也沒有開發過 Chrome extension，正好拿來練練技術，但果不其然在 Chrome extension shop 有看到很大量的社交分享工具了 OTZ   
但還是不死心想要自己動手玩玩看

參考資料：

Chrome team 本身的官方教學還不賴

[**Getting Started Tutorial — Google Chrome**](https://developer.chrome.com/extensions/getstarted)

強者 [羅拉拉](https://ithelp.ithome.com.tw/users/20079450/ironman)在 2016 年 IThome 鐵人賽的系列文，前半段把官方教學翻譯，後續加上作者個人開發分享，非常棒的教學。

[**Chrome Extension 開發與實作 系列文章列表  — iT 邦幫忙::一起幫忙解決難題，拯救 IT 人的一天** ](https://ithelp.ithome.com.tw/users/20079450/ironman/1149)

以下為個人開發簡略與簡化過後的筆記，所以要看詳細版還是看上附兩個文件

## 基本介紹

基本上開發 Chrome extension 跟寫網頁很類似，只是改了檔案結構、發布機制、API 調用多增加了 chrome.\* 函式

在 extension 開發中，目錄下必須先宣告 manifest.json，裡頭會註明 extension 的名稱/icon/所需權限等資料，還有不同時機對應執行的不同腳本

基本上開發會有幾個頁面可以選擇

1.  background page 背景頁面：  
    基本上是常駐，從安裝插件之後就一直執行到插件被移除(不完全正確的描述，但基本上可以這樣理解)  
    所以會在 background 指定的 script 中執行套件安裝或更新，又或是初始化的一些程序
2.  popup page 彈出頁面：  
    也就是右上角的小圖標，點擊後產生的頁面，又細分成 browser-action / page-action；  
    browser-action 代表 Extesion 是普遍性在每個網站都可以用，而 page-action 則代表只針對某些特定網站使用，平常會自動呈現灰暗的 icon 直到顯示宣告 pageAction.show()，像是 vue-devtool 只有在網站使用 vue.js 才能使用。
3.  option page 選項頁面：  
    應用程式如果太過於複雜，希望有個選項頁可以供客戶客製化行為，可以採用
4.  content script：  
    在 Extension 中，只要有索取權限就可以對每個頁面注入 content script，進行 DOM 操作等一般 js script 會執行的動作，可以看成合法的 XSS 注入。

## 實戰分享

[**sj82516/quick-share**](https://github.com/sj82516/quick-share)

### 定義與載入其他 script

可以參考 manifest.json，這裡我用了  
background：event.js，主要註冊與定義右鍵按下出現的選單行為  
popup page：分成 popup.html / popup.js，主要是定義瀏覽器右上角的工具列跳出視窗行為，並定義為 browser-action

因為右鍵行為跟 popup 行為類似，所以我將行為收整成 util/handleShare.js，需注意在 background 中要使用其他 script 必須宣告在 manifest.json 中；

```json
"background": {
    "scripts": ["util/handleShare.js", "event.js"],
    "persistent": true
}
```

而在 popup page 則以 `<script src="util/handleShare">`加入 html 中即可。

### 另開新頁、Popup script 與 Content script 溝通

社群媒體分享必須另開該網站的新頁面，同時為了可以自動把反白選取的文字自動插入，在開啟新頁，首先要設法取得新頁面的 Tab，之後要執行 content script

```js
// 先取得所有的分頁資料，可以透過 tab 的 url / title 找到指定頁面
chrome.tabs.query({
  active: true
}, function(tabs){})

// 必須確保分頁已經加載完成，這樣 content script 才有用
chrome.tabs.onUpdated.addListener(function (tabId, info) {
 if (tabId == factoryTab.id && info.status == 'complete') {
 // 在該分頁注入 content script
 chrome.tabs.executeScript(factoryTab.id, {
 file: "content/share.js"
 })
 ....
```

上面有個小 tricky 是必須要等到新分頁加載完成才可以執行 `chrome.tabs.executeScript` ，否則會出現 tab is closed 之類的錯誤訊息!

在跨 script 傳輸資料一次性可以使用`sendMessage(tabId, message)`/ `chrome.runtime.onMessage.addListener((message, sender, sendResponse)=>{})`   
其餘方式可以在查詢文件。

### 結語

開發一個簡單的 Chrome Extension 蠻有趣的，但也意外發現 Extension 的威力極為強大，尤其是可以注入 content script 這塊，所以搜尋一下 chrome store 可以找到例如密碼管理工具等應用，突然覺得一陣害怕因為整個 DOM 都被摸光了，甚至 cookie 再不小心授權出去後也都可以被讀取，在安裝插件上務必小心啊！ 尤其是沒有開源、非官方的插件更需要小心。

不過我上傳的插件被 Google 認定為 Spam 不給上架……
