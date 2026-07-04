# 多晶片參數化設計(RP2040 → RP2350 → STM32/ESP)

目標:讓「晶片」成為型別參數,SDK 對晶片泛型;
換板子 = 換一個 comptime 參數,約束在編譯期爆炸,而不是燒進板子後。

## 今天已驗證可用的語言機制(此 nightly 實測)

```mojo
trait Chip:
    comptime NAME: StaticString
    comptime NUM_GPIOS: Int
    comptime SIO_BASE: UInt32
    ...

struct RP2040(Chip):
    comptime NUM_GPIOS: Int = 30
    ...

def gpio_budget[C: Chip]() -> Int:   # 晶片泛型函式
    return C.NUM_GPIOS
```

- trait 的 **comptime 關聯常數** ✓ 編譯通過(src/pico/chips.mojo)
- 約束用 `comptime assert`(function body 內)✓ 已在 Pin[N] 使用中
- `where` 子句:官方手冊列為進行中的參數化強化方向;目前用
  comptime assert 可達成等價的硬約束,訊息品質甚至更好
  (自訂錯誤字串)。等 where 落地後可把約束上移到簽名。

## 分層

```
Board(Pico, Pico2, NucleoF401…)     comptime:CHIP、LED、XOSC_HZ、腳位別名
  └── Chip(RP2040, RP2350, STM32F4…) comptime:GPIO 數、SRAM、外設基址
        └── 外設驅動 Pin[C, N] / StateMachine[C, P, SM] / Timer[C]
              comptime assert N < C.NUM_GPIOS 等約束
```

遷移路徑(不破壞現有 API):
1. `src/pico/chips.mojo`(已存在,原型)
2. SDK 型別加預設參數:`struct Pin[N: Int, C: Chip = RP2040]`
3. 暫存器表從 module-level comptime 搬進 chip struct 的關聯常數
4. `board.init()` → `Board.init()`,時鐘參數來自 `Board.XOSC_HZ`

## 各晶片的後端路徑(關鍵現實)

| 晶片 | ISA | Mojo 後端 | 建置路徑 |
|---|---|---|---|
| RP2040 | ARMv6-M | ✗(無 ARM32) | riscv32 IR → retarget → 系統 llc(現行) |
| **RP2350(Pico 2)** | **RISC-V Hazard3** 或 ARMv8-M | **✓ riscv32 原生** | `mojo build` 直出,**免 retarget**——最順的下一站 |
| ESP32-C3/C6 | RISC-V | ✓ 原生 | 同上 + esp 開機頭(esptool) |
| ESP32(classic) | Xtensa | ✓(xtensa 後端已註冊) | 直出(需驗證) |
| STM32F/G/H | ARMv6/7/8-M | ✗ | 同 RP2040 retarget 管線,只換 link.ld + 暫存器表 |

RP2350 買一片就能驗證「Mojo 原生 RISC-V MCU」,是本設計的最佳試金石。

## 開放問題

- trait-typed 預設參數(`C: Chip = RP2040`)在 nightly 的支援度 — 待驗證
- 每晶片 linker script / crt0 的參數化(tools/build.mojo 已可按 chip 切換)
- comptime 關聯常數的位址表 vs 現行 module comptime:零成本等價(都折疊),
  純組織問題
