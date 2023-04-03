---
title: 初試 Terraform - 基本介紹與用程式碼部署 Lambda (下)
description: >-
    Terraform 提供跨雲平台的 Infrastructure as code 方案，用 DSL 編寫檔案管理雲端架構
date: '2019-11-04T00:21:40.869Z'
categories: ['雲端與系統架構']
keywords: ['cloud', 'terraform']
---

# 介紹
[上一篇](https://yuanchieh.page/posts/2019-10-31_try-terraform/)完成了用 Terraform 實作單一區域定時執行 Lambda 的部署，這一篇將轉成 module，並使用 for loop / if condition，一次部署到多個區域，同時探索 Terraform 本次教學沒有用到卻也值得留意的功能

# Module - 模組化
先前提到，只要在專案根目錄下，任何的 `*.tf` 檔案都是 root module，在 `$terraform apply` 時都會被執行；  
如果要獨立出個別的模組，可以放在不同專案下，透過放在 github、s3 等 remote 方式載入，又或是單純獨立出一個資料夾放置，用路徑的方式載入，先重整原本的專案資料夾架構

```md
---
  |--- main.tf // 進入點
  |--- input.tf // 定義參數
  |--- output.tf // 定義輸出
  |--- modules // 存放所有的路徑
     |--- lambda-api-test 
        |--- main.tf // module 的進入點
        |--- input.tf // module input
        |--- lambda-function.zip
        ... 上一篇所有的資料
  |--- global
     |--- global.tf
```

重新思考之後要部署的架構，`global` 用來存放全域的資源，例如說 IAM Role / DNS 等資源，這部分會需要先被創立，方便後續的資源綁定；

接著把各區域相同的架構包成 module 放置在 modules 底下，程式碼移除 IAM 資源，其餘大多雷同，只是要注意如果有用到 file 相關的參數，要改變路徑位置為 `${path.module}`，否則會找不到資源；


```HCL
resource "aws_lambda_layer_version" "lambda-layer_fetch" {
  filename   = "${path.module}/lambda_layer_payload.zip"
  layer_name = "lambda_layer_name"

  source_code_hash    = "${filebase64sha256("${path.module}/lambda_layer_payload.zip")}"
  compatible_runtimes = ["nodejs10.x"]
}
```

如果要引用 module，也就是 `./main.tf` 的內容為

```HCL
locals {
  region = "us-east-1"
}


provider "aws" {
  profile = "default"
  region  = "${locals.region}"
}

module "lambda-api-test_us-west-2" {
  source     = "./modules/lambda-api-test"
  # depends_on = ["aws_iam_role.iam_for_lambda"]

  region                     = "${local.region}"
  lambda_variables-SLACK_URL = "slack url"
  iam_role_name              = var.lambda_role_name
}
```

宣告 module 並透過相對路徑指定 source，其餘的參數對應 module 的 input；  
要注意目前 v0.12 `module 不支援 depends_on`，這也是為什麼 IAM Role 創立要獨立到 global.tf 先執行，不然目前無法先建立 IAM Role 再建立 module

### locals 
locals 用來宣告區域變數，就像是寫程式中僅用於限定範圍內的變數，後續透過 `local.{var}` 取用

# data source
如果有需要跨檔案路徑存取資源，又或是讀取某些資料例如 AWS 所有的可部署區域列表，又或是執行某些指令如呼叫 lambda，可以宣告 data source；  
data source 跟 resource 最大差別是 data source 是`唯讀`，並大多數執行於 apply 階段之前，後續的資源建立都可以使用；  
而 resource 則是會被 `$terraform` 指令影響而增加、刪除、修改資源。

看到 data source 讓我十分的興奮! 因為這代表我們有更好的方式與`既有的架構共存`

> 如果你擔心導入 Terraform 會不小心破壞現有的架構，可以透過 data source 去擷取重要的資料同時保證 Terraform 不會修改或是刪除，例如說 DNS設定、IAM Role 等等

data source 個別取用方式可以查文件，最基本就是用 name 當作搜尋依據，例如說我在 `./module/lambda-api-test/main.tf` 希望存取 `./global/global.tf` 或是不存在於 terraform 專案下的 IAM Role，可以用

```HCL
# data "資源類型" "資源名稱"
# { 搜尋條件與參數 }
data "aws_iam_role" "iam_for_lambda"{
  name = "iam_role_name"
}

# 存取示範
resource "aws_lambda_function" "lambda_main" {
  role          = "${data.aws_iam_role.iam_for_lambda.arn}"
  ....
}
```

data source 也是用來跨 module 間傳遞資源的方法，但要自己釐清 module 的先後順序

# 條件式 - for / if 
HCL 是個宣告式語言，讓我們可以用 high level 方式宣告我們的意圖，至於如何實作就不用我們操心；  
但跟程序式語言比起來，條件判斷與迴圈等邏輯判斷舊沒有如此的方便，不過 HCL 還是支援基本的條件判斷語法，雖然沒這麼直觀，但還是有辦法滿足大多數的應用場景

# count
count 是最早支援的語法，主要是重複創建資源，透過 `count.index` 取得當下 interation 的 index  
```HCL
resource "aws_iam_user" "example" {
  count = 3
  name  = "neo.${count.index}"
}
```
也可以搭配 list，動態調整變數
```HCL
variable "user_names" {
  description = "Create IAM users with these names"
  type        = list(string)
  default     = ["neo", "trinity", "morpheus"]
}
resource "aws_iam_user" "example" {
  count = length(var.user_names)
  name  = var.user_names[count.index]
}
```
如果想要 access 資源的輸出，可以透過 `[index/*]` 方式取得
```HCL
output "all_arns" {
  value       = aws_iam_user.example[*].arn
  description = "The ARNs for all users"
}
```
count 搭配三元運算式，就變成了現成的 if/else
```HCL
resource "aws_iam_user_policy_attachment" "neo_cloudwatch_full" {
  count = var.give_neo_cloudwatch_full_access ? 1 : 0
  ....
}
```

### count 限制
1. **不能用於 inline block**  
有些 resource 有 inline block，例如 auto scaling group 可以指定 tag，此時的 tag 不能使用 count
```HCL
resource "aws_autoscaling_group" "example" {
  ....
  tag {
    count = 3 (無法使用)
  }
}
```
2. **採用 list 時的元素增減**  
如果創建資源時是用 list 搭配 count，必須注意 Terraform 在後續更新資源時是認定 list index 而非元素本身  

例如原本是 ['ele1', 'ele2', 'ele3']，此時希望刪除 ele2，變成 ['ele1', 'ele3']  
但是 Terraform 會解讀成 `刪除 ele3，並更新 ele2 成 ele3`，這一點必須特別注意，不然就要使用其他的迴圈方式

# for_each
for_each 是在 0.12 加入，可以輪詢指定的 collection，並支援 inline block!  
如果 collection 為空值則效果等同於 count = 0  
> 如果多個 resource 本身近乎一致可以用 count，但大多數情況請用 for_each

配合 `dynamic` 就可以用於 inline block，以下是建立 security group 時指定 ingress 多組 port
```HCL
resource "aws_security_group" "example" {
  name = "example"

  dynamic "ingress" {
    for_each = var.service_ports
    content {
      from_port = ingress.value
      to_port   = ingress.value
      protocol  = "tcp"
    }
  }
}
```
for_each 也可以搭配 map 使用
```HCL
resource "azurerm_resource_group" "rg" {
  for_each = {
    a_group = "eastus"
    another_group = "westus2"
  }
  name     = each.key
  location = each.value
}
```
透過 `each 加上 key, value` 取得需要的值

# Warning!
目前 Terraform 還有幾個不支援的功能，例如說 `provider 不支援變數`、`module 不支援 depends_on`、`module 不支援 for loop`  

這三個功能不支援讓 multiple region 部署時相當不方便，`module 支援 for loop` 有在接下來的 Terraform roadmap 中，但還不確定何時會支援

另在 Refactor 時務必注意，例如說 resource name 更新，Terraform 大多數會刪除舊資料並重建新資料，即使改個名稱而已，所以務必要仔細看 `$ terraform plan` 的結果，避免造成不必要的 downtime

或是有幾個方式可以避免 downtime

1. **修改 lifecycle 為 create_before_destroy**     
每個 resource 可以指定 lifecycle，`create_before_destroy` 會先創建新資源再刪除舊資源，避免 downtime  
```HCL
resource "azurerm_resource_group" "example" {
  # ...

  lifecycle {
    create_before_destroy = true
  }
}
```  

其他 lifecycle 還有 `prevent_destroy` 不會Terraform 被刪除 以及 `ignore_changes` 指定某些屬性更新不觸發 Terraform 更新資源
2.  **使用 Terraform CLI 改變 state**    
像是要修改 resource 名稱，可以透過修改  state 而非資源本身即可 `$ terraform state mv`，盡量透過指令去修改 state，而不是手動直接改 tfstate


# 結語
[完整程式碼](https://github.com/sj82516/terraform-investigation)，後來決定將上一篇的內容整理成 module，接著 iam role 部分獨立出來創立，接著用 `data source` 方式引入；  
多區域部署套用 `module` 獨立宣告，可惜 for_each 尚未支援 module  

以下是 slack 的 log 畫面  
![](/posts/img/20191104_slack_result.jpeg)

對於導入 Terraform 評估蠻正面的，一來有 data source 或 import 與現有架構整合，又可以不擔心搞爛整個架構；  
二來語法都慢慢完整，可以應付大多數的場景，確實省下很多的管理上的心力，期待之後可以用 Terraform 整合 Kubernetes，並整合 CI/CD，讓開發、整合、部署、維運可以更順暢

接下來要繼續熟練 Terraform，希望挑戰整合 Docker 的跨區域跨 Provider 部署
