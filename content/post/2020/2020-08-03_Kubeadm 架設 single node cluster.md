---
title: 'Kubeadm 架設 single node cluster 與 remote access dashboard'
description: 初步嘗試 Kubernetes 但不想直接上 Cloud 託管服務，使用 Kubeadm 就可以用單機運行 Cluster 學習最基本的設定與觀念
date: '2020-08-03T08:21:40.869Z'
categories: ['雲端與系統架構']
keywords: ['Kubenetes']
draft: true
---

覬覦 Kubernetes 好一陣子了，在本地端用 Minikube 跑了一些教學後，決定在公司內部的小專案試運行看看，主要是公司內部大大小小有十幾個獨立的 script，主要負責一些資料的統整 / 內部服務檢查等等，執行的頻率或是 script 環境都大不相同  
目前是用土炮的 crontab 決定運行頻率，log 就打到 local file 上，另外運行一個服務監控 Agent 是否有按照指定頻率執行  

這樣有幾個缺點
1. 要查看機器上有哪些script，需要手動進去機器，如果要調整頻率也很不方便
2. 要看 script 執行的結果很麻煩，要看即時 log 也很不方便
3. 執行環境髒亂，不同的 nodejs 版本 / python 環境互相干擾  

所以才想說透過 Kubernetes + dashboard，解決上述的問題，只是在單機運行上遇到比我想像中還要多的問題，尤其是 dashboard / proxy 的網路連線問題   
一開始以為用 `minikube + kubeproxy` 就能夠很快速完成，後來發現要 `遠端連線 dashboard` 是最麻煩的事情，所以才改用 `kubeadm`，過程也遇到一些網路設定與安裝的問題

以下教學適用於知道 kubectl 基本操作 / pod、service、編寫 yaml 檔  
環境使用 
- AWS Amazon Linux2 on t2-medium (官方建議 2 cpu + 2gb 以上的硬體環境)  
- kubeadm 架設
- (法一) 用 Proxy + SSL tunnel 遠端連線 dashboard
- (法二) 將 dashbarod service 改成 NodePort 直接
- (法三) 用 https 遠端連線 dashboard

## 初始化環境
### 安裝 Docker 或其他 CRI(Container Runtime Interface)  
方便起見，這邊安裝 Docker，需要注意 `不要按照 Docker 官網的安裝步驟`，主要是不要增加 Docker 的 yum repo，因為最新版的 Docker-ce 需要較高的 container-selinux 版本，會遇到以下錯誤
```bash
Error: Package: containerd.io-1.2.13-3.2.el7.x86_64 (docker-ce-stable)
Requires: container-selinux >= 2:2.74
```
直接執行即可
```bash
$ sudo yum install docker
$ sudo systemctl start docker
```

### 安裝 Kubernetes 環境
[Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)  
以上步驟就是 copy paste，基本沒有遇到問題

[Creating a single control-plane cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)  
接著就是要設定 cluster 部分，上一步總共安裝了 3 個套件
1. kubectl  
管理 Cluster 工具
2. kubeadm  
管理工具，跟 Networking / Nodes 等硬體環境架構相關 
3. kubelet  
API Server，主要用來內部溝通用，像是部署 Pod 等  

需注意要運行 Cluster 必須另外安裝 Network add-on，用於 Nodes 之間的溝通，這邊選用蠻多人推薦的 [Calico](https://docs.projectcalico.org/getting-started/kubernetes/quickstart)，以下為安裝步驟
```bash
$ sudo kubeadm init --pod-network-cidr=192.168.0.0/16
$ mkdir -p $HOME/.kube
$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config

$ kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml

$ kubectl taint nodes --all node-role.kubernetes.io/master-
```
kubeadm 啟動時有幾個值得注意的參數
1. `pod-network-cidr`  
Pod 內部溝通的 IP 分配位址，每個 Pod 都會 Assign 獨立的內部 IP
2. `control-plane-endpoint`    
建立 HA Cluster 指定的 Endpoint  
3. `apiserver-advertise-address`    
用於其他 Node 決定加入 Cluster 時，所需要呼叫的 API Server 位址  

因為是建立 Single Node Cluster 所以後兩者可以忽略

> `kubectl taint nodes --all node-role.kubernetes.io/master-` 預設 Master Node 不會被分配到 Pod，但因為我們是用 One Node Cluster 所以要關閉此功能

檢查 Node 是否已經開始運作
```bash
$ kubectl get nodes

$ kubectl describe nodes ip-XXX-XXX-XXX-XXX.ec2.internal
```
預計應該要是 Ready 的狀態，有問題用 `describe` 查詢  

接著安裝 Dashboard
```bash
$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml

$ kubectl get po --all-namespaces
```
檢查是不是所以的 Pod 都在 Running 狀態

### 遠端 Access Dashboard  
確認上述都沒問題後，參考此篇教學 [Creating sample user](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md)，先幫 Dashboard 建立 User

參考教學，需要建立兩個 yaml 檔，第一步建立 `admin-user`，第二步綁定權限(暫時給予全部權限)，並執行
```bash
$ kubectrl apply -f {File}
```

接著取的 Token 備用
```bash
$ kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep admin-user | awk '{print $1}')
```

#### (法一) kubectl proxy + SSL Tunnel
預設 Dashboard Service 是以 `Cluster-Ip` 型態，也就是只有 Cluster 內部才能夠存取，連機器本身用 localhost 都無法連線  
所以使用 `$ kubectl proxy`，讓 localhost 也能夠存取 Kubernetes 的 API-Server  

接著就能夠從 `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/` 進去 Dashboard 頁面

以上操作都是在 remote machine 上，確保 proxy 持續運作中，接著回到 host machine
```bash
[host]
$ ssh -i {Key} ec2-user@{Server Ip} -L 8001:localhost:8001
```  
透過 ssh tunnel，將 host machine 的 8001 綁定到 remote  machine 的 8001，接著在 host machine 打開瀏覽器輸入上面的網址就也能看到 Dashboard 了  

這個方法的缺點是 remote machine 必須讓 proxy 一直運行，且 host machine 還要先開啟 ssl tunnel 才能在瀏覽器查看有點麻煩  

#### (法二) 將 dashbarod service 改成 NodePort
Dashboard Service 預設是 ClusterIp，所以不能直接連線，直接更改 config 成 NodePort 就能從 `https://{public ip}:{NodePort}` 查看囉

```bash
$ kubectl -n kubernetes-dashboard edit svc kubernetes-dashboard
$ kubectl get service --all-namespaces
```
第一步會跳出預設編輯器，找到 ClusterIp 改成 NodePort 即可
第二步查看 NodePort 綁定到 remote machine 的哪一個 IP，Port 範圍應該是 30000 起跳  

## 後記

