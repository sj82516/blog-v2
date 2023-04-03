---
title: 'Nodejs / Ruby / Golang 套件版本管理差異：比對 NPM 與 Bundler'
description: 使用套件對於一名開發者很重要，畢竟不可能一直重複造輪子，但套件的載入、版本管理不是一件這麼簡單的事，本篇比對 Nodejs 生態中的 NVM 與 Ruby 的 Gem/Bundler，看套件管理有什麼不同的方法與限制
date: '2021-07-10T01:21:40.869Z'
categories: ['程式語言', 'ruby']
keywords: ['npm', '套件管理','bundler']
---
開發上為了方便，常常使用別人開發好的套件，但是最近遇到幾次衝突，發現套件的版本管理沒有想像中簡單，以下將釐清 npm / gem+bundler 在套件的
1. 安裝
2. 載入方式
3. 子套件的版本衝突
做更深入的了解與比對  

實驗方式會準備 test_module_1 / test_module_2，分別使用 depend_module version 1 / version 2，最後同時使用 test_module_1 & 2
```md
- test_module_1
   |- depend_module@1.0.0
- test_module_2
   |- depend_module@2.0.0
```

> TLDR；NPM 可以在不同模組引用不同的版本；而 Gem 不行；Golang 可以透過 replace 指定多個版本

## NPM
### NPM install
節錄 NPM 7.x [npm-install 官方文件](https://docs.npmjs.com/cli/v7/commands/npm-install)部分內容

`$npm install` 主要是協助安裝 package 所相依的 packages，所謂的 package 是
1. 資料夾中有 package.json
2. gzip 壓縮的 tar 檔 (1)，也就是把有 package.json 的資料夾壓縮
3. 指向 (2) 的 url，例如 `$npm install https://github.com/indexzero/forever/tarball/v0.5.6`
4. 指向 (1) 的 git remote url
5. 被發佈到 registry 的 (3)，例如 `npm install git+ssh://git@github.com:npm/cli#semver:^5.0`
等

在 package 路徑下執行 $npm install，則會安裝 packages 在 node_modules 中；`-g` 會安裝到 global 環境下；`--production` 則不會安裝 devDependencies 下的 package

如果要安裝同一個 package 不同版本並同時使用，在 npm 6.9.0 以後可以用 alias
```md
npm install jquery2@npm:jquery@2
npm install jquery3@npm:jquery@3
```
### 載入 Nodejs require
節錄自 Nodejs v16.4.2 [Modules: CommonJS modules](https://nodejs.org/api/modules.html#modules_loading_from_node_modules_folders)，這邊先探討 Commonjs Module 而不是 ESM  

在 Nodejs 中，`每一個 file 就是一個獨立的 module`，可以透過 require 來引入，當 require(X) 在 Path Y 下發生時，會嘗試以下步驟
1. 如果 X 是 core module，則返回 core module 並結束
2. 如果 X 是 / 開頭，則將 Y 設定為 filesystem root (沒用過)
3. 如果 X 是 ./、 ../ 、 / 開頭，則嘗試載入對應路徑的檔案或資料夾
4. 如果 X 是 # 開頭，則往上層找到最近有 package.json 的地方 (稱為 scope)，並走 ESM 載入方式
5. 找到 scope，比對 package.json 中定義，看是不是要載入自己
6. 不斷地往上一層路徑找到 node_modules，並查詢有沒有對應的 package

實際載入的過程挺複雜的，只要載入一次後 package 就會被 cache 起來，可以從 `require.cache` 中看到被 cache 的狀況，所以如果一個套件被多個套件引用不同的版本，有可能因為 cache 而導致某些套件使用錯誤的版本嗎？
看起來是不會的，因為文件提到 module cache 是基於他們被解析的 filename，因此不同版本的 package 會安裝在不同的 node_modules 下，所以解析的 filename 自然也不同
> Modules are cached based on their resolved filename. Since modules may resolve to a different filename based on the location of the calling module (loading from node_modules folders), it is not a guarantee that require('foo') will always return the exact same object, if it would resolve to different files.

### 版本實驗
本地端使用 Nodejs@14.15.4 / NPM@6.14.0，我發佈了
1. depend_module 1.0.0 / 2.0.0
2. yuan_test_module_1 require depend_module@1
3. yuan_test_module_2 require depend_module@2  
最後
```js
require('yuan_test_module_1')
require('yuan_test_module_2')

console.log("require tow modules")
console.log(require.cache)

----- 輸出
depend_module version 1
test_module_1
depend_module version 2
test_module_2
require tow modules
[
  '/Users/zhengyuanjie/Desktop/package/test/index.js',
  '/Users/zhengyuanjie/Desktop/package/test/node_modules/yuan_test_module_1/index.js',
  '/Users/zhengyuanjie/Desktop/package/test/node_modules/depend_module/index.js',
  '/Users/zhengyuanjie/Desktop/package/test/node_modules/yuan_test_module_2/index.js',
  '/Users/zhengyuanjie/Desktop/package/test/node_modules/yuan_test_module_2/node_modules/depend_module/index.js'
]
```
出乎我意料之外，node_modules 的結構是
```md
|- node_modules
    |- depend_module (version 1)
    |- yuan_test_module_1
    |- yuan_test_module_2
        |- node_modules
            |- depend_module (version 2)
```
我沒有預期第一層結構中會有 depend_module，以為都會是在個別的 test_module 下，再回來看 npm 文件說明
1. package{dep} structure: A{B,C}, B{C}, C{D}，沒有版本衝突，則預設都安裝在最上層
```md
A
+-- B
+-- C
+-- D
```
2. A{B,C}, B{C,D@1}, C{D@2}，D@1 安裝在最上層，D@2 則安裝在 C 下面
```md
A
+-- B
+-- C
   `-- D@2
+-- D@1
```
這樣可以做到預設共享相同版本的 module 避免重複下載，卻也不用擔心多個版本衝突的問題

### 環狀相依
如果 package A require package B 而 package B 又 require package A，變成環狀相依的情況，在 Nodejs 中這樣不會拋出錯誤，只是行為可能不如預期

官網的案例中
1. main.js require a.js / b.js，因為 a.js 先被 require 則先被載入
2. 在 a.js 中，執行到 require b.js，則開始載入 b.js
3. 在 b.js 中，執行到 require a.js，則為了避免無限迴圈，此時會回傳`步驟(2)載入到一半的 a.js`，接著繼續完成 b.js 載入
4. 回到 a.js，此時的 b.js 引用是完整的，繼續載入 a.js
5. 回到 main.js 中，此時在 main.js 中 a.js / b.js 都是完整的引用

```js
$ node main.js
main starting
a starting
b starting
in b, a.done = false
b done
in a, b.done = true
a done
in main, a.done = true, b.done = true
```

## Gem / Bundler
接著來看 Ruby 生態如何用 Gem Bundler 管理套件，以下內容主要參考 [Understanding How Rbenv, RubyGems And Bundler Work Together](https://www.honeybadger.io/blog/rbenv-rubygems-bundler-path/)，首先先安裝 rbenv，用於管理主機上多個 Ruby 版本

RubyGem 在 Ruby 1.9 後就整合了，gem 安裝路徑可以透過 `$gem env` 中的 "INSTALLATION DIRECTORY" 路徑，不同版本有被分開不同的路徑安裝，但不像 npm 會在每個專案下都有獨立的 node_modules

### 載入
有三種方式
1. load:   
類似於 require，但會重複載入
2. require:   
到 $LOAD_PATH 下檢查是否有載入對應的 gem，沒有則去系統安裝路徑載入 gem 下的 lib，並加到 $LOAD_PATH 中，詳見龍哥的 [Ruby 語法放大鏡之「你知道 require 幫你做了什麼事嗎?」](https://kaochenlong.com/2016/05/01/require/)
3. require_relative:   
接受相對路徑載入

所以 RubyGem 管理相當單純，把 Gem 都安裝在統一的安裝路徑下
### Bundler
Bundler 負責幾項工作
1. 讀取 Gemfile 並安裝對應適合的版本
2. 產生 Gemfile.lock 確保在不同環境下還原時版本一致
3. 因為不能載入多版本，所以 Bundler 會在所有版號中找到適合的，例如 module_a 需要 module_c > 1.0.0，而 module_b 需要 module_c  <=1.1.0，則最後會安裝 module_c@1.1.0 符合兩者需求

### 實驗
實驗方式相同，但是發現 Ruby 不能載入多個版本，會出現
```md
`raise_if_conflicts': Unable to activate yuan_test_gem_2-2.0.0, because depend_gem-1.0.0 conflicts with depend_gem (= 2.0.0) (Gem::ConflictError)
```
使用 Bundler 會因為找不到適合版本而拋錯
```md
There was an error parsing `Gemfile`: You cannot specify the same gem twice with different version requirements.
You specified: depend_gem (~> 1.0) and depend_gem (~> 2.0). Bundler cannot continue.
```

## Golang mod
參考[Using Different Versions of a Package in an Application via Go Modules](https://www.percona.com/blog/2020/03/09/using-different-versions-of-a-package-in-an-application-via-go-modules/)，Golang 可以在 mod file 中指定 `replace`，就可以在程式中使用多個版本，也可以指向自己的 fork，相當的方便，[官方文件：Requiring external module code from your own repository fork](https://golang.org/doc/modules/managing-dependencies#external_fork)

## 結語
比對不同的實作蠻有趣，目前看來 npm 會 install 在當下路徑，換來好處是可以載入多個版本的相同模組；而 gem 沒有這樣的彈性
至於`載入多版本的相同模組`我覺得是蠻現代的需求，不確定為什麼 Ruby / Gem 沒有提供這樣的特性，背後的脈絡不知是如何考量