struct Color(Copyable, Movable):
    var R: UInt
    var G: UInt
    var B: UInt

    def __init__(out self, r: UInt, g: UInt, b: UInt):
        self.R = r
        self.G = g
        self.B = b
