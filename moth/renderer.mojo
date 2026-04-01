from tty import ansi
from tty.color import Color


struct RasterCanvas:
    """字符網格畫布，管理像素和光柵化"""
    var width: Int
    var height: Int
    var grid: List[List[String]]
    var color_grid: List[List[Tuple[UInt, UInt, UInt]]]

    def __init__(out self, width: Int, height: Int):
        self.width = width
        self.height = height
        self.grid = List[List[String]](capacity=height)
        self.color_grid = List[List[Tuple[UInt, UInt, UInt]]](capacity=height)
        
        for _ in range(height):
            var row = List[String](capacity=width)
            var color_row = List[Tuple[UInt, UInt, UInt]](capacity=width)
            for _ in range(width):
                row.append(" ")
                color_row.append((UInt(0), UInt(0), UInt(0)))
            self.grid.append(row^)
            self.color_grid.append(color_row^)

    def set_pixel(mut self, x: Int, y: Int, char: String, color: Tuple[UInt, UInt, UInt]):
        """設置像素"""
        if x >= 0 and x < self.width and y >= 0 and y < self.height:
            self.grid[y][x] = char
            self.color_grid[y][x] = color

    def get_pixel(self, x: Int, y: Int) -> String:
        """獲取像素"""
        if x >= 0 and x < self.width and y >= 0 and y < self.height:
            return self.grid[y][x]
        return " "

    def to_string(self) -> String:
        """轉換為帶色彩的字符串"""
        var result = ""
        for y in range(self.height):
            for x in range(self.width):
                var char = self.grid[y][x]
                var (r, g, b) = self.color_grid[y][x]
                var color_code = ansi.color_24bit(r, g, b)
                result += color_code + char + ansi.reset
            result += "\n"
        return result


struct Rasterizer:
    """線段光柵化引擎."""

    def __init__(out self):
        pass

    def draw_line(self, mut canvas: RasterCanvas, x1: Int, y1: Int, x2: Int, y2: Int, color: Tuple[UInt, UInt, UInt]):
        """用 Bresenham 算法繪製線段，根據角度選擇合適的 Unicode 線條字符."""
        var dx = x2 - x1
        var dy = y2 - y1
        var dx_abs = dx
        var dy_abs = dy
        if dx_abs < 0:
            dx_abs = -dx_abs
        if dy_abs < 0:
            dy_abs = -dy_abs
        
        # 根據線段方向選擇合適的字符
        var char: String
        
        if dy_abs == 0:
            # 完全水平
            char = ansi.HLINE
        elif dx_abs == 0:
            # 完全垂直
            char = ansi.VLINE
        elif (dx > 0 and dy < 0) or (dx < 0 and dy > 0):
            # 上升斜線 (向右上或向左下)
            char = ansi.SLASH
        else:
            # 下降斜線 (向右下或向左上)
            char = ansi.BACKSLASH
        
        var sx = 1 if x2 > x1 else -1
        var sy = 1 if y2 > y1 else -1
        var err = dx_abs - dy_abs
        var x = x1
        var y = y1
        
        while True:
            canvas.set_pixel(x, y, char, color)
            if x == x2 and y == y2:
                break
            var e2 = 2 * err
            if e2 > -dy_abs:
                err -= dy_abs
                x += sx
            if e2 < dx_abs:
                err += dx_abs
                y += sy

    def draw_polygon(self, mut canvas: RasterCanvas, vertices: List[InlineArray[Int, 2]], color: Tuple[UInt, UInt, UInt]):
        """繪製多邊形邊框."""
        var num_vertices = len(vertices)
        for i in range(num_vertices):
            var v1 = vertices[i]
            var v2 = vertices[(i + 1) % num_vertices]
            self.draw_line(canvas, v1[0], v1[1], v2[0], v2[1], color)

    def draw_box(self, mut canvas: RasterCanvas, x1: Int, y1: Int, x2: Int, y2: Int, color: Tuple[UInt, UInt, UInt]):
        """繪製矩形邊框（使用 Unicode 線條字符)."""
        for x in range(x1 + 1, x2):
            canvas.set_pixel(x, y1, ansi.HLINE, color)
        for x in range(x1 + 1, x2):
            canvas.set_pixel(x, y2, ansi.HLINE, color)
        for y in range(y1 + 1, y2):
            canvas.set_pixel(x1, y, ansi.VLINE, color)
        for y in range(y1 + 1, y2):
            canvas.set_pixel(x2, y, ansi.VLINE, color)
        canvas.set_pixel(x1, y1, ansi.TL, color)
        canvas.set_pixel(x2, y1, ansi.TR, color)
        canvas.set_pixel(x1, y2, ansi.BL, color)
        canvas.set_pixel(x2, y2, ansi.BR, color)
