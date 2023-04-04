---
title: 如何用解除授權攻擊強迫裝置斷線 Wifi 連線
description: 內容參考 @Brandon Skerritt 的創作，以下僅為個人轉譯成中文，執行平台從作者的 Kali Linux 改為 Mac，紀錄一些執行的細節。
date: '2019-01-20T01:12:22.083Z'
categories: ['網路與協定']
keywords: []

  
---

[**Forcing a device to disconnect from WiFi using a deauthentication attack**](https://hackernoon.com/forcing-a-device-to-disconnect-from-wifi-using-a-deauthentication-attack-f664b9940142)

內容參考 @[Brandon Skerritt](https://hackernoon.com/@brandonskerritt) 的創作，以下僅為個人轉譯成中文，執行平台從作者的 Kali Linux 改為 Mac，紀錄一些執行的細節。

### 緣由

[https://www.itcodemonkey.com/article/4742.html](https://www.itcodemonkey.com/article/4742.html)

當 Suppliant(終端裝置) 希望與 AP 建立 Wifi 連線時，需要經過四次 Handshake，而在第三次交握時 Suppliant 會輸入 Wifi密碼，這個 Wifi 密碼會經過加密，如果密碼正確則成功建立連線，反之則斷開連線。

而 deauthentication attack 利用這樣的交握特性，在第三步假裝是 AP 回覆給 Suppliant驗證錯誤，因此強迫裝置斷開 Wifi 連線，這並不是透過什麼漏洞攻擊，而是 Wifi 傳輸協定原有的機制。

這樣的機制使得 Wifi 非常的不安全，deauthentication attack 可以中斷任意裝置的 Wifi連線，這往往只是攻擊的第一步；  
一般裝置 Wifi 斷線後，會用同樣的密碼再次嘗試與 AP建立連線，而此時 Wifi 無線通訊的機制，會使得相鄰的用戶也可以偷聽到這些封包，進而拆解封包，從中暴力破解 AP 的密碼；  
又會是邪惡的用戶偽造一個假的 AP，其他人不明所以就傻傻的連線，透過簡單的釣魚，就可以完成 Middle man attack。

看似邪惡的工具，但不要用在破壞也能用在自保上，在 2015 年爆出多起 Airbnb 透過 Wifi Cam 偷窺住戶，作者寫了一個 script 可以自動斷開所有的 Wifi Cam

[**Detect and disconnect WiFi cameras in that AirBnB you're staying in**](https://julianoliver.com/output/log_2015-12-18_14-39)

同作者還寫了可以自動斷開 Google Glass 的 Script

[**Find a Google Glass and kick it from the network**](https://julianoliver.com/output/log_2014-05-30_20-52)

#### *警告

這項有力的工具可以用來保護個人隱私，但作者不鼓勵用於非法或是惡意的攻擊!

### Deauthentication Attack

首先要確認兩件事

1.  準備要斷開的裝置
2.  該裝置連結的 Router

原本是希望找到對應的 Cmd Tool 在 Mac 平台上，但後來參考此文章

[**WPA wifi cracking on a MacBook Pro with deauth**](https://louisabraham.github.io/articles/WPA-wifi-cracking-MBP.html)

可以直接用 [**JamWifi**](https://github.com/unixpickle/JamWiFi)  GUI Tool，打開後開始 Scan，Scan 後可以找到 AP 並透過 MAC Address 指定裝置斷線，我在家裡嘗試過是可行的。

![](/post/img/1__EugN6S__T4PU5Bd5__9eaJ2w.jpeg)

在同篇文章中有提到後續破解 Wifi 密碼的方式，透過 deauthentication attack 斷開裝置，接著開 `tcpdump`  監聽所有的封包；  
接著用 `cap2hccapx`將 tcpdump 的資料轉換格式；  
最後用 `hashcat`  類似暴力破解的方式，嘗試還原被 hashed 過的密碼，這裡他的演算法可以輸入 wordlist，網路上有人提供常見的 wifi 密碼，雖然說 wifi 密碼的完全字元(a-zA-Z0–9)可能性是 62 ^ 8 以上，但是利用人類的惰性，其實可能的組合沒有這麼多，這可以省下非常大量的計算時間。

[**berzerk0/Probable-Wordlists**  
_Version 2 is live! Wordlists sorted by probability originally created for password generation and testing - make sure…_github.com](https://github.com/berzerk0/Probable-Wordlists/tree/master/Real-Passwords/WPA-Length "https://github.com/berzerk0/Probable-Wordlists/tree/master/Real-Passwords/WPA-Length")[](https://github.com/berzerk0/Probable-Wordlists/tree/master/Real-Passwords/WPA-Length)

可以看一下自己的密碼有沒有在上面 XD

> 設定密碼不要用 12345678 或是 0000000 ，另外要記得常換密碼