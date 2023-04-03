---
title: '【算法】Sliding Window / 滑動視窗解題整理'
description: 整理 Sliding Window 的常見題目與解題技巧
date: '2022-03-26T01:21:40.869Z'
categories: ['Algorithm']
keywords: ['leetcode']
draft: true
---
題目整理：
1. [209. Minimum Size Subarray Sum](https://leetcode.com/problems/minimum-size-subarray-sum/)
2.  [713. Subarray Product Less Than K](https://leetcode.com/problems/subarray-product-less-than-k/)
3. [3. Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/)
4. [340. Longest Substring with At Most K Distinct Characters](https://leetcode.com/problems/longest-substring-with-at-most-k-distinct-characters/)
5. [438. Find All Anagrams in a String](https://leetcode.com/problems/find-all-anagrams-in-a-string/)
6. [76. Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/)

## 解題思路
當今天看到 `continues subarray`、`substring`加上 `minimum/maxsimun `時就可以留意是不是能套用滑動視窗，例如第一題 209. Minimum Size Subarray Sum
> Given an array of positive integers nums and a positive integer target, return the `minimal length` of a `contiguous subarray`

### 暴力解 1: 窮舉子陣列的可能
再進入滑動視窗前，先看暴力解的思考方式，今天 209 「給定一個陣列與一個目標，想要在陣列中找到一段連續的子陣列加總 >= 目標，如果找不到則回傳 0」  
既然是要找子陣列，那最直接暴力 n * n 展開，如
```bash
[1,2,3,4] 的所有子陣列組合有 
[1], [1, 2], [1, 2, 3], [1, 2, 3, 4]
[2], [2, 3], [2, 3, 4],
[3], [3, 4]
[4]
```
程式碼為
```cpp
class Solution {
public:
    int minSubArrayLen(int target, vector<int>& nums) {
        int minLen = INT_MAX;
        int sum = 0;
        for (int i = 0; i < nums.size(); i++) {
            sum = 0;
            for (int j = i; j < nums.size(); j++) {
                sum += nums[j];
                if (sum >= target) {
                    minLen = min(j - i + 1, minLen);
                    break;
                }
            }
        }
        
        return minLen == INT_MAX ? 0:minLen;
    }
};
```
時間複雜度為: O(n^2)

### 暴力解 2: 前綴和
來看另一個 O(n^2) 的解法，`前綴和`的概念蠻聰明的，未來在動態規劃也會用上，基本上求某一段子陣列的和可以用預先加總的方式去求，而不需要每次都 iterate 加總，公式如下
```cpp
// 先求出從頭開始到 index i 的加總
sums[i+1] = nums[0] + nums[1] .. nums[i]

// 如果要求 i ~ j 子陣列的合，不用 iterate i ~ j，只要用 sums[j] - sums[i-1]
sums[j+1] = sums[0] + ... + sums[i - 1] + ... + sums[j]  
sums[i] = sums[0] + ... + sums[i-1]  
sums[j+1] - sums[i] = sums[i] + ... sums[j]

// ex. nums = [1,2,3,4]
sums [0, 1, 3, 6, 10]
idx 1~2 = sums[3] - sums[1] = 5
```
![](/posts/2022/img/0326/prefix-sum.png)
實際運行，index 會差 1 因為 sums[0] 需要儲存初始值 0，sums[1] 才會是 nums[0]，否則會無法求出區段為 idx 0 的第一小段，程式碼如下
```cpp
class Solution {
public:
    int minSubArrayLen(int target, vector<int>& nums) {
        int minLen = INT_MAX;
        int n = nums.size();
        std::vector<int> sums (n+1, 0);
        for (int i = 1; i <= nums.size(); i++) {
            sums[i] = sums[i-1] + nums[i-1];
        }
        
        int sum = 0;
        for (int i = 0; i < nums.size(); i++) {
            for (int j = i; j < nums.size(); j++) {
                sum = sums[j+1] - sums[i];
                if (sum >= target) {
                    minLen = min(j - i + 1, minLen);
                    break;
                }
            }
        }
        
        return minLen == INT_MAX ? 0:minLen;
    }
};
```
時間複雜度同樣為 O(n^2)，多一個空間複雜度 O(n)

## Sliding Window
接下來看 Sliding Window 如何用 O(n) 解決這道題目，滑動視窗的解法提示在`找出在連續位置內符合某條件的狀況下，最短/最長/最小/最大的組合`，從剛才的窮舉子陣列可以看出，我們一直在移動試圖找出某個滿足條件的區間，接著我們要在區間內找出最佳組合

今天我們可以透過同向雙指針
1. 先從右指針開始往右走直到條件符合  
2. 為了找出最短解，開始移動左指針，直到條件不合
3. 如果條件不合，移動右指針

，用 pseudo code 表示大概為
```cpp
left = 0
for (int right = 0; right < size; right++) {
    條件 += arr[right]
    while (條件符合) {
        條件 - arr[left]
        left++
        ans = right - left + 1
    }
}
```
完整程式碼是
```cpp
class Solution {
public:
    int minSubArrayLen(int target, vector<int>& nums) {
        int left = 0;
        int sum = 0;
        int minLen = INT_MAX;
        for (int right = 0; right < nums.size(); right++) {
            sum += nums[right];
            while(sum >= target) {
                minLen = std::min(right - left + 1, minLen);
                sum -= nums[left];
                left++;
            }
        }
        
        return minLen == INT_MAX? 0:minLen;
    }
};
```
對比前面的程式碼，簡潔許多執行速度又快，這邊有幾個小地方
1. 記得移動左指針用 while，因為有可能會一次性移動很多
2. while 條件不需要檢查 left 會不會超過邊際，因為 sum >= target 已經會限制住 (left 是追隨 right 腳步)

> 會有疑慮說「這樣移動雙指針不會有任何遺漏嗎？」我們試著看滑動視窗節省了暴力解的哪些步驟  
> 假設題目是 nums = [1, 2, 3, 4], target = 5  
> 暴力解會是 [1] / [1,2] / [1,2,3] 找到一組解，換下一輪 [2] / [2,3] 找到第二組解    
> 但其實當我們找到 [1,2,3]，移動左指針 [2,3] 就可以找到，我們不需要從 [2] 開始從頭找起，因為第一輪的加總其實有涵蓋到這一段了 

### 變化題1 - 改求乘積
[713. Subarray Product Less Than K](https://leetcode.com/problems/subarray-product-less-than-k/) 變化了一些，改求連續乘積小於 k 的組合數，解法部分我先照模板先連續乘積，接著限縮乘積要小於 k，最後才是算組合數，組合數的算法是高中數學    
乘積容易有陷阱，尤其是遇到 `0 / 1`，所以 while loop 必須額外檢查 left <= right，避免遇到 \[1,1..\] 連續 1 的狀況，會讓後面的計算出錯
```cpp
class Solution {
public:
    int numSubarrayProductLessThanK(vector<int>& nums, int k) {
        if (k == 0) {
            return 0;
        }
        
        int product = 1;
        int left = 0;
        int count = 0;
        for (int right = 0; right < nums.size(); right++) {
            product *= nums[right];
            while(product >= k and left <= right) {
                product /= nums[left];
                left++;
            }
            count += (right - left + 1);
        }
        
        return count;
    }
};
```

### 變化題2 - 字串
字串類的處理比數字類再複雜一些，尤其是字串比對的時間複雜度要記得考慮到，但其實大致邏輯會一樣，看一下元老題 [3. Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/)

```cpp
class Solution {
public:
    int lengthOfLongestSubstring(string s) {
        std::array<int, 255> dict;
        dict.fill(0);
        
        int maxLen = 0;
        int left = 0;
        for (int right = 0; right < s.size(); right++) {
            char c = s[right];
            dict[c]++;
            while (dict[c] > 1) {
                char leftChar = s[left];
                dict[leftChar]--;
                left++;
            }
            maxLen = std::max(right - left + 1, maxLen);
        }
        
        return maxLen;
    }
};
```
邏輯是差不多，補充一下字符的數量計算，建議用 `std::array<int, 255>` 即可，方便好用，同時型別也很明確，但別忘了要 `arr.fill(0)` 初始化否則會出錯  

補充一下我原本想說降低不必要的儲存，想說用 `c - 'A'` 來降低儲存空間，但這樣換算很累，而且`英文字母大小寫在 ascii 表中不是連續的`，所以就直接用 255 儲存  

[340. Longest Substring with At Most K Distinct Characters](https://leetcode.com/problems/longest-substring-with-at-most-k-distinct-characters/) 很類似，完整解法為
```cpp
class Solution {
public:
    int lengthOfLongestSubstringKDistinct(string s, int k) {
        std::array<int, 255> dict;
        dict.fill(0);
        int distinctCount = 0;
        int maxLen = 0;
        int left = 0;
        for (int right = 0; right < s.size(); right++) {
            char c = s[right];
            dict[c]++;
            if(dict[c] == 1) {
                distinctCount++;
            }
            
            while(distinctCount > k) {
                c = s[left];
                dict[c]--;
                if (dict[c] == 0) {
                    distinctCount--;
                }
                left++;
            }
            
            maxLen = std::max(right - left + 1, maxLen);
        }
        
        return maxLen;
    }
};
```

### 變化題 3
[438. Find All Anagrams in a String](https://leetcode.com/problems/find-all-anagrams-in-a-string/) 再延伸一點字串的變化，這次比較兩個字串的字符數，判斷又更 tricky 些，需要注意子字串比對的過程，如果字符沒有出現在目標字串中，則捨棄目前的累積從頭開始
```cpp
class Solution {
public:
    vector<int> findAnagrams(string s, string p) {
        std::array<int, 26> pDict;
        pDict.fill(0);
        std::array<int, 26> sDict;
        sDict.fill(0);
        
        for (const auto c:p) {
            pDict[c-'a']++;
        }
        
        std::vector<int> indice;
        int left = 0;
        for (int right = 0; right < s.size(); right++) {
            int idx = s[right] - 'a';
            sDict[idx]++;
            
            
            if (pDict[idx] == 0) {
                // 如果該字符沒有出現在 p 當中，則代表目前這一整段都不會成立，直接從下一段開始 (left = right + 1)
                sDict.fill(0);
                left = right+1;
            } else if (sDict[idx] > pDict[idx]) {
                // 如果累積超過，則滑動左指針
                while(sDict[idx] > pDict[idx]) {
                    int leftIdx = s[left] - 'a';
                    sDict[leftIdx]--;
                    left++;
                }
            }
            
            if (findAnagram(sDict, pDict)) {
                indice.push_back(left);
            }
        }
        
        return indice;
    }
    
    bool findAnagram(std::array<int, 26>& dict1, std::array<int, 26>& dict2) {
        for(int i = 0; i < 26; i++) {
            if (dict1[i] != dict2[i]) {
                return false;
            }
        }
        return true;
    }
};
```

[76. Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) 這一系列唯一的 hard 難題，但是跟 438 相比我覺得反而比較簡單些；
```cpp
class Solution {
public:
    string minWindow(string s, string t) {
        std::array<int, 255> sDict;
        sDict.fill(0);
        std::array<int, 255> tDict;
        tDict.fill(0);
        for (const auto c:t) {
            tDict[c]++;
        }
        
        int left = 0;
        int minLeft = -1;
        int minRight = -1;
        for (int right = 0; right < s.size(); right++) {
            char c = s[right];
            sDict[c]++;
            while (isContain(sDict, tDict)) {
                if (minLeft == -1 || (minRight - minLeft) > (right - left)) {
                    minLeft = left;
                    minRight = right;
                }
                c = s[left];
                sDict[c]--;
                left++;
            }
        }
        
        return minLeft == -1 ? "": s.substr(minLeft, minRight - minLeft + 1);
    }
    
    bool isContain(std::array<int, 255> sDict, std::array<int, 255> tDict) {
        for (int i = 0; i < 255; i++) {
            if (sDict[i] < tDict[i]) return false;
        }
        return true;
    }
};
```

## 總結
Sliding Window 在於解決連續序列中求極值的過程，只要是這種窮舉子陣列的問題都能嘗試套用，時間複雜度優化到 O(N)