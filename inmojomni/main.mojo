import subprocess
from tty.ansi import *


fn main():
    # var buffer : String = ""
    print(ESC + CSI + "31" + SetStyle)
    var a = Erase[1]
    var b = ESC + a
    print(b)
