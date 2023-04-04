---
title: '【算法】Union Find 解題整理'
description: 參照《九章算法》，整理 Union Find 的常見題目與解題技巧
date: '2022-03-27T01:21:40.869Z'
categories: ['Algorithm']
keywords: ['leetcode']
draft: true
---
題目整理：
1. [200. Number of Islands](https://leetcode.com/problems/number-of-islands/)
2.  [305. Number of Islands II](https://leetcode.com/problems/number-of-islands-ii/)
3. [130. Surrounded Regions](https://leetcode.com/problems/surrounded-regions/)
4. [721. Accounts Merge](https://leetcode.com/problems/accounts-merge/)

## 解題思路
當今天看到找合併群組 `connecting adjacent / merge` 關鍵字，想要找兩個元素是否處於相同的連通塊 (disjoint union) / 連通塊數量，大概就是 Union Find 可以派上用場的地方，通常出現在 Graph 相關問題，所以大多數 Union Find 問題也能用 BFS / DFS 解決，但如果是 `動態改變`如 305 則使用 Union Find 會輕鬆很多

### Union Find 基本介紹
Union Find 主要是維護一個資料結構 (常用陣列，也可以用 HashMap)，保持元素所對應的群組，如果今天兩個元素要合併，找到元素所屬群組的代表值進行合併；  
如果要判斷兩元素`是否為相同群組`，則找到對應群組的代表值比對即可

聽起來有點抽象，但是用 Tree 的概念去想像就比較好理解，舉例我們該如何知道 Node 1 跟 Node 3 是同一個群組？
![](/post/2022/img/0328/uf_1.png)
維護一個 parents 數組，初始化 parents[i] = i 視為每個元素都為獨立的族群(自己的 root 就是自己)；如果合併時挑選某一方當作 group root，在查找時只要一直往下找就能找到相同的 root   

既然是 Tree 的構造，不免俗會遇到 `平衡的問題`，如果合併時 Tree 不平衡，最差情況在搜尋時會是 O(N)，因為要 iterate N 次才能找到組群代表；  
這時候需要套用`路徑壓縮`的技巧，當我在查找時，如果我是很深的葉節點，我沿路把父節點直接指向 root 攤平，這樣在合併與查找的複雜度會變成 `O(log* N)` 約等於 O(1)
![](/post/2022/img/0328/uf_2.png)

程式碼如下
```cpp
class UnionFind {
public:
    UnionFind(int s) {
        size = s;
        parents.resize(s);
        // 初始化，很重要不要忘記!
        for(int i = 0; i < size; i++) {
            parents[i] = i; // 每人都是 group root
        }
    }
    
    void connect(int idx1, int idx2) {
        int parent1 = find(idx1);
        int parent2 = find(idx2);
        if (parent1 == parent2) {
            return;
        }
        
        // 隨意合併
        parents[parent1] = parent2;
    }
    
    int find(int idx1) {
        int root = idx1;
        while(root != parents[root]) {
            root = parents[root];
        }
        
        int parent = idx1;
        int prevParent;
        // 路徑壓縮，把沿路的 parent 都直接指向 root
        while(parent != parents[parent]) {
            prevParent = parents[parent];
            parents[parent] = root;
            parent = prevParent;
        }
        
        return root;
    }
private:
    int size;
    vector<int> parents;
};
```

## 解題
[200. Number of Islands](https://leetcode.com/problems/number-of-islands/) 要找島嶼的數量，也就是算 Union Find 中族群數

解題思路大致為
1. 假設每一塊島嶼都不連通，預設數量為 "1" 的個數
2. 輪詢島嶼，檢查上下左右是否能連通，發生連通則代表島嶼合併，數量減一
3. 回傳最終島嶼數量
```cpp
class UnionFind {
public:
    int island = 0;
    
    UnionFind(vector<vector<char>>& grid) {
        rowSize = grid.size();
        colSize = grid.front().size();
        fathers.resize(rowSize * colSize);
        
        for (int row = 0; row < rowSize; row++) {
            for (int col = 0; col < colSize; col++) {
                if (grid[row][col] == '1') {
                    int idx1D = getIdx1D(pair<int, int> {row, col});
                    fathers[idx1D] = idx1D;
                    island++;
                }
            }
        }
    }
    
    void connect(pair<int, int> pos1, pair<int, int> pos2) {
        int idx1D1 = getIdx1D(pos1);
        int idx1D2 = getIdx1D(pos2);
        
        int father1 = find(idx1D1);
        int father2 = find(idx1D2);
        if (father1 == father2) {
            return;
        }
        
        // 當發生合併時，代表島嶼數量合併少一個
        island--;
        fathers[father1] = father2;
    }
    
    int find(int idx) {
        int root = idx;
        while(fathers[root] != root) {
            root = fathers[root];
        }
        
        int parent = idx;
        while(fathers[parent] != parent) {
            int temp = fathers[parent];
            fathers[parent] = root;
            parent = temp;
        }
        
        return root;
    }
    
    int getIdx1D(pair<int, int> pos) {
        return pos.first * colSize + pos.second;
    }
private:
    vector<int> fathers;
    int rowSize;
    int colSize;
};

class Solution {
public:
    int numIslands(vector<vector<char>>& grid) {
        if (grid.size() == 0 || grid.front().size() == 0) {
            return 0;
        }
        
        UnionFind* uf = new UnionFind(grid);
        int rowSize = grid.size();
        int colSize = grid.front().size();
        const std::vector<std::pair<int, int>> moves = {
            {1, 0},
            {-1, 0},
            {0, 1},
            {0, -1}
        };
        for (int row = 0; row < rowSize; row++) {
            for (int col = 0; col < colSize; col++) {
                if (grid[row][col] == '0') {
                    continue;
                }
                
                for (const auto move:moves) {
                    int newRow = row + move.first;
                    int newCol = col + move.second;
                    if (newRow < 0 || newRow >= rowSize || newCol < 0 || newCol >= colSize) {
                        continue;
                    }
                    if (grid[newRow][newCol] == '0') {
                        continue;
                    }
                    uf->connect(std::pair<int, int> {row, col}, std::pair<int, int> {newRow, newCol});
                }
            }
        }
        
        return uf->island;
    }
};
```
這題完全可以用 BFS 解，時間複雜度同為 O(M\*N)，但是 BFS 的空間複雜度是 O(min(M,N)) 更優於 Union Find 的 O(M\*N)，BFS 空間複雜度是看 queue 上的 Node 數量   

### 變化題：動態連通
[305. Number of Islands II](https://leetcode.com/problems/number-of-islands-ii/) 這一題是上一題延伸，使用 Union Find 就非常適合，因為題目是逐一增加島嶼，需要動態計算島嶼數量，如果用 BFS 都要每次從頭開始算，但 Union Find 不用  

解題類似上方，只是在每次加入島嶼時先加一，有連通再減一
```cpp
class UnionFind {
public:
    int island;
    
    UnionFind(int m, int n) {
        rowSize = m;
        colSize = n;
        island = 0;
        parents.resize(m * n);
        for (int row = 0; row < rowSize; row++) {
            for (int col = 0; col < colSize; col++) {
                int idx = get1DIdx(pair<int, int> {row, col});
                parents[idx] = idx;
            }
        }
    }

    void connect(pair<int, int> pos1, pair<int, int> pos2) {
        int idx1D_1 = get1DIdx(pos1);
        int idx1D_2 = get1DIdx(pos2);
        
        int parent1 = find(idx1D_1);
        int parent2 = find(idx1D_2);
        if (parent1 == parent2) {
            return;
        }
        
        // 有連通就減一
        island--;
        parents[parent1] = parent2;
    }
    
    int find(int idx) {
        int root = idx;
        while (parents[root] != root) {
            root = parents[root];
        }
        
        int parent = idx;
        while (parents[parent] != parent) {
            int prevParent = parents[parent];
            parents[parent] = root;
            parent = prevParent;
        }
        
        return root;
    }
    
    int get1DIdx (pair<int, int> pos) {
        return pos.first * colSize + pos.second;
    }
private:
    std::vector<int> parents;
    int rowSize;
    int colSize;
};

class Solution {
public:
    vector<int> numIslands2(int m, int n, vector<vector<int>>& positions) {
        if (m == 0 || n == 0) {
            return std::vector<int>{};
        }
        
        std::vector<std::vector<int>> grids(m, std::vector<int> (n, 0));
        UnionFind* uf = new UnionFind(m, n);
        std::vector<int> islandNums;
        for (const auto pos:positions) {
            int row = pos[0];
            int col = pos[1];
            if(grids[row][col] == 1) {
                islandNums.push_back(uf->island);
                continue;
            }
            
            grids[row][col] = 1;
            // 先假設沒有連通，直接加一
            uf->island++;
            for (const auto move:kMoves) {
                int newRow = row + move.first;
                int newCol = col + move.second;
                if (newRow < 0 || newRow >= m || newCol < 0 || newCol >= n ||
                    grids[newRow][newCol] == 0
                   ) {
                    continue;
                }

                uf->connect(std::pair<int, int> {row, col}, std::pair<int, int> {newRow, newCol});
            }
            islandNums.push_back(uf->island);
        }
        
        return islandNums;
    }
private:
    const std::vector<std::pair<int, int>> kMoves = {
        {1, 0},
        {-1, 0},
        {0, 1},
        {0, -1}
    };
};
```

### 變化題：額外追蹤對應數據
[130. Surrounded Regions](https://leetcode.com/problems/surrounded-regions/)除了要找出連通塊，還必須知道該連通塊是不是有碰到邊界，沒有就要全部更新

解題思路上非常類似，但多一個 isSurrounded 陣列追蹤該連通塊是不是碰到邊界

```cpp
class UnionFind {
public:
    UnionFind(std::vector<std::vector<char>>& board) {
        rowSize = board.size();
        colSize = board.front().size();
        parents.resize(rowSize * colSize);
        isSurrounded.resize(rowSize * colSize);
        for (int row = 0; row < rowSize; row++) {
            for (int col = 0; col < colSize; col++) {
                int idx = getIdx1D(std::pair<int, int> {row, col});
                parents[idx] = idx;
            }
        }
    }
    
    void connect(const std::pair<int, int> pos1, const std::pair<int, int> pos2) {
        int idx1 = getIdx1D(pos1);
        int idx2 = getIdx1D(pos2);
        
        int parent1 = find(idx1);
        int parent2 = find(idx2);
        if (isOnEdge(pos1) || isOnEdge(pos2) || isSurrounded[parent1] || isSurrounded[parent2]) {
            isSurrounded[parent1] = true;
            isSurrounded[parent2] = true;
        }
        
        if(parent1 == parent2) {
            return;
        }
        
        parents[parent1] = parent2;
    }
    
    bool isRegionConnectedEdge(const std::pair<int, int> pos) {
        if(isOnEdge(pos)) return true;
        
        int idx = getIdx1D(pos);
        int parent = find(idx);
        return isSurrounded[parent];
    }
private:
    std::vector<int> parents;
    std::vector<bool> isSurrounded;
    int rowSize;
    int colSize;
    
    bool isOnEdge(const std::pair<int, int> pos) {
        if (pos.first == 0 || pos.first == rowSize -1 || pos.second == 0 || pos.second == colSize - 1) return true;
        return false;
    }
    
    int getIdx1D(const std::pair<int, int> pos) {
        return pos.first * colSize + pos.second;
    }
    
    int find(int idx) {
        int root = idx;
        while(parents[root] != root) {
            root = parents[root];
        }
        
        int parent = idx;
        while(parents[parent] != parent) {
            int prevParent = parents[parent];
            parents[parent] = root;
            parent = prevParent;
        }
        
        return root;
    }
};

class Solution {
public:
    void solve(vector<vector<char>>& board) {
        // union find to join region
        // keep track root is surrounded or not
        // loop through uf and flip
        if (board.size() == 0 || board.front().size() == 0) {
            return;
        }
        
        int rowSize = board.size();
        int colSize = board.front().size();
        UnionFind* uf = new UnionFind(board);
        for (int row = 0; row < rowSize; row++) {
            for (int col = 0; col < colSize; col++) {
                if (board[row][col] == 'X') {
                    continue;
                }
                
                for (const auto move:kMoves) {
                    int newRow = row + move.first;
                    int newCol = col + move.second;
                    if (newRow < 0 || newRow >= rowSize || newCol < 0 || newCol >= colSize ||
                        board[newRow][newCol] == 'X'
                       ) {
                        continue;
                    }
                    
                    uf->connect(std::pair<int, int> {row, col}, std::pair<int, int> {newRow, newCol});
                }
            }
        }
        
        // 連通完再來更新數據
        for (int row = 0; row < rowSize; row++) {
            for (int col = 0; col < colSize; col++) {
                std::pair<int, int> pos {row, col};
                if (!uf->isRegionConnectedEdge(pos)) {
                    board[row][col] = 'X';
                }
            }
        }
    }
    
private:
    const std::vector<std::pair<int, int>> kMoves = {
        {1, 0},
        {-1, 0},
        {0, 1},
        {0, -1}
    };
};
```

### 變化題：結合複雜的數據結構
[721. Accounts Merge](https://leetcode.com/problems/accounts-merge/)是 medium 難度但我覺得他比 130 hard 還要難做 OTZ  

解題思路大概是
1. 先透過 Union Find 找出連通塊
2. 透過 Hash Map，把連通塊內用 set 儲存不重複 account
3. iterate Hash Map，組合出答案

```cpp
class UnionFind {
public:
    UnionFind(int s) {
        size = s;
        parents.resize(s);
        for(int i = 0; i < size; i++) {
            parents[i] = i;
        }
    }
    
    void connect(int idx1, int idx2) {
        int parent1 = find(idx1);
        int parent2 = find(idx2);
        if (parent1 == parent2) {
            return;
        }
        
        parents[parent1] = parent2;
    }
    
    int find(int idx1) {
        int root = idx1;
        while(root != parents[root]) {
            root = parents[root];
        }
        
        int parent = idx1;
        int prevParent;
        while(parent != parents[parent]) {
            prevParent = parents[parent];
            parents[parent] = root;
            parent = prevParent;
        }
        
        return root;
    }
private:
    int size;
    vector<int> parents;
};

class Solution {
public:
    vector<vector<string>> accountsMerge(vector<vector<string>>& accounts) {
        // store account group
        std::unordered_map<string, int> accountGroup;
        // union account group
        UnionFind* uf = new UnionFind(accounts.size());
        for (int i = 0; i < accounts.size(); i++) {
            int currGroup = i;
            for (int j = 1; j < accounts[i].size(); j++) {
                string account = accounts[i][j];
                if (accountGroup.find(account) != accountGroup.end()) {
                    // group is not the same as current group, union them
                    int group = accountGroup[account];
                    if (group != currGroup) {
                        uf->connect(currGroup, group);
                    }
                }
                accountGroup[account] = currGroup;
            }
        }
        
        std::unordered_map<int, std::unordered_set<string>> accountsMergeMap;
        for (int i = 0; i < accounts.size(); i++) {
            // find same group root
            int group = uf->find(i);
            for (int j = 1; j < accounts[i].size(); j++) {
                accountsMergeMap[group].insert(accounts[i][j]);
            }
        }
        
        std::vector<std::vector<string>> accountsMergeResult;
        for (const auto mergeMap:accountsMergeMap) {
            std::vector<string> accountGroup;
            accountGroup.push_back(accounts[mergeMap.first][0]);
            accountGroup.insert(accountGroup.end(), mergeMap.second.begin(), mergeMap.second.end());
            std::sort(accountGroup.begin() + 1, accountGroup.end());
            accountsMergeResult.push_back(accountGroup);
        }
        
        
        return accountsMergeResult;
    }
};
```

## 總結
Union Find 在解決連通塊問題蠻好用的，可以提供 O(1) 的合併與查詢時間複雜度，並且能處理動態合併的問題，需注意`如果有刪除合併則不能用 Union Find`  