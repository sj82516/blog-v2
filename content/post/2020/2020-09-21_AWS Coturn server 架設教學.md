---
title: 'Coturn Server 架設教學 - on AWS'
description: Coturn 是知名的 open source STUN/TURN server，本篇分享如何在 AWS 上架設與遇到的坑，以及設定檔的撰寫等
date: '2020-09-21T08:21:40.869Z'
categories: ['雲端與系統架構', 'WebRTC']
keywords: ['Coturn', 'WebRTC']
---

公司 P2P 通信採用 WebRTC tech stack，近日希望自建 STUN/TURN Server，決定採用 [Coturn](https://github.com/coturn/coturn) 這套知名的解決方案，在 AWS 架設過程遇到一些坑，決定分享如何架設，並分享設定檔如何設定與操作  
以下包含  
1. Coturn 於 AWS 上的架設與測試
2. 介紹設定檔內容
3. 上 Production 的考量  
4. 補充 NAT 與 STUN/TURN 關係   

如果想知道更詳細的協定介紹，請參考
1. [RFC 5398 - STUN](https://yuanchieh.page/posts/2020-09-22_rfc-5389-stun-%E5%8D%94%E5%AE%9A%E4%BB%8B%E7%B4%B9/) 

如果想要用 Container 架設，可以參考我用 docker-compose 架設的方式 [Running Coturn + Promethes + Grafana in Docker](https://github.com/sj82516/coturn-with-prometheus-grafana-on-docker)

## Coturn 於 AWS 上的架設
使用 Ubuntu 18.04 非常簡單，只要以下指令就能啟動 Coturn 
```bash
$ sudo apt-get -y update 
$ sudo apt-get -y install coturn
```

> 強烈建議使用 `Ubuntu 18.04` 而不要用 `Amazon Linux 2`，Amazon Linux 2 要自己處理各種套件的相依性，架設過程花了半天還沒架起來  

> 用 apt-get install 的話，會被限制版本，如果有其他需求，例如支援除了 SQLite 以外的 DB，或是要安裝 Prometheus，建議從 source code build 起，可以參考另一篇文章

安裝後會有幾個 command 能夠使用
1. turnserver  
啟動 STUN/TURN server instance
2. turnadmin  
介面管理後台  
其餘都是測試用工具
3. turnutils_peer  
UDP-only echo server，檢測連線使用
4. turnutils_stunclient  
呼叫 STUN server 並取得回應
5. turnutils_uclient  
可以模擬多人連線 TURN server 並取得回應  

上一步安裝後預設會自行啟動 Coturn，但為了後續的實驗，先把 turn service 關閉
```bash
$ sudo service coturn status
// 如果有在運行，先關閉
$ sudo service coturn stop
```  

接著啟動 turnserver
```bash
$ sudo turnserver
```  
稍微看一下 command line 跳出的訊息，大致說明  
1. file descriptor 上限，這會影響最大連線數，可以透過 `$ sudo ulimit -n {number}`去調整  
2. 支援的通訊協定，預設 STUN 支援 UDP / TCP / DTLS，但因為目前沒有指定憑證，所以 DTLS 不支援  
3. 採用的 Database，預設使用 SQLite，主要用來儲存 admin 資訊 / turn 連線資訊等，同時支援 MySQL / Redis / PostgreSQL / MongoDB，可以自由替換；  
根據 Spec `STUN/TURN Server 處理連線是 State-less`，意即 Database 不是用來儲存連線資料，所以不用擔心會是 bottleneck (如果 Coturn 遵守 Spec 的話)   

看一下有沒有什麼錯誤，cli-password 錯誤可以先忽略   

### 啟動 turnserver  
要測試之前，我們需要先設定 AWS security group，開放以下的 port   
```bash
3478: UDP+TCP // TURN Server 接收 request 的 port 
5394: UDP+TCP  // TURN Server 接收 TLS request 的 port 
49152-65536: UDP+TCP  // 實際連線的 Socket Port range
```  
以上三個都能夠調整，但就先採用預設  

接著啟動 turnserver
```bash
sudo turnserver -v --lt-cred-mech --user hello:world --realm <your domain name> --external-ip <your instance public-ip>
```

以上的參數代表
1. `-v`: 顯示詳細的 log
2. `--lt-cred-mech`: 指定為 long term credential，稍後解釋
3. `--user {username}:{password}`: 搭配 long term credential，指定 username / password  
4. `--realm`: 指定 TURN server 對應的 domain name，提示 client 要採用對應的驗證方式
5. `--external-ip`: 指定 external ip，在 Coturn 文件寫到，如果是在 AWS EC2 上架設 external-ip 只要指定 public ic  

記得要去將綁定 domain name A record 指向 AWS instance    

接著，有幾種測試方法  
#### 1. 使用 Coturn 自帶的 test tool  
```bash
$ turnutils_uclient -T <server ip>
$ turnutils_stunclient <server ip>
```  

第一個會嘗試傳送封包，可以看 packet 的 loss rate 是否為 0 /  
第二個會回傳主機 public ip (如果前面沒有 NAT 的話)，也就是 STUN 最主要的功用  

#### 2. 用瀏覽器開啟 WebRTC samples Trickle ICE  
![](/posts/img/20200922/trickle-ice.png)  
輸入 server domain 時記得要加 `turn:{domain name}`，就可以成功拿到 STUN (srflx) / TURN (relay) 的紀錄   

測試了一下，Chrome / Firefox 不支援 no auth 設定，Chrome 不支援 ip based 的 server   

這樣就完成第一步的設定與測試，接著看 Coturn 的完整介紹與設定  

## 設定檔  
設定檔的預設路徑為 `/etc/turnserver.conf`，也就是等等會修改的文件，可以放在其他地方用 cmd 指定  
也可以從網路上看到官方的預設設定檔 [# Coturn TURN SERVER configuration file](https://raw.githubusercontent.com/coturn/coturn/master/examples/etc/turnserver.conf)

### 驗證  
STUN 的費用很便宜，只有簡單的 request / response，但是 TURN 就非常貴，因為要回放(Relay) P2P 的 media stream，所以 Bandwidth 相當驚人，這時候就需要加上帳號密碼的檢查  

TURN 支援兩種模式，建議是兩者選其中一者  
#### long term credential  
長期憑證屬於靜態類型，也就是 Client / Server 共用固定的帳號密碼，例如上述的 hello:world  
在設定檔中
```bash
lt-cred-mech
user=hello:world
user=hello2:world2
....
```
#### short term credential
如果希望發給 Client 短期的憑證，或是希望多一層授權的流程例如從 API Server 給予等等，可以使用短期憑證  

TURN 實作的方式是 Client / Server 共享一個固定的 secret key，接著使用 `HMAC_SHA1 將 username hashed`，username 的前半段是 unix timestamp  
所以 TURN server 收到後，從 username 可以看出過期時間，透過 HMAC_SHA1 可以確保是由合法的 Client 所送出   
設定檔寫法  
```bash
use-auth-secret
static-auth-secret={secret}
```

Nodejs 版本的產生規則如下，參考自 [CoTURN: How to use TURN REST API?](https://stackoverflow.com/questions/35766382/coturn-how-to-use-turn-rest-api/35767224#35767224)
```js
var crypto = require('crypto');

// name 隨便填沒有關係
function getTURNCredentials(name, secret){    
    var unixTimeStamp = parseInt(Date.now()/1000) + 24*3600,   // this credential would be valid for the next 24 hours
        username = [unixTimeStamp, name].join(':'),
        password,
        hmac = crypto.createHmac('sha1', secret);
    hmac.setEncoding('base64');
    hmac.write(username);
    hmac.end();
    password = hmac.read();
    return {
        username: username,
        password: password
    };
}
```

### 網路設定  
網路設定就放在一塊看
```bash
external-ip=<public ip>
fingerprint
realm=turn.yuanchieh.page
```
以上是必須設定的參數
1. external-ip:   
TURN server 的 public ip，看文件完整的設定是 `external-ip=<public ip>/<private ip>`，但因為在 AWS 上 EC2 處於 NAT 之後，所以只能放 public ip  
2. fingerprint:  
主要是 TURN Server 用來區分 packet，後續的 Spec 會有更詳細介紹  
3. realm:  
設定為自己指向 TURN Server 的 domain name，文件表示 TURN Server 可以指定多個 realm，每個 realm 有各自的 user 權限管理，Client 表明所屬的 realm 就能用對應的 user 檢查   
 
其餘還有非常多的設定，例如說  
1. 是否要開放 UDP / TCP / DTLS / stun-only  
2. 設定不同的 port / port ranage  
3. 指定的 DB / Log 等等  
3. 每次連線 session 的時長 / 每個 user 的連線 quota 等等    
這些細部的設定可以在慢慢看或是保留預設即可    

以下是我測試過成功的設定檔
```bash
external-ip=52.72.33.185
verbose
fingerprint
use-auth-secret
static-auth-secret=north
realm=turn.yuanchieh.page
```

啟動 turnserver 時透過 `-c` 指定 turnserver.conf 的位置，完成後建議在使用測試工具測試過  

## Sample Code  
為了更方便測試 TURN Server，自己寫了一個 Sample Code [Connection through self-hosted TURN server](https://github.com/sj82516/webrtc-turn-server-test)，或是直接看 Demo Page [https://webrtc-turn-server-test.vercel.app/](https://webrtc-turn-server-test.vercel.app/)，輸入對應的帳號密碼，會主動生成對應的 iceServers   

## Go To Production
準備上正式環境時，還有監控以及可用性的調整
### 監控   
2020/12/04更新：目前 4.5.2 可以支援 `prometheus` 囉，可是只有支援 Debian，其他平台尚未支援，另外要注意直接用 `apt-get install coturn 版本目前是不支援 prometheus，需要自己手動編譯喔`
```bash
Version 4.5.2 'dan Eider':
	- fix null pointer dereference in case of out of memory. (thanks to Thomas Moeller for the report)
    - merge PR #517 (by wolmi)
		* add prometheus metrics
```  
> Warning: 撰文時開啟 prometheus 會有記憶體問題，建議先不要使用喔，詳見 github issue https://github.com/coturn/coturn/issues/666

~~看到文件的範例以及設定檔支援 `prometheus` 這套開源的監控工具，但可惜實測下來暫時無法使用(4.5.1.2)，雖然說有相關的 branch 已經 merged 但是 Issue 還是開著 [support export metrics to prometheus #474](https://github.com/coturn/coturn/issues/474)~~  

### 可用性  
如果只有單台 TURN server 掛掉導致服務中斷就很慘了，官方有幾個可用性/Load Balance 作法  
1. TCP Level LB Proxy:   
需注意如果有使用 TURN 功能，必須確保同一個 Client 持續連到同一台 TURN Server，否則普通的 TCP LB 即可  
2. DNS:  
透過 DNS Round-Robin 紀錄，讓 Client 連到對應的 TURN Server  
3. 內建的 ALTERNATE-SERVER:  
需要在所有的 TURN Server 之前建一台 LB，這台 LB 按照流量回給 Client ALTERNATE-SERVER 的錯誤，Client 就會按照指定的 Server 去走，達到 LB 的效果   

看來看去，採用 DNS 比較方便，AWS Route53 支援定期檢查 Server 狀態，只會回傳健康的 Server，同時能採用 Latency based 或是 Region based 的 DNS 紀錄，讓全球部署更加方便  

## NAT 介紹與 STUN/TURN 使用  
先前有提到因為 NAT 關係，所以要建立 P2P 連線會需要 STUN Server 的幫助，但有一種 NAT 是必須透過 TURN Server，以下解釋這部分的狀況  

[Wiki NAT 網路位址轉換](https://zh.wikipedia.org/wiki/%E7%BD%91%E7%BB%9C%E5%9C%B0%E5%9D%80%E8%BD%AC%E6%8D%A2)  
[NAT的四种类型](https://blog.csdn.net/eydwyz/article/details/87364157)

簡單整理上面文中的重點
```bash
ClientA (192.168.9.1:3000) ---> NAT (8.8.8.8:800) ---> Server1 (1.1.1.1:1000)
```
ClientA 預先與 Server1 取得連線，此時假設 Server2 (2.2.2.2) 想要從 (8.8.8.8:800) 送資料給 ClientB
1. 完全圓錐型NAT    
允許
2. 受限圓錐型NAT     
必須 ClientA 也送過請求給 Server2 (2.2.2.2)才可以
3. 埠受限圓錐型NAT      
必須 ClientA 也送過請求給 Server2 (2.2.2.2:1000)才可以，相較於上者 Port 必須固定
4. 對稱NAT   
不允許      

所以在 WebRTC 下，如果 Client 在完全圓錐型NAT，任一方發請連線都可以；  
如果是在二、三種，則 Client 必須雙方同時發送請求，才符合 NAT 轉發條件；  
第四種則不允許直接的 P2P  
