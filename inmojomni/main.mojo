import subprocess
from tty.ansi import *

fn main():
    # var buffer : String = ""
    print(ESC+CSI+"31m") 
    print(ESC+CSI+ Clear(2))
    # print(buffer)

    while True:
        try:
            _ = input()
        except:
            ...