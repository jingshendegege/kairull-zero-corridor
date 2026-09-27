extends Node2D
class_name ExhaustRidgeArt
## 04 排风脊线专用美术层（Claude）：屋顶设备、塔身/桁架/桅杆结构、竖井内壁与撤离塔吊。
## boot 把本节点插在关卡碰撞层之前 → 画在视差天空（GameBackground）之后、地形与角色之前。
## 纯静态装饰：只在 setup 时绘制一次，不参与碰撞、清场、时停，也不逐帧重绘（Web 性能）。
## 素材由 tools/art/m06/build_m06_decor.py 生成；坐标均为世界像素（地面顶 = row35 = 1120）。

const TS := 32.0
const GROUND := 35.0 * TS
const AC := preload("res://assets/maps/m06/decor_ac_unit.png")
const STACK := preload("res://assets/maps/m06/decor_vent_stack.png")
const ANTENNA := preload("res://assets/maps/m06/decor_antenna.png")
const TANK := preload("res://assets/maps/m06/decor_water_tank.png")
const SIGN := preload("res://assets/maps/m06/decor_sign.png")
const BEACON := preload("res://assets/maps/m06/decor_beacon.png")

const BODY := Color("#1b2536")
const BODY_D := Color("#131b28")
const RIM := Color("#2e4560")
const EDGE := Color("#0b1019")
const INTERIOR := Color("#0d131d")
const RIB := Color("#162031")
const CYAN := Color("#3fb7c9")
const AMBER := Color("#d9a14a")

## (贴图, 世界 x, 底边 y)；底边贴在所站地面/屋顶上
const PROPS := [
	[AC, 60.0, GROUND], [SIGN, 360.0, 29.0 * TS],
	[STACK, 700.0, GROUND], [ANTENNA, 1180.0, GROUND], [TANK, 1640.0, GROUND], [STACK, 1780.0, GROUND],
	[SIGN, 2440.0, 24.0 * TS], [AC, 1950.0, GROUND], [STACK, 3180.0, GROUND],
	[AC, 4640.0, GROUND],
	[ANTENNA, 5160.0, GROUND], [TANK, 5420.0, GROUND],
	[AC, 7000.0, 20.0 * TS], [STACK, 7520.0, 20.0 * TS], [AC, 8100.0, 20.0 * TS],
	[STACK, 8760.0, GROUND], [TANK, 9460.0, GROUND], [SIGN, 9900.0, 22.0 * TS],
]
## 冷却塔跳台：塔顶平台 (x0 格, x1 格, 平台行) → 画开放式支腿桁架，压机可从中间落下
const TOWER_CAPS := [[111, 114, 27], [119, 122, 25], [128, 131, 27], [134, 142, 24], [101, 106, 29]]
## 其余需要支腿的单向平台（泵站二层、扇阵步道、索桥备用台）
const PLATFORM_LEGS := [[284, 292, 29], [300, 306, 29], [17, 30, 29], [37, 58, 29]]
## 高空索桥桥段（row14）→ 下垂吊索 + 两端立柱落到基座 row20
const BRIDGES := [[217, 221], [230, 235], [244, 249]]   # 与 gen_m06_exhaust_ridge.BRIDGE_SEGMENTS 一致
## 竖井内壁：(x0 格, x1 格, 顶行, 底行)
const SHAFTS := [[200, 215, 1, 35], [258, 271, 1, 35]]

var game: Node2D


func setup(host: Node2D) -> void:
	game = host
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	for shaft: Array in SHAFTS:
		_draw_shaft(shaft)
	_draw_gallery_interior()
	for cap: Array in TOWER_CAPS:
		_draw_legs(float(cap[0]), float(cap[1]), float(cap[2]), true)
	for plat: Array in PLATFORM_LEGS:
		_draw_legs(float(plat[0]), float(plat[1]), float(plat[2]), false)
	_draw_mast()
	_draw_bridges()
	_draw_crane()
	for prop: Array in PROPS:
		var tex: Texture2D = prop[0]
		draw_texture(tex, Vector2(float(prop[1]), float(prop[2]) - tex.get_height()).round())
	for bx: float in [40.0 * TS, 147.0 * TS, 196.0 * TS, 257.0 * TS, 313.0 * TS]:
		draw_texture_rect_region(BEACON, Rect2(bx, GROUND - 6.0, 6, 6), Rect2(0, 0, 6, 6))


func _draw_shaft(s: Array) -> void:
	var r := Rect2(float(s[0]) * TS, float(s[2]) * TS, (float(s[1]) - float(s[0]) + 1.0) * TS,
			(float(s[3]) - float(s[2])) * TS)
	draw_rect(r, INTERIOR)
	var x := r.position.x + 16.0
	while x < r.end.x:
		draw_rect(Rect2(x, r.position.y, 2, r.size.y), RIB)
		x += 64.0
	var y := r.position.y + 48.0
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, r.size.x, 2), RIB)
		y += 96.0
	# 井顶巨型排风扇剪影
	var fan_c := Vector2(r.get_center().x, r.position.y + 80.0)
	draw_circle(fan_c, 64.0, EDGE)
	draw_circle(fan_c, 60.0, BODY_D)
	for k in 5:
		var a := TAU * float(k) / 5.0 + 0.3
		draw_line(fan_c, fan_c + Vector2(cos(a), sin(a)) * 56.0, RIB, 10.0)
	draw_circle(fan_c, 9.0, RIM)


func _draw_gallery_interior() -> void:
	# 玻璃天窗廊：廊道后壁（row25–28）与顶部天窗框（row24 之上）
	var r := Rect2(62.0 * TS, 25.0 * TS, 36.0 * TS, 4.0 * TS)
	draw_rect(r, INTERIOR)
	var x := r.position.x
	while x < r.end.x:
		draw_rect(Rect2(x, r.position.y, 3, r.size.y), RIB)
		draw_rect(Rect2(x + 40.0, r.position.y + 18.0, 48, 40), Color("#10202c"))
		draw_rect(Rect2(x + 40.0, r.position.y + 18.0, 48, 2), Color("#1d3a4a"))
		x += 128.0
	for gx in range(62, 98, 4):
		var p := Vector2(float(gx) * TS, 24.0 * TS)
		draw_line(p, p + Vector2(64, -40), RIM, 2.0)
		draw_line(p + Vector2(64, -40), p + Vector2(128, 0), EDGE, 2.0)


func _draw_legs(x0: float, x1: float, row: float, tower: bool) -> void:
	var top := row * TS + 6.0
	var left := x0 * TS + 6.0
	var right := (x1 + 1.0) * TS - 10.0
	for lx: float in [left, right]:
		draw_rect(Rect2(lx, top, 4, GROUND - top), EDGE)
		draw_rect(Rect2(lx, top, 1, GROUND - top), RIM)
	var y := top + 24.0
	var flip := false
	while y + 24.0 < GROUND:
		var a := Vector2(left + 4.0, y) if not flip else Vector2(right, y)
		var b := Vector2(right, y + 24.0) if not flip else Vector2(left + 4.0, y + 24.0)
		draw_line(a, b, BODY, 2.0)
		draw_rect(Rect2(left, y, right - left + 4.0, 2), BODY_D)
		y += 24.0
		flip = not flip
	if tower:
		# 塔顶：冷却塔帽檐 + 琥珀警示条
		draw_rect(Rect2(x0 * TS - 4.0, row * TS - 2.0, (x1 - x0 + 1.0) * TS + 8.0, 4), EDGE)
		var sx := x0 * TS
		while sx < (x1 + 1.0) * TS:
			draw_rect(Rect2(sx, row * TS + 4.0, 6, 3), AMBER)
			sx += 12.0


func _draw_mast() -> void:
	# 狙击桅杆：柱体（c192–193）外包格构塔，顶部平台（row27）下挂警示灯
	var left := 191.0 * TS
	var right := 195.0 * TS
	var top := 27.0 * TS
	draw_rect(Rect2(left, top, 3, GROUND - top), EDGE)
	draw_rect(Rect2(right, top, 3, GROUND - top), EDGE)
	var y := top + 8.0
	while y < GROUND:
		draw_line(Vector2(left, y), Vector2(right, y + 20.0), RIM, 2.0)
		draw_line(Vector2(right, y), Vector2(left, y + 20.0), BODY, 2.0)
		y += 20.0
	draw_texture_rect_region(BEACON, Rect2(193.0 * TS, top + 6.0, 6, 6), Rect2(0, 0, 6, 6))


func _draw_bridges() -> void:
	var base := 20.0 * TS
	for b: Array in BRIDGES:
		var x0 := float(b[0]) * TS
		var x1 := (float(b[1]) + 1.0) * TS
		var deck := 14.0 * TS
		for px_: float in [x0 + 4.0, x1 - 8.0]:
			draw_rect(Rect2(px_, deck + 6.0, 4, base - deck - 6.0), EDGE)
			draw_rect(Rect2(px_, deck + 6.0, 1, base - deck - 6.0), RIM)
		draw_line(Vector2(x0, deck + 8.0), Vector2(x1, deck + 8.0), BODY_D, 3.0)
		# 桥面护栏
		var rx := x0
		while rx <= x1:
			draw_rect(Rect2(rx, deck - 18.0, 2, 18), RIM)
			rx += 16.0
		draw_rect(Rect2(x0, deck - 18.0, x1 - x0, 2), RIM)
	# 桥段之间的下垂吊索（读作空中缺口，需要冲刺跨越）
	for i in BRIDGES.size() - 1:
		var a := Vector2((float(BRIDGES[i][1]) + 1.0) * TS, 14.0 * TS - 18.0)
		var c := Vector2(float(BRIDGES[i + 1][0]) * TS, 14.0 * TS - 18.0)
		var prev := a
		for k in range(1, 13):
			var t := float(k) / 12.0
			var p := a.lerp(c, t) + Vector2(0.0, sin(t * PI) * 22.0)
			draw_line(prev, p, BODY, 1.0)
			prev = p


func _draw_crane() -> void:
	# 撤离塔吊：塔身 + 起重臂 + 吊钩，品红顶灯标出终点
	var mast_x := 322.0 * TS
	var top := 6.0 * TS
	draw_rect(Rect2(mast_x, top, 28, GROUND - top), EDGE)
	var y := top
	while y < GROUND:
		draw_line(Vector2(mast_x, y), Vector2(mast_x + 28.0, y + 28.0), RIM, 2.0)
		draw_line(Vector2(mast_x + 28.0, y), Vector2(mast_x, y + 28.0), BODY, 2.0)
		y += 28.0
	draw_rect(Rect2(mast_x - 260.0, top - 6.0, 340, 10), EDGE)
	draw_rect(Rect2(mast_x - 260.0, top - 6.0, 340, 2), RIM)
	draw_line(Vector2(mast_x + 14.0, top - 60.0), Vector2(mast_x - 250.0, top - 4.0), BODY, 2.0)
	draw_line(Vector2(mast_x + 14.0, top - 60.0), Vector2(mast_x + 76.0, top - 4.0), BODY, 2.0)
	draw_line(Vector2(mast_x - 200.0, top + 4.0), Vector2(mast_x - 200.0, 24.0 * TS), EDGE, 1.0)
	draw_rect(Rect2(mast_x - 208.0, 24.0 * TS, 16, 12), AMBER)
	draw_texture_rect_region(BEACON, Rect2(mast_x + 11.0, top - 66.0, 6, 6), Rect2(0, 0, 6, 6))
