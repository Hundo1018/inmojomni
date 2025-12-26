# Control Sequence Introducer


fn CSI_Combine[n: UInt, char: String]() -> String:
    return String("[", n, char)


comptime Up[n: UInt] = CSI_Combine[n, "A"]()
comptime Down[n: UInt] = CSI_Combine[n, "B"]()
comptime Right[n: UInt] = CSI_Combine[n, "C"]()
comptime Left[n: UInt] = CSI_Combine[n, "D"]()
# alias Position[col: UInt, row: UInt] = CSI_Combine[col, "H"]()

comptime Erase[mode: UInt] = CSI_Combine[mode, "J"]()


# Escapes
comptime ESC = "\x1b"
comptime SPLIT = ";"

comptime SetStyle = "m"
# SGR

# Colors
