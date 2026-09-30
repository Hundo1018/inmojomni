# Roadmap(內部文件)

> 對外的現況描述放 README「Current limitations」;這裡是計畫與野心,
> 順序代表目前想做的優先序,隨時可調。

## 未竟事項(2026-09-30 更新)

### 已完成(本輪,host tier 驗證;硬體未重跑)

- 改追最新**穩定版** Mojo 1.1.0(使用者決策),pins 仍為 `==`;
  CI `nightly-latest` 改為 `stable-latest`:先放寬 Mojo pins 再
  `pixi update`,真的會測到新版(本機模擬解析到 1.1.0)。
- bounds check:選 (a) `-D ASSERT=none`,集中在 `MOJO_FIRMWARE_FLAGS`。
- 主機 LLVM 改由 pixi 釘 conda-forge 23.1.2(opt/llc/clang/ld.lld)。
  retarget 從 15 條規則減為 4 條(triple、datalayout、target-cpu、
  target-features 改寫);11 條「LLVM 版本落差」降級規則全部刪除。
  新增 `opt -force-attribute=nounwind`(裸機不會 unwind;否則 llc 產生
  EHABI 表,連進 libgcc unwinder)。
- 對照:RP2040 blink 780 B → 780 B,反組譯差 4 組指令
  (`ands`+`cmp` → `mvns`+`tst`,語意相同);volatile 數 15/371/80 不變;
  RP2350 blink 的 flash 映像(objcopy binary)md5 完全相同。
- CI 加 RP2350 build。README limitations 已更正。

### 待辦

1. **接探針重跑全部硬體 gate**:`pixi run test`、`bench`、所有
   `*-rp2350`;重量 benchmark 並更新 BENCHMARKS(目前各節仍是舊工具鏈數字,
   已標註)。`pixi run sizes` 也要重跑(需 rustc thumbv6m target)。
2. **刪掉 retarget 的根本解:讓 Mojo 帶 ARM 後端。** 編譯器已開源
   (2026-08-18,Apache-2.0 w/ LLVM exceptions;1.1 起收外部貢獻)。
   調查結果(modular/modular @98ef37b):
   - `bazel/public-patches/llvm_project.bzl`:`BACKENDS = ["AArch64",
     "RISCV", "X86"]`,另有 `llvm_configure.configure(extra_targets=[...])`。
   - `Mojo/lib/Target/Host/HostTraits.h` 的 `isSupported` 已接受
     `triple.isARM()`,註解說「covers the CPU targets the shipped build
     carries an LLVM backend for」——與 BACKENDS 不一致。
   - 實測 1.1.0:`--target-triple=thumbv6m-none-eabi` 等全部報
     「No available targets are compatible」(LLVM registry 沒有 ARM),
     不是 Mojo allowlist 擋的。
   - 做法:(a) 向上游提 issue/PR,把 "ARM" 加進 BACKENDS(一行,理由是
     HostTraits 已宣稱支援 isARM);上游接受後,RP2040 路徑可用
     `mojo build --target-triple=armv6m-none-eabi --target-cpu=cortex-m0plus
     --emit=object`,retarget.mojo、opt/llc、主機 LLVM 釘版全部可刪。
     (b) 等上游期間,可在自己機器用 `extra_targets = ["ARM"]` 自建編譯器
     驗證;雲端 session 不行:Bazel 從 github.com 下載 archive 被 egress
     政策擋(403),BuildBuddy remote downloader 回 UNAUTHENTICATED。
   - 未驗證:Mojo 的 ARM32 lowering(ABI、Int 寬度、soft-float 呼叫)是否
     直接可用;自建後第一個 gate 就是 test-host + 硬體 `pixi run test`。
3. riscv32 仍無上游承諾(stable 1.0.0 就關過)。`stable-latest` 會在
   新穩定版出現當天變紅。
4. GitHub Actions Node 20 棄用警告(checkout@v4、setup-pixi@v0.8.1)。
5. 仍等材料:I²C/SPI、邏輯分析儀自動化、WS2812/SSD1306/MPU6050 驅動。

## 近期

- [x] `print()`/log over **RTT** —— 2026-07-04 完成(`pico.rtt`,SEGGER 相容
      up channel,實機 HIL 驗證;`probe-rs attach` 即可看輸出)
- [x] **中斷**:NVIC + Mojo handler —— 2026-07-04 完成(`pico.irq` +
      crt0 弱符號向量,`@export("isr_irqN")` 連結期靜態綁定;比原計畫的
      RAM 向量表更簡單、零 RAM 成本。TIMER ALARM0 實機驗證兩次非同步觸發)
- [x] PWM、ADC(溫度感測器)、UART —— 2026-07-04 完成(`pico.pwm` comptime
      slice/channel、`pico.adc` XOSC 時脈 + read_temp_milli_c、`pico.uart`
      PL011 + LBE 零接線迴路測試;全部實機驗證)
- [x] GPIO 中斷 —— 2026-07-04 完成(`Pin.irq_enable` 路由 IO_IRQ_BANK0)
- [ ] I²C/SPI 驅動(需外部裝置驗證,等材料)
- [x] PIO v2(部分):side-set(含 optional/pindirs)、前向標籤 ——
      2026-07-04 完成,實機驗證(編碼檢查 + side-set 方波邊緣計數)
- [x] PIO comptime 組譯 —— 2026-07-04 完成(`comptime PROG = make()`,
      指令字成為 flash 常數;`comptime assert` 讓非法程式變編譯錯誤;
      host 單元測試釘住編碼 + 實機測試跑 comptime 組譯的程式)
- [x] 雙核心啟動 —— 2026-07-04 完成(`pico.multicore.launch()`,PSM 重置 +
      bootrom FIFO 握手 + timeout,core1 跑 Mojo 實機驗證)
- [x] 雙核心同步原語 —— 2026-07-04 完成(`pico.sync.Spinlock[N]` 硬體
      spinlock,雙核 2×20k 競爭遞增精確 40000;`multicore.fifo_push/pop`
      核間訊息,乒乓測試實機驗證)
- [ ] 韌體瘦身(已調查 2026-07-04):blink 780 B = boot2 256 + 向量表 192
      + core1 meta 8 + crt0 ~76 + mojo_main 248。mojo_main 內:常數池 44 B
      (11 個週邊位址)+ sleep 迴圈 4× 展開 ~24 B + 時脈初始化。-Oz 無效。
      要 <600 B 需把 mmio/init 重構為 base+offset 定址(動全 SDK,
      會影響 benchmark 暫存器壓力)——擱置,等有明確需求再做

## 中期

- [x] **RP2350 / Pico 2(RISC-V)原生編譯**——2026-07-18 完成:免 retarget,
      Mojo 直出;GPIO/PIO(含 PIO2)/雙核/TIMER/PWM/ADC/UART/Xh3irq/RTT/
      除錯全部實機 gate。架構:[MULTICHIP.md](MULTICHIP.md)
- [ ] riscv32 後端沒有上游支援承諾:dev2026071105 與 stable 1.0.0 都關過,
      1.1.0 release notes 列為 bug 修復。這是兩條路徑的單點依賴
      (README limitations 連到這裡)
- [ ] DMA、USB device(CDC serial → `print()` 到 USB)
- [ ] `inmojomni new` 專案模板:三行指令從零到第一次 blink
- [ ] WS2812 / SSD1306 / MPU6050 驅動(Mojo trait 風格 driver 生態的種子)

## 遠期

- [ ] ESP32-C3(RISC-V 原生)、STM32(共用 retarget 管線)
- [ ] async/await 風格的事件迴圈(embassy 的 Mojo 版)
- [ ] 向上游 Modular 回報嵌入式需求(ARM32 後端、no-std profile、
      freestanding assert)

## 採購清單(按 roadmap 驗證價值排序)

| 優先 | 材料 | 驗證什麼 |
|---|---|---|
| ✓ 已購 | Raspberry Pi Pico 2(RP2350) | 已完成原生 RISC-V 支援 |
| ★★★ | **8ch 24 MHz 邏輯分析儀**(fx2lafw 相容,~$10)| PIO 波形、PWM/I²C/SPI 時序的自動化驗證(sigrok-cli 可進 CI) |
| ★★☆ | 第二片 Pico(1 代)| MicroPython 第一手 benchmark;USB 功能開發時保留一片跑測試 |
| ★★☆ | WS2812 燈條(8–16 顆)| PIO 的殺手級 demo(800 kHz 精準時序) |
| ★★☆ | 麵包板 + 杜邦線 + 按鈕×4 + LED×8 + 電阻包(220Ω/1k/10k) | GPIO 事件/外部中斷/去彈跳的真實外部訊號測試 |
| ★☆☆ | SSD1306 0.96" OLED(I²C)| I²C driver + 畫面 = 最有感的 demo |
| ★☆☆ | MPU6050 模組 | I²C 讀感測器驅動的驗證載具 |
| ★☆☆ | B10K 電位器 | ADC 驗證 |
| ★☆☆ | SG90 舵機 | PWM 驗證 |
| ☆☆☆ | ESP32-C3 devkit / STM32 Nucleo-64 | 多晶片架構的第二、三個目標 |
