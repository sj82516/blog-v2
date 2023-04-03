---
title: 初試 Terraform - 基本介紹與用程式碼部署 Lambda (上)
description: >-
    Terraform 提供跨雲平台的 Infrastructure as code 方案，用 DSL 編寫檔案管理雲端架構
date: '2019-10-30T00:21:40.869Z'
categories: ['雲端與系統架構']
keywords: ['cloud', 'terraform']
---

# 介紹
Terraform 在 Github 上有一萬九千多顆星星(截自發文日)的開源專案，由 HashiCorp 這間專注於 DevOps 工具開發的公司所維護，主要透過 DSL 編寫定義檔，管理跨雲端架構，讓架構也可以程式碼化，近一步更好的`協作`、`版本控制`等好處，達到 Infrastructure as code 的目標。

Terraform 可以達到以下幾件事：

1. **架構代碼化**  
   Terraform 採用宣告式程式語言(declarative language)的 DSL，但同樣提供基礎的程式語言該有的功能，例如變數、輸入輸出、模組化等，其中模組化也支援加載外部模組，不用擔心違反 DRY，內建一些函示也都很好用；
   當你有多個環境要部署時，可以用同樣的架構但是不同的機器規格與參數，管理上很方便
2. **跨平台服務**  
    Azure / GCP / AWS / Heroku 都可以，其他的工具包山包海，可以參考文件 [Providers](https://www.terraform.io/docs/providers/index.html)
3. **自動管理架構升級**  
    架構異動時，Terraform 會自動更新或替換正確的資源，同時也可以一鍵刪除
4. **團隊協作**  
    提供多樣的解決方案，可以用官方的 Terraform Cloud 或 AWS S3 等，在團隊內共同管理
5. **與現有架構整合**   
    Terraform 提供兩種方式與既有架構整合，一是維持唯讀型態只存取資源(例如讀 AWS arn 綁定到 Lambda 上)、二是 Import 資源一並由 Terraform 管理(增加、刪除、修改)
6. **DX 很好**  
   Developer Experience 還不賴，官方的文件、教學，以及整體的設計上都很友善，錯誤也會很直接顯示哪一行的哪一部分語法錯誤，學習上 Debug 上都很容易，HashiCorp 員工有分享這是他們在 0.12 很大的修正，讓用戶更快找出錯誤是他們重視的一環

這次目標跟上次的 CDK 研究一樣，部署一個每五分鐘執行的 Lambda，並分佈到多個區域，CDK 教學連結 [AWS-CDK教學 — Infrastructore As Code 用程式碼管理架構](https://yuanchieh.page/posts/2019-01-27_aws-cdk-infrastructore-as-code/)

# 事前準備
請先安裝 Terraform，並設定好 AWS configuration，也可以先玩過官方教學 [Terraform getting started](https://learn.hashicorp.com/terraform/getting-started/intro)；
另一個很棒的參考資料 [An Introduction to Terraform](https://blog.gruntwork.io/an-introduction-to-terraform-f17df9c6d180)，系列文超仔細也超實用，比官方文件還推薦，作者也有出書，有機會應該會入手

# 部署單區域的 Lambda 與 IAM Role
創建一個檔案，先命名為 `main.tf` ，在 Terraform 中檔案分成 `root module` 與 `module`，沒有特別宣告是 module 則為 root module，目錄下可以有多個 root module，檔案名稱沒有進入點問題，只要結尾是 `.tf` 即可

首先第一步，先部署單一區域的 Lambda，與建立對應需要的 IAM Role，以下程式碼主要做幾件事

1. 宣告 aws 部署的區域
2. 建立新的 IAM role 命名為 iam_for_lambda，並給予調用 lambda 的權限
3. 建立 IAM Policy 命名為 lambda_logging，給予 Cloudwatch log 權限
4. 將 IAM Policy 賦予 IAM role，lambda_logging 給 iam_for_lambda
5. 等等 Lambda 會用到一些 node_modules，建立 Lambda layer 命名為 lambda-layer_fetch
6. 建立 Lambda function aws_lambda_function，綁定 lambda-layer_fetch 與執行角色 iam_for_lambda

寫完介紹，剛好一步對照一塊程式碼，如果對 AWS 有點熟悉的人應該可以很快理解語法，尤其是變數命名跟後台設定很雷同，所以上手相當輕鬆

```HCL
# 指定後續資源的提供者是哪個平台的哪個區域
# provider 沒有指定 alias 代表為預設 provider
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# 建立 IAM role，取名為 iam_for_lambda
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# 建立 IAM Policy，主要給 Cloudwatch Log 權限
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}

resource "aws_lambda_layer_version" "lambda-layer_fetch" {
  filename   = "./lambda_layer_payload.zip"
  layer_name = "lambda_layer_name"

  source_code_hash    = "${filebase64sha256("lambda_layer_payload.zip")}"
  compatible_runtimes = ["nodejs10.x"]
}

resource "aws_lambda_function" "lambda_main" {
  function_name = "global-api-lantency-test"
  filename      = "./lambda_payload.zip"
  handler       = "index.handler"
  runtime       = "nodejs10.x"
  role          = "${aws_iam_role.iam_for_lambda.arn}"

  source_code_hash = "${filebase64sha256("lambda_payload.zip")}"
  layers = [
    "${aws_lambda_layer_version.lambda-layer_fetch.arn}"
  ]
  publish = true
  environment {
    variables = {
      REGION    = "us-east-1"
      SLACK_URL = "https://hooks.slack.com/services/....."
    }
  }
}
```

### Provider
指定資源是套用在哪個平台，目前是指定在 us-east-1 AWS 上，如果沒有指定 `alias` 則代表是預設的 provider

### Resource
命名的方式是
```HCL
resource 資源類型 資源名稱 {
    資源參數
}
```
資源參數對應資源類型，可以從文件中找範例與定義的方式，資源的定義依賴於 Provider 平台的不同，可以指定 `provider`，不指定則用預設 

除了個別的資源定義外，像有些資源會相依，例如 Lambda 要綁定特定的 IAM Role，注意到這邊的寫法是
```HCL
resource "aws_lambda_function" "lambda_main" {
  role          = "${aws_iam_role.iam_for_lambda.arn}"
  ....
}
```

要引用其他資源的參數，需要用`"${資源類型.資源名稱.arn}"`，arn 是 AWS 用來識別資源的全域 ID，透過這樣的方式就能夠綁定資源，這邊我指定要用 Lambda 的 Execution Role 是 iam_for_lambda 這個 Role。  
另外為了效率，定義的資源會並行建立，但有些資源有相依性，Terraform 會自動處理相依性，所以上述的資源理論上要 Policy > Role > Lambda Layer > Lambda，但我們不用宣告 Terraform 會自行處理；
但有時候相依性不明顯或是有特殊需求，可以顯示宣告 `depends_on`。

Lambda Function 建立完成後，如果只是要單純更改 Lambda 內容而不調整架構，可以宣告
```HCL
resource "aws_lambda_function" "lambda_main" {
  source_code_hash = "${filebase64sha256("lambda_payload.zip")}"
```
`source_code_hash` 是指說如果 hash 值改變就更新 Lambda 內容，而 `filebase64sha256()` 是 Terraform 的內建函示，自動用 sha 256 算出檔案 hash 值並用 base64 編碼

題外話，Lambda 的 zip file 記得解壓縮後不要有額外的資料夾，不然會失敗，正確應該要是
```md
--- lambda.zip
  |--- index.js
```

# 部署架構
編寫好架構，此時要調用 Terraform CLI 來部署架構
首先初始化環境與載入需要的執行資源

> $ terraform init

一開始 Terraform 並不知道建立的 Provider 是誰，直到初始化才會下載對應的 Library，放在專案路徑底下的 `.terraform` 資料夾下

成功後，就可以部署架構了
> $ terraform apply

此時 Terraform 會列出更動的資源，`+` 代表需要新建的資源、`-`代表會被刪除的資源、`~`代表會被更新的資源，注意資源更新可是刪除舊的資源部署新的資源，依照各家 provider 的 API 而有所不同，需要特別留意 
如果確認就輸入 "yes"，等 Terraform 幫忙部署

這樣就完成了，後續有什麼調整就重複 `$ terraform apply` 步驟，可以到 AWS 後台確認資源的建立狀況

# 加上 Cloudwatch 
這一段雷同，補上 cloudwatch event rule / cloudwatch event targe，最後別忘了要加綁定 lambda permission 不然觸發 Lambda 會失敗
```HCL
# add cloudwatch event
resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name        = "routine-api-request"
  description = "Routinely call global api lantency test"

  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "api_request" {
  rule      = "${aws_cloudwatch_event_rule.every_five_minutes.name}"
  target_id = "CallApiRequest"
  arn       = "${aws_lambda_function.lambda_main.arn}"
}

# 
resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_api" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda_main.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.every_five_minutes.arn}"
}
```

# Import 現有的 IAM Role
回過頭說一下之前採用 AWS CDK 的最大問題，當初研究時沒有看到 AWS CDK 與現有架構的整合，這導致公司要採用需要很大的決心，或是只能用在測試或新的環境建設，沒有辦法 graceful 轉移，這點我覺得對於要導入新技術來說，有點麻煩，尤其是架構這麼重要的地方；  

另一點是角色的權限管理，公司都會有針對不同的職位給予不同的權限，AWS CDK 預設就要 CreateRole 等權限，基本上很難直接要到這麼高的權限，也是當初要在公司專案嘗試 AWS CDK 最大失敗的原因

Terraform 現行支援 `import` 既有的資源，但是資源內容要自己填寫，未來宣稱會支援自動載入內容；   
`existed_role` 是我預先在 AWS 創建的 IAM Role，權限跟上面的 `iam_for_lambda` 一樣，記得要先在設定檔宣告，接著執行指令就完成了，之後 `terraform destroy` 也會一並刪除 (需要留意)

> $ terraform import aws_iam_role.existed_role existed_role

```HCL
# existed iam role
resource "aws_iam_role" "existed_role" {
  name = "existed_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
```

# Variables - 抽離參數
目前的參數都是寫死的，例如說部署的區域、Lambda 名稱等，Terraform 支援 variable 定義，可以有以下幾種類型
1. string
2. boolean
3. number
4. set
5. map
6. object (等同於 map，但會蓋過 map)
7. tuple

如果要在參數使用變數的話，必須要先在資源檔 `.tf` 宣告
```HCL
variable "image_id" {
    type        = string
    default = "default 值"
    description = "The id of the machine image (AMI) to use for the server."
}
```

type 必填，但是 default 跟 description 不用，當沒有 default 且後續變數沒有賦值的話，在 `>$terraform apply` 時會中斷要求輸入

在資源定義檔上，可以採用 `var.變數名稱`
```HCL
provider "aws" {
  profile = "default"
  region  = var.image_id
}
```

接著，透過以下幾種方式賦值給 variable

1. 環境變數  
   ```HCL
   $export TF_VAR_image_id=ami-abc123
   $export TF_VAR_availability_zone_names='["us-west-1b","us-west-1d"]'    
    ```  
2. `terraform.tfvars` 檔案中
    ```HCL
    image_id = "ami-abc123"
    availability_zone_names=["us-west-1b","us-west-1d"]
    ```
3. `terraform.tfvars.json` 檔案中
   ```json
   {
        "image_id": "ami-abc123",
        "availability_zone_names": ["us-west-1a", "us-west-1c"]
    }
   ```
4. `*.auto.tfvars` 或是 `*.auto.tfvars.json`，順序按照檔名
5. 在 CLI 執行時指定 `-var` `-var-file`
   > $terraform apply -var="image_id=ami-abc123"

如果有同樣的變數名稱，按照上面的規則順序後者蓋過前者，例如 `-var` 會蓋過其他檔案的宣告

# Output - 輸出參數
對於 root module 來說，設定 output 會在 `> $terraform apply` 時打印，例如說 EC2 Instance 的 public DNS等；
對 module 來說，Output 等同於 function 的 return value，決定哪些資源讓外部讀取

在範例程式的目錄下有獨立的 `output.tf`
```HCL
output "lambda-arn" {
    value = aws_lambda_function.lambda_main.arn
}

output 輸出參數名餐 {
    value = 資源類別.資源命名.資源屬性
}
```

會在 apply 成功後打印出來
```md
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

lambda-arn = arn:aws:lambda:us-east-1:.....
```


# State - Terraform 如何掌管架構的更動
當架構異動的時候，Terraform 如何知道前後架構的差異呢？
每次在執行 `$ terraform plan` 時，專案目錄底下有 `terraform.tfstate` 檔案，用 JSON 描述架構中的所有資源，每當下次執行 `$ terraform plan` 時，Terraform 會根據 tfstate 中的資源 ID 取得最新的資訊，接著與描述檔做 diff 決定哪部分資源要更新

當我們要跨團隊協作時，就需要把 terraform 描述檔 + terraform.tfstate 與團隊共享，此時會有有三個要素

1. **共享檔案與版本控制**   
    檔案共享是最基本的協作必備條件，同時將程式碼做版本控制也是很必要的功能
2. **Lock 機制**   
    當共享了之後，Lock 就變成是必須考量的因素，避免團隊同時多人同步修改，造成前後衝突的狀況
3. **獨立不同的 state 狀態**   
   在實際應用上，可能會有 development / staging / production 不同環境，希望共用程式碼建立雷同的架構，但又因為環境不同希望有不同的配置，例如機器大小或 VPC 等，此時就需要考量如何獨立不同環境

在跨同團隊協作很容易想到 `git` ，但嚴格來說 git 只能滿足第一點，所以在 Terraform 可以指定不同的 state 管理方式，除了官方的 Terraform Cloud，可以採用 `AWS S3 + DynamoDB` 達到上述的條件，並附帶版本控制，再之後會更詳細的描述操作流程，詳情可以參考 [How to manage Terraform state](https://blog.gruntwork.io/how-to-manage-terraform-state-28f5697e68fa)

# 結語
就這樣完成了單區域的 Lambda 部署與最基本的 Terraform 學習，以下是這次教學的程式碼
[terraform-investigation](https://github.com/sj82516/terraform-investigation/commit/9106731fcb895c4aa31a1b95670d627fa60e4a4a)

[下一篇](https://yuanchieh.page/posts/2019-11-04_try-terraform-2/)將整個架構模組化，並一鍵部署多個區域