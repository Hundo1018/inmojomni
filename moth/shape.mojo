from layout import LayoutTensor, Layout


struct Shape[dimension: Int](Copyable, Writable):
    comptime D = Self.dimension
    var vertices: List[InlineArray[Int, Self.D]]

    def __init__(out self, vertices: List[InlineArray[Int, Self.D]]):
        self.vertices = vertices.copy()


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
        writer.write(self.axis_max)
        writer.write(self.axis_min)
        
        


def main():
    coord = Coordinate[2](
        [
            Shape[2]([[0, 0], [1, 1], [1, 2]]),
            Shape[2]([[4, -1], [5, -2], [6, -2]]),
        ]
    )
    print(coord)
