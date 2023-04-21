---
title: '在 Clean Architecture 下 transaction 該如何實作的問題發想 (Golang 與 Ruby 實作)'
description: 在學習 Clean Architecture 時最困擾的問題莫過於 transaction 到底該算是商務邏輯由 usecase 控制還是要下放到 repository 包含一些商務判斷內不外洩 ?! 以下用電子商務的場景，透過實作驗證不同的解決方式
date: '2023-04-21T02:21:40.869Z'
categories: []
keywords: ['Clean Architecture']
---
在套用 Clean Architecture (後續簡稱 CA)過程，最常討論的問題莫過於「Transaction 如果跨多個 repository，該怎麼處理？如果 Transaction 由 Use Case 控制會不會違反 CA 原則？如果放到 Repository 那有一些判斷的邏輯是不是也混雜進去？」  
這個問題確實有點棘手，網路上也常看到各種不同的作法，決定今天重新整理一下，檢視不同的作法與考量，並透過實際的案例去驗證不同作法的優劣，使用動態語言 Ruby / 靜態語言 Golang 確保實作是真實可行

目前想到的驗證場景為
> 「用戶」帳號有點數，透過點數購買「商品」並成立對應的「訂單」
> 商品必須有足夠數量、用戶點數必須有足夠的點數才可以成立訂單
> 以上行為必須包含在一個 transaction 中


## 外部的幾種做法
### 1. 由 UseCase 控制，因為 Usecase 才知道所有的 Context
這部分說法是從《Clean Architecture 實作篇》第 84 頁所截取的內容，作者提到只有 Usecase 有足夠的上下文去判斷這幾個 repository 操作是否該放到同一個 transaction，[範例 code](https://github.com/thombergs/buckpal/blob/master/src/main/java/io/reflectoring/buckpal/account/application/service/SendMoneyService.java?fbclid=IwAR03bRjdRX_AWnkJ8mGrfp61AFOdnw_Pr8gqLmx6YAqjIDWQknN0yQh0NUg) 如下
```java
@UseCase
@Transactional
public class SendMoneyService implements SendMoneyUseCase {
	@Override
	public boolean sendMoney(SendMoneyCommand command) {
		....
		AccountId sourceAccountId = sourceAccount.getId()
				.orElseThrow(() -> new IllegalStateException("expected source account ID not to be empty"));
		AccountId targetAccountId = targetAccount.getId()
				.orElseThrow(() -> new IllegalStateException("expected target account ID not to be empty"));

		accountLock.lockAccount(sourceAccountId);
		if (!sourceAccount.withdraw(command.getMoney(), targetAccountId)) {
			accountLock.releaseAccount(sourceAccountId);
			return false;
		}

		accountLock.lockAccount(targetAccountId);
		if (!targetAccount.deposit(command.getMoney(), sourceAccountId)) {
			accountLock.releaseAccount(sourceAccountId);
			accountLock.releaseAccount(targetAccountId);
			return false;
		}

    .....
	}
}
```
作者直接使用 framework 提供的 annotation @Transaction 把所有的操作都放到同一個 Transaction 中
### 2. 應該放到 repository 中，有其他的需求用 callback function 補充
這是我在 Coscup 聽到的 [golang 版本 CA 實作](https://github.com/chatbotgang/go-clean-arch)，作者一開始想要的解法是usecase 控制 lock，repository 控制 transaction
```golang
func (s *BarterService) ExchangeGoods(ctx context.Context, param ExchangeGoodsParam) common.Error {
	// 1. Claim an event to exchange goods X and Y 
  s.lockServer.claim(X, Y, ttl)

  // 2. Check ownership of request good
	// 3. Check the target good exist or not
	// 4. Exchange ownership of two goods
  // .......

  // 5. Disclaim the event
  s.lockServer.disclaim(X, Y)

	return nil
}

func (r *PostgresRepository) CheckOwnerIDsAndUpdateGoods(ctx context.Context,  param CheckOwnerIDsAndUpdateGoodsParam) (updatedGoods []barter.Good, err common.Error) {
	tx, err := r.beginTx()
	if err != nil {
		return nil, err
	}
	defer func() {
		err = r.finishTx(err, tx)
	}()
        // 1. Get goods again
       if  _, err  = r.getGoodByIDandOwnerID(ctx, tx, param.G1.ID, param.G1.OnwerID); err != nil { // ...}
       if  _, err  = r.getGoodByIDandOwnerID(ctx, tx, param.G2.ID, param.G2.OnwerID); err != nil { // ...}
       
        // 2. Update Goods
	for i := range goods {
		updatedGood, err := r.updateGood(ctx, tx, param.updateGoods[i])
		if err != nil {
			return nil, err
		}
		updatedGoods = append(updatedGoods, *updatedGood)
	}

	return updatedGoods, nil
}
```
但在這個 issue 中有人補充不同的作法 [Is there a race condition bug?](https://github.com/chatbotgang/go-clean-arch/issues/13)，另一個人提到 `lock 比較不像商務邏輯，比較像實作的細節，所以他會想要放到 repository 中`，而商務邏輯就用 callback function 方式傳入
```golang
func (s *BarterService) ExchangeGoods(ctx context.Context, param ExchangeGoodsParam) common.Error {
    g1, g2, err := s.goodRepo.UpdateTwoGoods(ctx, param.G1, param.G2, func(g1, g2 barter.Good) common.Error {
        // 1. Check ownership of request good
        // ......

        // 2. Check the target good exist or not
        // ......

        // 3. Exchange ownership of two goods
        // ......
        return nil
    })

    return err
}

func (r *PostgresRepository) UpdateTwoGoods(
    ctx context.Context,
    id, id2 string,
    updateFn func(*barter.Good, *barter.Good) (*barter.Good, *barter.Good, common.Error),
) (barter.Good, barter.Good, err common.Error) {
    tx, err := r.beginTx()
    if err != nil {
        return nil, err
    }
    defer func() {
        err = r.finishTx(err, tx)
    }()

    // 1. Fetch required data
    if g1, err  = r.getGoodByID(ctx, tx, id); err != nil { // ... }
    if g2, err  = r.getGoodByID(ctx, tx, id2); err != nil { // ... }

    // 2. Apply business logic (usecase)
    if g1, g2, err = updateFn(g1, g2); err != nil { // ... }

    return g1, g2, nil
}
```
## 重新思考
重新抽象化一下遇到的困境
```
usecase
   1. 從 repo 讀取，同時要 lock
   2. 針對讀取的數值判斷
   3. 根據判斷，將結果寫回 repo
   4. 以上三步要在同一個 transaction
```
重新審思 CA 的條件，有幾點規則我們應該要遵守
1. repository 應該只包含儲存層的操作，不應該有商務邏輯
2. usecase 不應該知道太多 repository 細節，或換個角度，當抽換 repository 時應該要很容易，不改變 usecase 的實作

根據以上的條件，來測試兩種方式
1. usecase 控制 lock 與 transaction
2. repository 用 callback function 注入商務邏輯
兩者實作起來的感覺

## 實作比較
參考程式碼 [clean-architecture-transaction-issue](https://github.com/sj82516/clean-architecture-transaction-issue)

### 方法一：use case 控制 transaction 與 lock
首先在 [usecase 中控制](https://github.com/sj82516/clean-architecture-transaction-issue/blob/1e5f66cf6df40b38a3df7c510d58e845a58493be/usecase/purchase_product.rb#L11)
```rb
def run(user_id, product_id, count)
  user_repository.transaction()
  user = user_repository.find_by_id_with_lock(user_id)
  product = product_repository.find_by_id_with_lock(product_id)
  total = product.price * count
  return unless user.can_purchase?(total)
  return unless product.can_purchase?(count)

  # to test race condition
  sleep 1

  user.points -= total
  product.stock -= count

  order = Order.new(user, product, count)
  user_repository.save(user)
  product_repository.save(product)
  order_repository.create(order)
  user_repository.commit()
end
```
這邊暴露了蠻多關於 DB 的細節，包含 transaction / lock / commit，但所有的商業邏輯也都在 usecase 中；  
但整體傷害應該不算到太嚴重，主要是也沒有直接跟 DB 耦合，如果抽換成其他 NoSQL 頂多 transaction / commit method 留空，不會直接違反 CA 依賴方向的原則

### 方法二：由 repository 控制 transaction
[由 repository 控制 transaction](https://github.com/sj82516/clean-architecture-transaction-issue/blob/1e5f66cf6df40b38a3df7c510d58e845a58493be/usecase/purchase_product.rb#L32)，商務邏輯用 block 方式傳入，其餘的邏輯都在 repository 中
```rb
# usecase
def run_in_repo(user_id, product_id, count)
  aggregate_root_repository.purchase_product(user_id, product_id, count) do |user, product|
    total = product.price * count
    next false unless user.can_purchase?(total)
    next false unless product.can_purchase?(count)
    true
  end
end

# repository
class AggregateRootRepository < Repository

  def purchase_product(user_id, product_id, count)
    transaction
    result = client.prepare("SELECT * FROM users WHERE id = ? FOR UPDATE")
                 .execute(user_id)
                 .first
    user = User.new(result['id'], result['points'])
    result = client.prepare("SELECT * FROM products WHERE id = ? FOR UPDATE")
                    .execute(product_id)
                    .first
    product = Product.new(result['id'], result['price'], result['stock'])

    is_pass = yield(user, product, count)
    return unless is_pass

    client.prepare("INSERT INTO orders (user_id, product_id, count) VALUES (?, ?, ?)")
          .execute(user.id, product.id, count)
    total = product.price * count
    client.prepare("UPDATE users SET points = ? WHERE id = ?")
          .execute(user.points - total, user.id)
    client.prepare("UPDATE products SET stock = ? WHERE id = ?")
          .execute(product.stock - count, product.id)

    commit
  end
end
```
這邊的商務邏輯只有判斷是否可以購買，其餘的 DB 操作封裝在 repository 中，這邊取名叫做 Aggregate Root 是想呼應 DDD 裡面的想法「由 Aggregate Root 操作保證底下多個 Aggregate 的一致性」

### 比較兩者差異
1. **usecase 乾淨程度(方法二勝)：**  
蠻明顯作法很乾淨，把所有的 DB lock / transaction 都封裝得一乾二凈，而商務邏輯還是保留在 usecase 中呼叫
2. **擴充性(方法一勝)：**  
如果未來商務邏輯變得更複雜，有可能 DB 查完資料要增加新的比對，例如「高級會員有更多的折價」、「特殊商品買 10 送 1」等等，方法二需要不斷的增加 function 傳入，而方法一因為都是在 usecase 操作，所以直接增加就好，相對好擴充
3. **可測試性(方法一勝)：**
我覺得兩個作法最大的差異是`可測試性`，測試可以用 integration test 連 DB 一起測 / 或是 unit test 把其他相依的物件 mock 掉；
integration 測試部分兩者沒太多差異 (參考 [main_spec.rb](https://github.com/sj82516/clean-architecture-transaction-issue/blob/master/main_spec.rb))；  
但是 unit test 就有很大的差異 (參考 [usecase.rb](https://github.com/sj82516/clean-architecture-transaction-issue/blob/master/usecase_spec.rb))，因為方法一的 repository 方法都是 public 讓 usecase 呼叫，所以很好 mock，但方法二目前我想不到比較好的方法測試，因為 callback function (block) 是在 repo 中呼叫，那我直接 mock 掉不就什麼都測不了了 ?!!  

## 結論
即使 usecase 會比較混亂一些，我還是選擇方法一

(golang 版本待補)