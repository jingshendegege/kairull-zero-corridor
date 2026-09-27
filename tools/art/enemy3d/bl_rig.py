"""Blender 端通用工具：用基本几何体搭关节层级、摆姿势、渲染 ID 图与法线图。

在 Blender 内运行（bpy）。坐标约定：1 Blender 单位 = 1 游戏世界像素；角色面朝 +X，Z 向上，
近侧（离镜头近）为 -Y。每个网格部件拥有唯一 ID 颜色，渲染两遍：
  id_XXXX.png      Workbench FLAT + 材质色 → 部件 ID（无抗锯齿）
  nrm_XXXX.png     Workbench MATCAP check_normal+y → 视图空间法线（R≈nx，G≈ny）
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
import mathutils

RES_X, RES_Y = 128, 112
BASELINE = 104            # 脚底 z=0 落在图像第 104 行
CAM_YAW = 28.0            # 镜头从正侧向前偏转，露出一点正面
SS = 4                    # 超采样倍数：按 4× 渲染，post.py 按覆盖率缩回 1×
SMOOTH = False            # 盒体/锥体/柱体加细分平滑
PARTS: list[dict] = []    # {name, material, rank, id_rgb}
JOINTS: dict[str, bpy.types.Object] = {}


def _srgb_to_lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def id_color(i: int) -> tuple[int, int, int]:
    # 彼此相距较远的离散色；0 号保留给背景
    r = (i * 67 + 40) % 256
    g = (i * 139 + 90) % 256
    b = (i * 211 + 20) % 256
    return r, g, b


def reset_scene() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    PARTS.clear()
    JOINTS.clear()
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.render.resolution_x, scn.render.resolution_y = RES_X * SS, RES_Y * SS
    scn.render.resolution_percentage = 100
    scn.render.film_transparent = True
    scn.display.render_aa = "OFF"
    scn.view_settings.view_transform = "Standard"
    scn.view_settings.look = "None"
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = RES_X
    co = bpy.data.objects.new("cam", cam)
    scn.collection.objects.link(co)
    yaw = math.radians(CAM_YAW)
    dist = 600.0
    center_z = RES_Y / 2 - (RES_Y - BASELINE)
    co.location = (math.sin(yaw) * dist, -math.cos(yaw) * dist, center_z)
    co.rotation_euler = (math.radians(90), 0, yaw)
    scn.camera = co


def joint(name: str, parent: str | None, loc) -> bpy.types.Object:
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = JOINTS[parent]
    e.location = loc
    e.rotation_mode = "XYZ"
    JOINTS[name] = e
    return e


def _material(part_index: int) -> bpy.types.Material:
    r, g, b = id_color(part_index)
    m = bpy.data.materials.new(f"id_{part_index}")
    m.diffuse_color = (_srgb_to_lin(r / 255), _srgb_to_lin(g / 255), _srgb_to_lin(b / 255), 1.0)
    return m


def part(name: str, parent: str, shape: str, size, loc=(0, 0, 0), rot=(0, 0, 0),
         material: str = "armor", rank: int = 0, bevel: float = 0.0, segments: int = 16) -> bpy.types.Object:
    """shape: box(size=x,y,z) / cyl(size=r,depth, 轴=Z) / sph(size=rx,ry,rz) / cone(size=r1,r2,depth)"""
    idx = len(PARTS) + 1
    if shape == "box":
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object
        o.scale = size
    elif shape == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(radius=size[0], depth=size[1], vertices=segments)
        o = bpy.context.active_object
    elif shape == "sph":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=segments * 2, ring_count=segments)
        o = bpy.context.active_object
        o.scale = size
        bpy.ops.object.shade_smooth()
    elif shape == "cone":
        bpy.ops.mesh.primitive_cone_add(radius1=size[0], radius2=size[1], depth=size[2], vertices=segments)
        o = bpy.context.active_object
    else:
        raise ValueError(shape)
    if shape in ("cyl", "cone"):
        bpy.ops.object.shade_smooth()
    o.name = name
    if bevel > 0:
        mod = o.modifiers.new("bev", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "NONE"
    if SMOOTH and shape in ("box", "cone", "cyl"):
        # 细分平滑：倒角盒体变成圆润装甲板，法线连续 → 阴影自然过渡
        sub = o.modifiers.new("sub", "SUBSURF")
        sub.levels = sub.render_levels = 2
        bpy.ops.object.shade_smooth()
    o.data.materials.append(_material(idx))
    o.parent = JOINTS[parent]
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot]
    PARTS.append({"name": name, "material": material, "rank": rank, "id_rgb": id_color(idx)})
    return o


def pose(values: dict) -> None:
    """values: joint -> {'ry':deg,'rx':deg,'rz':deg,'loc':(x,y,z)}；未给出的关节回到零姿态。"""
    for name, j in JOINTS.items():
        spec = values.get(name, {})
        j.rotation_euler = (math.radians(spec.get("rx", 0.0)), math.radians(spec.get("ry", 0.0)),
                            math.radians(spec.get("rz", 0.0)))
        if "loc" in spec:
            j.location = spec["loc"]
        elif "_rest" in j:
            j.location = j["_rest"]


def freeze_rest() -> None:
    for j in JOINTS.values():
        j["_rest"] = tuple(j.location)


def set_visible(names: list[str], visible: bool) -> None:
    for n in names:
        o = bpy.data.objects[n]
        o.hide_render = not visible


def world_to_pixel(point) -> tuple[float, float]:
    """世界坐标 → 图像像素（左上原点）。"""
    from bpy_extras.object_utils import world_to_camera_view
    scn = bpy.context.scene
    co = world_to_camera_view(scn, scn.camera, mathutils.Vector(point))
    return co.x * RES_X, (1.0 - co.y) * RES_Y


def render_pair(out_dir: Path, tag: str) -> None:
    scn = bpy.context.scene
    bpy.context.view_layer.update()
    sh = scn.display.shading
    sh.light = "FLAT"
    sh.color_type = "MATERIAL"
    scn.render.filepath = str(out_dir / f"id_{tag}.png")
    bpy.ops.render.render(write_still=True)
    sh.light = "MATCAP"
    sh.studio_light = "check_normal+y.exr"
    sh.color_type = "SINGLE"
    sh.single_color = (1, 1, 1)
    scn.render.filepath = str(out_dir / f"nrm_{tag}.png")
    bpy.ops.render.render(write_still=True)


def write_parts(out_dir: Path, extra: dict) -> None:
    (out_dir / "parts.json").write_text(json.dumps({"parts": PARTS, "ss": SS, **extra}, ensure_ascii=False, indent=1),
                                       encoding="utf-8")
