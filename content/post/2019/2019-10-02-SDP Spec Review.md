---
title: SDP Spec 閱讀筆記
description: >-
    SDP 被應用於多種媒體串流協定中，主要是用來協議雙方所支援的媒體通訊格式
date: '2019-10-02T00:21:40.869Z'
categories: ['網路與協定', 'WebRTC']
keywords: ['javascript', 'book review']
---

# 介紹
SDP 是一種標準化的資訊傳達方式，用來表達多媒體的內容、傳輸的位址及其他傳遞所需的 metadata，主要應用場景於多媒體傳輸的前置溝通，例如說視訊會議、VoIP(Voice over IP) 通話、影音串流等會話(Session)
在規範中並沒有定義 SDP 該怎麼被傳輸，可以自由選用 HTTP / XMPP / RTSP / Email 等傳輸協定等

# 名詞定義
1. Conference:
   兩個以上的用戶正在相互通信的集合
2. Session:
   有一個發送者，一個接收者，兩者間建立一條多媒體串流的通道，資料由發送者寄發到接收者
3. Session Description：
   讓其他人可以成功加入 Conference 的資訊

# 要求與建議
SDP 主要功用為傳遞多媒體會話中多媒體串流的資訊，溝通會話的存在 / 及讓其他非參與者知道如何加入此會話(主要用於廣播 multicast)，內容大概分成幾個
1. 名稱跟目的
2. 會話有效的時間
3. 會話中涵蓋的多媒體
4. 要如何接收串流的資訊 (如 位址、Port、格式等)
5. 會話需要的帶寬資訊
6. 個人的聯絡資料

## 媒體與傳輸資訊
這部分包含了
1. 媒體形式 (影片、聲音等)
2. 傳輸協定 (RTP/UDP/IP等)
3. 媒體格式 (H. 264/MPEG等)

另外還會包含位址與埠口的資訊，SDP 傳輸形式包含單播(unicast)跟多播(multicast)，多播則包含多播的群組位址，單播則是單一台的位址

## 時間資訊
1. 任意數量的開始與結束時間組合
2. 週期性表示 (如每週三早上十點一小時)
時間表示是全球統一格式，不包含時區或是日光節約時間

## 私人會話
SDP 本身不涉及 public 或 private session，如果需要加密或是限定，則在傳輸時自行決定

## 其他
SDP 本身就應該夾帶足夠的資訊讓參與者知道是否該加入 session，但如果有其他額外資訊要夾帶，可以放在另外的 URI 中；

# SDP Spec
文字編碼上，SDP 採用  ISO 10646 字符集並用 UTF-8 編碼方式，但是在屬性/欄位上採用 UTF-8 的子集合 US-ASCII，只有在文字欄位可以使用完整的 ISO 10646 字符集

SDP 是由這樣格式的文字組成
> \<type>=\<value>

type 必須是單一個大小寫區分的字元；
value 則是相對應有結構的文字，多個值可以用空白分隔；
切記在 = 兩側不可以有空白

SDP 中包含了 session-level 區段與多個 media-level 區段，session-level 區段以 `v=` 開始，其屬性套用在所有的 media 區段上，但如果 media 區段有相同屬性則會被覆蓋；
而 media-level 則是 `m=`開始直到下一個 media level 區段開始

在 SDP 定義的順序很重要，主要是幫助更快的錯誤偵測與容易實作 parser

有些欄位是必填有些是選擇性，但重點是一定要按照順序，選擇性欄位以 * 註記，屬性欄位大致介紹含義，不會完整介紹
```md
Session description
    v=  (protocol version)
    o=  (originator and session identifier)
    s=  (session name)
    i=* (session information)
    u=* (URI of description)
    e=* (email address)
    p=* (phone number)
    c=* (connection information -- not required if included in
        all media)
    b=* (zero or more bandwidth information lines)
    One or more time descriptions ("t=" and "r=" lines; see below)
    z=* (time zone adjustments)
    k=* (encryption key)
    a=* (zero or more session attribute lines)
    Zero or more media descriptions

Time description
    t=  (time the session is active)
    r=* (zero or more repeat times)

Media description, if present
    m=  (media name and transport address)
    i=* (media title)
    c=* (connection information -- optional if included at
        session level)
    b=* (zero or more bandwidth information lines)
    k=* (encryption key)
    a=* (zero or more media attribute lines
```

a= 屬性機制主要是擴展 SDP，由各個使用 SDP 的協定去使用
有些屬性有制式的含義，有些則基於應用程式的解讀，例如

有些定義在 Session-level 的屬性如 連線相關 c= 或是屬性相關 a= 會套用在 Session 底下所以的 Media，除非被特別指定覆寫

如以下範例，所有的 media 都會被冠上 recvonly 的屬性
      
```md
v= 0
o=jdoe 2890844526 2890842807 IN IP4 10.47.16.5
s=SDP Seminar
i=A Seminar on the session description protocol
u=http://www.example.com/seminars/sdp.pdf
e=j.doe@example.com (Jane Doe)
c=IN IP4 224.2.17.12/127
t=2873397496 2873404696
a=recvonly
m=audio 49170 RTP/AVP 0
m=video 51372 RTP/AVP 99
a=rtpmap:99 h263-1998/900000
```

文字欄位如 session 名稱和資訊等可以是包含任意位元組的字串除了以下 0x00 Nul 、  0x0a (new line) 、 0x0d (carriage return) ；
字串以 CRLF(0x0d0a) 當作斷行，但 parser 也應該將 newline 視為斷行的標誌；
如果沒有 a=charset 屬性指定字符集，則預設為 ISO-10646 字符集搭配 UTF-8 編碼方式

如果是包含 domain name，則必須確保符合 ASCII Compatible Encoding (ACE)，也就是要經過編碼跳脫字元，因為有些 SDP 相關協定定義早於國際化 domain name，所以不能直接用 UTF-8 表示

欄位介紹
### 協定版本 (v=)
沒有其他版本號，就是 v=0

### 來源 (o=)
描述Session 的發起者資料
```md
o=<username> <sess-id> <sess-version> <nettype> <addrtype><unicast-address>
```
1. sess-id：數字組成的字串，由<username> <sess-id> <sess-version> <nettype> 四者組成的字串必須是全域唯一的 (globally unique)，sess-id 的產生可自行定義，但建議採用 NTP 格式的 timestamp 保證唯一性
2. sess-version：此 Session 描述的版號，在改變 SDP 內容時確保版號是遞增的，同樣建議用 NTP 格式 timestamp
3. nettype：採用網路類型
4. addrtype：指定 address 的類型，例如 IP4 / IP6 等
5. unicast-address：
  創建 session 機器的位址，可以是 domain name 或是 IP 表示法，不可使用 local ip 因為不確定對方是否在 local 範圍內

如果有隱私問題， username / unicast-address 可以被混淆，只要不影響全域唯一性

### Session 名稱 (s=)
文字欄位，表示 Session 名稱，每份 Session description 中只能有一個，不能為空值且必須採用 ISO-10646 字元 (除非有另外指定字符集)，如果沒有要特別指定 Session 名稱，可以用空白代替如 (s= )

### Session 資訊 (i=)
文字欄位，每份 session description 中每個 session 最多只能有一個，每個 media 最多也只能宣告一個；
這資訊主要是寫給人類閱讀的，用來表示 session 或是 media stream 的用處

### URI (u=)
選擇性欄位，用來表示關於Session額外資訊的位址連結，最多只能有一個，必須放置在 media 欄位之前

### Email 及電話號碼 (e= , p=)
聯絡人的 email 跟電話號碼

### 連線資訊 (“c=“)
```c=<nettype> <addrtype> <connection-address>```
一份 session description 必須包含一個或是 media description 至少一個
1. nettype：
    採用網路類型，IN 表示 internet，但未來可能有其他的支援
2. addrtype：
    位址類型，可以是非 IP 家族的
3. connection address：
    依據位址類型，顯示不同的格式

如果是應用在多播的場景下，IPv4 需要在網址後加上 TTL，而 IPv6 沒有 TTL 的概念
在階層式的編碼下，資料串流可能被依照不同頻寬拆分成不同的來源，可以在位址加上來源數量，IP 位置會以連續的方式呈現
例如說

```md
c=IN IP4 224.2.1.1/127/3

這等同於在 media description 中如此表示
c=IN IP4 224.2.1.1/127
c=IN IP4 224.2.1.2/127
c=IN IP4 224.2.1.3/127
```

### 頻寬 (b=)
顯示預計使用的頻寬，根據不同的 bwtype 有不同含意
`b=<bwtype>:<bandwidth>`
1. CT：conference total
    全部 Conference 帶寬上限，可能一個 Conference 包含多個 session，則建議所有 session 使用的帶寬加總合
2. AS：application specifivc

### Timing (t=)
`t=<start-time> <stop-time>`
表示 Session 的開始結束時間
如果沒有指定 stop-time，則 Session 為 unbounded，表示在 start-time 之後 Session 一直保持活躍
如果連 start-time 也沒指定，則表示 Session 是永久存在

建議不要採用 unbounded Session，因為 client 不知道 Session 何時結束，也不知道如何排程

### 重複次數 (r=)
`r=<repeat interval> <active duration> <offsets from start-time>`
這會搭配 t 做使用，例如說一個節目是每次播放一小時，於週一 10am 開播，接著每週二 11am 每週播放持續三個月，則表示法為
```md
t=3034423619 3042462419
r=604800 3600 0 90000
// 或這樣表示
r=7d 1h 0 25h
```
3034423619 是開始時間，也就是某週一 10am
3042462419 是結束時間，也就是開播三個月後的週二 11am

7d 是播放間隔，所以是 7天的秒數
1h 是播放的時長
0 25h 是距離 start time 的時間間隔，也就是(週二 11am - 週一 10am)

如果是以月或年重複的播放，則不能使用 r 表示，需要改用多個的 t 表示播放時間

### 時區 (z=)
這欄位會影響 t 跟 r
`z=<adjustment time> <offset> <adjustment time> <offset> ....`
如果是一個重複播放的 Session，可能會遇到日光節約日，所以要主動減去一小時，又因為不同的國家與地區對於日光節約日的計算不同，所以保留表示的彈性，如
`z=2882844526 -1h 2898848070 0`
在重複播放時間是 2882844526 要減去一小時，但是在 2898848070 就恢復正常

### 加密金鑰 (k=)
如果 SDP 是在已安全以及可被信任的方式傳遞下，可以考慮傳遞加密的金鑰(加密 media stream 而非 session description 本身)，這個欄位不傳達加密的演算法、金鑰類型等，這些全留給採用 SDP的協定去規範

目前支援以下幾種定義
1. `k=clear:<encryption key>`：key 沒有改變過
2. `k=base64:<encoded encryption key>`：用 base64 將 key 編碼
3. `k=uri:<URI to obtain key>`：指名去 URI 拿 key，通常 URI 會走安全通道，例如 HTTPS 等
4. `k=prompt`：雖然 Session 有加密但是 session description 沒有提供 key，用戶要額外去索取

再次強調 SDP 本身要是在安全的情況下才能加 k 欄位

### 屬性 (a=)
```md
      a=<attribute>
      a=<attribute>:<value>
```
屬性值主要用來擴展 SDP，可以用在 session level 補充對 conference 的資訊，也可放在 media level 傳遞 media stream 的資訊，在 SDP 會有若干的屬性值宣告

屬性值有兩種宣告方式
1. Flag概念 (a=<flag>)，例如 a=recvonly
2. 鍵值 (a=<attribute>:<value>)，如 a=orient:landscape

至於如何處理與定義屬性值，有些屬性有定義的含義，其餘則應用程式可以彈性處理

### media description (m=)
```md
      m=<media> <port> <proto> <fmt> ...
```
一份 session description 中可能含有多個 media description，每一份 media description 從 `m=` 開始直到下一個 `m=`或是 session description 結束

1. media
    類別，可以是 audio / video / text 等
2. port
    串流從哪個 port 發送，這會根據 connection infomation (c=) 而決定，對於某些傳輸協定，如 rtp 會使用兩個 port (RTP+RTCP)，所以宣告時會是 `m=video 49170/2 RTP/AVP 31`，表示 RTP 使用 49170 / RTCP 使用 49171；
    如果 c 指定多個 IP 位置，則 port 成一對一映射關係，如
```md
c=IN IP4 224.2.1.1/127/2
m=video 49170/2 RTP/AVP 31
```
    則因為 RTP 一次使用兩個 port，這表示 224.2.1.1 使用 49170、49171，224.2.1.2 使用 49172、49173
3. proto
    指定傳輸協定，常用的有 udp 、 RTP/AVP、RTP/SAVP 等
4. fmt
    媒體格式，會跟著 <proto> 的定義，如果 <proto> 是 udp 則 <fmt> 需要指定 audio / video / text / application / message 一者

# SDP Attributes
1. a=cat:<category>
    用逗點分隔，用來過濾 category
2. a=keywds:<keywords>
    類似於 cat 屬性，透過關鍵字篩選想要的 session
3. a=tool:<name and version of tool>
    表示用來創建 session 工具的名稱與版號
4. a=ptime:<packet time>
    用 ms 表示一個封包中媒體的總時長
5. a=maxptime:<maximum packet time>
    用 ms 表示一個封包中媒體的總時長上限
6. a=rtpmap:<payload type> <encoding name>/<clock rate> [/<encoding parameters>]
    搭配 media type(m=)宣告，補充RTP所採用的編碼方式，雖然 RTP 檔案本身就會包含 payload 格式，但是常見做法是透過參數設定動態改變
    例如說 `u-law PCM coded single-channel audio sampled at 8 kHz`，他的 encode 方式固定只有一種，所以不需要另外宣告rtpmap
```md
m=audio 49232 RTP/AVP 0
```bash 

    但如果是 `16-bit linear encoded stereo audio sampled at 16 kHz`，希望用 RTP/AVP payload 格式 98 的話，就必須另外宣告解碼方式
    
```
m=audio 49232 RTP/AVP 98
a=rtpmap:98 L16/16000/2
```
    rtpmap 可以針對 payload 格式做映射，如
```md
m=audio 49230 RTP/AVP 96 97 98
a=rtpmap:96 L8/8000
a=rtpmap:97 L16/8000
a=rtpmap:98 L16/11025/2
```
    參數對應的參數可以參考 [RTP Profile for Audio and Video Conferences with Minimal Control](https://tools.ietf.org/html/rfc3551)
7. a=recvonly 
    表明單純接收
8. a=sendrecv
    可以接收與發送，此為預設值
9. a=sendonly
    單純發送
10. a=inactive
    不接收也不發送媒體，基於 RTP 系統的即使是 inactive 也要持續發送 RTCP
11. a=orient:<orientation>
    用於白板或是介紹的工具，可以指定 portrait / landscape / seascape(上下顛倒的 landscape)
12. a=framerate:<frame rate>
    video frame rate 最大值，只有 medial level 的 video 類型需要
13. a=sdplang:<language tag>
    SDP 資訊採用的語言，如果有多種語言建議每種語言都拆成獨立的 session description
14. a=fmtp:<format> <format specific parameters>
    用來傳達某些特定格式，且這些特定格式不需要是 SDP 所能理解的

## 安全考量
SDP 常用於 offer/answer 模型的 SIP 中，用來溝通單播的會話機制，當採用這樣的模式時，要記得考量協定本身的安全性

SDP 只是用來描述多媒體會話的內容，接收方要注意 session description 是否通過可信任的管道與來自可信任的來源，否則網路傳輸過程可能遭遇攻擊，必須要自己承擔安全上的風險

常用的傳輸方式是 SAP，SAP 本身提供加密與驗證機制；
不過有些情況下無法採用，例如接收者事前不知道發送者的時候，此時就要特別小心 parse，並注意權限的管控(僅開放有限的軟體可以操作)