---
title: Google Sheet API 與Google OAuth2 API授權研究
description: >-
  Google 提供可以大量用 API介接的服務，本篇整理 Google 常用的幾種 API授權，與 Google Sheet API 如何使用
date: '2018-06-01T13:03:55.867Z'
categories: ['應用開發']
keywords: []
---

最近有個需求是希望可以將各網站的退款紀錄同步到Google Sheet上，方便PM與財務部門追蹤，相比於自建網站，Google Sheet 有方便的同步編輯 / 匯出匯入 / 登入權限管理等，就不必自己重造輪子，而且也不見得造得出來(汗

整篇分成兩部分，第一是研究Google OAuth2 API授權部分，第二是Google Sheet API。

## Google OAuth2 API授權

[Google API授權](https://developers.google.com/identity/protocols/OAuth2)有兩種方式

1.  **OAuth 2.0：**  
    如果是涉及用戶隱私資料，就必須走OAuth 2.0授權方式取得用戶授權；  
    例如說 Drive / Sheet / Doc / Google+ … 等等。
2.  **API keys：**  
    如果是單純使用Google提供的對外服務，例如 Map / URL Shortener / Geocoding 等。  
    API Keys使用蠻簡單的，也不是這次使用重點，就不另外贅述。

這次要使用 Sheet API 就需走 OAuth 2.0授權，Google 支援多種[OAuth 2.0 授權方式](https://developers.google.com/identity/protocols/OAuth2)：

### Server-Side Web App

APP主動觸發，讓用戶登入Google帳號並授權，接著透過 redirect 或其他方式取得code，最後用code去換token。  
這也是對終端用戶最為常見的授權方式。

![From Google](/posts/img/0__kYLCVa75Nl6Fb3dt.png)
From Google

### Applications on limited-input devices

適用於在沒有螢幕或是輸入的裝置，例如列印機、TV等嵌入式裝置

![From Google](/posts/img/0__ueo8fqWlyUkudIPy.png)
From Google

這裡同樣是 App主動觸發，但變成回傳一個URL連結，用戶必須另外找支援瀏覽器裝置輸入URL並授權；  
這裡因為 App(ex. TV)跟用戶授權的裝置(ex. 手機)不同，兩者辨識用戶方式透過 device code(“code” & URL -> User)，App透過polling不斷間隔請求Google才能知道該 device code 的用戶是否已經授權，後續流程就相同。

但須注意此流程授權的權限不多，需要先評估，因為我專案需要 Sheet API授權，這個授權流程就不支援，所以無法採用。

### Server-to-Server

![From Google](/posts/img/0__013W__2kCyhYRycgb.png)
From Google

在Google APIs Console中的憑證欄位，除了API金鑰 / OAuth 2.0 用戶端 ID ，第三個能夠創建的就是 `服務帳戶金鑰`，服務帳號像是創建一個新的用戶，只是此用戶是被用於 Server 端授權，並透過 IAM 管理權限。

透過服務帳號最大好處是應用程式是授權於服務帳號，而非個體用戶，像是遇到人員流動就不需要手動在管理授權；  
而且也不需要在 Client又要跳出用戶授權頁面，非常適合用於對內的專案開發(此流程又稱為 two-legged OAuth)。

也是我們這次會嘗試的流程之一。

### Long Live Token

授權後Google會回傳token，但token都是短期的只有一小時的壽命，Google並不像FB，`不會核發長期無限期的Token` ，反之Google是不斷的透過 refresh token機制，不斷的核發短期Token，而refresh次數是沒有限制，也不需要用戶再次授權，所以可以長期儲存起來使用。

但必須注意，如果發生以下幾點 refresh token機制會失效  
1\. 用戶取消對應用程式的授權  
2\. refresh token超過6個月沒有使用  
3\. 用戶更改帳號密碼且refresh token含Gmail的權限  
4\. 用戶擁有太多refresh token，目前是每個應用程式每用戶上限50個refresh token。  
5\. 用戶本身也存在著refresh token總數上限，但文件只寫到正常狀況不會發生，沒有明講多少。

### 實作

這一步主要是先取得 access token與 refresh token。

[**Node.js Quickstart | Sheets API | Google Developers**](https://developers.google.com/sheets/api/quickstart/nodejs?authuser=1&hl=zh-cn)

Google Sheet API有個 Node.js 快速上手說明，並用 [google-api-nodejs-client](https://github.com/google/google-api-nodejs-client)，運行後會在終端機出現授權URL，點擊後就可以取得token。

但我個人不愛[google-api-nodejs-client](https://github.com/google/google-api-nodejs-client) 的寫法，因為是採用層層 Callback的方式，還不如自己接REST API來得清爽。

scope部分需要取得 `[https://www.googleapis.com/auth/drive](https://www.googleapis.com/auth/drive) [https://www.googleapis.com/auth/spreadsheets](https://www.googleapis.com/auth/spreadsheets)`

### OAuth 2.0 for Web Server Applications 取得授權方式

這個做法會透過瀏覽器取得用戶授權，並儲存 refresh_token，方便後續Server呼叫API使用。

需注意Google OAuth2登入文件並沒有明講如何取得refresh_token，所以查了一下作法

[**Not receiving Google OAuth refresh token**](https://stackoverflow.com/questions/10827920/not-receiving-google-oauth-refresh-token?utm_medium=organic&utm_source=google_rich_qa&utm_campaign=google_rich_qa)

文章中的解答說要 `approval_prompt=force&access_type=offline` 我嘗試是不行的，後來驗證結果是必須在 redirect URL中同時加入`prompt=consent&access_type=offline`

這部分比較簡單常見，就不贅述。

### Server-to-Server 取得授權

這部分Google文件強烈建議使用sdk而非 REST API，主要是因為Server-to-Server是透過加密JSON Web Tokens (JWTs)實作，如果出錯容易有資安風險，但範例還是採用接 REST API

1.  首先先到 [Google APIs Console](https://console.cloud.google.com/apis/credentials) 加入憑證，這次要加入的是服務帳號金鑰，記得要下載 json檔的金鑰檔案

![](/posts/img/1__1M5Qa1SGllse7Oghqfwl7Q.png)

2\. 接著到 IAM管理權限，找到剛才的服務帳號 Email，類似於 `….@….iam.gserviceaccount.com`，並加入「Service Management 管理員」權限，才能操作API。

3\. 記得比剛才的服務帳號加入表單的共同編輯者。

![](/posts/img/1__uobyyholII4abCvitAC9fg.png)
![左圖為IAM管理 / 右圖為表單共用設定](/posts/img/1__W0O65uuktYNrJcugUzVXqg.png)
左圖為IAM管理 / 右圖為表單共用設定

需注意 Server-to-Server不會有 refresh_token，token過期就必須重新產生JWT並取得新的token。

文件中有提到，部分API可以用JWT而不用access token就可以呼叫，但同樣只有部分支援，所以避免踩坑還是統一用 access token。

### Sheet API 使用

[**Introduction to the Google Sheets API | Sheets API | Google Developers**](https://developers.google.com/sheets/api/guides/concepts?authuser=1&hl=zh-cn)

Google Sheet API有兩個部分：  
1\. 單純讀跟寫是在 [spreadsheets.values](https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values?authuser=1&hl=zh-cn)底下  
2\. 其餘表單的屬性(合併欄位、更改欄位顏色等)等在 [spreadsheets](https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets?authuser=1&hl=zh-cn)底下

這次只有單純的讀寫，所以就只研究上者。

操作表單API，首先需要先創建一個 Google表單，連結大概會是  
[https://docs.google.com/spreadsheets/d/1dMJ…../edit#gid=0](https://docs.google.com/spreadsheets/d/1dMJEsOayj7RxMJ4-dX7LnrDOxqNzi1WeV3ref6q2okY/edit#gid=0)

`1dMJ….` 代表是表單的ID，而 `gid={id}`則是內頁的ID，在API用內頁名稱直接描述如 sheet1(也支援中文如 `表單一`)；  
整體上API操作可以 讀/寫/寫入文件最後(Append)/清除，每筆API都可以指定範圍如 `A1:A5` ，就跟一般表單操作類似。

程式碼請參考

[**sj82516/google-sheet-api-test**](https://github.com/sj82516/google-sheet-api-test)

在插入欄位的部分(API如 append / update)，有個參數可以指定Google Sheet如何處理輸入的欄位(valueInputOption)，可以指定為：  
1\. RAW，不處理完全依照輸入  
2\. USER_ENTERED，按照一般 Google Sheet輸入處理，如 `=MAX(A1:A2)` 就會自動轉成公式，字串如果符合格式會被轉製成數字等。  
3\. INPUT_VALUE_OPTION_UNSPECIFIED，有趣的是這個`預設值不能用`，API會報錯。

另一個參數是處理 Concurrency 問題，InsertDataOption可以指定當遇到插入新欄時遇上手動更新時，選擇覆蓋 OVERWRITE 或是插入在新欄位 INSERT_ROWS。

這次只有簡單用到 read / append 這兩個API，read可以指定範圍，append蠻有趣的如果有手動插入新欄，或是手動Delete整個表單，下次 append會自動正確的位置開始，這點倒不需要擔心。  
其餘的寫入/更新/刪除都沒用上，不過在文件中的參考網頁有提供測試很方便。

### 補更：插入新行於表單最上層

透過append是將新行插在表單最下層，但很多時候我們希望後面的資料出現在最上層，查了一下SO，有個解法是先創建新行再將值更新進去

### Push Notification

試想如果表單有新增資料，可以自動通知Server就能處理一些更進階的需求；Google Drive API 提供 Push Notification，而表單身為 Drive下的其中之一檔案型態，也有支援此功能，那就來研究一下吧。

[**Push Notifications | Drive REST API | Google Developers**](https://developers.google.com/drive/api/v3/push)

參考 [Files: watch](https://developers.google.com/drive/api/v2/reference/files/watch) 文件說明，以下為操作步驟

1.  定義好callback url並通過網域驗證：  
    因為是webhook關係，所以必須定義好 Google回呼的 callback url，這部分需要再 Google API Console > 憑證 > 網域驗證申請，網域驗證有多種方式，最簡單是Google會提供一份html並指定要放在網域的對應路徑下，用於驗證網域是屬於本人的。
2.  呼叫API

```js
axios.post(\`https://www.googleapis.com/drive/v2/files/${spreadsheet_id}/watch\`, {  
   type: 'web_hook',  
   id: 'channelIdAndShouldBeUnique',  
   address: \`${domain}/drive/webhook\`  
});
```

address 放 callback url，id則是自行定義channel，到時候回呼用於驗證，type固定為 web_hook。

Google回呼是用POST，但是內容是放在header，以 `x-goog-` 開頭的標頭，反而body中沒有資料。

但不得不說Google的Push Notification有點弱，因為他只會回傳哪個檔案改了、channel ID等，但不會有實質的改變內容，例如表單的哪一行修改、哪一行新增等等；  
不過也是，因為這是廣泛的Drive檔案異動通知，所以不會有太細緻的內容呈現。

## 總結

以上是Google OAuth2 授權模式研究，以及簡單的Google Sheet API研究，評估後符合專案的需求  
1\. Server主動append遞增資料  
2\. 保留Google表單原始功能  
3\. 取得Google表單異動觸發

因為是對內專案，所以是採用 Server-to-Server授權方式。

可惜不能得知更進一步的異動，只能自己重新抓資料，在Server端重新比對。

另外Google Sheet還可以透過 App Script插入資料，客製化前端，之後有空再來研究。