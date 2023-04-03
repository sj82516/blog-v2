---
title: '使用 InversifyJS 達到 Iversion of Control 控制反轉'
description: 高層次物件不應該依賴於低層次物件，例如 Controller 處理商業邏輯不應該依賴於資料庫儲存的邏輯，避免低層次物件的改動與耦合導致高層次物件需要跟著修改，透過 InversifyJS 管理 IoC
date: '2021-09-05T01:21:40.869Z'
categories: ['程式語言']
keywords: ['IoC', '控制反轉']
---
一開始學寫程式，很習慣依照執行順序，把低層次的物件寫死在高層次的物件中，更甚者直接讀取資料庫沒有任何的抽象化，例如
```js
class PaymentService {
    constructor() {
        this.orderCollection = mongoClient.collection('order');
        this.s3Service = new S3Service();
    }

    async pay(orderId) {
        const order = this.orderCollection.find({ id: orderId });
        .....
        this.s3Service.uploadResult(....);
    }
}
```
可能會覺得資料庫、雲端服務本身不太會有變動，所以寫死沒差，但除了服務被綁死外，另一個難題是`寫測試`，沒辦法將第三方服務 mock 寫出乾淨的 unit test，或是必須 mock 整個第三方 module 在寫測試前就先花了一小時在 mocking 非常浪費時間

當我們把外部相依抽出來，透過建構式注入，就解決了以上的問題，但帶來的新問題是呼叫方需要花很多時間先建構出需要的服務，例如
```js
function main() {
    const orderStorageService = new OrderStorageService();
    const s3Service = new S3Service();
    const paymentService = new PaymentService(orderStorageService, s3Service);
}
```
在每一個使用 paymentService 的地方，都需要手動建立相依的服務，即使有用 Factory Pattern 再多一層抽象化，管理起來也是十分的麻煩

此時可以用 [InvertifyJS](https://github.com/inversify/InversifyJS) 解決依賴注入的麻煩

原始碼 [sj82516/inversify-js-example](https://github.com/sj82516/inversify-js-example)

## 靜態相依
InversifyJS 概念大概是
1. 初始化 Container，將可以被注入的 Class 都打上標記，可以把 Container 當作是 Namespace
2. 在要注入的地方，透過標記決定初始化並注入相依的 Class
3. 如果要動態取得物件，可以從 Container 拿取

讓我們先看一個簡單的範例，假設我們有一個 Payment Service，會依賴於第三方付款平台 PaymentGatewayService 以及基本的 LogService 蒐集 log  

靜態相依是只說 Payment Service 在初始化就決定相依的物件，而不會動態的決定，第一步將 LogService 標記 `@injectable`，需注意要先定義 interface，接著把實作設定為 injectable，讓服務相依於抽象介面而不是實作，符合 `ISP - 介面隔離原則`，例如說 LogService 實作上可以是儲存於本地端檔案、上傳到 Slack 等等
```js
export interface LogService {
    log(message: string): void;
    error(message: string): void;
}

export const LogServiceTypes = {
   slack: Symbol("slack"),
   local: Symbol("local")
}
export type LogServiceTypeValueTypes = typeof LogServiceTypes[keyof typeof LogServiceTypes];

@injectable()
export class LocalLogService implements LogService {
    static NORMAL_FILE = './normal.log'
    static ERROR_FILE = './error.log'
    async log(message: string) {
       await fs.appendFile(LocalLogService.NORMAL_FILE, message);
    }

    async error(message: string) {
        await fs.appendFile(LocalLogService.ERROR_FILE, message);
    }
}

@injectable()
export class SlackLogService implements LogService {
    async log(message: string) {
        console.log("send log to slack", message)
    }

    async error(message: string) {
        console.log("send error log to slack", message)
    }
}
```
1. `LogServiceTypes` 是為了讓使用者在指定 logService 時有型別的提示
2. `LogServiceTypeValueTypes` 主要是為了指向 LogServiceTypes 的 values type

在 PaymentGatewayService 做類似的事情，接著定義我們 PaymentService
```js
@injectable()
export class StaticPaymentService {
    constructor(
        @inject("slackLog") private logService: LogService,
        @inject("stripePaymentGateway") private paymentGatewayService: PaymentGatewayService
    ) {
    }

    pay(client: Client, order: Order): string|void {
       const totalFee = this.paymentGatewayService.totalFee(order)
        if (totalFee > client.balance) {
            return this.logService.error(`${client.name} doesn't have enough money`);
        }

        this.logService.log(`${client.name} paid ${totalFee}`)

        return this.paymentGatewayService.generateLink(client, totalFee);
    }
}
```
重點在 constructor 中主動宣告了相依的物件，這邊我們指定要注入 `slackLog`、`stripePaymentGateway`  

最後是定義這些資源的地方 `invertify.config.ts`
```js
const paymentServiceContainer = new Container();
paymentServiceContainer.bind<LogService>("localLog").to(LocalLogService);
paymentServiceContainer.bind<LogService>("slackLog").to(SlackLogService);
paymentServiceContainer.bind<StaticPaymentService>("staticPaymentService").to(StaticPaymentService);
paymentServiceContainer.bind<StripePaymentGatewayService>("stripePaymentGateway").to(StripePaymentGatewayService);
paymentServiceContainer.bind<PaypalPaymentGatewayService>("paypalPaymentGateway").to(PaypalPaymentGatewayService);
```
我們定義一個 paymentServiceContainer，接著將物件都註冊到 Container 之中，方便後續的調用，上一步 inject() 的名稱 `slackLog` 就是在這邊定義，可以自由替換，只要單個 Container 中不重複就好

最後是 PaymentService 的初始化與調用
```js
const staticPaymentService = paymentServiceContainer.get<StaticPaymentService>("staticPaymentService");
staticPaymentService.pay(client, order);
```
這樣就完成了
------
### 小結
透過以上的案例，可以發現 InvertifyJS 做的事情也不複雜，讓開發者顯式的註冊對應的物件與其介面，接著在需要注入的地方直接用註冊名稱呼叫，如果需要動態初始化物件與其相依的服務使用 `container.get("name")` 即可

讓呼叫端要做的工作少了非常多

## 動態相依
如果我們希望動態一些，在初始化時才決定要選擇，可以採用工廠模式
```js
export class DynamicPaymentService {
    constructor(
        private logService: LogService,
        private paymentGatewayService: PaymentGatewayService
    ) {
    }

    pay(client: Client, order: Order): string|void {
        ....
    }
}
```
我們不用在宣告的地方加上 Injectable，而是透過 Container 建立 Factor
```js
paymentServiceContainer.bind<PaymentGatewayService>("PaymentGatewayService").to(StripePaymentGatewayService).whenTargetNamed("stripe")
paymentServiceContainer.bind<PaymentGatewayService>("PaymentGatewayService").to(PaypalPaymentGatewayService).whenTargetNamed("paypal")

type PaymentServiceFatory = (logType: LogServiceTypeValueTypes, paymentPlatform: string) => DynamicPaymentService;

paymentServiceContainer.bind<PaymentServiceFatory>("DynamicPaymentService").toFactory<DynamicPaymentService>((context: interfaces.Context) => {
    return (logType: string, paymentPlatform: string) => {
        let paymentGatewayService = context.container.getNamed<PaymentGatewayService>("PaymentGatewayService", paymentPlatform);
        let logService = context.container.get<LogService>(logType);
        return new DynamicPaymentService(logService, paymentGatewayService);
    };
});
```
看起來有點嚇人，分成幾段
1. `<(logType: symbol, paymentPlatform: string) => DynamicPaymentService>` bind 裏面放的是回傳的型別，我們的 Factor 是有兩個參數 logType / paymentPlatform 並且回傳 DynamicPaymentService 的函式  
2. `("DynamicPaymentService")` 在 Container 他對應的名稱是 "DynamicPaymentService"，可以用 String，更謹慎可以用 Symbol
3. `.toFactory<DynamicPaymentService>` 定義 Factory 回傳 DynamicPaymentService 型別的物件
4. `(context: interfaces.Context) => {}` 透過當前上下文取得相關資訊，並返回實際 Factory 函式的實作
5. 為了更方便取得對應的服務，可以加上 `whenTargetNamed` 直接指定名稱

最後使用
```js
const factory = paymentServiceContainer.get<PaymentServiceFatory>("DynamicPaymentService");
const paymentService = factory(LogServiceTypes.slack, "paypal");
paymentService.pay(client, order);
```

## 結語
Inversify 還有其他有趣的功能，包含使用 tag / 定義 middleware 等等，整體看起來是個擴充性非常良好的設計，有機會再來研究內部的實作