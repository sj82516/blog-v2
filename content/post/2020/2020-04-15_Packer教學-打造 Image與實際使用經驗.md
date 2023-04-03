---
title: 'Packer教學-打造 Image與實際使用經驗'
description: 使用 Packer 打造建制步驟透明的 Image 流程
date: '2020-04-15T02:21:40.869Z'
categories: ['雲端與系統架構']
keywords: ['Infrastucure as Code', 'Hashicorp', '技術教學', 'Packer']
---

當我們在利用 Vagrant 建立開發環境，或是雲端上準備部署時，都需要用 VM 執行指定的 Image，準備好環境後開始執行應用程式，但是管理 Image 是一件有點麻煩的事，尤其是要記錄每個步驟到底做過了什麼，又或是要整合入持續部署 CD 的環節都不這麼友善    

Packer 用 json 檔指定基礎 Image / Provision 步驟 / 指定平台打造對應的 Image，例如可以同時針對 AWS / DigitalOcean / vmware 等不同平台建立，透過 command line 就可以建立 Image   

以下教學專注在 AWS 的 Image 建立上，並分享實際使用經驗   

Packer 在建立 AWS Image 時會需要開機器，自動上傳的 AMI 並關閉機器，Packer 開立的機器型別時 `t2.micro` 有免費的額度，但如果超過可能會有額外的一點點費用，取決於 build image 的次數與時間；  
另外 AWS AMI 儲存於 S3，也會有額外的成本，Packer 只負責建立 Image，後續的管理要自己處理  

之前在公司建立 Image 也是要先開新機器，動手處理完壓成 Image，缺點是整個操作步驟是不透明，雖然可以翻 bash_history 但還是不這麼容易，如果文件漏寫後人維護就會很痛苦；  
用 Packer 就解決了 `Image 建立過程不透明`、`每次都要開關機器`的困擾   

## 安裝
[Packer 下載連結](https://www.packer.io/downloads.html)

## 指定基礎 Image
可以在 [AWS Marketplace](https://aws.amazon.com/marketplace) 上找想要採用的 Image，或直接指定 ami-id，例如我在 us-east-1 使用 Ubuntu 18.04 LTS - Bionic 的 ami-id 是 `ami-0d03e44a2333dea65`，要找到 ami-id 其實有點小麻煩，可以參考下列步驟

![](/posts/img/20200415/amiid.png)  
先找到 Image，點進去後按 "Continue to Subscribe" -> "Continue to Configuration" (沒截圖)，接著選定區域就能看到 ami-id 了  

## Packer 設定檔
Packer 的設定檔是 json 格式，內容相當簡單明瞭，主要四塊   
- `variables`  
文件有說為了變數管理方便，後續設定檔的參數全部都要定義在這裡  
- `builders`  
指定的平台與對應的建立方式，如 AWS 要指定 credential / region / vpc 等  
- `provisioners`  
Image 要執行的設定，可以用 shell 執行 / file 上傳檔案，或是其他的 provisioning 工具如 Ansible 等  
- `post-processors`  
產生 Image 的後處理，可以壓縮上傳到指定位置等，這邊先略過  

以下檔案是建立 API server image，基於 ubuntu 安裝 Nodejs 並將 Server 檔案上傳至指定路徑執行，所以的設定檔在github 上 [packer_get_started](https://github.com/sj82516/packer_get_started)  

```json
{
    "variables": {
        "aws_access_key": "{{env `AWS_ACCESS_KEY_ID`}}",
        "aws_secret_key": "{{env `AWS_SECRET_ACCESS_KEY`}}",
        "region": "us-east-1"
    },
    "builders": [{
        "type": "amazon-ebs",
        "access_key": "{{user `aws_access_key`}}",
        "secret_key": "{{user `aws_secret_key`}}",
        "region": "us-east-1",
        "source_ami": "ami-0d03e44a2333dea65",
        "instance_type": "t2.micro",
        "ssh_username": "ubuntu",
        "ami_name": "packer-example {{timestamp}}"
    }],
    "provisioners": [{
        "type": "shell",
        "script": "init.sh"
    }, {
        "type": "shell",
        "inline": [
            "ls",
            "pwd"
        ]
    }, {
        "type": "file",
        "source": "server",
        "destination": "~/server"
    }, {
        "type": "shell",
        "script": "start.sh"
    }]
}
```
在 json 檔中，變數取用都是以 `{{}}` 雙括號括住，只有在 `variables` 中可以用 `env` 指定使用環境變數，也可以留空在 command line 執行時指定，如 `$ packer build -var 'aws_access_key=YOUR ACCESS KEY' ...`     
來源還可以從 Consul / Vault 等地方，可以參考文件  

後續階段要讀取就要用 
```bash
{{user `aws_access_key/`}} 
```
的形式讀取 variables 中的參數   

#### builders
可以看到 `builders` 是以陣列形式，這邊可以指定多個建立的目標，例如增加 vmware / virtualbox 等等，Packer 會併發建立 Image    

#### provisioner
常用搭配 `shell` / `file` 執行 shell script 或是上傳本地端資料到 server上，可以指定在某些目標下才複寫，如
```json
{
    "type": "shell",
    "script": "script.sh",
    "override": {
        "vmware-iso": {
            "execute_command": "echo 'password' | sudo -S bash {{.Path}}"
        }
    }
}
```

Packer 大概就是這麼簡單! Do one thing and do it well.     
執行的時候照樣 hashicorp 工具的操作方式，`$packer validate` 先檢查語法正確性，接著 `$packer build` 就完成囉   

最後看一下 Packer 每次 Build 所產生的 instance    
![](/posts/img/20200415/packer-tm.png)  

## 使用經驗談
以下分享一些實際遇到的問題與解決辦法
### 使用 AWS build Image 偶爾遇到 package 安裝失敗的問題
症狀大概是 Packer 在執行 `$sudo apt-get install` 時偶發說 package not found，但偶爾可以，且進去機器安裝網路狀況都是沒問題的

問題主要出自於開啟 AWS 機器時有可能網路還沒有好，所以才會是偶發性，解決辦法就是確認網路好才開始執行 shell script，詳細請參考 Packer Github Issue [Option for builder to wait on cloud-init to complete](https://github.com/hashicorp/packer/issues/2639)  

在 provisions 第一步加入以下 script (答案摘錄自上方 issue 回覆)
```shell
provisions:[{
    "type": "shell"
    "inline": "/usr/bin/cloud-init status --wait"
}, 
....
]
```
### 希望在 launch 機器時就啟動服務
這比較偏原有的系統 service 設定，使用 ubuntu 的話可以設定 systemd service，並指定 target 就可以在 launch 機器時啟動，詳細參考 
[How To Use Systemctl to Manage Systemd Services and Units](https://www.digitalocean.com/community/tutorials/how-to-use-systemctl-to-manage-systemd-services-and-units) 與  
[Understanding Systemd Units and Unit Files](https://www.digitalocean.com/community/tutorials/understanding-systemd-units-and-unit-files) 兩篇來自 DigitalOcean 的好文，預計這篇會在產出一篇文章 (挖坑)   
### 希望在 launch 機器後取得機器資訊與 IP
這應該是蠻實用的需求，像是綁定一些網路服務，會需要在 config 檔指定機器的 IP 等，須注意這邊要等到 launch 後才綁定，而不是在 Packer Build 的機器產生，所以會結合上一點，指定 script 在機器啟動後才執行

1. 取得 AWS 機器資訊
2. 取得 IPv6
3. 修改文件