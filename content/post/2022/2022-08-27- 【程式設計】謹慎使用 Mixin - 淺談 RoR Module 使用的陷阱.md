---
title: '【程式設計】謹慎使用 Mixin - 淺談 RoR Module 使用的陷阱'
description: Ruby 提供 Module 用來跨 class reuse code (Mixin)，但如果隨意使用會造成可讀性與維護性困難，淺談問題與分享解法
date: '2022-08-27T01:21:40.869Z'
categories: ['Program']
keywords: ['RoR', 'Module', 'Mixin', 'OOP']
---

平日在公司使用 RoR 開發，過往 code base 在跨 class 時為了方便會抽出一個名為 `XXFunction::SharedMethod` 的 module，讓多個 class 直接 include 使用，但後續在閱讀時發現 module 與 class 職責不清楚，導致閱讀時要不斷地多個檔案切換，最可怕是 instance variable 在 module / class 都會讀寫，強耦合的情況下任意的改動都有可能破壞原本的設計   

因此有了這篇的文章誕生，探討 Module 在 RoR 中該如何正確地使用，才可以再享有 code reuse 的便利卻不造成可讀性 / 維護性上的困擾

以下文章大量參考
- Gitlab 上的討論 [Rails module using instance variable is harmful](https://docs.gitlab.com/ee/development/module_with_instance_variables.html)
- [Good Module or Bad Module](https://www.cloudbees.com/blog/good-module-bad-module)
- [When To Be Concerned About Concerns](https://www.cloudbees.com/blog/when-to-be-concerned-about-concerns)

## Module 簡介
Module 在 Rudy 中是一個類似 class 的存在，是 class / method / constant 的集合但不可以被 initiailize，主要的功能有兩個
#### 1. Namespace
如果有兩個 class 在不同的 context 中卻有類似的命名，可以用 Module 當作前綴隔開，例如
```ruby
module FeatureA
    class Hello
    end
end

module FeatureB
    class Hello
    end
end

FeatureA::Hello
FeatureB::Hello
```
#### 2. Code Reuse
在 Ruby 中繼承只能夠 `單一繼承`，繼承設計的理念偏向是 `is-a`；  
如果想更廣泛的賦予 class 某種能力 `could-do`，那用 module 的方式會更加的適合，在 module 嵌入的數量上 Ruby 並沒有限制 (參考 [類別（Class）與模組（Module）](https://railsbook.tw/chapters/08-ruby-basic-4))

最基本的例子是 Ruby Core Module [`Comparable`](https://ruby-doc.org/core-2.5.0/Comparable.html)，當 class include Module 後只要實作 `<=>` method，就可以使用 Comparable 定義的功能如 `<、>、==、between?` 等
```rb
class SizeMatters
  include Comparable
  attr :str
  def <=>(other)
    str.size <=> other.str.size
  end
  def initialize(str)
    @str = str
  end
  def inspect
    @str
  end
end

s1 = SizeMatters.new("Z")
s2 = SizeMatters.new("YY")
s1 < s2
```
## 濫用 Module 的壞味道
介紹了 Module 的功用，來看一下在濫用的情況下造成的副作用
### 臭味 1. 相依性變成隱式，降低易讀性
試想今天只是為了降低 class 的程式碼行數，而單純把 code 抽到 Module 會發生什麼？
```ruby
class AfterSignupController
  include Wicked::Wizard
  include SetAdmin
  include MailAfterSuccessfulCreate
  include FooBarFighters::MyHero
  # ...
end
```
打開了一個檔案，結果發現 class 中所有的 method 都在別的 module 內，這時候要找到對應的 module 在哪就很麻煩

更可怕的是當你找到後，你怎麼改保證在有 class 依賴的情況下，改動 Module 會不會壞掉？

> `Extracting methods into a module to only turn around and include them is worse than pointless.` It's actively damaging to the readability of your codebase.

### 臭味 2. 嚴重耦合，如果共用 Instance Variable 會讓情況更糟
分享一下目前遇到的案例
```rb
module SharedFunction
    def update_method
        self.var += 10
    end

    def print
        puts self.var + self.var2
    end
end

class Hello
    include SharedFunction

    def initialize
        self.var = 0
        self.var2 = 10
        # 耦合點1: class 必須先 initial var，否則 update_method 就會出錯
        # 耦合點2: 必需要知道 module method 呼叫順序，變成是要知道 module 所有細節才能使用，缺少封裝的意義
        update_method
        print
    end

    def update_var
        # 耦合點3. var 這邊也有機會變動，未來在找 var 的值到底是什麼會很困難
        self.var = 20
    end

    attr_accessor var
end
```
可以看出 module 在使用 instance variable 後會有很多耦合的地方，包含 initialzie 的時機 / 暴露過多細節等問題

### 壞味道3. 多個 Module 間可能會有命名衝突
如果今天兩個 Module 命名重複怎麼辦？ 在 Ruby 中會依照繼承鏈決定套用到的 method，但可能不符合 caller 的預期，這邊可以參考前端 React 圈的討論 [Mixins Considered Harmful](https://reactjs.org/blog/2016/07/13/mixins-considered-harmful.html)

```rb
module A
    def method_a
    end
end

module B
    def method_b
    end
end

# 如果 module B 不小心也定義了 method_a，就會覆蓋過去
class C
    include A
    include B
end
```

## 如何解決
### 建議 1. Composition over Inheritance 
Module 某種程度是多重繼承，也可以用 class.ancestors 看到 included Module 在繼承鏈上，要解決這樣的臭味可以改用 `Composition`

Composition 是指說把類似的行為封裝成 class，直接在原本的 class 中使用，這帶來的好處是
1. class 有更好的封裝性，只有 public method 可以被使用 (在 Ruby 中不完全正確)
2. class 可以獨立測試

例如以下，原本 tracking 相關的行為被抽到 module 中，要知道 notify_next! 定義在哪就必須找所有的 module 包含繼承的 class
```rb
class Todo < ActiveRecord::Base
  # Other todo implementation
  # ...
  include EventTracking
end

module EventTracking
  extend ActiveSupport::Concern
  included do
    has_many :events
    before_create :track_creation
    after_destroy :track_deletion
  end
  def notify_next!
    #
  end
  private
    def track_creation
      # ...
    end
end
```

但現在 tracking 變成 class `EventPlanning`，好處是不用猜 `notify_next!` 在哪個 module，職責與細節都封裝在 EventPlanning 裡面，要改動只要確保相依的 class，就不用特別擔心，而且還有測試保護
```rb
class Todo < ActiveRecord::Base
  # Other todo implementation
  # ...
  has_many :events
  before_create :track_creation
  after_destroy :track_deletion
  def notify_next!
    EventPlanning.new(self.events).notify_next!
  end
end
```

### 建議 2. 設計 Module 時有明確的職責，並確保暴露的細節
千萬不要為了 reuse code 而放棄 Object Oriented 的思考，要確保每一個 Module 被設計的含義，具體來說就是
1. include 的 class 必須實作什麼功能 (決定耦合點)
2. Module 可以提供 class 怎樣的額外功能

讓我們看幾個漂亮的 Module 設計
#### 範例：Enumerable
[Enumerable](https://ruby-doc.org/core-3.1.2/Enumerable.html) 是提供集合類型的 class 有方便遍歷 (iterate) 的方法
1. include class 必須實作 `each`
2. Module 可以提供 class `map / select / sort / count` 等 iterator 該有的功能
```rb
class Foo
  include Enumerable
  def each
    yield 1
    yield 1, 2
    yield
  end
end
Foo.new.each_entry{ |element| p element }
```
Enumerable 與 class 耦合點只有 each 這個 method，完全沒有 instance variable 等其他耦合，非常乾淨

### 建議 3. 如果要用 instance variable 請確保只有 Module 自己使用 
如果 Module 還是需要使用 instance variable 也沒關係，確保 class 不會用到即可
#### 範例：Sidekiq::Worker
讓我們看一個稍微複雜的案例
```rb
class HardWorker
    include Sidekiq::Worker
    sidekiq_options queue: 'critical', retry: 5

    def perform(*args)
        # do some work
    end
end

HardWorker.perform_async(1, 2, 3)
```
在 include Sidekiq::Worker，可以手動調整參數 sidekiq_options，這邊實作就會建立 instance variable
```rb
self.sidekiq_options_hash = get_sidekiq_options.merge(opts)
```
但很明顯這個 variable 在 class 是完全不會用到，只有 module 內部使用，所以沒有問題

另外當我們往下追 perform_async 時，可以看到
```rb
def perform_inline(*args)
    Setter.new(self, {}).perform_inline(*args)
end
```
這邊出現一個 module 內部定義的 class `Setter`，可以看到實際發送的邏輯在這邊，透過 class 封裝好處是不怕被其他人不小心複寫或改動
```rb
module Test
    def module_method
        puts private_method
    end

    private
    def private_method
        "module private"
    end
end

class A
    include Test

    private
    def private_method
        "class private"
    end
end

A.new.module_method // "class private"
```
module 內的 method 會被覆寫，但如果改用 class 指定就不會
```rb
module Test
    def module_method
        puts ModuleClass.new.private_method
    end

    private
    class ModuleClass
        def private_method
            "module private"
        end
    end
end

class A
    include Test

    private
    def private_method
        "class private"
    end
end

A.new.module_method // "module private"
```

## 爭議 Rails ActiveSupport::Concern
ActiveSupport::Concern 是 Rails 中蠻有趣的設計，類似於 Module 但有增加更多的 `魔法`，可以把太大的 orm class 以 module 的形式分拆出去，算是 orm 版的 Module，在使用的心法與上述雷同，就不贅述，也可以參考 [Rails Concerns: To Concern Or Not To Concern](https://blog.appsignal.com/2020/09/16/rails-concers-to-concern-or-not-to-concern.html)

基本上也都是提到 `如果 module 與 class 產生了 circular dependency`，如果有人沒注意到直接改 class，那 module 就可能會壞掉；解法同樣是降低依賴的機會，讓 module 做的事情簡單一些

但有趣的是 [DHH 本人看起來很喜歡這樣的寫法](https://twitter.com/jubiweb/status/964346236588494848) ，或許這也是一種 convention over configuration 的體現 XD 但蠻多人抱持反對立場，就大家斟酌使用 

## 結語
Ruby 是一門有趣的物件導向語言，所有的東西都是物件，所以在設計上如果多使用物件導向的思維去設計，會讓程式碼更好維護

另外發現很多人都會把 `DRY (Dont repeat yourself)` 當作聖旨，看到一點點重複就會忍不住抽共用，但沒有考慮到`抽共用看起來避免了重複代碼，但這樣造成了意外的耦合`，在理解 Clean Architecture 後會發現很多看似重複都是`隱性的重複`，其實沒有必要抽共用導致耦合的存在，這點未來有機會再延伸探討

在使用 Module 上，請確保
1. 真的需要用 module 在用，否則用 composition + class 會讓生活更簡單
2. Module 設計上要確定暴露的細節與耦合點
3. 使用 instance variable 要小心，請限縮在 module 內使用