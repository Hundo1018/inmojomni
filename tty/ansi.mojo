# Control Sequence Introducer
# 目前只能用 mojo run的方式才會正常運作
# Escapes
comptime ESC = "\x1b"
comptime CSI = "["
comptime SPLIT = ";"

comptime SetStyle = "m"
# SGR

# Colors

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
"""
0: From Cursor to End
1: From Start to End
2: Full Screen
"""


def main():
    comptime a = 5 + 1
    print("A" + Right[a] + "B" + NextLine[a] + "C" + Right[a] + "D")
