---
title: 'Golang Test - 單元測試、Mock與http handler 測試'
description: 分享如何在 Golang 中針對 http server 寫測試，包含單元測試 / 如何針對有外部相依性的物件做 Stub / Mock，以及最後針對 http handler 的 http request 測試
date: '2021-03-18T08:21:40.869Z'
categories: ['程式語言', 'Golang','測試']
keywords: []
url: '/posts/2021/2021-03-18-golang-test/'
---

上過 91 老師的 TDD 後，開始注重程式語言支援的測試框架，`編寫測試代碼與寫出容易寫測試的代碼`是很重要的一件事，好測試的代碼通常好維護，因為通常代表有更低的耦合性、物件依賴關係明確等，說是「通常」也代表不是這麼絕對；但反之 `不容易寫測試的代碼`往往都是有奇怪 smell 的  

關於測試案例的種類請參考 91 老師的 [Unit Test - Stub, Mock, Fake 簡介](https://dotblogs.com.tw/hatelove/2012/11/29/learning-tdd-in-30-days-day7-unit-testing-stub-mock-and-fake-object-introduction)

以下將分享如何在 Golang 中編寫
- 單元測試
- 如何 Stub/Mock 外部相依
- 如何針對 http handler 做 http request 假請求檢查

自己開始真正寫 Golang 也是這幾個禮拜，有一些命名、寫法不正確，煩請指教，但針對測試的本身應該是沒什麼問題的   
目前採用 `Ginkgo` + `gomock` + `httptest` 組合的測試工具

以下我們將寫一個簡單的匯率兌換表，用戶輸入既有的幣別 / 欲兌換的幣別 / 數量，Server 回傳兌換後的數量，程式碼於此 [golang-exchange-currency](https://github.com/sj82516/golang-exchange-currency)  

以下是程式碼結構
- main.go: 啟動 http server
- src/exchange_currency_model.go: 模擬去資料庫讀取匯率兌換表
- src/currency_exchange_handler.go: http handler，處理 request 與 response

## 單元測試  
首先要決定測試框架，這部分評估過 `原生的testing`、`Testify`，最後選擇了 [`Ginkgo`](https://onsi.github.io/ginkgo/#getting-ginkgo)，最大原因是熟悉原本 Nodejs的 `Decribe / It` 組織 test case 的方式，以及有方便的 BeforeEach 可以抽出重複測試行為的部分，例如在每個測試案例之前都先 new 好 object   
這些在 testing / Testify 都要額外的功夫處理  

```golang
import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)
var _ = Describe("currency exchange", func() {
	c := &CurrencyExchangeHandler{}
	....

	BeforeEach(func() {
		c = NewCurrencyExchangeHandler(e)
	})

	It("should get 0 if amount is 0", func(done Done) {
		....
		Expect(c.Exchange("US", "TW", 0)).To(Equal(0))
		close(done)
	})
    ....
}
```

## Stub/Mock  
`Stub` 專注於測試物件本身，只是把外部相依的方法塞一個設定值回傳；  
`Mock` 則延伸 Stub，除了塞回傳值外，而外檢查被呼叫物件的傳入值 / 呼叫次數 / 狀態改變等非測試物件本身的狀態

在 Golang 中，使用 [`gomock`](https://github.com/golang/mock) 真的是超級方便，可以直接針對檔案產出對應的 mock 檔 exchange_price_model_mock.go，這邊要注意 mock 是針對 interface 產生，所以如果你的檔案中沒有 interface，mock 檔出來就會是空的

所以我在 exchange_price_model.go 中有定義
```golang
type IExchangePriceModel interface {
	GetExchangeRate(string, string, chan<- ExchangeRateResult)
}
```
接著執行 `mockgen -source={要 mock 的檔案} -destination={輸出位置} -package={package 名稱}`，例如 `$ mockgen -source=exchange_price_model.go -destination=exchange_price_model_mock.go -package=src`，mockgen 是 gomock 用來產生 mock 檔案的 binary 執行工具  

之後測試案例採用 `NewMockIExchangePriceModel` 這個由 mockgen 產生的 struct 即可  
```golang
var _ = Describe("currency exchange", func() {
	c := &CurrencyExchangeHandler{}
	var (
		mockCtrl *gomock.Controller
		e        *MockIExchangePriceModel
	)

	BeforeEach(func() {
		mockCtrl = gomock.NewController(GinkgoT())
		e = NewMockIExchangePriceModel(mockCtrl)
		c = NewCurrencyExchangeHandler(e)
	})

	It("should get 0 if amount is 0", func(done Done) {
		e.EXPECT().GetExchangeRate("US", "TW", gomock.Any()).Do(func(from string, to string, ch chan<- ExchangeRateResult) {
			ch <- ExchangeRateResult{
				IsExists:     true,
				ExchangeRate: 40,
			}
		})
		Expect(c.Exchange("US", "TW", 0)).To(Equal(0))
		close(done)
		....
	})
}
```
編寫 mock 的方式如下
```golang
e.EXPECT().Method("預期 method 要收到的參數").Do(func("實際執行時收到的參數") {
    做任何造假
})
```
等於是寫一次連`預期輸入`、`造假輸出`都一並做完，如果要方便可以 `.Return()` 直接寫回傳內容，但因為涉及 channel 要傳遞資料，所以我選擇 .Do() 並塞入造假的資料回傳 channel   

如果不在意預期輸入，可以都用 `gomock.Any()` 跳過檢查  

### 如何造假 Time.Now 等系統相依的函式
搜尋了一下這類問題，建議是把有外部相依都抽到另一個 Object 去，然後透過依賴注入的方式傳進去，才能夠造假

例如
```golang
type ObjectA {}

func (a *ObjectA) MethodA(){
    a.MethodB()
}

func (a *ObjectA) MethodB(){
    return Time.Now()
}
```
這樣是無法測試的，要拆解成
```golang
interface IObjectB {
    MethodB func()
}

type ObjectA {
    ObjB IObjectB
}

func (a *ObjectA) MethodA(){
    a.ObjB.MethodB()
}
```

在使用 Interface 替換過程，要注意 *Type 跟 Type 的差異，如果發現以下錯誤訊息請參考 [X does not implement Y (… method has a pointer receiver)](https://stackoverflow.com/questions/40823315/x-does-not-implement-y-method-has-a-pointer-receiver)   
從問答中回去文件看，可以注意到以下內容
[Method sets ¶](https://golang.org/ref/spec#Method_sets)
```bash
The method set of any other type T consists of all methods declared with receiver type T. The method set of the corresponding pointer type *T is the set of all methods declared with receiver *T or T (that is, it also contains the method set of T)
```
這一段也就是說
- 如果 method 宣告的 reciever 是 non pointer type `func (t T) method`，則 T / *T 都有包含此 method
- 但如果 method 宣告的 reciever 是 pointer type，則只有 *T 包含此 method

延伸至 embedded struct
```bash
- If S contains an embedded field T, the method sets of S and *S both include promoted methods with receiver T. The method set of *S also includes promoted methods with receiver *T.   

- If S contains an embedded field *T, the method sets of S and *S both include promoted methods with receiver T or *T.
```
如果是
- S 是 non pointer，且 T 也是 non pointer，則包含了 T non pointer type methods
- S 是 non pointer + T 是 pointer / 只要 S 是 pointer type，則包含了 T non pointer / pointer type methods  

詳見程式碼，我把 struct 有的 method 都列出來，可以清楚看到以上的規則 [Go playground](https://play.golang.org/p/jkYrqF4KyIf)

另外抽出依賴再注入，如果忘記初始化會有記憶體存取失敗的錯誤 `http: panic serving runtime error: invalid memory address or nil pointer dereference`，看到錯誤記得去檢查

## 針對 HTTP Handler 做檢查
透過單元測試與 Stub/Mock，可以檢查完商業邏輯的部份，但如果想更確定 server 是否有正確處理 http request，包含是否回傳預期的錯誤結果，可以再進一步針對 http handler 做測試   

這邊採用 core library 包含 `net/http/httptest` 測試，完整教學可以參考 [Testing Your (HTTP) Handlers in Go](https://blog.questionable.services/article/testing-http-handlers-go/)  

```golang
It("test ServeHttp integration", func(done Done) {
    e.EXPECT().GetExchangeRate(gomock.Any(), gomock.Any(), gomock.Any()).Do(func(from string, to string, ch chan<- ExchangeRateResult) {
        ch <- ExchangeRateResult{
            IsExists:     false,
            ExchangeRate: 0,
        }
        close(ch)
    })

    req, _ := http.NewRequest("GET", "/exchange-currency", nil)
    query := req.URL.Query()
    query.Add("from", "US")
    query.Add("to", "TW")
    query.Add("amount", "10")
    req.URL.RawQuery = query.Encode()

    rr := httptest.NewRecorder()
    e := &ExchangePriceModel{}
    c := &CurrencyExchangeHandler{
        E: e,
    }
    handler := http.HandlerFunc(c.ServeHTTP)

    handler.ServeHTTP(rr, req)
    Expect(rr.Code).To(Equal(200))

    var body struct {
        Amount int
    }
    _ = json.Unmarshal(rr.Body.Bytes(), &body)
    Expect(body.Amount).To(Equal(300))

    close(done)
})
```
以上基本就是造假 / 初始化 handler / 初始化 http request / 透過 `handler.ServeHTTP(rr, req)` 模擬 http handler 處理過程 / 檢查 response  

基本上 Context / Cookie 等都可以處理，處理起來相當方便  

## 結語
從動態語言過來，最不習慣的就是要一直去想物件之間的相依，包含要處理 mock 時要拆出 interface 與外部物件，而不能針對某一個 object 的某一個 method 造假  

但整體上，Golang 的測試算方便且好上手，~找不到偷懶不寫測試的理由了~
