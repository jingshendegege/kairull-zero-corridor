extends Node2D
class_name RoomLights
## M02 光影层（task B.3）：L 光条在脚下地板投一圈柔和光池 + 地板顶面泛光丝。
## 光池是预烘焙的径向渐变纹理（品红/青交替，alpha ≤0.14，武士零式"阴郁不晃眼"），
## 画在 TileMapLayer 之后、油漆层/角色之前——像灯光落在地板顶面上。
## 泛光丝：每个房间地板顶沿下 3px 一条 1px 极低 alpha 亮线（漆面反射的暗示）。
## 暗角已在 WallBackdrop 里随房间绘制（越靠角越暗），此处不重复。

const TS := 32
const POOL_W := 120.0    ## 光池宽（约 3.7 格）
const POOL_H := 30.0     ## 光池高（压在地板顶面）
const STRIP_GLOW_H := 46.0  ## 光条下方垂直渐隐辉光高度

var level: CorridorLevel
var pools: Array = []    ## [{"pos": Vector2 地板顶面中心, "magenta": bool}]（测试断言数量）

var _pool_m: GradientTexture2D
var _pool_c: GradientTexture2D
var _strip_glow: GradientTexture2D


func _ready() -> void:
	_pool_m = _make_pool(KZPalette.NEON_MAGENTA)
	_pool_c = _make_pool(KZPalette.NEON_CYAN)
	_strip_glow = _make_strip_glow()
	if level != null:
		_scan_lights()


## 扫描全部 L 格：光条位置 + 向下找到地板顶面，生成光池记录
func _scan_lights() -> void:
	pools.clear()
	for r in level.map_h:
		for c in level.map_w:
			if level.tile_at(c, r) != "L":
				continue
			var fr := r + 1
			while fr < level.map_h and not level.is_solid_char(level.tile_at(c, fr)):
				fr += 1
			if fr >= level.map_h:
				continue
			pools.append({
				"pos": Vector2(c * TS + TS * 0.5, fr * TS),
				"strip": Vector2(c * TS + TS * 0.5, r * TS + TS),
				"magenta": (c / 2) % 2 == 0,
			})


func _draw() -> void:
	for p in pools:
		# 光条正下方的垂直渐隐辉光（连接光源与光池，极低 alpha）
		draw_texture_rect(_strip_glow,
				Rect2((p["strip"] as Vector2) + Vector2(-TS * 0.5, 0),
						Vector2(TS, STRIP_GLOW_H)), false)
		# 地板光池：径向渐变，宽扁椭圆
		var tex: GradientTexture2D = _pool_m if p["magenta"] else _pool_c
		var c: Vector2 = p["pos"]
		draw_texture_rect(tex,
				Rect2(c.x - POOL_W * 0.5, c.y - POOL_H * 0.35, POOL_W, POOL_H), false)
	# 地板泛光丝：每房间地板顶沿下 3px，1px 极低 alpha 亮线
	if level != null:
		for room in level.rooms:
			var rect: Rect2i = room["rect"]
			var y := float(rect.end.y * TS) + 3.0
			draw_line(Vector2(rect.position.x * TS + 4.0, y),
					Vector2(rect.end.x * TS - 4.0, y),
					Color(KZPalette.FLOOR_TOP, 0.07), 1.0)


## 径向渐变光池纹理：中心 alpha 0.14 → 边缘 0（64×16 足够，采样平滑靠 GPU）
func _make_pool(tint: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(tint, 0.17), Color(tint, 0.08), Color(tint, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 16
	return t


## 光条垂直辉光：顶 alpha 0.10 → 底 0
func _make_strip_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([
		Color(KZPalette.NEON_MAGENTA, 0.12), Color(KZPalette.NEON_MAGENTA, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 16
	t.height = 32
	return t
