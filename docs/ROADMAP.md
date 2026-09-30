# Roadmap(內部文件)

> 對外的現況描述放 README「Current limitations」;這裡是計畫與野心,
> 順序代表目前想做的優先序,隨時可調。

## 未竟事項(2026-09-30 盤點)

實測依據:本機 host tier(無探針)。硬體項目未重跑。

1. **Nightly 落後 2.5 個月,且 canary 失明。** pixi.toml 釘 `==dev2026071006`,
   CI `nightly-latest` 的 `pixi update` 只會解析回同一版(09-29 run log:
   `mojo-compiler 1.0.0b3.dev2026071006`),所以每天綠燈但沒有測到新版。
   最新 1.2.0.dev2026092905 實測:
   - riscv32 `--emit=object` 已恢復(釘死版本的原因可能已消失;何時恢復未二分)。
   - host tier 原樣 FAIL,需 4 處修改後全綠(改動在 scratch,未提交):
     `InlineArray`→`Array`;`Asm` 去掉 `ImplicitlyCopyable` + `materialize[]`;
     `x = String(x[byte=…])` 經暫存變數;retarget 去除 GEP `nuw`/`nusw`。
   - 第 5 處需要決策:預設 bounds check 讓 `test_on_target` 連到
     `__aeabi_memcpy`(RP2040 crt0 沒提供)。選項:(a) `-D ASSERT=none`
     (已驗證全綠);(b) crt0.S 補 `__aeabi_memcpy`/memset,保留檢查,
     但失敗路徑用 2 KB stack buffer;(c) 兩者並存,debug build 保留檢查。
   - 對照:blink `firmware.elf` 與 RP2350 `main_rp2350.elf` 在新舊版
     md5 完全相同(780 B / 1040 B);`test_on_target.elf` 23,691 → 15,936 B
     (舊版加 ASSERT=none 仍是 23,691,差異來自編譯器/stdlib)。
   - 升版後需要實機重跑:`pixi run test`(RP2040)+ 全部 `*-rp2350` gate,
     benchmark 數字要重量。
2. **Canary 修正**:`nightly-latest` 要先把 pins 改成最新版再 `pixi update`,
   否則 README「breakage surfaces within a day」這句沒有 gate。
3. **CI 沒有建 RP2350 路徑**:只跑 RP2040 `test-host`。RP2350 blink
   build + 大小檢查可在 CI 做(需 clang/ld.lld,不需硬體)。
4. **README 不一致**:「Current limitations」說 RP2350 的 PWM/ADC/UART/
   RTT/中斷只在 RP2040 實機驗證過,但 96a0975、8013758 已在 RP2350 實機
   gate(`periph-rp2350`、`rtt-rp2350`),能力矩陣也標 ✅。
5. RP2040 四語言 benchmark 在 dev2026071006 上未重跑(07-18 時探針接 Pico 2)。
6. GitHub Actions 警告:checkout@v4 / setup-pixi@v0.8.1 用 Node 20(已強制跑 Node 24)。
7. 仍等材料:I²C/SPI、邏輯分析儀自動化、WS2812/SSD1306/MPU6050 驅動。

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
- [ ] riscv32 後端在 Mojo 是非官方 tier:dev2026071105 起被 backend
      allowlist 關掉,1.2.0.dev2026092905 實測恢復。沒有上游承諾,任何
      nightly 都可能再關——這是整個專案的單點依賴(README limitations 連到這裡)
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
