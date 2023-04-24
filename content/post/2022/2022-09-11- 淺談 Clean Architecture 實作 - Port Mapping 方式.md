---
title: '淺談 Clean Architecture 實作 - Port Mapping 方式'
description: 目前聽過幾個不同版本的 Clean Architecture 實作，最有趣的地方莫過於在外層在與 usecase 層互動時該採用什麼方式，以下整理出幾種不同模式
date: '2022-09-11T01:21:40.869Z'
categories: ['Program']
keywords: ['Clean Architecture']
---

在一月初時上 Teddy 的 DDD 課程時，第一次見識到 DDD 結合 Clean Architecture，可以將設計跟實作完美的結合，打造出彈性、易懂、好維護的程式碼，就一直對 Clean Architecture 很感興趣 ([課程 ezKanban 原始碼](https://gitlab.com/-/ide/project/TeddyChen/dddcleankanban/tree/master/-/board/))；   
後來在 2022 Coscup 上聽到強者 Jalex 分享 [Clean Architecture in Go: The Crescendo Way](https://slides.com/jalex-chang/go-clean-arch-cresclab) 提供了另一種實作的方式；  
最後在看【Clean Architecture 實作篇】時，作者又提供另一種方式以六角架構為基底的實作   

在看了這幾種不同實作的角度後，整理一下實作 Clean Architecture 中不同層轉換的取捨

## Clean Architecture 的解讀
【Clean Architecture】一書談了非常多的觀念，整理後自己的解讀是 `架構是為了降低後續的開發、維運成本並最大化工程師的產能`，而在這樣的原則下提出了以下的依賴原則

![](/post/2022/img/0911/dep.png)

1. 離 IO 越遠的元件越是核心，而核心不應該因為外層的改變而受到影響，就好比說用戶不會在意資料庫是用 MySQL 還是 MongoDB (IO)，他只會在意他購買的品項與折扣對不對 (業務規則)
2. 依賴的物件不可以跨層，所以 Adapter 不能直接存取 Entity  

所以從內而外，可以分成 Entity (Domain Object) / Use Case / Adapter (Controller, Gateway, Repository - 常指 DB 儲存層) 等


### 六角架構
![](/post/2022/img/0911/hex.png)
由 Alistair Cockburn 提出的六角架構，剛好與 Clean Architecture 觀點呼應，外部 IO (Adapter) 如果要與內層 (Entity / Use Case) 互動必須通過 `Port`，這些 Port 會透過依賴反轉當作隔離層，避免內層被外層的變動而改變

Port 方向依照核心的對應有兩種
1. In 從外層呼叫核心
2. Out 核心呼叫外層 (透過 interface)

## 跨層的溝通原則
在【Clean Architecture】一書中，提到如果跨層的話`內層的物件是不可以直接被輸出到更外層`，例如 Entity 只能在 Use Case 使用，如果要傳到 Controller , Gateway，必須再轉一層 DTO (data to object)，反之從外層往內傳也是，這是為了符合 `SRP 單一職責`  

例如一般的 web request，會從 Controller 取得參數 -> Use Case + Entity 處理業務邏輯 -> Controller 回傳結果，此時如果 Controller 在顯示結果直接依賴於 Entity，那 Entity 就會可能因為 API 要多回傳某個欄位而受到改動，違反最一開始的原則

但是如果每一層之間都需要 DTO 轉換，那程式碼會很多重複宣告，因為我們透過`重複取代耦合`，在【Clean Architecture 實作篇】有整理幾種方式，供大家取捨

### 1. No Mapping 跨層不轉換
![](/post/2022/img/0911/no_mapping.jpeg)
先看跨層完全不轉換的方式，參考我用 golang 實作的版本 [github/no-mapping](https://github.com/sj82516/clean-architecture-mapping/tree/feat/no-mapping/internal)，這邊我的 Entity 宣告混雜了 Controller 的 json tag 與 ORM 的 tag

```go
// Entity
type Order struct {
	gorm.Model
	ID        int `json:"id" gorm:"autoincrement"`
	Price     int `json:"price"`
	Count     int `json:"count"`
	Total     float64
	CreatedAt time.Time
}

// Use Case
func (s CreateOrderService) Action(o *domain.Order) *domain.Order {
	withTax := 1.1
	o.Total = float64(o.Count*o.Price) * withTax
	o.CreatedAt = now()
	s.saveOrder.SaveOrder(o)
	return o
}
```

在後續的 Controller / Gateway 中，就直接使用 Entity
```go
// Repo 儲存資料
func (r OrderRepository) SaveOrder(o *domain.Order) {
	result := r.db.Create(&o)
	fmt.Println(result.Error)
}

// Controller 直接用 Entity 取得 API request 內容
// 並傳入 UseCase 中
func (c *OrderController) CreateOrder(ctx *gin.Context) {
	var srv = service.NewCreateOrder(c.repo)

	var order domain.Order
	if err := ctx.ShouldBindJSON(&order); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err})
		return
	}
	srv.Action(&order)

	ctx.JSON(http.StatusOK, gin.H{"total": order.Total})
}
```

#### 優缺點
如果是很單純的 CRUD，API / DB 的資料格式都一模一樣才會使用，減少不必要的跨層轉換；  

但缺點是如果 API / DB 格式開始分歧，Entity 就會受到污染，出現部分欄位只有在特定用途使用，而不是跟業務邏輯有關，就像是 CreatedAt 欄位只是為了 DB 紀錄，卻出現在業務邏輯上不太合理；  
再加上如果未來不用 json 而走 gRPC，那 Entity 就要重新改 tag，因為 IO 變化而改動 Entity 違反了 Clean Architecture 原則

所以建議還是少用

### 2. Two way mapping
![](/post/2022/img/0911/two-way_mapping.jpeg)
[github/two-way mapping](https://github.com/sj82516/clean-architecture-mapping/tree/feat/two-way-mapping) 則是 Controller / Gateway 獨立宣告自己的物件，建立出 Entity後再傳入 Use Case 中

```golang
type Order struct {
	ID    int
	Price int
	Count int
	Total float64
}
```

```golang
//  Repo  獨立 DAO 定義
type OrderDAO struct {
	Id        int `gorm:"autoincrement"`
	Price     int
	Count     int
	Total     float64
	CreatedAt time.Time
}

func (r OrderRepository) SaveOrder(o *domain.Order) {
    // 用 Entity 去轉換 DAO
	orderDao := OrderDAO{
		Price: o.Price,
		Count: o.Count,
		Total: o.Total,
	}

	result := r.db.Create(&orderDao)
	fmt.Println(result.Error)
}

// Controller 獨立 Request Object
func (c *OrderController) CreateOrder(ctx *gin.Context) {
	var srv = service.NewCreateOrder(c.repo)

    // 獨立 DTO 
	type CreateOrderRequest struct {
		Price int `json:"price"`
		Count int `json:"count"`
	}

	var o CreateOrderRequest
	if err := ctx.ShouldBindJSON(&o); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err})
		return
	}

    // DTO 重建 Entity
	order := domain.Order{Price: o.Price, Count: o.Count}
	srv.Action(&order)

	ctx.JSON(http.StatusOK, gin.H{"total": order.Total})
}
```
可以看到 Entity 變得很乾淨，而 Controller / Gateway 要自己負責 DTO 的轉換，讓職責變得更明確

#### 優缺點
這算是蠻平衡的設計方式，適合用在 `Use Case -> Adapter` 這一層，可以看到 Jalex 大大在 DB 儲存層是用 Two way mapping 的方式 [go-clean-arch](https://github.com/chatbotgang/go-clean-arch/blob/develop/internal/adapter/repository/postgres/good_repository.go)

```golang
// DAO 另外定義
type repoGood struct {
	ID        int       `db:"id"`
	Name      string    `db:"name"`
	OwnerID   int       `db:"owner_id"`
	CreatedAt time.Time `db:"created_at"`
	UpdatedAt time.Time `db:"updated_at"`
}

// 直接拿 Good (Entity) 當作參數
func (r *PostgresRepository) updateGood(ctx context.Context, db sqlContextGetter, good barter.Good) (*barter.Good, common.Error) {
	where := sq.And{
		sq.Eq{repoColumnGood.ID: good.ID},
	}

	update := map[string]interface{}{
		repoColumnGood.Name:      good.Name,
		repoColumnGood.OwnerID:   good.OwnerID,
		repoColumnGood.UpdatedAt: time.Now(),
	}

	// build SQL query
	.....

	// execute SQL query
	.....

	updatedGood := barter.Good(row)
	return &updatedGood, nil
}
```

### 3. Full Mapping
![](/post/2022/img/0911/full_mapping.jpeg)
[github/full-mapping](https://github.com/sj82516/clean-architecture-mapping/tree/feat/full-mapping) 這次嚴格遵守 Clean Architecture，在 two-mapping 上增加`跨層都要有 DTO 的轉換`，所以 Controller -> Use Case 不能直接用 Entity，多宣告一個 Command Object 
```golang
// CreateOrder Use Case 改吃 CreateOrderCommand 當作參數而非 Entity
type CreateOrder interface {
	Action(command *CreateOrderCommand) *domain.Order
}

type CreateOrderCommand struct {
	Price int
	Count int
}

// New Command 可以負責驗證參數
func NewCreateOrderCommand(price int, count int) (CreateOrderCommand, error) {
	if price < 0 || count < 0 {
		return CreateOrderCommand{}, errors.New("params error")
	}

	return CreateOrderCommand{
		Price: price,
		Count: count,
	}, nil
}


func (s CreateOrderService) Action(command *in.CreateOrderCommand) *in.CreateOrderOutput {
	o := domain.Order{
		Price: command.Price,
		Count: command.Count,
	}

	withTax := 1.1
	o.Total = float64(o.Count*o.Price) * withTax

    // 與 Adapter 互動也是透過 cmd 而非直接傳入 Entity
	cmd := out.NewSaveOrderCommand(o.Price, o.Count, o.Total, now())
	s.saveOrder.SaveOrder(&cmd)

	output := in.NewCreateOrderOutput(o.Total)
	return &output
}
```
外部使用上
```go
// Controller 呼叫 Command Object
func (c *OrderController) CreateOrder(ctx *gin.Context) {
	var srv = service.NewCreateOrder(c.repo)

	type CreateOrderRequest struct {
		Price int `json:"price"`
		Count int `json:"count"`
	}

	var o CreateOrderRequest
	if err := ctx.ShouldBindJSON(&o); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err})
		return
	}

    // 透過 new cmd 去互動
    cmd, _ := in.NewCreateOrderCommand(o.Price, o.Count)
    output := srv.Action(&cmd)

	ctx.JSON(http.StatusOK, gin.H{"total": output.Total})
}

// Adapter 部分
type OrderDAO struct {
	Id        int `gorm:"autoincrement"`
	Price     int
	Count     int
	Total     float64
	CreatedAt time.Time
}

func (r OrderRepository) SaveOrder(cmd *out.SaveOrderCommand) {
	orderDao := OrderDAO{
		Price: cmd.Price,
		Count: cmd.Count,
		Total: cmd.Total,
	}

	result := r.db.Create(&orderDao)
	fmt.Println(result.Error)
}
```

#### 優缺點
多了一個 CreateOrderCommand 最大好處是可以進一步分散職責，由 Port 物件協助`驗證資料`，這樣 Use Case 可以專心驗證業務規則，而基本的資料驗證可以由 Port (也就是 CreateOrderCommand) 負責

其他地方驗證資料的考量點
1. Use Case: 要驗證資料同時驗證業務規則，這樣會比較複雜，讓 Use Case 專注業務規則會比較好  
2. Controller: 不適合驗證資料，如果有其他地方要呼叫 Use Case 那驗證規則要在重複寫一次  

> 資料驗證 vs 業務規則   
> 業務規則通常指的是與 Entity 本身狀態有關，例如 `轉帳餘額不可為空`，至於資料驗證比較是一般性的規則檢查例如 Email 格式、金額不可小於零等  

缺點就是如果是 CRUD 的話 DTO 會寫起來很瑣碎，建議是在 Controller -> Use Case 這一層使用

### 小作弊
上述的案例我們只有管輸入，當 Controller 要呼叫 Use Case 時 輸入參數用獨立的 Command Object

但是 Use Case 回傳值還是用 Entity，這還是違反了 Clean Architecture 物件不可跨層原則，這邊主要是方便使用，這也是【Clean Architecture 實作篇】作者在 p. 112 建議的做法

如果 in / out port 的輸入輸出都要有 DTO，建議參考 Teddy 的實做 [dddcleankanban](https://gitlab.com/TeddyChen/dddcleankanban/-/blob/master/board/src/main/java/ntut/csie/sslab/kanban/board/usecase/service/GetBoardContentService.java)

```java
// 在 Use Case 中回傳 output 而非 Entity
output.setBoardId(input.getBoardId())
    .setBoardMemberDtos(boardMemberDtos)
    .setWorkflowDtos(workflowDtos)
    .setCommittedWorkflowDtos(committedWorkflowDtos)
    .setCardDtos(cardDtosInBoard);

return output
```

## 總結
![](/post/2022/img/0911/overview.png)
總結整體架構大致是
1. Controller 有獨立的 Request / Response Object
2. Controller 會去建立 In Port Command，並呼叫 Use Case
3. Use Case 實作 In Port Interface，外界是與 Interface 相依
4. 透過 Out Port 與 Repository 溝通
5. Repository 定義 DAO 儲存資料到 DB
6. 因為 return 都偷懶用 Entity，所以大家都與 Entity 相依

採用 Clean Architecture 可以讓每一層變得更獨立、更好測試，開發的模式也可以更固定，在團隊增加人數時也更好上手，增加生產力

剛好公司的專案一邊是 Rails，框架本身就帶有很強烈的架構風格；另一邊微服務用 Golang 實作 Clean Architecture 試著讓框架與架構解耦，算是蠻有趣的衝突與相互印證