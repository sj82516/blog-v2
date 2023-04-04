---
title: 'Webassembly 教學 - 基本運算、陣列處理與指針'
description: Webassembly 實戰分享
date: '2020-01-01T05:21:40.869Z'
categories: ['應用開發']
keywords: ['Webassembly', 'JS']
---

近日因為公司專案，要把之前寫好處理圖片的 C++ code 搬移至網頁上，趁機會探索 Web Assembly，未來可以持續移植現有的 C/C++ Library，增加程式的復用性與前端的開發自由度

Webassembly 其實也不是什麼新技術了，在 2017 年已經正式推出，並在`四大瀏覽器`都能夠使用，Nodejs 也支援，但網路上相對的中文較少，例如記憶體操作、pass by reference 等等較少提及，這也是讓我頭疼許久的地方，花了兩天不斷試錯，趁跨年假期整理並分享

以下兩天是主要參考的文章  
[Creating a WebAssembly module instance with JavaScript](https://hacks.mozilla.org/2017/07/creating-a-webassembly-module-instance-with-javascript/)  
[Emscripting a C library to Wasm
](https://developers.google.com/web/updates/2018/03/emscripting-a-c-library)  
[Passing and returning WebAssembly array parameters
](https://becominghuman.ai/passing-and-returning-webassembly-array-parameters-a0f572c65d97)

Webassembly(Wasm) 主要目的是將其他語言透過編譯方式輸出瀏覽器可以運作的 bytecode，目前除了 C/C++ 外，Rust 也是個熱門的 Wasm 開發語言，周圍的生態系與工具鏈都相對完善；

以下的教學主要專注於使用 `Emscripten`，Emscripten 功用是將 C/C++ 編譯成 Wasm，除此之外提供 JS 嫁接到 Wasm 這端的處理(膠水程式)，例如說 malloc / free / printf / cout 等等 C/C++ 的標準函式庫支援的函式，`目前 Wasm 不能直接 Access，只能透過 JS 去操作 WebAPI`，這些都必須在編譯時被納入實作，此外 Wasm 目前還不能像一般的 JS Library 直接 include 就能使用，而是要處理 Memory Mapping 等，這些 Emscripten 都會處理好

主要教學項目有

1. 使用 Emscripten 產生範例 code
2. 移植乘法運算 C++ Code
3. 記憶體操作，關於 Pointer & Array
4. Wasm 總結

## 使用 Emscripten 產生範例 code

### 安裝 Emscripten

[Emscripten 官方安裝步驟](https://emscripten.org/docs/getting_started/downloads.html)，按照步驟安裝最新版的 Emscripten，確認安裝完成

> emcc --version

### 官方基礎教學 Hello World

以下參考 [官方基礎教學 Hello World](https://emscripten.org/docs/getting_started/Tutorial.html)，並翻譯(解釋)每個步驟

#### 產生 hello_world.c

```c
/*
 * Copyright 2011 The Emscripten Authors.  All rights reserved.
 * Emscripten is available under two separate licenses, the MIT license and the
 * University of Illinois/NCSA Open Source License.  Both these licenses can be
 * found in the LICENSE file.
 */

#include <stdio.h>

int main() {
  printf("hello, world!\n");
  return 0;
}
```

執行

> $ emcc build/hello_world.c -o hello_world.html

此時會輸出三個檔案，`hello_world.html、hello_world.out.js、hello_world.wasm`

`-o` 指定輸出的檔案與檔名，如果沒有指定會輸出 `a.out.js、a.wasm`；  
- .html 檔是 Emscripten 方便開發者除錯用的網頁；  
- .wasm 檔即是 binary 格式的 assembly code，人類無法閱讀；  
- .js 檔是後續與 JS 整合會需要用到的檔案，也可以直接用 NodeJS 執行

> \$ node hell_world.out.js

`-o` 如果有指定 `{file_name}.html`，則會生成配合的前端頁面，顯示 main function 的執行結果

有了 html 檔，可以使用 http server 用瀏覽器開啟網頁，例如 npm 套件 `http-server`，在本地端開啟頁面查看結果

C++ 的 code 雷同

```c++
#include <iostream>

int main() {
  std::cout << "hello, world!" << std::endl;
  return 0;
}
```

## 乘法運算並移植到網頁上

上述的 hello_world 主要是檢測環境與工具鍊是否正常，接著開始暖身，用 C++ 寫一個簡單的整數乘法運算，輸入兩個整數，回傳兩整數相乘的結果，`著重於如何將 Wasm 整合進前端中`

### 產生 multiply.cpp

```c++
#include <iostream>
#include <emscripten/emscripten.h>

extern "C"
{
    EMSCRIPTEN_KEEPALIVE
    int multiply(int num1, int num2)
    {
        return num1 * num2;
    }

    int main()
    {
        int result = multiply(2, 5);
        std::cout << result << std::endl;
        return 0;
    }
}
```

預設 Emscripten 產生的 .js 只會執行 main function，如果想要呼叫其他韓式必須在欲輸出 function 前加上 `EMSCRIPTEN_KEEPALIVE`，在 Comile 時指定參數 `-s NO_EXIT_RUNTIME=1` 避免 wasm 執行 main function 後直接退出

另外如果是使用 C++ 而不是 C，建議在要輸出的 function 前加上 `extern "C"`，主要是指定這一段程式碼用 C 的方式編譯，這樣輸出的 function 名稱會保持原狀，可以試著拿掉看看

> \$ emcc build/multiply.cpp -s NO_EXIT_RUNTIME=1 -o multiply.js

此時會輸出 `multiply.js & multiply.wasm`

如果不確定 compiled 出來的檔案能不能運行，建議先 `-o {filename}.html` 確認可以運作，接著再考慮移植

### 在網頁使用 multiply.out.js

獨立產生 index.html

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="X-UA-Compatible" content="ie=edge" />
    <title>Document</title>
    <script src="./multiply.js"></script>
    <script>
      Module.onRuntimeInitialized = function() {
        console.log(Module);
        console.log(Module._main());
        console.log(Module._multiply(2, 7));
      };
    </script>
  </head>
  <body>
    請打開 Console
  </body>
</html>
```

當我們打開 Console，可以看到 `10`，以及 `Module` 這個由 `multiply.js` export 的 Object，當我們想要使用 Module 當中的參數，需要包在 `onRuntimeInitialized` listener 當中，等 Module 初始化完成才能調用，Module 裡頭包含非常多的參數與 function，後續會再介紹

而我們輸出的 function 會主動被加上 `_` 前綴，如果要傳入 int 直接用 JS 的 number 就可以了

甚至如果用 `Module._multiply(2, "10")` 都會成功輸出 20，傳入參數時會自動做型別轉換，如果輸入純字串則會回傳 0

## 記憶體操作，關於 Pointer & Array

在 C/C++ 中，pointer 很常被直接當作參數傳遞，讓 sub function 直接操作 pointer 指向的記憶體位置，function return 後原 function 可以直接取值出來用

目標是實作一個 filter function biggerThan，只有大於 target 的 element 會被塞進 array_pointer 指向的記憶體位置，size 指向最後的 array length

```js
// 目標
biggerThan([elements], elements.length, target, &array_pointer, &size)
```

```cpp
#include <iostream>
#include <stdlib.h>
#include <emscripten/emscripten.h>

extern "C"
{
    EMSCRIPTEN_KEEPALIVE
    void biggerThan(int *elementList, int elementListLength, int target, int **result, int *size)
    {
        *result = (int *)malloc(sizeof(target) * elementListLength);
        std::cout << *result << std::endl;
        for (int i = 0; i < elementListLength; i++)
        {
            if (elementList[i] > target)
            {
                (*result)[*size] = elementList[i];
                *size = *size + 1;
            }
        }
        std::cout << "size mem position:" << *size << "\nresult mem position:" << result[0] << std::endl;
    }
}
```

> \$ emcc build/bigger_than.cpp -O1 -s NO_EXIT_RUNTIME=1 -o bigger_than.js

`-O1` 是指名要 compiler optimize 輸出結果，-O1 是初步優化，-O2 / -O3 是更進階耗時的優化，但要小心優化可能會移除需要的功能

接著是 index.html

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="X-UA-Compatible" content="ie=edge" />
    <title>Document</title>
    <script src="./bigger_than.js"></script>
    <script>
      Module.onRuntimeInitialized = function() {
        const elementList = new Int32Array([1, 2, 3, 4, 5, 6]);
        const elementListBuffer = Module._malloc(
          elementList.length * elementList.BYTES_PER_ELEMENT
        );
        Module.HEAP32.set(elementList, elementListBuffer >> 2);

        const target = 2;
        const result = new Int32Array(1);
        const resultBuffer = Module._malloc(
          result.length * result.BYTES_PER_ELEMENT
        );
        Module.HEAP32.set(result, resultBuffer / result.BYTES_PER_ELEMENT);

        const size = new Int32Array(1);
        const sizeBuffer = Module._malloc(size.length * size.BYTES_PER_ELEMENT);
        Module.HEAP32.set(size, sizeBuffer / size.BYTES_PER_ELEMENT);

        console.log(
          `mem position:\nsizeBuffer: ${sizeBuffer} resultBuffer: ${resultBuffer}`
        );
        Module._biggerThan(
          elementListBuffer,
          elementList.length,
          target,
          resultBuffer,
          sizeBuffer
        );

        const sizeInMem =
          Module.HEAP32[sizeBuffer / Int32Array.BYTES_PER_ELEMENT];
        const resultRef =
          Module.HEAP32[resultBuffer / Int32Array.BYTES_PER_ELEMENT];
        const resultInMem = new Int32Array(sizeInMem);

        console.log(
          resultBuffer,
          resultRef,
          Module.HEAP32[resultRef / Int32Array.BYTES_PER_ELEMENT + 1]
        );
        for (let i = 0; i < sizeInMem; i++) {
          resultInMem[i] =
            Module.HEAP32[resultRef / Int32Array.BYTES_PER_ELEMENT + i];
        }

        console.log(sizeInMem, resultInMem);

        Module._free(resultBuffer);
        Module._free(sizeBuffer);
        Module._free(elementListBuffer);
      };
    </script>
  </head>

  <body>
    請打開 Console
  </body>
</html>
```

#### ArrayBuffer & TypedArray

在開始之前，必須先了解 JS 如何處理 binary data，在 JS 中 binary data 是以 `ArrayBuffer` 表示，ArrayBuffer 只能讀不能做其他的操作，只能透過 `TypedArray` 與 `Dataview`轉換，而 Wasm 中會用到的是 TypedArray

TypedArray 有許多不同長度的類型，如 Int8Array / Int16Array，數字代表每個 element 的 bit 長度

```js
const buffer = new ArrayBuffer(2);
const i8 = new Int8Array(buffer);
i8[0] = 100;
i8[1] = 20;
const i16 = new Int16Array(buffer);
console.log(i16[0]); // 5220，因為是 0x14 0x64
```

如果兩個 Type Array 從同一個 ArrayBuffer 生成，則兩者改動都會互相影響，如果遇到不同類型互轉，則高位在後低位在前，所以 `i16[0] = i8[1] * 2^8 + i8[0]`
![](https://media.prod.mdn.mozit.cloud/attachments/2014/09/16/8629/80522bcbdb9d77c4a4c72a289365ea63/typed_arrays.png)

在 C/C++中，有多種不同長度的型別，例如 char / int / float / double 加上 signed / unsigned 等，就會一一對照到 JS 的 Typed Array
![](/post/img/typedarray.jpeg)

#### Pass Array by pointer

當我們要讓 C++ 讀取陣列，我們不能直接傳遞陣列，而是先在 JS 中把陣列放進 Memory --> 接著傳遞 Memory 中的位址 --> 從 Memory 位址讀取陣列的元素

在 Wasm 中，一開始初始化會需要 Memory Object，表明整個 Wasm 能夠使用多大的記憶體，接著把資料放進記憶體當中，並取得存放的位址，將位址從 JS 傳遞給 C++，C++ 去相對應的記憶體空間將值取出

Emscripten 簡化這個過程，改用 `_malloc` 去取得記憶體空間，並由對應類別大小的 HEAP 塞入空間，此時會拿到記憶體位址

```js
const elementList = new Int32Array([1, 2, 3, 4, 5, 6]);
const elementListBuffer = Module._malloc(
  elementList.length * elementList.BYTES_PER_ELEMENT
);
Module.HEAP32.set(elementList, elementListBuffer >> 2);
```

這段話的翻譯是

1. 產生 [1, 2, 3, 4, 5, 6] 陣列，每個元素是 32 bits (4 bytes) 大，剛好對應 C++ 的 int 大小
2. 索取記憶體空間，\_malloc 需指定要多大的 bytes 空間，此例需要 6 \* 4 = 24 bytes，elementListBuffer 此時代表這塊記憶體的起始位置，每間隔 4 個 bytes 就是陣列的下一個元素
3. 因為每個元素是 32 bits，所以用 HEAP32 塞資料，這邊 elementListBuffer >> 2 是因為每個儲存單位是 4 bytes， >> 2 代表 / 4  
   可以想像是大小抽屜，JS 中操作最小單位是單一個 byte，如果是 Int8Array 則是一個抽屜對應一個單位，但如果是 Int32Array，就是一個抽屜對應四個單位，所以編號(位址)也會比小抽屜少四分之一

在 C++ 當中，要輪詢 elementList 陣列的值，就只要

```c++
for (int i = 0; i < elementListLength; i++)
{
    elementList[i]....
}
```

#### Pointer

在 Wasm 中，pointer 是 32 bits，所以針對 result / size 都是用 Int32Array，即使 size 是整數而非"陣列"，但是一樣用 Int32Array 宣告

先看 size，宣告方式相同，最後要取值時，同樣是去 Memory 中的位置找，記得一樣要做位址座標的切換

```js
const size = new Int32Array(1);
const sizeBuffer = Module._malloc(size.length * size.BYTES_PER_ELEMENT);
Module.HEAP32.set(size, sizeBuffer / size.BYTES_PER_ELEMENT);

// 取值
const sizeInMem = Module.HEAP32[sizeBuffer / Int32Array.BYTES_PER_ELEMENT];
```

##### Pointer of pointer

再來是比較特別的 result，這其實是一個 pointer of pointer，先看 C++ 實作

```cpp
*result = (int *)malloc(sizeof(target) * elementListLength);
```

在 JS 層我並沒有先建立整個陣列，而是到了 C++ 才用 malloc 方式去索取陣列的記憶體空間，此時新增加的記憶體空間 JS 並不知道在哪裡，所以我必須想辦法回傳，此時可以透過 return value，我選擇直接修改 result 的值，暫存記憶體位址，再用這個位址去找真正的陣列所在處

```js
const resultRef = Module.HEAP32[resultBuffer / Int32Array.BYTES_PER_ELEMENT];
const resultInMem = new Int32Array(sizeInMem);

for (let i = 0; i < sizeInMem; i++) {
  resultInMem[i] = Module.HEAP32[resultRef / Int32Array.BYTES_PER_ELEMENT + i];
}
```
唸起來很擾口，但也就是多一次的記憶體位址的轉換

#### free
最後別忘了要釋放索取的記憶體，避免 Memory leak
```js
Module._free(resultBuffer);
```

## 總結

WebAssembly 讓網頁開發的「部分功能」可以外包給給其他語言，讓網頁開發的疆域與技術更加的彈性與兼容，甚至未來可以有更多的跨語言協作的可能，十分令人期待

這一篇教學介紹了 Emscripten 工具，與 C/C++ 編譯出的 Wasm 如何跟 JS 互動，包含基本的整數運算、陣列操作、Pointer 與記憶體存取

下一篇預計介紹不使用 Emscripten，直接用 Clang 編譯 Wasm，還原到最簡單原始的狀態去認識 Wasm
