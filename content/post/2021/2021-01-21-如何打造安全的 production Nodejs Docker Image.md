---
title: '如何打造安全的 production ready Node.js Docker Image'
description: 近日常把舊有的 Node.js 專案打包成 Docker Image 部署，過程中不斷思考怎樣的打包過程才是安全、有效率的，分享一些好文與發現
date: '2021-01-21T08:21:40.869Z'
categories: ['雲端與系統架構']
keywords: ['Docker', 'Node.js']
---

要打造一個「可以動的 Docker Image」很簡單，參考 Node.js 官方文件 [Dockerizing a Node.js web app](https://node.js.org/en/docs/guides/node.js-docker-webapp/) 就可以產出一個將近 `1GB` 的 Docker Image    
```bash
FROM node:14

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./

RUN npm install
# If you are building your code for production
# RUN npm ci --only=production

# Bundle app source
COPY . .

EXPOSE 8080
CMD [ "node", "server.js" ]
```  
就開始想  
1. 這樣安全嗎？
2. 可以打造更輕量、更好 ship 的 Image 嗎？

後來找到這一篇文章[10 best practices to containerize Node.js web applications with Docker](https://snyk.io/blog/10-best-practices-to-containerize-node.js-web-applications-with-docker/)覺得十分實用，也解決安全性上的疑慮，以下摘要重點  

![daily](/post/img/20210121/synk_docker.png)  

## 1. 選擇正確的 Base Image 並透過 Build Stage 精簡產出
> tldr; 
> 1. 採用 alpine 或 -slim 版本的 base image
> 2. 用 sha256 指定 base image 版本避免異動
> 3. 支援多階段，可以前期 build 用比較大的 base image，最後產出在使用精簡的 base image
> ```bash
> FROM node:latest AS build
> ....
> # --------------> The production image
> FROM node:lts-alpine@sha256:b2da3316acdc2bec442190a1fe10dc094e7ba4121d029cb32075ff59bb27390a
> ....
> COPY --from=build /usr/src/app/node_modules /usr/src/app/node_modules
> ....
> ```  
> 

進入 docker hub node.js 官方 image，可以看到玲琅滿目的版本，除了對應不同的 node.js 版本，底層的 os 可以分成幾種
1. stretch: 基於 debian 9  
2. bulter: 基於 debian 10  
3. alpine: 基於 alpine linux  

坦白說目前還不太理解 debian 9 / 10 真正的差異，而 alpine linux 目標是打造最輕量的 container os，最大差異在採用 musl libc 取代 glibc，如果使用的 js 套件有利用到 libc 可能會有問題  

而帶有 `-slim` 結尾則是代表該 image 是最輕量可運行 Node.js 的 container os，也是官方建議在生產環境採用  
例如說 `node:14.15.4-stretch 尺寸 942MB` vs `node:14.15.4-stretch-slim 尺寸 167MB`，前者連 build 工具都有包含如 python / node-gyp 等，這導致尺寸差異非常巨大  
安裝越多工具的 Image，導致的潛藏性安全漏洞就越多，所以正式環境運行盡量採用 slim 版本  

所以最棒的是在第一階段採用完整 Image 方便 build node_modules，最後階段產出用精簡 Image 確保運行時沒有多餘的工具

## 2. 確保只安裝 production 需要的 node modules 並指定 NODE_ENV 為 production  
> 透過 `RUN npm ci --only=production` 只安裝 dependencies 而沒有 dev_dependencies 開發用的套件  

npm ci 與 npm install 看似都在安裝套件但有很大的差異；  
**npm ci** 只讀取 lock file，並用 package.json 做比對，如果 lock file 與 package.json 版本不合會噴出錯誤，`最適合用在要穩定且強一致的套件版本要求`   
**npm install** 則是讀取 package.json，並透過 lock file 做安裝的版本指定，如果有套件沒有出現在 lock file 中，則 npm 直接安裝  

運行環境，根據 Node.js 的不成文規定，請指定`NODE_ENV=production`，各個套件都會針對 production 進行優化，另如文中舉例 express.js 會在生產環境加入頁面 cache 機制  

## 3. 不要用 root 運行 container!!  
> 記得加入 `USER node` 切換使用者，並記得 COPY 時要給予使用者相對權限 `COPY --chown=node:node . /usr/src/app`  

這很重要，也很容易忘記，給予用戶不多不少的權限一直是安全性的基本準則，預設 docker container 內是以 root 運行 process，但如果不小心應用程式有漏洞，甚至有可能讓駭客跳脫 container context 獲得 host root 權限  

## 4. 正確接收程序中斷事件與優雅地退出
> 採用 dump-init 直接啟動 Node.js process
> ```bash
> RUN apk add dumb-init
> CMD ["dumb-init", "node", "server.js"]
> ```
> 並記得在 Node.js 中偵測事件
> ```bash
> process.on('SIGINT', closeGracefully)
> process.on('SIGTERM', closeGracefully)
> ```
>


伺服器長時間運行時，總會遇到版本更新的時候，最理想的做法是讓中斷流量並讓程序完成剩餘工作後優雅退出，但如果採用的方式錯誤 Docker Container 會無法收到系統中斷的事件 `SIGKILL` 、`SIGTERM` 等  

以下是幾種常見的 Container 執行指令，但分別有一些問題
#### 1. CMD "npm" "start"  
這會遇到兩個問題
1. 透過 npm 啟動 Node.js process，但是 `npm 不會正確 pass 所有的系統中斷到 Node.js process 上`
2. `CMD "cmd" "params" ..` 與 `CMD ["cmd", "params"]` 是不同的，前者是先啟動 shell 再去執行後面的 cmd；而後者則是直接執行 cmd，最直接的差異就是 `PID 1 是 shell 還是 cmd`，透過 shell 同樣有可能不會收到全部的系統中斷  

#### 2. CMD ["node", "index.js"]
優化上面的指令，改由直接啟動 node.js 少了 npm 與 shell，這會遇到另一個問題 `linux 對於 PID 1 的程序有特別的處理`，因為 PID 1 代表此程序要負責系統的初始化，所以 Kernel 會有額外的處理機制，實際的影響有
1. 一般的程序收到 `SIGTERM` 後 Kernel 會有預設的結束處理，但是 `PID 1 沒有預設終止處理，也就是收到後沒有主動退出就不會退出`  
2. 如果有 orphan process 會被主動掛載到 PID 1 之下，但一般的 process 不會去處理 orphan process，會留下很多 zombie process

根據 Node.js Docker 小組建議，不要讓 Node.js 運行在 PID 1 上
> Node.js was not designed to run as PID 1 which leads to unexpected behaviour when running inside of Docker. For example, a Node.js process running as PID 1 will not respond to SIGINT (CTRL-C) and similar signals

#### 最終解法：透過 init process 再去啟動 Node.js 
最後用 dumb-init，這套由 yelp 釋出的啟動 process，會正確將所有的系統中斷都 pass 給所有的 child process，並且在退出時清除所有的 orphan process

[Introducing dumb-init, an init system for Docker containers](https://engineeringblog.yelp.com/2016/01/dumb-init-an-init-for-docker.html)  

市面上還有不同的選擇，可以參考此篇 [Choosing an init process for multi-process containers](https://ahmet.im/blog/minimal-init-process-for-containers/)

## 5. 正確處理 Build 階段使用的機敏資料
> 善用 multi stage，讓機敏資料不要外洩在 Image 當中，並使用 mount secret 同步機敏資料
> ```bash
> RUN --mount=type=secret,id=npmrc,target=/usr/src/app/.npmrc npm ci --only=production
> ```
> 

如果有一些機敏資料是在 Building 階段所需要，例如要去 private github 拉 repo 的 .npmrc 等資料，需要被妥善處理，常見的錯誤示範有
1. hard code 寫死
2. 採用環境變數，在 docker build 時指定，但如果用 docker history 還是會被發現    

奇怪的是我並沒有在 Docker 文件 [Use bind mounts](https://docs.docker.com/storage/bind-mounts/) 看到 --mount type=secret 的說明，但確實有在官方教學看到 [Build images with BuildKit](https://docs.docker.com/develop/develop-images/build_enhancements/)

## 結語
最終的產出會長這樣
```bash
# --------------> The build image
FROM node:latest AS build
WORKDIR /usr/src/app
COPY package-*.json /usr/src/app/
RUN --mount=type=secret,id=npmrc,target=/usr/src/app/.npmrc npm ci --only=production
 
# --------------> The production image
FROM node:lts-alpine
RUN apk add dumb-init
ENV NODE_ENV production
USER node
WORKDIR /usr/src/app
COPY --chown=node:node --from=build /usr/src/app/node_modules /usr/src/app/node_modules
COPY --chown=node:node . /usr/src/app
CMD ["dumb-init", "node", "server.js"]
```