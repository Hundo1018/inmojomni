# Control Sequence Introducer


fn CSI_Combine[n: Int, char: String]() -> String:
    return String("[", n, char)


alias Up[n: UInt] = CSI_Combine[n, "A"]()
alias Down[n: UInt] = CSI_Combine[n, "B"]()
alias Right[n: UInt] = CSI_Combine[n, "C"]()
alias Left[n: UInt] = CSI_Combine[n, "D"]()
# alias Position[col: UInt, row: UInt] = CSI_Combine[col, "H"]()

alias Erase[mode: UInt] = CSI_Combine[mode, "J"]()


# Escapes
alias ESC = "\x1b"
alias SPLIT = ";"

alias SetStyle = "m"
# SGR

# Colors
