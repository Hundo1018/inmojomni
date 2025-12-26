import subprocess
from tty.ansi import *


fn main():
    # var buffer : String = ""
    var a = Erase[1]
    var b = ESC + a
    print(a,b)
