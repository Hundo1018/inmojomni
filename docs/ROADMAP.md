# Roadmap(內部文件)

> 對外的現況描述放 README「Current limitations」;這裡是計畫與野心,
> 順序代表目前想做的優先序,隨時可調。

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
- [ ] PIO comptime 組譯(程式進 flash 常數)
- [x] 雙核心啟動 —— 2026-07-04 完成(`pico.multicore.launch()`,PSM 重置 +
      bootrom FIFO 握手 + timeout,core1 跑 Mojo 實機驗證)
- [x] 雙核心同步原語 —— 2026-07-04 完成(`pico.sync.Spinlock[N]` 硬體
      spinlock,雙核 2×20k 競爭遞增精確 40000;`multicore.fifo_push/pop`
      核間訊息,乒乓測試實機驗證)
- [ ] 韌體瘦身:assert 路徑替換為輕量 trap,目標 blink < 600 B

## 中期

- [ ] **RP2350 / Pico 2(RISC-V)原生編譯**——免 retarget,Mojo 直出;
      多晶片參數化架構已設計並有可編譯原型:[MULTICHIP.md](MULTICHIP.md)
- [ ] DMA、USB device(CDC serial → `print()` 到 USB)
- [ ] `pico-mojo new` 專案模板:三行指令從零到第一次 blink
- [ ] WS2812 / SSD1306 / MPU6050 驅動(Mojo trait 風格 driver 生態的種子)

## 遠期

- [ ] ESP32-C3(RISC-V 原生)、STM32(共用 retarget 管線)
- [ ] async/await 風格的事件迴圈(embassy 的 Mojo 版)
- [ ] 向上游 Modular 回報嵌入式需求(ARM32 後端、no-std profile、
      freestanding assert)

## 採購清單(按 roadmap 驗證價值排序)

| 優先 | 材料 | 驗證什麼 |
|---|---|---|
| ★★★ | **Raspberry Pi Pico 2(RP2350)** | Mojo **原生 RISC-V** MCU——本專案最重要的下一步 |
| ★★★ | **8ch 24 MHz 邏輯分析儀**(fx2lafw 相容,~$10)| PIO 波形、PWM/I²C/SPI 時序的自動化驗證(sigrok-cli 可進 CI) |
| ★★☆ | 第二片 Pico(1 代)| MicroPython 第一手 benchmark;USB 功能開發時保留一片跑測試 |
| ★★☆ | WS2812 燈條(8–16 顆)| PIO 的殺手級 demo(800 kHz 精準時序) |
| ★★☆ | 麵包板 + 杜邦線 + 按鈕×4 + LED×8 + 電阻包(220Ω/1k/10k) | GPIO 事件/外部中斷/去彈跳的真實外部訊號測試 |
| ★☆☆ | SSD1306 0.96" OLED(I²C)| I²C driver + 畫面 = 最有感的 demo |
| ★☆☆ | MPU6050 模組 | I²C 讀感測器(pico-drone 的方向,想繼續就買) |
| ★☆☆ | B10K 電位器 | ADC 驗證 |
| ★☆☆ | SG90 舵機 | PWM 驗證 |
| ☆☆☆ | ESP32-C3 devkit / STM32 Nucleo-64 | 多晶片架構的第二、三個目標 |
