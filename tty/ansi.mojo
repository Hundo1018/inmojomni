# Control Sequence Introducer
# Escapes
comptime ESC = "\x1b"
comptime CSI = "["
comptime SPLIT = ";"

comptime SetStyle = "m"

# ============ 24-bit RGB Color Support ============
def color_24bit(r: UInt, g: UInt, b: UInt) -> String:
    """生成 24-bit RGB 彩色 ANSI 代碼
    用法: print(color_24bit(255, 0, 0) + "紅色文字" + reset)
    """
    return String(ESC, CSI, "38;2;", r, ";", g, ";", b, "m")

def color_24bit_bg(r: UInt, g: UInt, b: UInt) -> String:
    """生成 24-bit RGB 背景色 ANSI 代碼"""
    return String(ESC, CSI, "48;2;", r, ";", g, ";", b, "m")

comptime reset = "\x1b[0m"

# ============ Unicode Line Characters ============
comptime HLINE = "─"      # 水平線
comptime VLINE = "│"      # 垂直線
comptime SLASH = "╱"      # 上升斜線 45° (/)
comptime BACKSLASH = "╲"  # 下降斜線 45° (\)
comptime TL = "┌"         # 左上角
comptime TR = "┐"         # 右上角
comptime BL = "└"         # 左下角
comptime BR = "┘"         # 右下角
comptime CROSS = "┼"      # 十字
comptime T_LEFT = "┤"     # 左邊 T 形
comptime T_RIGHT = "├"    # 右邊 T 形
comptime T_TOP = "┴"      # 上邊 T 形
comptime T_BOT = "┬"      # 下邊 T 形

# ============ Existing ANSI Functions ============
comptime CSI_Combine[n: UInt, char: String]: String = String(ESC, CSI, n, char)
comptime CSI_Combine_Multiple[n: UInt, m: UInt, char: String]: String = String(
    ESC, CSI, n, SPLIT, m, char
)

# Cursor Movement
comptime Up[n: UInt] = CSI_Combine[n, "A"]
comptime Down[n: UInt] = CSI_Combine[n, "B"]
comptime Right[n: UInt] = CSI_Combine[n, "C"]
comptime Left[n: UInt] = CSI_Combine[n, "D"]
comptime NextLine[n: UInt] = CSI_Combine[n, "E"]
comptime PrevLine[n: UInt] = CSI_Combine[n, "F"]
comptime HorizontalAbs[n: UInt] = CSI_Combine[n, "G"]
comptime Position[row: UInt, col: UInt] = CSI_Combine_Multiple[row, col, "H"]

# Erase Functions
comptime Erase[mode: UInt] = CSI_Combine[mode, "J"]
"""Erase in Display.
    - 0: Erase from Cursor to End
    - 1: Erase from Start to End
    - 2: Erase Full Screen
"""

def main():
    comptime a = 5 + 1
    print("A" + Right[a] + "B" + Down[a] + "C" + Right[a] + "D")
