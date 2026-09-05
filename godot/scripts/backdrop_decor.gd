extends Node2D
class_name BackdropDecor
## M03 背景墙装饰层：概念图装饰全量移植（挂画 / 告示 / 通缉海报 / 档案书柜 /
## 通风口 / 挂钟 / 货箱 / 监控摄像头 + 干线 / 雪花屏监视器 / 警报喇叭）。
## 绘制在 wall_backdrop 之上、TileMapLayer 之下 —— 装饰黏在背景墙上，
## 被实心 tiles 天然遮挡交叠部分。清单来自地图生成器 DECOR 输出。
##
## 明度纪律：全部用色 < KZPalette.WALL_PANEL（玩法墙），不抢角色与信号色。
## 颗粒/雪花用固定 seed —— 每帧重绘结果稳定，无闪烁。

const TS := 32

var items: Array = []
var _rng := RandomNumberGenerator.new()


func _draw() -> void:
	for it in items:
		_rng.seed = hash(str(it))
		## cable 用 c0/c1 区间锚，无 c 键 —— 先行分支
		if it["kind"] == "cable":
			_draw_cable(float(it["c0"]) * TS, float(it["c1"]) * TS, float(it["r"]) * TS)
			continue
		var ax: float = float(it["c"]) * TS + TS * 0.5   ## 锚格中心 x
		var ay: float = float(it["r"]) * TS              ## 锚格顶 y
		match it["kind"]:
			"frame":
				_draw_frame(ax, ay, 64.0, 78.0, int(it.get("seed", 0)))
			"notice":
				_draw_notice(ax, ay)
			"poster":
				_draw_poster(ax, ay)
			"shelf":
				_draw_shelf(ax, ay)
			"crate":
				_draw_crate(ax, ay)
			"vent":
				_draw_vent(ax, ay)
			"clock":
				_draw_clock(ax, ay)
			"monitor":
				_draw_monitor(ax, ay)
			"speaker":
				_draw_speaker(ax, ay)
			"camera":
				_draw_camera(ax, ay, it.get("facing", "right") == "left",
						bool(it.get("sweep", false)))
			"sofa":
				_draw_sofa(ax, base_of(ay, it))
			"tv":
				_draw_tv(ax, base_of(ay, it))
			"bottle":
				_draw_bottle(ax, base_of(ay, it), int(it.get("count", 1)))
			"neon_sign":
				_draw_neon_sign(ax, ay, it.get("text", ""))
			"radiation":
				_draw_radiation(ax, ay)
			"desk":
				_draw_desk(ax, base_of(ay, it))
			"door_prop":
				_draw_door_prop(ax, base_of(ay, it))
			"trashcan":
				_draw_trashcan(ax, base_of(ay, it))
			"warning_light":
				_draw_warning_light(ax, ay)


## —— 挂画（seed 0 远山 / 1 肖像 / 2 色块）——
func _draw_frame(cx: float, top: float, w: float, h: float, kind: int) -> void:
	var x := cx - w * 0.5
	var y := top + 4.0
	draw_rect(Rect2(x + 3, y + 4, w, h), Color("#1c262c"))           # 落墙影
	draw_rect(Rect2(x, y, w, h), Color("#5e402e"))                   # 框
	draw_rect(Rect2(x + 2, y + 2, w - 4, h - 4), Color("#74523a"))
	var ix := x + 7
	var iy := y + 7
	var iw := w - 14
	var ih := h - 14
	draw_rect(Rect2(ix, iy, iw, ih), Color("#32464e"))               # 画芯底
	if kind == 0:      # 远山
		draw_circle(Vector2(x + w - 20, iy + 10), 5.0, Color("#607476"))
		draw_polygon(PackedVector2Array([
				Vector2(ix, iy + ih), Vector2(ix + iw * 0.38, iy + ih * 0.42),
				Vector2(ix + iw * 0.55, iy + ih)]), [Color("#24343c")])
		draw_polygon(PackedVector2Array([
				Vector2(ix + iw * 0.40, iy + ih), Vector2(ix + iw * 0.72, iy + ih * 0.30),
				Vector2(ix + iw, iy + ih)]), [Color("#1e2c34")])
	elif kind == 1:    # 肖像剪影
		draw_rect(Rect2(ix, iy, iw, ih), Color("#3a4c52"))
		var pcx := cx
		draw_circle(Vector2(pcx, iy + 18), 9.0, Color("#222e34"))
		draw_polygon(PackedVector2Array([
				Vector2(pcx - 15, iy + ih), Vector2(pcx + 15, iy + ih),
				Vector2(pcx + 10, iy + 38), Vector2(pcx - 10, iy + 38)]),
				[Color("#222e34")])
	else:              # 抽象色块
		var cols := [Color("#60503e"), Color("#3a5258"), Color("#6c5846")]
		for i in 3:
			var bx := ix + i * iw / 3.0
			draw_rect(Rect2(bx, iy + 5 + (i % 2) * 10, iw / 3.0 - 2, ih - 12), cols[i])
	draw_line(Vector2(ix + 3, iy + ih - 3), Vector2(ix + iw - 7, iy + 3),
			Color("#78969c"), 1.0)                                    # 玻璃反光


## —— 告示便签（微歪 + 胶带）——
func _draw_notice(cx: float, top: float) -> void:
	var x := cx - 18.0
	var y := top + 6.0
	draw_polygon(PackedVector2Array([
			Vector2(x + 1, y + 2), Vector2(x + 36, y + 1),
			Vector2(x + 34, y + 46), Vector2(x, y + 45)]), [Color("#968a6c")])
	draw_rect(Rect2(x + 4, y + 7, 28, 2), Color("#685e48"))
	draw_rect(Rect2(x + 4, y + 14, 22, 2), Color("#685e48"))
	draw_rect(Rect2(x + 12, y - 2, 12, 6), Color("#788080"))          # 胶带


## —— 黑市通缉海报（泛黄纸 + 人像印块 + 字条 + 一角翘起）——
func _draw_poster(cx: float, top: float) -> void:
	var x := cx - 26.0
	var y := top + 6.0
	var w := 52.0
	var h := 70.0
	draw_polygon(PackedVector2Array([
			Vector2(x + 2, y + 3), Vector2(x + w, y), Vector2(x + w - 1, y + h),
			Vector2(x, y + h - 2)]), [Color("#a4926e")])
	draw_rect(Rect2(x + 4, y + 5, w - 9, h - 11), Color("#76684e"),
			false, 1.0)
	var pcx := cx
	draw_rect(Rect2(pcx - 8, y + 12, 16, 16), Color("#40382c"))
	draw_polygon(PackedVector2Array([
			Vector2(pcx - 14, y + 48), Vector2(pcx + 14, y + 48),
			Vector2(pcx + 9, y + 28), Vector2(pcx - 9, y + 28)]), [Color("#40382c")])
	for i in 3:
		var yy := y + h - 22 + i * 6
		draw_rect(Rect2(x + 6, yy, w - 12 - (i % 2) * 8, 3), Color("#70644a"))


## —— 档案书柜（落地：底边贴锚点；杂色书脊 + 斜靠书 + 顶上枯盆栽）——
func _draw_shelf(cx: float, base_y: float) -> void:
	var w := 76.0
	var h := 90.0
	var x := cx - w * 0.5
	var y := base_y - h
	draw_rect(Rect2(x + 5, y + 6, w, h), Color("#182026"))            # 落地影
	draw_rect(Rect2(x, y, w, h), Color("#382e28"))                    # 柜体
	draw_rect(Rect2(x + 4, y + 4, w - 8, h - 8), Color("#282220"))    # 内腔
	var spines := [Color("#763e3a"), Color("#405c6e"), Color("#8a6c3c"),
			Color("#48644a"), Color("#6a4c5c"), Color("#38525e"),
			Color("#7c5e38"), Color("#543a3a")]
	var sh := (h - 10) / 2.0
	for s in 2:
		var sy1 := y + 6 + (s + 1) * sh
		draw_rect(Rect2(x + 4, sy1 - 4, w - 8, 4), Color("#403630"))  # 层板
		_rng.seed = 11 + s
		var bx := x + 9.0
		var i := 0
		while bx < x + w - 16:
			var bw: float = [5.0, 7.0, 9.0, 12.0][_rng.randi() % 4]
			var bh := maxf(8.0, sh - 10 - [0.0, 0.0, 5.0][_rng.randi() % 3])
			var col: Color = spines[(i * 3 + s * 2) % spines.size()]
			draw_rect(Rect2(bx, sy1 - 4 - bh, bw, bh), col)
			draw_line(Vector2(bx, sy1 - 4 - bh), Vector2(bx, sy1 - 5),
					col.lightened(0.2), 1.0)
			bx += bw + 2
			i += 1
	# 顶上枯盆栽
	var px := x + w - 24
	draw_rect(Rect2(px, y - 12, 14, 12), Color("#543c2e"))
	for a in [-50.0, -20.0, 10.0, 40.0]:
		var ang := deg_to_rad(a)
		draw_line(Vector2(px + 7, y - 12),
				Vector2(px + 7 + 14 * sin(ang), y - 12 - 14 * cos(ang)),
				Color("#4a543a"), 2.0)
	draw_line(Vector2(x, y), Vector2(x + w, y), Color("#181412"), 2.0)


## —— 黑市货箱（木板 + 交叉加固条；落地）——
func _draw_crate(cx: float, base_y: float) -> void:
	var w := 52.0
	var h := 46.0
	var x := cx - w * 0.5
	var y := base_y - h
	draw_rect(Rect2(x + 3, y + 4, w, h), Color("#1a2228"))
	draw_rect(Rect2(x, y, w, h), Color("#684e36"))
	var yy := y + 6
	while yy < y + h - 3:
		draw_line(Vector2(x + 2, yy), Vector2(x + w - 2, yy), Color("#543e2a"), 2.0)
		yy += 8
	draw_line(Vector2(x + 2, y + 2), Vector2(x + w - 2, y + h - 2), Color("#463424"), 3.0)
	draw_line(Vector2(x + w - 2, y + 2), Vector2(x + 2, y + h - 2), Color("#463424"), 3.0)
	draw_rect(Rect2(x, y, w, h), Color("#2c221a"), false, 2.0)


## —— 通风口 ——
func _draw_vent(cx: float, top: float) -> void:
	var w := 56.0
	var h := 26.0
	var x := cx - w * 0.5
	var y := top + 8.0
	draw_rect(Rect2(x, y, w, h), Color("#40505a"))
	draw_rect(Rect2(x + 2, y + 2, w - 4, h - 4), Color("#26323a"))
	var yy := y + 6
	while yy < y + h - 4:
		draw_rect(Rect2(x + 6, yy, w - 12, 2), Color("#16202六".hex_to_int() if false else Color("#162026")))
		yy += 6
	for xx in [x + 3, x + w - 5]:
		draw_line(Vector2(xx, y), Vector2(xx, y + h), Color("#182226"), 2.0)


## —— 挂钟（停在某个没人记得的时刻）——
func _draw_clock(cx: float, top: float) -> void:
	var r := 15.0
	var y := top + 26.0
	draw_circle(Vector2(cx + 2, y + 3), r, Color("#1a2226"))
	draw_circle(Vector2(cx, y), r, Color("#343028"))
	draw_circle(Vector2(cx, y), r - 4, Color("#5e5a4e"))
	draw_line(Vector2(cx, y), Vector2(cx, y - r + 8), Color("#1e2022"), 2.0)
	draw_line(Vector2(cx, y), Vector2(cx + r - 9, y + 4), Color("#1e2022"), 2.0)


## —— 雪花屏监视器（黑市偷录画面：噪点 + 扫描线）——
func _draw_monitor(cx: float, top: float) -> void:
	var w := 56.0
	var h := 42.0
	var x := cx - w * 0.5
	var y := top + 8.0
	draw_rect(Rect2(x + 3, y + 4, w, h), Color("#182026"))
	draw_rect(Rect2(x, y, w, h), Color("#2c3036"))
	draw_rect(Rect2(x + 4, y + 4, w - 8, h - 12), Color("#606e70"))
	_rng.seed = 23
	for i in 50:
		var px := x + 6 + _rng.randf() * (w - 12)
		var py := y + 6 + _rng.randf() * (h - 16)
		var g := 60 + _rng.randf() * 90
		draw_rect(Rect2(px, py, 1.5, 1.5), Color8(int(g), int(g), int(g)))
	var sy := y + 6.0
	while sy < y + h - 9:
		draw_line(Vector2(x + 4, sy), Vector2(x + w - 4, sy), Color("#465456"), 1.0)
		sy += 3
	draw_rect(Rect2(cx - 8, y + h - 6, 16, 3), Color("#464c52"))


## —— 警报喇叭（朝下喇叭口 + 暗红待机灯）——
func _draw_speaker(cx: float, top: float) -> void:
	var x := cx - 17.0
	var y := top + 8.0
	draw_rect(Rect2(x + 6, y - 3, 18, 9), Color("#30363c"))
	draw_polygon(PackedVector2Array([
			Vector2(x + 2, y + 6), Vector2(x + 28, y + 6),
			Vector2(x + 34, y + 30), Vector2(x - 4, y + 30)]), [Color("#3a4046")])
	draw_line(Vector2(x + 2, y + 6), Vector2(x - 4, y + 30), Color("#5c666e"), 1.0)
	draw_circle(Vector2(x + 15, y + 24), 6.0, Color("#181e24"))
	draw_rect(Rect2(x + 13, y + 1, 4, 4), Color("#963232"))


## 落地类锚点：底边 = 锚格顶（ay）；挂墙类顶边 = ay。
func base_of(ay: float, _it: Dictionary) -> float:
	return ay


## —— 黑皮沙发（落地）：靠背 + 双坐垫 + 扶手亮边 + 落地影 ——
func _draw_sofa(cx: float, base_y: float) -> void:
	var w := 92.0
	var h := 42.0
	var x := cx - w * 0.5
	var y := base_y - h
	draw_rect(Rect2(x + 5, y + 6, w, h), Color("#0e0c12"))            # 落地影
	draw_rect(Rect2(x, y, w, 22), Color("#1e1c26"))                   # 靠背
	draw_rect(Rect2(x, y, w, 3), Color("#2c2836"))
	draw_rect(Rect2(x + 4, y + 22, w - 8, 12), Color("#171520"))      # 坐垫面
	draw_line(Vector2(x + w * 0.5, y + 22), Vector2(x + w * 0.5, y + 34),
			Color("#0d0b12"), 2.0)                                     # 坐垫分缝
	draw_rect(Rect2(x, y + 30, 12, 12), Color("#24202c"))             # 左扶手
	draw_rect(Rect2(x + w - 12, y + 30, 12, 12), Color("#24202c"))    # 右扶手
	draw_rect(Rect2(x, y + 30, 12, 2), Color("#3a3446"))              # 扶手上沿高光
	draw_rect(Rect2(x + w - 12, y + 30, 12, 2), Color("#3a3446"))
	draw_rect(Rect2(x + 2, y + 40, w - 4, 2), Color("#0a0810"))       # 底沿


## —— 落地电视：电视柜 + 暗框屏 + 彩条画面 ——
func _draw_tv(cx: float, base_y: float) -> void:
	var y := base_y
	# 电视柜
	draw_rect(Rect2(cx - 22, y - 16, 44, 16), Color("#2a2018"))
	draw_rect(Rect2(cx - 22, y - 16, 44, 2), Color("#3c2e22"))
	draw_line(Vector2(cx, y - 12), Vector2(cx, y - 3), Color("#1a140f"), 2.0)
	# 机身 + 屏
	var ty := y - 16 - 30
	draw_rect(Rect2(cx - 20, ty, 40, 30), Color("#171520"))
	draw_rect(Rect2(cx - 17, ty + 3, 34, 22), Color("#2b3440"))       # 屏底
	# 彩条画面（暗调 SMPTE 感）
	var bands := [Color("#3a4a5c"), Color("#4a3a44"), Color("#33463a"),
			Color("#4a4432"), Color("#2e3846"), Color("#46323a")]
	for i in 6:
		var bw := 34.0 / 6.0
		draw_rect(Rect2(cx - 17 + i * bw, ty + 3, bw, 22), bands[i])
	draw_rect(Rect2(cx - 17, ty + 3, 34, 22), Color(0.0, 0.0, 0.0, 0.18), false)
	draw_rect(Rect2(cx - 20, ty, 40, 2), Color("#262230"))            # 顶棱
	draw_rect(Rect2(cx + 12, ty + 26, 5, 2), Color("#4a4a56"))        # 电源灯


## —— 啤酒瓶（落地小件）：绿玻璃 + 高光，count 支持并排 ——
func _draw_bottle(cx: float, base_y: float, count: int) -> void:
	for i in count:
		var ox := cx + (i - (count - 1) * 0.5) * 11.0
		var h := 17.0
		var w := 7.0
		y_from(ox, base_y, w, h)
		draw_rect(Rect2(ox + 1, base_y - 1, w, 2), Color(0.0, 0.0, 0.0, 0.35))
		draw_rect(Rect2(ox, base_y - h, w, h - 4), Color("#2e5a44"))   # 瓶身
		draw_rect(Rect2(ox + 2, base_y - h - 4, w - 4, 5), Color("#254a38"))  # 瓶颈
		draw_rect(Rect2(ox + 2, base_y - h - 5, w - 4, 2), Color("#3a6a50"))  # 瓶口
		draw_rect(Rect2(ox, base_y - h, 2, h - 4), Color("#4a7a5e"))   # 高光
		draw_rect(Rect2(ox, base_y - h + 5, w, 5), Color("#8a7a3c"))   # 标签


func y_from(_ox: float, _base_y: float, _w: float, _h: float) -> void:
	pass


## —— 霓虹红字门牌：暗底牌 + 发光红字块 + 外晕（黑市招牌意象）——
func _draw_neon_sign(cx: float, top: float, text: String) -> void:
	var w := 76.0
	var h := 24.0
	var x := cx - w * 0.5
	var y := top + 6.0
	draw_rect(Rect2(x + 4, y + 4, w, h), Color("#0d0a12"))            # 牌体
	draw_rect(Rect2(x, y, w, h), Color("#151222"))
	draw_rect(Rect2(x, y, w, 2), Color("#241f33"))
	# 发光字：按字符数切竖笔画块（不渲染真字体，保持像素风）
	var n := maxi(3, text.length())
	var gw := (w - 12) / float(n)
	var neon := Color(1.0, 0.22, 0.30)
	for i in n:
		var gx := x + 6 + i * gw
		draw_rect(Rect2(gx, y + 7, gw - 2, 10), Color(neon, 0.22))
		draw_rect(Rect2(gx, y + 9, gw - 2, 4), Color(neon, 0.85))
		draw_rect(Rect2(gx + 1, y + 7, gw - 4, 1), Color(neon, 0.55))
	draw_rect(Rect2(x - 3, y - 2, w + 6, h + 8), Color(1.0, 0.25, 0.3, 0.09))  # 外晕
	draw_circle(Vector2(x + 4, y + h + 2), 2.0, Color(1.0, 0.3, 0.25, 0.5))    # 挂灯


## —— 辐射警告牌：黄底 + 黑三瓣 + 黑边（危险品仓库读法）——
func _draw_radiation(cx: float, top: float) -> void:
	var cy := top + 22.0
	var r := 17.0
	draw_polygon(PackedVector2Array([
			Vector2(cx, cy - r), Vector2(cx + r, cy + r * 0.8),
			Vector2(cx - r, cy + r * 0.8)]), [Color("#d8b23c")])
	draw_line(Vector2(cx, cy - r), Vector2(cx + r, cy + r * 0.8), Color("#1a160f"), 2.0)
	draw_line(Vector2(cx + r, cy + r * 0.8), Vector2(cx - r, cy + r * 0.8),
			Color("#1a160f"), 2.0)
	draw_line(Vector2(cx - r, cy + r * 0.8), Vector2(cx, cy - r), Color("#1a160f"), 2.0)
	# 三瓣扇形
	for i in 3:
		var a0 := TAU * float(i) / 3.0 - 0.5
		var a1 := a0 + 0.85
		var pts := PackedVector2Array([Vector2(cx, cy + 4)])
		pts.append_array(_arc(cx, cy + 4, 9.0, a0, a1))
		draw_colored_polygon(pts, Color("#1a160f"))
	draw_circle(Vector2(cx, cy + 4), 3.2, Color("#1a160f"))
	draw_circle(Vector2(cx, cy + 4), 1.2, Color("#d8b23c"))


func _arc(cx: float, cy: float, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 6
	for i in n + 1:
		var a: float = lerpf(a0, a1, float(i) / n)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts


## —— 桌椅组（落地）：长桌 + 两把靠背椅（参考图下层办公角）——
func _draw_desk(cx: float, base_y: float) -> void:
	var w := 76.0
	var x := cx - w * 0.5
	var ty := base_y - 34.0
	# 椅子（桌后两把）
	for i in 2:
		var chx := x + 14.0 + i * 34.0
		draw_rect(Rect2(chx, base_y - 30.0, 14.0, 30.0), Color("#26222e"))   # 椅背
		draw_rect(Rect2(chx, base_y - 30.0, 14.0, 3.0), Color("#383244"))
		draw_rect(Rect2(chx + 2.0, base_y - 12.0, 10.0, 12.0), Color("#1c1824"))
	# 桌面 + 桌腿
	draw_rect(Rect2(x, ty, w, 5.0), Color("#463628"))
	draw_rect(Rect2(x, ty, w, 2.0), Color("#5c4834"))
	draw_rect(Rect2(x + 4.0, ty + 5.0, 5.0, base_y - ty - 5.0), Color("#332820"))
	draw_rect(Rect2(x + w - 9.0, ty + 5.0, 5.0, base_y - ty - 5.0),
			Color("#332820"))
	# 桌上杂物：显示器 + 瓶
	draw_rect(Rect2(x + 20.0, ty - 12.0, 16.0, 12.0), Color("#20262e"))
	draw_rect(Rect2(x + 22.0, ty - 10.0, 12.0, 8.0), Color("#31414e"))
	draw_rect(Rect2(x + 48.0, ty - 9.0, 4.0, 9.0), Color("#2e5a44"))
	# 落地影
	draw_rect(Rect2(x + 3.0, base_y - 1.0, w, 2.0), Color(0.0, 0.0, 0.0, 0.3))


## —— 深色木门（装饰：贴墙假门，与 RoomDoor 功能门区分）——
func _draw_door_prop(cx: float, base_y: float) -> void:
	var w := 26.0
	var h := 62.0
	var x := cx - w * 0.5
	var y := base_y - h
	draw_rect(Rect2(x + 4.0, y + 4.0, w, h), Color("#0e0b10"))           # 门套影
	draw_rect(Rect2(x, y, w, h), Color("#3a2a1c"))                       # 门板
	draw_rect(Rect2(x + 3.0, y + 3.0, w - 6.0, h - 6.0), Color("#463424"))
	# 门板拼条
	draw_rect(Rect2(x + 5.0, y + 8.0, w - 10.0, 16.0), Color("#3a2c1e"))
	draw_rect(Rect2(x + 5.0, y + 30.0, w - 10.0, 20.0), Color("#3a2c1e"))
	# 把手 + 黄黑警示带（门顶）
	draw_circle(Vector2(x + w - 7.0, y + 34.0), 2.0, Color("#8a7a3c"))
	draw_rect(Rect2(x, y, w, 4.0), Color("#d8b23c"))
	for i in range(0, int(w), 8):
		draw_polygon(PackedVector2Array([
				Vector2(x + i, y), Vector2(x + i + 4.0, y),
				Vector2(x + i, y + 4.0)]), [Color("#1a160f")])
		draw_polygon(PackedVector2Array([
				Vector2(x + i + 4.0, y), Vector2(x + i + 8.0, y),
				Vector2(x + i + 4.0, y + 4.0)]), [Color("#d8b23c")])


## —— 垃圾桶（落地小件）——
func _draw_trashcan(cx: float, base_y: float) -> void:
	var w := 14.0
	var h := 20.0
	var x := cx - w * 0.5
	var y := base_y - h
	draw_rect(Rect2(x + 2.0, base_y - 1.0, w, 2.0), Color(0.0, 0.0, 0.0, 0.3))
	draw_rect(Rect2(x, y, w, h), Color("#2c3038"))
	draw_rect(Rect2(x - 1.0, y - 3.0, w + 2.0, 4.0), Color("#3c424c"))   # 桶沿
	draw_rect(Rect2(x, y + 4.0, w, 2.0), Color("#22262c"))
	draw_rect(Rect2(x + 2.0, y + 11.0, w - 4.0, 2.0), Color("#22262c"))
	draw_rect(Rect2(x, y, 2.0, h), Color("#3e444e"))                     # 高光


## —— 警示灯（墙装红灯，待机微光）——
func _draw_warning_light(ax: float, top: float) -> void:
	var y := top + 10.0
	draw_rect(Rect2(ax - 6.0, y, 12.0, 5.0), Color("#2c3038"))           # 支架
	draw_rect(Rect2(ax - 8.0, y + 5.0, 16.0, 10.0), Color("#402228"))    # 灯罩
	draw_rect(Rect2(ax - 6.0, y + 7.0, 12.0, 6.0), Color(0.9, 0.25, 0.22, 0.55))
	draw_rect(Rect2(ax - 4.0, y + 8.0, 3.0, 3.0), Color(1.0, 0.55, 0.5, 0.8))
	# 红光下渗
	draw_rect(Rect2(ax - 10.0, y + 15.0, 20.0, 14.0),
			Color(0.9, 0.2, 0.2, 0.06))


## —— 监控摄像头（垂杆 + 俯角机身 + 镜头 + REC 红灯；sweep 加半透明视野锥）——
func _draw_camera(ax: float, cable_y: float, facing_left: bool, sweep: bool) -> void:
	var drop := 26.0
	draw_line(Vector2(ax, cable_y + 6), Vector2(ax, cable_y + 6 + drop),
			Color("#464e54"), 4.0)
	draw_rect(Rect2(ax - 5, cable_y + 2, 10, 5), Color("#282e34"))    # 固定座
	var y0 := cable_y + 6 + drop
	var dir := -1.0 if facing_left else 1.0
	if sweep:
		# 视野锥（信号级亮色 —— 全图仅有的红之一）
		var tip := Vector2(ax + dir * 44, y0 + 20)
		draw_polygon(PackedVector2Array([
				tip, tip + Vector2(dir * -206, 130), tip + Vector2(dir * -26, 92)]),
				[Color(1.0, 0.28, 0.28, 0.09)])
	draw_polygon(PackedVector2Array([
			Vector2(ax, y0), Vector2(ax, y0 + 26),
			Vector2(ax + dir * 46, y0 + 34), Vector2(ax + dir * 46, y0 + 10)]),
			[Color("#343a40")])
	draw_line(Vector2(ax, y0), Vector2(ax + dir * 46, y0 + 10), Color("#606a70"), 1.0)
	var lens := Vector2(ax + dir * 44, y0 + 24)
	draw_circle(lens, 7.0, Color("#10161c"))
	draw_circle(lens + Vector2(-2, -2), 2.0, Color("#78a0b0"))
	var rec := Vector2(ax + dir * 5, y0 + 4)
	draw_circle(rec, 4.0, Color(1.0, 0.28, 0.28, 0.16))
	draw_circle(rec, 1.8, Color("#f03c3c"))                            # REC 红灯


## —— 监控干线（沿墙横线 + 固定卡扣）——
func _draw_cable(x0: float, x1: float, y: float) -> void:
	var cy := y + 6
	draw_line(Vector2(x0, cy), Vector2(x1, cy), Color("#1e262c"), 3.0)
	draw_line(Vector2(x0, cy + 2), Vector2(x1, cy + 2), Color("#343e46"), 1.0)
	var x := x0 + 20.0
	while x < x1:
		draw_rect(Rect2(x - 3, cy - 3, 6, 8), Color("#465058"))
		draw_line(Vector2(x - 3, cy - 3), Vector2(x + 3, cy - 3), Color("#687278"), 1.0)
		x += 64.0
