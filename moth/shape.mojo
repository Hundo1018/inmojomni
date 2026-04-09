from tty import ansi
from tty.renderer import RasterCanvas, Rasterizer
from tty.axes import Axes
from std.time import perf_counter_ns

struct Shape[dimension: Int](Copyable, Movable, Writable):
    comptime D = Self.dimension
    var vertices: List[InlineArray[Int, Self.D]]
    var color: Tuple[UInt, UInt, UInt]  # RGB 24-bit

    def __init__(
        out self, 
        vertices: List[InlineArray[Int, Self.D]], 
        color: Tuple[UInt, UInt, UInt]
    ):
        self.vertices = vertices.copy()
        self.color = color


struct Coordinate[dimension: Int](Writable):
    comptime D = Self.dimension
    var axis_max: InlineArray[Int, Self.D]
    var axis_min: InlineArray[Int, Self.D]
    var shapes: List[Shape[Self.D]]

    def __init__(out self, shapes: List[Shape[Self.D]]):
        self.shapes = shapes.copy()
        self.axis_max = InlineArray[Int, Self.D](fill=0)
        self.axis_min = InlineArray[Int, Self.D](fill=0)

        comptime for d in range(Self.D):
            d_max = 0
            d_min = 0
            for shape in self.shapes:
                for vertex in shape.vertices:
                    current = vertex[d]
                    d_max = max(current, d_max)
                    d_min = min(current, d_min)
            self.axis_max[d] = d_max
            self.axis_min[d] = d_min

    def write_to(self, mut writer: Some[Writer]):
        # 占位符 - 由 main() 直接調用渲染
        writer.write("Coordinate structure")


struct RandomShapeGenerator:
    """隨機形狀生成器 (矩形、圓形、三角形)."""
    var seed: Int

    def __init__(out self, seed: Int = 42):
        self.seed = seed

    def next(mut self) -> Int:
        """線性同餘生成器 (LCG)."""
        self.seed = (self.seed * 1103515245 + 12345) % 2147483648
        return self.seed

    def next_range(mut self, min_val: Int, max_val: Int) -> Int:
        """生成範圍內的隨機數."""
        if max_val <= min_val:
            return min_val
        var range_size = max_val - min_val + 1
        return min_val + (self.next() % range_size)

    def generate_rectangle(mut self, x_center: Int, y_center: Int, width: Int, height: Int) -> Shape[2]:
        """生成矩形."""
        var vertices = List[InlineArray[Int, 2]](capacity=4)
        var hw = width / 2
        var hh = height / 2
        
        # 四個角
        var v1 = InlineArray[Int, 2](fill=0)
        v1[0] = x_center - hw
        v1[1] = y_center + hh
        vertices.append(v1^)
        
        var v2 = InlineArray[Int, 2](fill=0)
        v2[0] = x_center + hw
        v2[1] = y_center + hh
        vertices.append(v2^)
        
        var v3 = InlineArray[Int, 2](fill=0)
        v3[0] = x_center + hw
        v3[1] = y_center - hh
        vertices.append(v3^)
        
        var v4 = InlineArray[Int, 2](fill=0)
        v4[0] = x_center - hw
        v4[1] = y_center - hh
        vertices.append(v4^)
        
        var r = UInt(self.next_range(50, 255))
        var g = UInt(self.next_range(50, 255))
        var b = UInt(self.next_range(50, 255))
        return Shape[2](vertices^, (r, g, b))

    def generate_circle(mut self, x_center: Int, y_center: Int, radius: Int) -> Shape[2]:
        """生成圓形 (八邊形近似)."""
        var vertices = List[InlineArray[Int, 2]](capacity=8)
        var diag = (radius * 707) / 1000  # 0.707 * r

        var points = List[InlineArray[Int, 2]](capacity=8)

        var p0 = InlineArray[Int, 2](fill=0)
        p0[0] = radius; p0[1] = 0; points.append(p0^)
        var p1 = InlineArray[Int, 2](fill=0)
        p1[0] = diag; p1[1] = diag; points.append(p1^)
        var p2 = InlineArray[Int, 2](fill=0)
        p2[0] = 0; p2[1] = radius; points.append(p2^)
        var p3 = InlineArray[Int, 2](fill=0)
        p3[0] = -diag; p3[1] = diag; points.append(p3^)
        var p4 = InlineArray[Int, 2](fill=0)
        p4[0] = -radius; p4[1] = 0; points.append(p4^)
        var p5 = InlineArray[Int, 2](fill=0)
        p5[0] = -diag; p5[1] = -diag; points.append(p5^)
        var p6 = InlineArray[Int, 2](fill=0)
        p6[0] = 0; p6[1] = -radius; points.append(p6^)
        var p7 = InlineArray[Int, 2](fill=0)
        p7[0] = diag; p7[1] = -diag; points.append(p7^)
            
        for pt in points:
            var v = InlineArray[Int, 2](fill=0)
            v[0] = x_center + pt[0]
            v[1] = y_center + pt[1]
            vertices.append(v^)
        
        var r = UInt(self.next_range(50, 255))
        var g = UInt(self.next_range(50, 255))
        var b = UInt(self.next_range(50, 255))
        return Shape[2](vertices^, (r, g, b))

    def generate_triangle(mut self, x_center: Int, y_center: Int, size: Int) -> Shape[2]:
        """生成三角形."""
        var vertices = List[InlineArray[Int, 2]](capacity=3)
        
        # 頂部
        var v1 = InlineArray[Int, 2](fill=0)
        v1[0] = x_center
        v1[1] = y_center + size
        vertices.append(v1^)
        
        # 左下
        var v2 = InlineArray[Int, 2](fill=0)
        v2[0] = x_center - size
        v2[1] = y_center - size
        vertices.append(v2^)
        
        # 右下
        var v3 = InlineArray[Int, 2](fill=0)
        v3[0] = x_center + size
        v3[1] = y_center - size
        vertices.append(v3^)
        
        var r = UInt(self.next_range(50, 255))
        var g = UInt(self.next_range(50, 255))
        var b = UInt(self.next_range(50, 255))
        return Shape[2](vertices^, (r, g, b))


def main():
    # 創建隨機形狀生成器
    var gen = RandomShapeGenerator(Int(perf_counter_ns()))
    
    # 定義座標範圍
    var x_min = -20
    var x_max = 20
    var y_min = -10
    var y_max = 10
    
    # 生成真正隨機、且保證留在邊界內的矩形、圓形、三角形
    var shapes = List[Shape[2]](capacity=3)

    var rect_w = gen.next_range(4, 10)
    var rect_h = gen.next_range(3, 7)
    var rect_hw = rect_w / 2
    var rect_hh = rect_h / 2
    var rect_x = gen.next_range(x_min + rect_hw, x_max - rect_hw)
    var rect_y = gen.next_range(y_min + rect_hh, y_max - rect_hh)
    shapes.append(gen.generate_rectangle(rect_x, rect_y, rect_w, rect_h))

    var circle_r = gen.next_range(2, 4)
    var circle_x = gen.next_range(x_min + circle_r, x_max - circle_r)
    var circle_y = gen.next_range(y_min + circle_r, y_max - circle_r)
    shapes.append(gen.generate_circle(circle_x, circle_y, circle_r))

    var tri_size = gen.next_range(2, 5)
    var tri_x = gen.next_range(x_min + tri_size, x_max - tri_size)
    var tri_y = gen.next_range(y_min + tri_size, y_max - tri_size)
    shapes.append(gen.generate_triangle(tri_x, tri_y, tri_size))
    
    # 建立座標系統
    var coord = Coordinate[2](shapes^)
    
    # 外側標示的步進（等距刻度）
    var x_step = 5
    var y_step = 5

    # 畫布：資料區 + 邊框 + 外側標示保留區(gutter)
    var show_top_labels = False
    var show_right_labels = False

    var inner_width = (x_max - x_min) + 1
    var inner_height = (y_max - y_min) + 1
    var max_y_label_len = max(len(String(y_min)), len(String(y_max)))

    var left_gutter = max_y_label_len + 3
    var right_gutter = 2
    if show_right_labels:
        right_gutter = max_y_label_len + 3

    var top_gutter = 1
    if show_top_labels:
        top_gutter = 3

    var bottom_gutter = 3

    var width = left_gutter + (inner_width + 2) + right_gutter
    var height = top_gutter + (inner_height + 2) + bottom_gutter
    var canvas = RasterCanvas(width, height)
    
    # 從渲染器繪製
    var rasterizer = Rasterizer()
    
    # 邊框與內容區定位
    var plot_left = left_gutter
    var plot_top = top_gutter
    var plot_right = plot_left + inner_width + 1
    var plot_bottom = plot_top + inner_height + 1

    # 將世界座標映射到內容區，內容區從 (plot_left + 1, plot_top + 1) 起
    var x_offset = plot_left + 1
    var y_offset = plot_top + 1
    
    # 繪製每個形狀
    # 座標軸（在框內）最後覆蓋繪製，避免數字標籤被形狀覆蓋
    var axes = Axes(
        x_min, x_max, y_min, y_max,
        (UInt(90), UInt(90), UInt(90))
    )

    for shape in coord.shapes:
        # 轉換座標到畫布座標系
        var transformed_vertices = List[InlineArray[Int, 2]](capacity=len(shape.vertices))
        for vertex in shape.vertices:
            var v = InlineArray[Int, 2](fill=0)
            v[0] = x_offset + (vertex[0] - x_min)
            v[1] = y_offset + (y_max - vertex[1])
            transformed_vertices.append(v^)

        # 八點形狀視為圓形，使用圓演算法渲染以保持圓感。
        if len(shape.vertices) == 8:
            var cx_world = 0
            var cy_world = 0
            for sv in shape.vertices:
                cx_world += sv[0]
                cy_world += sv[1]
            cx_world = cx_world / 8
            cy_world = cy_world / 8

            var radius_world = shape.vertices[0][0] - cx_world
            if radius_world < 0:
                radius_world = -radius_world

            var cx_canvas = x_offset + (cx_world - x_min)
            var cy_canvas = y_offset + (y_max - cy_world)
            rasterizer.draw_circle_outline(canvas, cx_canvas, cy_canvas, radius_world, shape.color)
        else:
            rasterizer.draw_polygon(canvas, transformed_vertices, shape.color)

    axes.draw_center_axes(canvas, x_offset, y_offset)

    # 框線外側等距標示（科學圖表風格）
    axes.draw_outer_ticks_and_labels(
        canvas,
        plot_left,
        plot_top,
        plot_right,
        plot_bottom,
        x_step,
        y_step,
        show_top_labels,
        show_right_labels,
    )
    
    # 輸出畫布與尺度/尺寸導引
    print(canvas.to_string())

    print("shape-size: rect=" + String(rect_w) + "x" + String(rect_h) + ", circle-r=" + String(circle_r) + ", tri-size=" + String(tri_size))
