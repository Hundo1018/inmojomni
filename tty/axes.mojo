from tty.renderer import RasterCanvas, Rasterizer
from tty import ansi


struct Axes:
    """座標軸管理 - 邊框、標籤、網格線."""
    var x_min: Int
    var x_max: Int
    var y_min: Int
    var y_max: Int
    var label_color: Tuple[UInt, UInt, UInt]

    def __init__(
        out self,
        x_min: Int,
        x_max: Int,
        y_min: Int,
        y_max: Int,
        label_color: Tuple[UInt, UInt, UInt],
    ):
        self.x_min = x_min
        self.x_max = x_max
        self.y_min = y_min
        self.y_max = y_max
        self.label_color = label_color

    def _draw_text(
        self,
        mut canvas: RasterCanvas,
        x: Int,
        y: Int,
        text: String,
    ):
        """逐字寫入，避免多字元標籤破壞格線對齊。"""
        if y < 0 or y >= canvas.height:
            return

        var cursor_x = x
        for ch in text.codepoint_slices():
            if cursor_x >= 0 and cursor_x < canvas.width:
                canvas.set_pixel(cursor_x, y, String(ch), self.label_color)
            cursor_x += 1

    def _draw_text_centered(
        self,
        mut canvas: RasterCanvas,
        center_x: Int,
        y: Int,
        text: String,
    ):
        var start_x = center_x - (len(text) / 2)
        self._draw_text(canvas, start_x, y, text)

    def draw_outer_ticks_and_labels(
        self,
        mut canvas: RasterCanvas,
        plot_left: Int,
        plot_top: Int,
        plot_right: Int,
        plot_bottom: Int,
        x_step: Int,
        y_step: Int,
        show_top: Bool,
        show_right: Bool,
    ):
        """在框線外側繪製等距刻度與數字標示。"""
        var rasterizer = Rasterizer()
        rasterizer.draw_box(canvas, plot_left, plot_top, plot_right, plot_bottom, self.label_color)

        var safe_x_step = max(1, x_step)
        for xv in range(self.x_min, self.x_max + 1, safe_x_step):
            var cx = (plot_left + 1) + (xv - self.x_min)
            if cx <= plot_left or cx >= plot_right:
                continue

            var label = String(xv)

            var bottom_tick_y = plot_bottom + 1
            if bottom_tick_y >= 0 and bottom_tick_y < canvas.height:
                canvas.set_pixel(cx, bottom_tick_y, ansi.VLINE, self.label_color)

            var bottom_label_y = plot_bottom + 2
            self._draw_text_centered(canvas, cx, bottom_label_y, label)

            if show_top:
                var top_tick_y = plot_top - 1
                if top_tick_y >= 0 and top_tick_y < canvas.height:
                    canvas.set_pixel(cx, top_tick_y, ansi.VLINE, self.label_color)
                var top_label_y = plot_top - 2
                self._draw_text_centered(canvas, cx, top_label_y, label)

        var safe_y_step = max(1, y_step)
        for yv in range(self.y_min, self.y_max + 1, safe_y_step):
            var cy = (plot_bottom - 1) - (yv - self.y_min)
            if cy <= plot_top or cy >= plot_bottom:
                continue

            var label = String(yv)

            var left_tick_x = plot_left - 1
            if left_tick_x >= 0 and left_tick_x < canvas.width:
                canvas.set_pixel(left_tick_x, cy, ansi.HLINE, self.label_color)

            var left_label_x = plot_left - len(label) - 2
            self._draw_text(canvas, left_label_x, cy, label)

            if show_right:
                var right_tick_x = plot_right + 1
                if right_tick_x >= 0 and right_tick_x < canvas.width:
                    canvas.set_pixel(right_tick_x, cy, ansi.HLINE, self.label_color)
                var right_label_x = plot_right + 2
                self._draw_text(canvas, right_label_x, cy, label)

    def draw_center_axes(
        self,
        mut canvas: RasterCanvas,
        x_offset: Int,
        y_offset: Int,
    ):
        """只在框內繪製 x=0 與 y=0 的座標軸，不輸出框外標籤."""
        var rasterizer = Rasterizer()

        var left = x_offset
        var right = x_offset + (self.x_max - self.x_min)
        var top = y_offset
        var bottom = y_offset + (self.y_max - self.y_min)

        # x 軸（y=0）
        var has_x_axis = False
        var axis_y = 0
        if self.y_min <= 0 and self.y_max >= 0:
            has_x_axis = True
            axis_y = y_offset + (self.y_max - 0)
            rasterizer.draw_line(canvas, left, axis_y, right, axis_y, self.label_color)

        # y 軸（x=0）
        var has_y_axis = False
        var axis_x = 0
        if self.x_min <= 0 and self.x_max >= 0:
            has_y_axis = True
            axis_x = x_offset + (0 - self.x_min)
            rasterizer.draw_line(canvas, axis_x, top, axis_x, bottom, self.label_color)

        # 刻度：在軸線上添加細刻度，保持 ANSI 細線風格。
        if has_x_axis:
            var x_step = 5
            for xv in range(self.x_min, self.x_max + 1, x_step):
                if xv != 0:
                    var tx = x_offset + (xv - self.x_min)
                    if tx > left and tx < right:
                        canvas.set_pixel(tx, axis_y, ansi.CROSS, self.label_color)

        if has_y_axis:
            var y_step = 5
            for yv in range(self.y_min, self.y_max + 1, y_step):
                if yv != 0:
                    var ty = y_offset + (self.y_max - yv)
                    if ty > top and ty < bottom:
                        canvas.set_pixel(axis_x, ty, ansi.CROSS, self.label_color)

        # 原點（0,0）交點
        if self.x_min <= 0 and self.x_max >= 0 and self.y_min <= 0 and self.y_max >= 0:
            var ox = x_offset + (0 - self.x_min)
            var oy = y_offset + (self.y_max - 0)
            canvas.set_pixel(ox, oy, ansi.CROSS, self.label_color)
