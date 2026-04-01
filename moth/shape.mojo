from tty import ansi
from moth.renderer import RasterCanvas, Rasterizer
from moth.axes import Axes
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
        var num_pts = 8
        
        for i in range(num_pts):
            var angle = i * 360 / num_pts
            var x_off = 0
            var y_off = 0
            
            if angle == 0:
                x_off = radius
            elif angle == 45:
                x_off = radius
                y_off = radius
            elif angle == 90:
                y_off = radius
            elif angle == 135:
                x_off = -radius
                y_off = radius
            elif angle == 180:
                x_off = -radius
            elif angle == 225:
                x_off = -radius
                y_off = -radius
            elif angle == 270:
                y_off = -radius
            elif angle == 315:
                x_off = radius
                y_off = -radius
            
            var v = InlineArray[Int, 2](fill=0)
            v[0] = x_center + x_off
            v[1] = y_center + y_off
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
    
    # 生成矩形、圓形、三角形
    var shapes = List[Shape[2]](capacity=3)
    shapes.append(gen.generate_rectangle(-8, 0, 8, 6))
    shapes.append(gen.generate_circle(0, 5, 3))
    shapes.append(gen.generate_triangle(10, -2, 4))
    
    # 建立座標系統
    var coord = Coordinate[2](shapes^)
    
    # 根據定義的座標軸範圍計算畫布大小（而不是自動計算的邊界）
    var width = (x_max - x_min) + 10
    var height = (y_max - y_min) + 10
    var canvas = RasterCanvas(width, height)
    
    # 從渲染器繪製
    var rasterizer = Rasterizer()
    
    # 計算形狀在定義座標系中的位置，並轉換到畫布座標
    # 將 x: [x_min, x_max] 映射到 [2, 2+width-10]
    # 將 y: [y_min, y_max] 映射到反向的 height 座標
    var x_center = 2
    var y_center = 2
    
    # 繪製每個形狀
    for shape in coord.shapes:
        # 轉換座標到畫布座標系
        var transformed_vertices = List[InlineArray[Int, 2]](capacity=len(shape.vertices))
        for vertex in shape.vertices:
            var v = InlineArray[Int, 2](fill=0)
            # 將座標從 [x_min, x_max] 映射到 [x_center, ...]
            v[0] = x_center + (vertex[0] - x_min)
            # Y 軸倒轉：將 [y_min, y_max] 映射到倒序的行
            v[1] = y_center + (y_max - vertex[1])
            transformed_vertices.append(v^)
        
        rasterizer.draw_polygon(canvas, transformed_vertices, shape.color)
    
    # 繪製座標軸
    var axes = Axes(
        x_min, x_max, y_min, y_max, 
        (UInt(100), UInt(100), UInt(100))
    )
    axes.draw(canvas, x_center, y_center, height)
    
    # 輸出畫布
    print(canvas.to_string())
