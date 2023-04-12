---
title: '【刷題長知識】Mercle tree 識別子樹相同與否'
description: Leetcode 549 要找出是否有重複子樹，在解答區有人分享 Mercle Tree 解法，在 O(n) 的時間與空間複雜度下解決問題，延伸了解到 Mercle Tree 被廣泛應在許多地方，如 Git / Dynamo DB 等
date: '2022-06-01T01:21:40.869Z'
categories: ['Algorithm']
keywords: ['leetcode', 'Mercle Tree']
---

今天在解 [549. Binary Tree Longest Consecutive Sequence II](https://leetcode.com/problems/binary-tree-longest-consecutive-sequence-ii/)，在評論區發現有趣的解法 Merkle Tree，說來解法也很單純，就是 tree 節點會 (左子樹的 hash value \+ 右子樹的 hash value \+ 自己的 hash value) 再取一次 hash value 代表整棵 tree，所以需要 O(n) 的時間複雜度與空間複雜度，n 為節點數

![](https://upload.wikimedia.org/wikipedia/commons/thumb/9/95/Hash_Tree.svg/310px-Hash_Tree.svg.png)  
圖片來自 wiki

\#549 程式碼大致是，以下代碼的來源是 [awice-Python, O(N) Merkle Hashing Approach](https://leetcode.com/problems/find-duplicate-subtrees/discuss/106030/Python-O(N)-Merkle-Hashing-Approach)

```python
def findDuplicateSubtrees(self, root):
    from hashlib import sha256
    def hash_(x):
        S = sha256()
        S.update(x)
        return S.hexdigest()

    def merkle(node):
        if not node:
            return '#'
        m_left = merkle(node.left)
        m_right = merkle(node.right)
        node.merkle = hash_(m_left + str(node.val) + m_right)
        count[node.merkle].append(node)
        return node.merkle

    count = collections.defaultdict(list)
    merkle(root)
    return [nodes.pop() for nodes in count.values() if len(nodes) >= 2]
```

透過 hash value 比對兩個 subtree 是否相同，以上解法要小心有 hash collision 問題，最好重新檢查一下比較保險

Merkle Tree 在現實中有什麼應用呢？ 以下內容參考自  [Understanding Merkle Trees](https://medium.com/geekculture/understanding-merkle-trees-f48732772199)\
主要會出現在樹狀結構且需要快速找出這兩棵 Tree / Subtree 差異之處，例如 

* Git 在 pull request 需要快速知道是從哪個 git commit tree 開始不同 / file tree 中有哪些檔案有異動需要同步
* Blockchain 中需要知道交易鏈上的某筆交易是否存在於該區塊中
* 分散式資料庫中在同步資料時，要確認哪部分資料有落差需要同步，如 Dynamo DB 中

讓我們更深入看一下 Git 內部實作

# Git Internals - Git Objects

<https://git-scm.com/book/en/v2/Git-Internals-Git-Objects>

讓我們先來看一下 Git 內部怎麼儲存資料，Git 內部有一個 key-value database，裡面會儲存 hash key 與對應的內容 (Object)，包含的類型有檔案 (blob) / 資料夾 (tree) / commit 都會以這樣的方式儲存，不同的類型會 hash function 的參數會有所不同，但都是透過 SHA-1 產生

以上的內容會儲存在 `.git/object` 的路徑

### Blob Objects

檔案包含文字圖檔等都是 blob 形式，我們可以透過

* `$git hash-object` 將指定的檔案或內容儲存到 git database 中，並取得 hash code

* `$git cap-file` 輸入對應的 hash code 可以取出對應的內容

如官方案例

```sh
$ mkdir test && cd test
$ git init
$ echo 'test content' | git hash-object -w --stdin
d670460b4b4aece5915caf5c68d12f560a9fe3e4

$ find .git/objects -type f
.git/objects/d6/70460b4b4aece5915caf5c68d12f560a9fe3e4

$ git cat-file -p d670460b4b4aece5915caf5c68d12f560a9fe3e4
test content
```

在 .git/objects 下可以看到 `d6/70460b4b4aece5915caf5c68d12f560a9fe3e4`，git 會把 40 碼 hash code 拆成 2 \+ 38，前 2 碼變成資料夾名稱＋後 38 碼變成檔案名稱，如果試著直接讀取 file 會發現無法識別，主要是 Git 會用 zlib 壓縮內容

### Tree Objects

資料夾在 Git 中以 Tree 的格式儲存，其內容會儲存路徑下 tree / blob 的 hash code

```sh
$ mkdir -p test1/test2
$ echo "123" > test1/test2/test.txt
$ git add .
$ git commit -m "init"

$ git cat-file -p master^{tree}
040000 tree b5a59142d85435f6a41a972e376a422fc6b2df93    test1

$ git cat-file -p b5a59142d85435f6a41a972e376a422fc6b2df93
040000 tree 33dacd7d9ac656ddebea4ecfc8ab9a87b37c2736    test2

$ git cat-file -p 33dacd7d9ac656ddebea4ecfc8ab9a87b37c2736
100644 blob d800886d9c86731ae5c4a62b0b77c437015e00d2    test.txt
```

其中 `master^{tree}`是代表 master branch 的目錄，內容儲存第一層的所有檔案與資料夾 test1，接著一層一層往下找就能找到 test.txt

* 如果我們更新 test.txt 會發生什麼事？

```sh
$ echo "456" > test1/test2/test.txt
$ git cat-file -p master^{tree}
040000 tree ff1e53b4ff4c130ece8c9f12cdcc3f2613a779e7    test1

$ git cat-file -p b5a59142d85435f6a41a972e376a422fc6b2df93
040000 tree 33dacd7d9ac656ddebea4ecfc8ab9a87b37c2736    test2

$ git cat-file -p e9e2bd5dfa2916e3b1cba933bd9250a9822406e4
100644 blob 4632e068d5889f042fe2d9254a9295e5f31a26c7    test.txt
```

可以看到 test.txt 因為內容改變而 SHA key 也改變，同樣的 test1 、test2 對應的 tree object SHA key 已經變成了，所以只要底下的 blob 改變 tree SHA key也會跟著改變

我暫時沒有找到直接把資料夾轉成 hash code 並儲存的方式，在文件中只有記載當在 staging 區增加檔案時，git 會幫忙建立 index 與 tree

#### 每次變動 git 都會儲存整份檔案內容，這樣 .git/objects 就會超肥？
沒錯，會非常肥，所以 git 提供指令可以清除檔案太舊的資料，參考 [How to shrink the .git folder](https://stackoverflow.com/questions/5613345/how-to-shrink-the-git-folder)，在 git 文件中有更詳細描述 [10.7 Git Internals - Maintenance and Data Recovery](https://git-scm.com/book/zh-tw/v2/Git-Internals-Maintenance-and-Data-Recovery)

```sh
$ git repack -a -d --depth=250 --window=250
```


### Commit Objects

在 git 中 commit 儲存是樹狀結構，當執行 $ git commit 時，git 會產生 commit object 並記錄 commit 訊息 / 時間 / 作者與 parent commit，如

```sh
$ git add .
$ git commit -m "init"
$ git remove .
$ git commit -m "delete"

$ git log
commit 8864a737bf54b251c878655c263dc9b1e16640e2 (HEAD -> master)
.....
    delete

commit ff226f74f095fd1acb5c965583688be28ad3bbb4
....
    init

$ git cat-file -p 8864a737bf54b251c878655c263dc9b1e16640e2
tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904
parent ff226f74f095fd1acb5c965583688be28ad3bbb4
author Yuanchieh <sj82516@gmail.com> 1654239635 +0800
committer Yuanchieh <sj82516@gmail.com> 1654239635 +0800

delete
```

### SHA key 如何運算

在文件最後有補充如何計算 blob 的 SHA key，這邊參考龍哥教學 【[冷知識】那個長得很像亂碼 SHA-1 是怎麼算出來的？](https://gitbook.tw/chapters/using-git/how-to-calculate-the-sha1-value) 

```ruby
# 引入 SHA-1 計算函式庫
require "digest/sha1"

# 要計算的內容
content = "Hello, 5xRuby"

# 計算公式
input = "blob #{content.length}\0#{content}"

puts Digest::SHA1.hexdigest(input)
# 得到 "4135fc4add3332e25ab3cd5acabe1bd9ea0450fb"
```

> 總結：在 Git 中檔案與 Commit 都是以樹狀結構儲存，只要節點下的子節點有變動，往上一路到跟節點的 Hash key 都會跟著改變，透過 Mercle Tree 就可以在 O(N) 找到變動的地方

## 結語
刷題有時候有趣的不是單純答案寫出來，而是看到討論區有各種牛鬼蛇神的強大解法，許多資料結構或演算法在日常的系統中都扮演重要的角色