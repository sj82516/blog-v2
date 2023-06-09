---
title: '開發簡易的 Protobuf plugin'
description: 透過動手做學習 Protobuf options 與對應 plugin 設計的方式
date: '2022-11-26T01:21:40.869Z'
categories: ['Program']
keywords: ['Protobuf', 'Golang']
---

最近工作重心轉往 Golang 與 gRPC server 開發，最讓我感到神奇的是透過 proto 宣告中的 options，搭配不同的 protobuf plugin 可以 gen 出對應的檔案，包含 [OpenAPI Doc](https://github.com/solo-io/protoc-gen-openapi)  / [不同程式碼語言實作的 gRPC server](https://grpc.io/docs/languages/go/quickstart/) / [JSON 檔](https://pkg.go.dev/github.com/sourcegraph/prototools/cmd/protoc-gen-json)，不禁讓我好奇這些神秘的 Protobuf options 與背後產生檔案的 Protobuf plugin 到底是怎麼運作 ?!  

以下文章將會透過一個簡單案例 - protoc-gen-http-client 利用 proto 產生對應 Golang http client request 的程式碼，會涵蓋
1. protobuf 與 plugin 的互動機制
2. 如何從 command 讀取到 plugin 設定
3. 如何設計 protobuf extension

以下內容主要參考自
- [Creating a protoc plugin to generate Go code with protogen](https://rotemtam.com/2021/03/22/creating-a-protoc-plugin-to-gen-go-code/)

## 1. Protobuf 與 plugin 的互動機制
### prerequisite
首先我們要安裝 protoc 以及 protoc-gen-go
- 安裝 protoc https://grpc.io/docs/protoc-installation/
- 安裝 protoc-gen-go 方便開發 plugin https://pkg.go.dev/google.golang.org/protobuf/compiler/protogen#GeneratedFile 
  - `$ go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28`

前者是 protobuf 的 compiler，後者是 protobuf golang plugin 負責從 protobuf 產出對應的 golang code  
確保 terminal 可以執行 $ protoc / $ protoc-gen-go

### 互動機制
一般我們在使用 protoc 產生檔案指令是
> $ protoc --go_out=paths=source_relative:. --proto_path=.  example/proto/*.proto

指定 protoc 去載入呼叫對應的 plugin ，plugin 必須是   
1. shell 可以執行的 binary file 
2. 命名格式固定是 `proto-gen-${plugin name}`

protoc 指令有幾個參數  
1. `${plugin name}_out` 解析要執行的 plugin，如透過 \-\-go_out 指定了 proto-gen-go 的執行，並指定輸出的資料夾位置
2. `${plugin name}_opt` plugin 參數
3. `--proto-path=` 指定 input proto 的資料夾位置

如果 plugin name 有多個字母，可以用 `-` 分隔如 protoc-gen-grpc-gateway 如此命名

### 建立專案 protoc-gen-http-client
參考程式碼：[phase1](https://github.com/sj82516/protoc-gen-go-http-client/tree/feat/go-gen-p1)

第一步，產生 protoc plugin 並成功產生空殼檔案，參考目錄
```shell
protoc-gen-go-http-client
├── main.go // plugin code
├── example // 範例 proto
│   └── proto
│       ├── test.proto
│       ├── test.pb.go // protoc-gen-go 產生的
│       └── test_http.go // 自製 plugin 產生的
└── go.mod // 記得 module 命名必須是 protoc-gen-xxxx
```

在開發上我們主要透過 golang program，並採用 [protobuf golang package](https://pkg.go.dev/google.golang.org/protobuf/compiler/protogen) 協助開發
```golang
package main

import "google.golang.org/protobuf/compiler/protogen"

func main() {
    protogen.Options{}.Run(func(gen *protogen.Plugin) error {
        for _, f := range gen.Files {
            if !f.Generate {
                continue
            }
            generateFile(gen, f)
        }
        return nil
    })
}

// generateFile generates a _http.pb.go file containing gRPC service definitions.
func generateFile(gen *protogen.Plugin, file *protogen.File) {
    filename := file.GeneratedFilenamePrefix + "_http.pb.go"
    g := gen.NewGeneratedFile(filename, file.GoImportPath)
    g.P("// Code generated by protoc-gen-go-http-client. DO NOT EDIT.")
    g.P()
    g.P("package ", file.GoPackageName)
    g.P()
    g.P("func main() {")
    
    for _, srv := range file.Services {
        for _, method := range srv.Methods {
            if method.GoName == "Get" {
                g.P("// it's get")
            }
        }
    }
    
    g.P()
    g.P("}")
}
```
簡單帶過程式碼
- L7 會拿到輸入的 proto file，我們可以一個一個檔案處理
- L19~L20 是產生輸入檔案
- L27,28 是針對 proto 裡面的 service / message 輪詢
- 透過 `g.P()` 或是 stdout `fmt.Println` 都會把 string 內容寫入輸出的檔案中

#### 安裝並測試
開發後可以直接在專案目錄下安裝
> $ go install

此時對應在 $GOBIN 應該會有對應的 binary file，如果 shell $PATH 有正確指定那 $ protoc-gen-http-client 可以正確執行

此時 protoc 就可以載入 http-client 的 plugin，看到 .go file 產生
> $ protoc --go-http-client_out=. --go-http-client_opt="paths=source_relative" --go_out=. --go_opt=paths=source_relative example/proto/*.proto

## 2. 如何從 command 讀取到 plugin 設定
參考程式碼：[phase2](https://github.com/sj82516/protoc-gen-go-http-client/tree/feat/go-gen-p2)

讓我們在執行 protoc 指令時，順便帶上指定參數來設定 http client request 的 url `base-url`

主要程式碼改動透過 flag 取得參數
```golang
    var flags flag.FlagSet
    baseUrl := flags.String("base_url", "", "flags from command")
    opts := &protogen.Options{
        ParamFunc: flags.Set,
    }
```

> $ protoc --go-http-client_out=. --go-http-client_opt=paths=source_relative,base_url=api.com example/*.proto

在 protoc-gen-go 中，可以指定 `paths` 參數，指定輸出的資料夾位置 (與 go_out 一起影響)，參考 [Compiler Invocation](https://developers.google.com/protocol-buffers/docs/reference/go-generated#invocation)

## 3. 如何設計 Protobuf extension
參考程式碼：[phase3](https://github.com/sj82516/protoc-gen-go-http-client/tree/feat/go-gen-p3)

接著我們要來增加 plugin 的 Protobuf extension，在 proto file 中指定 options 讓 plugin 產生對應行為

我們主要在
1. service 中增加 method / path 的指定
2. message 中增加 field default value 指定

### 3-1 增加 proto extension
首先要針對 protobuf 不同的結構去 extend，從上到下有 file > service / message > method/field
```proto
// options.proto

// package name 要指向 proto 所在位置，而不是 golang 專案目錄
option go_package="github.com/sj82516/protoc-gen-go-http-client/protos";

message HttpClientMethodOptions {
  string method = 1;
  string path = 2;
}
// 
extend google.protobuf.MethodOptions {
  HttpClientMethodOptions method_opts = 2050;
}
//
extend google.protobuf.FileOptions {
  HttpClientFileOptions file_opts = 2048;
}
```
接著在 example 中就可以使用
```proto
// test.proto

import "example/http-client/options.proto";

message User {
  int64 id = 1[(field_opts).default="1"];
}

service HelloService {
  rpc GetUser(Hello) returns (User) {
      option (method_opts).method="get";
      option (method_opts).path="/user";
  };
}
```

這邊有幾點比較 tricky
1. protobuf import 跟 golang package 分開，聽起來很直覺但我一開始搞混了所以卡很久，尤其是要使用第三方的 protobuf extension 要`手動下載 proto file 到自己的資料夾中`，參考 [gRPC gatewate 文件：we need to copy some dependencies into our proto file structure.](https://grpc-ecosystem.github.io/grpc-gateway/docs/tutorials/adding_annotations/#using-protoc)
2. 如果有用上 protoc-go-gen 則對應的 proto extension 同路徑要有 compiled .pb.go 檔案否則會出錯

資料夾結構如下
```shell
protoc-gen-go-http-client
├── example 
│   ├── http-client // 任何第三方的 proto extension 都需要自己複製
│   │   └── options.proto
│   └── proto
│       ├── test.proto
│       └── test.pb.go
└── protos
    ├── options.proto
    └── options.pb.go // 需要 compiled 出 .pb.go，否則
```
只是剛好我的 protobuf plugin 跟 example 放在同一個資料夾下，但如果兩者是分開的專案也要按照相同的方式  
可以參考 [protoc-gen-openapiv2](https://github.com/grpc-ecosystem/grpc-gateway/tree/main/protoc-gen-openapiv2)

### 3-2 調整 plugin 讀取 options
```golang
// parse option
options := method.Desc.Options().(*descriptorpb.MethodOptions)
if options == nil {
}

v := proto.GetExtension(options, customProto.E_MethodOpts)
if v == nil {
}

// wrap as client
opts, _ := v.(*customProto.HttpClientMethodOptions)
if opts.Method == "get" {
	g.P(fmt.Sprintf("func %s() {", method.GoName))
	g.P(fmt.Sprintf("res, err := http.Get(\"https://%s%s\")\n", *baseURL, opts.Path))
	g.P(fmt.Sprintf("target := %s{}", method.Output.Desc.Name()))
	...
}
```
截取部分程式碼，主要是透過 protogen package 就可以取得個別 proto 結構中的 options

## 總結
透過 protoc plugin 讓 proto file 可以身兼多職，當作整個專案的核心定義檔，如架起 gRPC server 同時能順便產出對應的 api doc，透過自己撰寫個小 demo 更理解其中的原理還蠻有趣的