from moth.renderer import RasterCanvas, Rasterizer
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

    def draw(
        self,
        mut canvas: RasterCanvas,
        x_offset: Int,
        y_offset: Int,
        canvas_height: Int,
    ):
        """繪製座標軸框線和標籤 (完整四邊)."""
        var rasterizer = Rasterizer()

        # 計算工作區邊界（資料顯示範圍）
        var x_range = self.x_max - self.x_min
        var y_range = self.y_max - self.y_min
        
        var left = x_offset
        var right = x_offset + x_range
        var bottom = y_offset + y_range
        var top = y_offset

        # 繪製邊框
        rasterizer.draw_box(canvas, left, top, right, bottom, self.label_color)

        # X軸標籤（下邊框下方）
        var x_step = max(1, x_range / 5)
        for x in range(self.x_min, self.x_max + 1, x_step):
            var label = String(x)
            var canvas_x = left + (x - self.x_min)
            var canvas_y = bottom + 1
            if canvas_y < canvas_height - 1:
                self._draw_label(canvas, canvas_x, canvas_y, label)

        # X軸標籤（上邊框上方）
        for x in range(self.x_min, self.x_max + 1, x_step):
            var label = String(x)
            var canvas_x = left + (x - self.x_min)
            var canvas_y = top - 1
            if canvas_y >= 0:
                self._draw_label(canvas, canvas_x, canvas_y, label)

        # Y軸標籤（左邊框左側）
        var y_step = max(1, y_range / 5)
        for y in range(self.y_min, self.y_max + 1, y_step):
            var label = String(y)
            var canvas_x = left - len(label) - 1
            var canvas_y = bottom - (y - self.y_min)
            if canvas_x >= 0:
                self._draw_label(canvas, canvas_x, canvas_y, label)

        # Y軸標籤（右邊框右側）
        for y in range(self.y_min, self.y_max + 1, y_step):
            var label = String(y)
            var canvas_x = right + 2
            var canvas_y = bottom - (y - self.y_min)
            if canvas_x + len(label) < canvas.width:
                self._draw_label(canvas, canvas_x, canvas_y, label)

    def _draw_label(
        self, mut canvas: RasterCanvas, x: Int, y: Int, label: String
    ):
        """在畫布上繪製文字標籤."""
        # 簡化：只在首個位置放置標籤，無需迭代
        if x >= 0 and y >= 0 and x < canvas.width and y < canvas.height:
            canvas.set_pixel(x, y, label, self.label_color)
