---
title: 'Python - 直接執行 package 下的 module 的錯誤'
description: 最近因為資料分析開始大量使用 Python，因為是與同事在同一個 Package 下拆分不同 Module 協作，當我想要直接執行 Module 就遇上 「ModuleNotFoundError No module named」的錯誤
date: '2021-11-22T01:21:40.869Z'
categories: ['Python']
keywords: []
---
最近因為資料分析開始大量使用 Python，與同事協作在同一個 Package 下拆分不同 Module 實作，當我想直接執行 Module 遇上了 「ModuleNotFoundError: No module named」的錯誤，讓我開始想瞭解 Python 的 Package 系統運作的原理

## Python Package 載入方式
[官方文件：6. 模組 (Module)](https://docs.python.org/zh-tw/3/tutorial/modules.html) 寫得很詳盡，模組的載入順序是根據 `sys.path`，而 sys.path 依序由以下組成
1. 當前路徑
2. 環境變數 PYTHONPATH
3. site-package

其中 site-package 是使用手動建置 package 所在位置 (`pip install, python setup.py install`)，可能會有非常多組，每一位 user / venv 下又有對應的 site-package，參考 [How do I find the location of my Python site-packages directory?](https://stackoverflow.com/questions/122327/how-do-i-find-the-location-of-my-python-site-packages-directory?rq=1)可以找出對應的路徑
1. Global: `$ python -m site`
2. User: `$ python -m site --user-site`

所以 sys.path 決定了 package 載入的順序，例如當前路徑下 package 名稱與核心模組重複，那會以當前路徑優先載入；  
所以能透過動態改變 sys.path 決定載入順序

## 為什麼直接執行 Package 下的 Module 會失敗
在 Python 中，import 可以選擇完整的 Module 路徑或是相對路徑，而路徑會受到執行檔案的 sys.path 與 \_\_package\_\_ 的影響，相關的 magic method 為
1. `__name__`：Module 的完整名稱
2. `__package__`：決定相對路徑 import 的解析路徑，如果檔案是 Package，則 \_\_package\_\_ 會等於 \_\_name\_\_；  
如果是 Module 則 \_\_package\_\_ 是所屬的 Package 名稱；  
如果 Module 是 `top-level modules`，也就是 `__name__ == __main__`，則 \_\_package\_\_ 為 None

以下參考自 [Relative imports in Python 3](https://stackoverflow.com/questions/16981921/relative-imports-in-python-3)，假設目前的專案目錄是
```bash
main.py
mypackage/
    __init__.py
    mymodule.py
    myothermodule.py
```
在 myothermodule.py 中，載入 mymodule，可以透過完整路徑 `import mypackage.mymodule` 或是相對路徑 `import .mymodule` 的方式，但如果直接執行 $python myothermodule 會分別遇到以下錯誤
1. 完整路徑
```bash
ModuleNotFoundError: No module named 'mypackage'
```
2. 相對路徑
```bash
ImportError: attempted relative import with no known parent package
```

完整路徑的錯誤原因是因為 sys.path 中沒有 mypackage，sys.path 是加入`script 當前的資料夾 (./mypackage)`而不是 ./，所以 mypackage 是無法被載入的；  
相對路徑的錯誤則是因為當前 myothermodule.py 是 top-level module， \_\_package\_\_ 被設定為 None，所以相對路徑解析會失敗  

## 如何解決
分別針對完整路徑與相對路徑提出解決方案
### 1. 完整路徑
既然完整路徑是因為 sys.path 沒有包含到 package 的上層路徑而沒有被載入，那就加上去即可

Python 鼓勵但不強制 import 都要放在檔案開頭
```python
import sys
from pathlib import Path # if you haven't already done so
file = Path(__file__).resolve()
parent, root = file.parent, file.parents[1]
sys.path.append(str(root))

# Additionally remove the current file's directory from sys.path
try:
    sys.path.remove(str(parent))
except ValueError: # Already removed
    pass

import mypackage.mymodule # 成功 Import
```

#### 直接安裝 package
另一個作法是透過 setuptools 直接安裝相依的套件，這樣就能從 site-package import，但這改動相對麻煩些，且變成套件要額外管理反而麻煩

### 2. 相對路徑
#### 使用 -m 執行
直接指定完整的 package.module 路徑 `$ python -m mypackage.myothermodule`，此時 \_\_package\_\_ 會被正確解析成 mypackage，參考 [PEP366](https://www.python.org/dev/peps/pep-0366/)

> By adding a new module level attribute, this PEP allows relative imports to work automatically if the module is executed using the -m switch

#### 手動指定
手動實作 PEP366 的提案，參考[PEP366_boilerplate.py](https://gist.github.com/vaultah/d63cb4c86be2774377aa674b009f759a)，加入對應的 sys.path 並指定 \_\_package\_\_，達到跟 -m 相同的效果
```py
import sys, importlib
from pathlib import Path


def import_parents(level=1):
    global __package__
    file = Path(__file__).resolve()
    parent, top = file.parent, file.parents[level]
    
    sys.path.append(str(top))
    try:
        sys.path.remove(str(parent))
    except ValueError: # already removed
        pass

    __package__ = '.'.join(parent.parts[len(top.parts):])
    importlib.import_module(__package__) # won't be needed after that


if __name__ == '__main__' and __package__ is None:
    import_parents(level=...)
```

## 結語
第一次接觸 Python 覺得頗神奇，有許多 magic number 以及獨樹一格的 package 管理方式，包含 virtual env 的使用等