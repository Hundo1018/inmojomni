from tty import ansi


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

    def _char_to_mask(self, ch: String) -> Int:
        if ch == ansi.HLINE:
            return 10  # left + right
        if ch == ansi.VLINE:
            return 5  # up + down
        if ch == ansi.TL:
            return 6  # right + down
        if ch == ansi.TR:
            return 12  # left + down
        if ch == ansi.BL:
            return 3  # right + up
        if ch == ansi.BR:
            return 9  # left + up
        if ch == ansi.T_RIGHT:
            return 7  # right + up + down
        if ch == ansi.T_LEFT:
            return 13  # left + up + down
        if ch == ansi.T_BOT:
            return 14  # left + right + down
        if ch == ansi.T_TOP:
            return 11  # left + right + up
        if ch == ansi.CROSS:
            return 15
        return 0

    def _mask_to_char(self, mask: Int) -> String:
        if mask == 10:
            return ansi.HLINE
        if mask == 5:
            return ansi.VLINE
        if mask == 6:
            return ansi.TL
        if mask == 12:
            return ansi.TR
        if mask == 3:
            return ansi.BL
        if mask == 9:
            return ansi.BR
        if mask == 7:
            return ansi.T_RIGHT
        if mask == 13:
            return ansi.T_LEFT
        if mask == 14:
            return ansi.T_BOT
        if mask == 11:
            return ansi.T_TOP
        if mask == 15:
            return ansi.CROSS
        return " "

    def _merge_orthogonal(self, existing: String, incoming: String) -> String:
        var m1 = self._char_to_mask(existing)
        var m2 = self._char_to_mask(incoming)
        if m1 == 0:
            return incoming
        if m2 == 0:
            return existing
        return self._mask_to_char(m1 | m2)

    def _paint_line_pixel(
        self,
        mut canvas: RasterCanvas,
        x: Int,
        y: Int,
        incoming: String,
        color: Tuple[UInt, UInt, UInt],
    ):
        var existing = canvas.get_pixel(x, y)

        # Orthogonal lines merge into proper junction glyphs.
        var is_incoming_orth = incoming == ansi.HLINE or incoming == ansi.VLINE
        var is_existing_orth = self._char_to_mask(existing) != 0
        if is_incoming_orth and is_existing_orth:
            canvas.set_pixel(x, y, self._merge_orthogonal(existing, incoming), color)
            return

        # Diagonal-on-diagonal intersection keeps a thin cross.
        if (existing == ansi.SLASH and incoming == ansi.BACKSLASH) or (
            existing == ansi.BACKSLASH and incoming == ansi.SLASH
        ):
            canvas.set_pixel(x, y, "╳", color)
            return

        # Orthogonal crossing with a diagonal: prefer visible crossing.
        if is_existing_orth and (
            incoming == ansi.SLASH or incoming == ansi.BACKSLASH
        ):
            canvas.set_pixel(x, y, ansi.CROSS, color)
            return
        if is_incoming_orth and (
            existing == ansi.SLASH or existing == ansi.BACKSLASH
        ):
            canvas.set_pixel(x, y, ansi.CROSS, color)
            return

        canvas.set_pixel(x, y, incoming, color)

    def _sgn(self, v: Int) -> Int:
        if v > 0:
            return 1
        if v < 0:
            return -1
        return 0

    def _corner_char_from_dirs(
        self,
        in_dx: Int,
        in_dy: Int,
        out_dx: Int,
        out_dy: Int,
    ) -> String:
        # Only apply box-style corners when both edges are orthogonal.
        var in_orth = (in_dx == 0 and in_dy != 0) or (in_dx != 0 and in_dy == 0)
        var out_orth = (out_dx == 0 and out_dy != 0) or (out_dx != 0 and out_dy == 0)
        if not in_orth or not out_orth:
            return ""

        var mask = 0
        if in_dx > 0:
            mask |= 8
        if in_dx < 0:
            mask |= 2
        if in_dy > 0:
            mask |= 1
        if in_dy < 0:
            mask |= 4
        if out_dx > 0:
            mask |= 2
        if out_dx < 0:
            mask |= 8
        if out_dy > 0:
            mask |= 4
        if out_dy < 0:
            mask |= 1

        return self._mask_to_char(mask)

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
            self._paint_line_pixel(canvas, x, y, char, color)
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

        # 對可折角情況補上不分岔的直角字元。
        for i in range(num_vertices):
            var prev = vertices[(i + num_vertices - 1) % num_vertices]
            var cur = vertices[i]
            var nxt = vertices[(i + 1) % num_vertices]

            var in_dx = self._sgn(cur[0] - prev[0])
            var in_dy = self._sgn(cur[1] - prev[1])
            var out_dx = self._sgn(nxt[0] - cur[0])
            var out_dy = self._sgn(nxt[1] - cur[1])

            var c = self._corner_char_from_dirs(in_dx, in_dy, out_dx, out_dy)
            if len(c) > 0:
                canvas.set_pixel(cur[0], cur[1], c, color)

    def draw_circle_outline(
        self,
        mut canvas: RasterCanvas,
        cx: Int,
        cy: Int,
        radius: Int,
        color: Tuple[UInt, UInt, UInt],
    ):
        """中點圓演算法繪製圓形外框。"""
        var x = radius
        var y = 0
        var decision = 1 - radius

        while x >= y:
            canvas.set_pixel(cx + x, cy + y, "○", color)
            canvas.set_pixel(cx + y, cy + x, "○", color)
            canvas.set_pixel(cx - y, cy + x, "○", color)
            canvas.set_pixel(cx - x, cy + y, "○", color)
            canvas.set_pixel(cx - x, cy - y, "○", color)
            canvas.set_pixel(cx - y, cy - x, "○", color)
            canvas.set_pixel(cx + y, cy - x, "○", color)
            canvas.set_pixel(cx + x, cy - y, "○", color)

            y += 1
            if decision <= 0:
                decision += 2 * y + 1
            else:
                x -= 1
                decision += 2 * (y - x) + 1

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
