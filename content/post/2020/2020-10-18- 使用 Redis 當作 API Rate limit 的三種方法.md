---
title: '使用 Redis 當作 API Rate limit 的三種方法'
description: API Service 在操作某些行為時需要耗費資源，如果 Client 不如預期的大量呼叫，會造成服務受到嚴重的影響，所以需要針對用戶做 API 呼叫次數的限制；Redis 作為中心化的高效能記憶體資料庫，很適合拿來當作 Rate Limit 的儲存方案，以下分享三種常見的做法 static time window / sliding time window 與 token bucket
date: '2020-10-18T08:21:40.869Z'
categories: ['系統架構', '資料庫', '應用開發']
keywords: ['Redis', 'Rate-Limit']
---

最近公司 API 服務被 Client 不預期的高頻存取，造成後端 DB 很大的負擔，開始評估各種 API Rate Limit 的方案，其中一個最常見的作法就是靠 Redis，但具體的方案其實有蠻多種，參考以下影片整理三種作法  

{{<youtube HnSb8DFU5UA>}}

順便推薦一下 RedisLabs 所推出的 GUI 管理工具 `RedisInsights`，可以快速分析 Redis 中 Key Space 的使用 / Profiling 一段時間內哪些 Key 被大量存取等等，基本的 Redis CLI 操作就更不用提了，對比之前用的 `medis` 功能強化不少，尤其是`管理/監控這一塊的功能`  
目前是免費的，支援 Cluster Mode，連接 AWS ElasticCache 也沒問題，十分推薦  

## Rate Limit 全觀
要設計 Rate Limit 機制時需要考量幾個面向
### Who 
該如何識別要限制的對象？  
最直覺是透過 IP，但是使用 IP 最大的風險是 如果是大客戶，他一個人的流量遠超過其他小客戶，對公司的價值顯然也是遠遠重要，如果用 IP 很容易有誤殺的情況，把有價值的用戶阻擋在外  

其他的作法可以用 JWT Token / API Key 等個別用戶識別的方式，需要針對自家的業務場景去判斷  
### How  
該使用怎樣的方式計算限制的方式？  
通常是在某個時間區段內，限制只能存取多少次的計算模式，有三種方式可以參考
### static time window - 固定時間區段  
例如說每一分鐘為一個單位，這一分鐘內只能存取五次  
這樣的方式十分簡單，但可能會有短時間內超量的問題，例如說 0:59 存取 4 次，接著 1:01 存取4 次，分開在兩個時間區段都是合法，但是才隔兩秒就存取 8 次，這可能不會是希望的結果    

實作方式，以目前每週 160 k 下載的 `express-rate-limit` 中 redis 版本 [rate-limit-redis](https://www.npmjs.com/package/rate-limit-redis) 是以下做法  
1. 先計算出該時間段的鍵值，例如 01:00 ~ 01:59 的鍵值都是 `01`    
```js
var expiryMs = Math.round(1000 * options.expiry);
```
2. 增加 key 並更新 ttl 時間，incr 會回傳當下增加後的值，藉此判斷是否超過限制  
```js
options.client.multi()
      .incr(rdskey)
      .pttl(rdskey)
      .exec()
```
因為有 ttl，所以不用擔心 key 的刪除，這個方法簡單直覺儲存成本也很低     

為了嚴格限制`任意時間區段內的最大存取數量`，參考以下文章提及兩種做法 [Better Rate Limiting With Redis Sorted Sets
](https://engineering.classdojo.com/blog/2015/02/06/rolling-rate-limiter/)

### token bucket  
每一個用戶都有一個對應的 bucket，只有 token 足夠時可以進行操作，每隔一段時間會回補 token 數量，好處是可以制定多種操作的 token 需要數量，像是更繁雜的操作需要消耗更多的 token ，更有彈性應對不同的限制方案  

資料結構使用 Redis 的 `Hash`，演算法大致如下
1. 用戶要操作的時候，如果此時沒有紀錄，先插入一筆 Hash `user: 當下 的 timestamp => token 初始化數量`
2. 後續操作時，取出上一次操作的 timestamp，接著回補這一段時間需要補充的 Token 數量
3. 接著扣除操作所需的 Token 數，查看是否有符合限制  

需注意這種做法會有 `Race Condition` 問題，如果一個用戶同時有兩個操作，在第三步驟檢查時，會誤以為自己都有足夠的 token，除非使用 `Lua script`，Redis 才會將`多個操作視為 atomic 避免 Race Condition` 

[node-redis-token-bucket-ratelimiter](https://github.com/BitMEX/node-redis-token-bucket-ratelimiter) 便是採用 Lua script 作法，讓我們來欣賞一下

1. 取得參數，並指定 `redis.replicate_commands()`，這是在調用 `$ redis eval` 時要產生隨機 IO 時需要提前執行的指令 [Redis - EVAL script numkeys key](https://redis.io/commands/eval)，這一篇有易懂的解釋 [Redis · 引擎特性 · Lua脚本新姿势](http://mysql.taobao.org/monthly/2019/01/06/)，基本上就是為了符合 Redis 在持久化以及副本資料時的功能，在 5.0 以後是默認選項；    
接著就是分別計算上一次更新時間 `initialUpdateMS` / 殘留的 token 數 `prevTokens`
```lua
-- valueKey timestampKey | limit intervalMS nowMS [amount]
local valueKey     = KEYS[1] -- "limit:1:V"
local timestampKey = KEYS[2] -- "limit:1:T"
local limit      = tonumber(ARGV[1])
local intervalMS = tonumber(ARGV[2])
local amount     = math.max(tonumber(ARGV[3]), 0)
local force      = ARGV[4] == "true"

local lastUpdateMS
local prevTokens

-- Use effects replication, not script replication;; this allows us to call 'TIME' which is non-deterministic
redis.replicate_commands()

local time = redis.call('TIME')
local nowMS = math.floor((time[1] * 1000) + (time[2] / 1000))
local initialTokens = redis.call('GET',valueKey)
local initialUpdateMS = false


if initialTokens == false then
   -- If we found no record, we temporarily rewind the clock to refill
   -- via addTokens below
   prevTokens = 0
   lastUpdateMS = nowMS - intervalMS
else
   prevTokens = initialTokens
   initialUpdateMS = redis.call('GET',timestampKey)

   if(initialUpdateMS == false) then -- this is a corruption
      -- 如果資料有問題，需要回推 lastUpdateMS 時間，也就是用現在時間回推殘存 Token 數量的回補時間
      lastUpdateMS = nowMS - ((prevTokens / limit) * intervalMS)
   else
      lastUpdateMS = initialUpdateMS
   end
end
```
2. 接著計算上一次到現在需要回補的 Token `addTokens` / 這一次運算配額夠不夠 `netTokens` / 如果下一次要嘗試需要等多久的時間 `retryDelta`
```lua
local addTokens = math.max(((nowMS - lastUpdateMS) / intervalMS) * limit, 0)

-- calculated token balance coming into this transaction
local grossTokens = math.min(prevTokens + addTokens, limit)

-- token balance after trying this transaction
local netTokens = grossTokens - amount

-- time to fill enough to retry this amount
local retryDelta = 0

local rejected = false
local forced = false

if netTokens < 0 then -- we used more than we have
   if force then
      forced = true
      netTokens = 0 -- drain the swamp
   else
      rejected = true
      netTokens = grossTokens -- rejection doesn't eat tokens
   end
   -- == percentage of `intervalMS` required before you have `amount` tokens
   retryDelta = math.ceil(((amount - netTokens) / limit) * intervalMS)
else -- polite transaction
   -- nextNet == pretend we did this again...
   local nextNet = netTokens - amount
   if nextNet < 0 then -- ...we would need to wait to repeat
      -- == percentage of `invervalMS` required before you would have `amount` tokens again
      retryDelta = math.ceil((math.abs(nextNet) / limit) * intervalMS)
   end
end
```
3. 如果成功操作 ( rejected == false )，則延長 key 的過期時間
```lua
if rejected == false then
   redis.call('PSETEX',valueKey,intervalMS,netTokens)
   if addTokens > 0 or initialUpdateMS == false then
      -- we filled some tokens, so update our timestamp
      redis.call('PSETEX',timestampKey,intervalMS,nowMS)
   else
      -- we didn't fill any tokens, so just renew the timestamp so it survives with the value
      redis.call('PEXPIRE',timestampKey,intervalMS)
   end
end
```

### sliding time window - 滑動時間區段 
最後一個是使用 sorted set，可以使用 `$ redis.multi` 將多個 sorted set 的指令串再一起 Atomic 執行所以能夠避免 Race Condition 狀況  
具體想法是
1. 用一個 sorted set 儲存所有的 timestamp
2. request 進來後，先用 `ZREMRANGEBYSCORE` 捨棄 time window 以外的 key
3. 取得 sorted set 剩餘的所有元素 `ZRANGE(0, -1)`
4. 加上這一次的操作 `ZADD`，並延長 sorted set 的 ttl
5. 接著算整個 sorted set 的元素量，就知道存取幾次了  

需要特別注意，這邊如果第五步判斷失敗也會被計算在 limit 當中，因為第四步已經先加上去了，如果`在第三步先判斷數量夠不夠再去更新 sorted set，中間的時間差就有可能發生 Race Condition`，所以要嚴格限制必須要這麼做，除非又要包成 lua script  

這會導致一個風險，如果 Client 真的失控一直打，那他會無止盡的失敗，因為每一次的失敗操作都會被加入 sorted set 當中，但其實都沒有真的執行到

模組請參考 [rolling-rate-limiter](https://github.com/peterkhayes/rolling-rate-limiter)，程式碼在這
```js
const batch = this.client.multi();
batch.zremrangebyscore(key, 0, clearBefore);
if (addNewTimestamp) {
    batch.zadd(key, String(now), uuid());
}
batch.zrange(key, 0, -1, 'WITHSCORES');
batch.expire(key, this.ttl);

return new Promise((resolve, reject) => {
    batch.exec((err, result) => {
        if (err) return reject(err);

        // 加完後才來計算是不是扣打足夠
        const zRangeOutput = (addNewTimestamp ? result[2] : result[1]) as Array<unknown>;
        const zRangeResult = this.getZRangeResult(zRangeOutput);
        const timestamps = this.extractTimestampsFromZRangeResult(zRangeResult);
        return resolve(timestamps);
    });
});
```

## 結論  
Rate Limit 看似簡單，但也有不少的眉角要去考量，之前一直都沒有客製 Redis 中 lua script 的部分，也是蠻有趣的  