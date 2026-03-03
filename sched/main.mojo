from algorithm import parallelize
from memory import alloc

fn main():
    var iterations = 1000000
    
    # 它會回傳一個 UnsafePointer[Int]
    var counter = alloc[Int](1)
    
    # 初始化記憶體內容為 0
    counter[0] = 0

    print("--- 併發測試開始 ---")

    # 定義平行任務
    # @parameter 閉包會捕捉外部的 counter 指標
    @parameter
    fn worker(i: Int):
        # 觸發 Race Condition 的核心：
        # counter[0] += 1 本質上是：
        # 1. 讀取 (Load) counter[0] 的值
        # 2. 進行加法
        # 3. 寫回 (Store) 到 counter[0]
        # 當多個執行緒同時執行第 1 步時，它們會拿到相同的舊值，導致更新遺失。
        counter[0] += 1

    # 使用 parallelize 執行並行運算
    parallelize[worker](iterations)

    var final_val = counter[0]
    print("預期結果:", iterations)
    print("實際結果:", final_val)
    
    if final_val < iterations:
        print("狀態：Race Condition 成功觸發！")
        print("遺失更新次數:", iterations - final_val)
    else:
        print("狀態：未發生競爭。請嘗試在更強大的多核 CPU 上執行或增加 iterations。")

    # 使用全域 free 函數釋放分配的記憶體
    counter.free()