from python import Python, PythonObject

# Maybe will transfer to SDL2

def test():
    var gfx = Python.import_module("pygfx")
    var wgpu = Python.import_module("wgpu")
    Python.import_module("wgpu.Fgui.auto")

    # 創建基本場景要素
    var canvas = wgpu.gui.auto.WgpuCanvas()
    var renderer = gfx.renderers.WgpuRenderer(canvas)
    var scene = gfx.Scene()

    # 設置Camera
    var camera = gfx.PerspectiveCamera(70, 16 / 9)
    camera.local.position = (0, 2, 5)
    camera.look_at((0, 0, 0))

    # 創建軌道控制器 綁定事件到renderer
    var controller = gfx.OrbitController(camera, register_events=renderer)

    # 方塊
    var box_geometry1 = gfx.box_geometry(20, 20, 20)
    var box_material1 = gfx.MeshBasicMaterial(color=(1.0, 0.0, 0.0, 1.0))  # 红色
    var box1 = gfx.Mesh(box_geometry1, box_material1)
    box1.local.position = (20, 0, 0)
    scene.add(box1)

    # 方塊2
    var box_geometry2 = gfx.box_geometry(20, 20, 20)
    var box_material2 = gfx.MeshBasicMaterial(color=(0.0, 0.0, 1.0, 1.0))  # 蓝色
    var box2 = gfx.Mesh(box_geometry2, box_material2)
    box2.local.position = (-20, 0, 0)
    scene.add(box2)

    # 坐標軸
    var axes_helper = gfx.AxesHelper(size=2)
    scene.add(axes_helper)

    # 燈光
    var light = gfx.PointLight(color=(1.0, 1.0, 1.0), intensity=2.0)
    light.local.position = (5, 5, 5)
    scene.add(light)

    # 渲染循環
    while input() != "q":
        # 著色器上色
        renderer.render(scene, camera)
        # 通知更新(實際渲染到畫布上)
        canvas._draw_frame_and_present()
        # 移動邏輯
        box1.local.x = box1.local.x + 1
