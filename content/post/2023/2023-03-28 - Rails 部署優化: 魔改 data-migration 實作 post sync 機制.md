---
title: 'Rails 部署優化: 魔改 data-migration 實作 post sync 機制'
description: 公司一開始在 pre sync 階段採用 data-migration 在部署前觸發事件，例如回補資料等，但後來在一些場景需要在 post sync 機器部署後也觸發事件，分享自己簡單魔改 data-migration 完成需求
date: '2023-03-28T02:21:40.869Z'
categories: []
keywords: []
---
## 前言
公司當前是透過 GitOps ArgoCD 這套工具來管理持續部署的流程，ArgoCD 有個方便的 hook 機制 `pre sync` 和 `post sync`，可以在機器部署前與部署後執行對應的腳本

在我們原本的 Rails 部署機制，會於 pre sync 階段執行
- `db:migration`：負責 DB schema 改動
- `data:migration`：[data-migrate](https://github.com/ilyakatz/data-migrate) 負責跑一些 Rails script 回補資料等
避免 API server 上線因為有髒資料或錯誤的 DB schema 而執行錯誤

```
.
└── db/
    ├── data => data migration at presync
    └── migrate => schema change
```

但有時候我們會需要在機器部署完成後觸發 script，例如說當我們新增了 sidekiq job 需要觸發時，必須等到 sidekiq server 都更新到最新的版本才可以觸發，否則會 sidekiq server 會認不得新的 job

簡而言之，我們會需要在 pre sync 有一套 data-migration，在 post sync 也需要在一套 data-migration，但同一套 data-migration 是不能直接用在兩個觸發點，執行時會無法區分哪些 migration script 該在什麼時間點觸發

化成具體的需求是提供一套基於 data-migration 的 post sync 觸發機制，希望封裝出類似於 data-migration 的效果
1. 透過指令可以簡單產生 migration script template `$ $ bin/rails generate post_sync hello_post_sync`
2. 執行指令 `$ bin/rake post_sync:migrate`
3. 紀錄在 DB 中避免 script 反覆執行
4. 不影響現有的 pre sync 機制
```
.
└── db/
    ├── data => data migration at presync
    ├── migrate => schema change
    └── post_sync => data migration at post sync
```

以下將介紹透過 rails generator 簡單魔改達到我們要的效果

## 實作
### 1. 透過 Generator 產生 migration script template
透過 [Rails Generator](https://guides.rubyonrails.org/generators.html) 基於模板產生對應的檔案，透過 generator 產生 generator `$ bin/rails generate generator initializer`

在 generator 中可以定義產生檔案的方式，也可以從 CLI 吃不同的參數
```rb
class InitializerGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  def copy_initializer_file
    copy_file "initializer.rb", "config/initializers/#{file_name}.rb"
  end

    def create_helper_file
    create_file "app/helpers/#{file_name}_helper.rb", <<-FILE
module #{class_name}Helper
  attr_reader :#{plural_name}, :#{plural_name.singularize}
end
    FILE
  end
end
```
- file_name 是從 Rails::Generators::NamedBase 繼承而來，從 CLI 讀取，例如 `$ bin/rails generate initializer core_extensions` file_name 就是 core_extensions
- copy_file 複製檔案
- create_file 直接輸入檔案內容
- 其他更多有趣的 method [10 Generator methods](https://guides.rubyonrails.org/generators.html#generator-methods)

#### Generator 實作
目標是打造一個類似 data-migrate 的 generator，儲存在獨立的 folder 下，並有著 timestamp 結尾的檔案

在閱讀 [data-migrate 原始碼時](https://github.com/ilyakatz/data-migrate/blob/86f10f277deaf9aac4844f12ffea727442690d47/lib/data_migrate/config.rb#L20-L23)，看到可以針對 data_migrations script 的 folder 進行調整
```
@data_migrations_path = "db/data/"
```
所以靈機一動就想說在 generator 中如果可以動態置換，並觸發 data-migrate 就可以產生新的檔案到對應的資料夾下，而不會污染於本的 data-migrate

```rb
# lib/generators/post_sync_generator.rb

class post syncGenerator < Rails::Generators::NamedBase
  def copy_initializer_file
    DataMigrate.configure do |config|
      config.data_migrations_path = POST_SYNC_PATH
    end
    Rails::Generators.invoke("data_migration", [file_name])
  end
end
```
data-migrate 本身就有提供 data_migration 的 generator，而且可以直接在 generator 中觸發另一個 generator，再加上 file_name 可以從 CLI 讀取，這樣就可以串起來

成果是輸入 `$ rails generate post_sync xxxx_xxx`，會在指定的路徑下產生
```
.
└── rails/
    └── db/
        ├── data/
        │   └── 20210408091311_migration.rb
        └── post_sync/
            └── 20210429100009_post_sync.rb
```

### 2. 註冊 Rake 指令
當我們希望透過 CLI 觸發特定指令時，可以透過 [Rake](https://github.com/ruby/rake)，處理任務與任務間相依性的 gem 套件

這邊的用法相當簡單，同樣去改 migrations_path，並觸發原本 data migrate 的 Rake task 即可
```rb
# lib/tasks/post_sync.rake

namespace :post_sync do
  task :migrate do
    DataMigrate.configure do |config|
      config.data_migrations_path = POST_SYNC_PATH
    end

    Rake::Task['data:migrate'].invoke
  end
end
```

### 3. 避免 timestamp collision
前面我們透過 generator 與 rake 成功產生 migration script template 與執行 post sync，並且在檔案路徑上與原本的 data migration 分開

但目前還有個問題是最後 data-migrate 紀錄 script 是否曾經跑過`還是在同一張 DB table` 中，這邊沒有 config 可以直接調整

後來跟同事討論後，決定手寫一個檢查在 CI 執行時確認 db/data 跟 db/post_sync 下的 timestamp 沒有重複
```rb
class post syncChecker
  CHECK_FOLDER = [
    DataMigrate.config.data_migrations_path,
    POST_SYNC_PATH
  ]

  class << self
    def is_collision?
      (pre sync_versions, post sync_versions) = CHECK_FOLDER.map do |path|
        list_migration_versions(path: File.join(Rails.root, path))
      end

      puts pre sync_versions
      (pre sync_versions & post sync_versions).present?
    end

    def list_migration_versions(path:)
      Dir.entries(path)
         .map { |filename| parse_version(filename: filename) }
         .compact
    end

    # ref: https://github.com/ilyakatz/data-migrate/blob/2dd90c495b4d57e4dc700e3f9be149c7e2b93b57/lib/data_migrate/data_migrator_five.rb#L44
    def parse_version(filename:)
      result = /(\d{14})_(.+)\.rb$/.match(filename)
      return unless result.present?
      result[1]
    end
  end
end
```
夾在測試中執行
```rb
# spec/unit/lib/post_sync_checker_spec.rb
require 'rails_helper'

describe "post syncChecker" do
  let(:version) { 12345678901234 }
  let(:file_paths) {
    ::post syncChecker::CHECK_FOLDER.map do |path|
      File.join(Rails.root, path, "#{version}_test.rb")
    end
  }

  context "when there are two file with same version" do
    before do
      file_paths.each do |file_path|
        File.new(file_path, File::CREAT)
      end
    end

    after do
      file_paths.each do |file_path|
        File.delete(file_path)
      end
    end

    it 'should failed' do
      expect(::post syncChecker.is_collision?).to eq(true)
    end
  end

  it "check when running test" do
    expect(::post syncChecker.is_collision?).to eq(false)
  end
```

## 總結
這是一個小小的工具，不過在對於整個部署流程有還不錯的幫助