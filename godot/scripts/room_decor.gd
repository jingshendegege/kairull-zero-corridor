extends Node2D
class_name RoomDecor
## M02 房间装饰剪影：按房间名程序化绘制背景陈设（纯背景，无碰撞无交互）。
## 覆盖度控制在墙面 ~20-30%，全部取 KZPalette 背景层暗色，保持玩法可读性。
##
##   大堂     —— 前台接待桌 + 盆栽 ×2 + 墙上徽牌
##   事务所   —— 工位桌 + 显示器（暗青/暗琥珀屏）+ 墙相框
##   休息室   —— 售货机（暗青橱窗辉光，呼吸）+ 长沙发 + 墙海报
##   服务器厅 —— 服务器机柜列 + 成排红绿 LED 闪烁 + 顶部走线槽与垂线
##   核心前厅 —— 大导管横管 + 抱箍 + 警示纹带 + 近核心侧红色脉冲辉光
##   塔心     —— 竖向管束 + 核心圆柱剪影（红缘光脉冲）+ 警示纹带
##   楼梯间   —— 顶部横管 + 通风格栅 + 暗青小标牌
##
## 动画（LED 闪烁 / 售货机辉光 / 红色脉冲）只靠 _phase 驱动 queue_redraw，
## 静态房间画一次即止。game 按房间实例化并插在 tilemap 之前（装饰在玩法层之后）。

const TS := 32

var room_name := ""
var room_rect := Rect2i()
var decor_count := 0          ## 陈设件数（setup 时按布局规划算出，无头可测；测试断言 > 0）

var _phase := 0.0
var _animated := false


func setup(p_name: String, p_rect: Rect2i) -> void:
	room_name = p_name
	room_rect = p_rect
	_animated = room_name.contains("服务器") or room_name.contains("休息") \
			or room_name.contains("核心") or room_name.contains("塔心")
	decor_count = _plan_count()
	queue_redraw()


## 陈设件数预算（与 _draw_xxx 的布局一一对应；无头模式 _draw 不会被调用，
## 计数必须在 setup 阶段就可查询）
func _plan_count() -> int:
	if room_name.contains("大堂"):
		return 4    ## 前台 + 盆栽×2 + 徽牌
	if room_name.contains("事务所"):
		return 5    ## 工位×2 + 相框×3
	if room_name.contains("服务器"):
		# 机柜数与 _draw_server_hall 同循环边界 + 顶部走线槽
		var n := 0
		var rx := room_rect.position.x * TS + 3 * TS
		while rx < (room_rect.position.x + room_rect.size.x) * TS - 2 * TS:
			n += 1
			rx += 7 * TS
		return n + 1
	if room_name.contains("休息"):
		return 3    ## 售货机 + 沙发 + 海报
	if room_name.contains("核心前厅"):
		return 4    ## 导管组 + 警示纹×2 + 红色脉冲
	if room_name.contains("塔心"):
		return 6    ## 核心柱 + 管束×3 + 警示纹×2
	if room_name.contains("楼梯间"):
		return 4    ## 横管 + 格栅×2 + 标牌
	return 0


func _process(dt: float) -> void:
	if not _animated:
		set_process(false)
		return
	_phase += dt
	queue_redraw()


func _draw() -> void:
	if room_rect.size.x == 0:
		return
	if room_name.contains("大堂"):
		_draw_lobby()
	elif room_name.contains("事务所"):
		_draw_office()
	elif room_name.contains("服务器"):
		_draw_server_hall()
	elif room_name.contains("休息"):
		_draw_break_room()
	elif room_name.contains("核心前厅"):
		_draw_antechamber()
	elif room_name.contains("塔心"):
		_draw_tower_core()
	elif room_name.contains("楼梯间"):
		_draw_stairwell()


## 房间像素边界与地板顶面 Y
func _x0() -> float: return float(room_rect.position.x * TS)
func _y0() -> float: return float(room_rect.position.y * TS)
func _w() -> float: return float(room_rect.size.x * TS)
func _floor_y() -> float: return float(room_rect.end.y * TS)


## ---------- 大堂 ----------
func _draw_lobby() -> void:
	var fy := _floor_y()
	# 前台接待桌：宽台面 + 前板缝 + 顶沿受光 + 暗琥珀小台灯点
	var dx := _x0() + 14.0 * TS
	draw_rect(Rect2(dx, fy - 30, 92, 30), KZPalette.DECOR_BODY)
	draw_rect(Rect2(dx, fy - 30, 92, 4), KZPalette.DECOR_FACE)
	draw_line(Vector2(dx, fy - 30), Vector2(dx + 92, fy - 30), KZPalette.DECOR_EDGE, 2.0)
	draw_line(Vector2(dx + 46, fy - 24), Vector2(dx + 46, fy - 2),
			KZPalette.BACKDROP_SEAM, 1.0)
	draw_rect(Rect2(dx + 66, fy - 38, 6, 8), KZPalette.DECOR_BODY)
	draw_rect(Rect2(dx + 64, fy - 41, 10, 3),
			Color(KZPalette.WINDOW_AMBER, 0.55))
	# 盆栽 ×2：暗盆 + 三杈叶线（压暗绿）
	for pot_x in [_x0() + 4.0 * TS, _x0() + 33.0 * TS]:
		draw_rect(Rect2(pot_x, fy - 10, 14, 10), KZPalette.DECOR_FACE)
		draw_line(Vector2(pot_x, fy - 10), Vector2(pot_x + 14, fy - 10),
				KZPalette.DECOR_EDGE, 2.0)
		var leaf := Color("#224030")
		draw_line(Vector2(pot_x + 7, fy - 10), Vector2(pot_x + 7, fy - 26), leaf, 2.0)
		draw_line(Vector2(pot_x + 7, fy - 18), Vector2(pot_x + 1, fy - 30), leaf, 2.0)
		draw_line(Vector2(pot_x + 7, fy - 20), Vector2(pot_x + 14, fy - 32), leaf, 2.0)
	# 墙上徽牌（公司 logo 板，暗底 + 品红细线——全场最低饱和用法）
	var px := _x0() + 22.0 * TS
	draw_rect(Rect2(px, _y0() + 44, 34, 22), KZPalette.DECOR_FACE)
	draw_rect(Rect2(px, _y0() + 44, 34, 22), KZPalette.DECOR_EDGE, false, 1.0)
	draw_line(Vector2(px + 6, _y0() + 55), Vector2(px + 28, _y0() + 55),
			Color(KZPalette.NEON_MAGENTA, 0.30), 2.0)


## ---------- 事务所 ----------
func _draw_office() -> void:
	var fy := _floor_y()
	# 两个工位：桌面 + 桌腿 + 显示器（一青一琥珀，屏幕极暗）+ 显示器支架
	for i in range(2):
		var dx := _x0() + (6.0 + 18.0 * i) * TS
		draw_rect(Rect2(dx, fy - 26, 58, 5), KZPalette.DECOR_FACE)      # 桌面
		draw_line(Vector2(dx, fy - 26), Vector2(dx + 58, fy - 26),
				KZPalette.DECOR_EDGE, 2.0)
		draw_rect(Rect2(dx + 4, fy - 21, 4, 21), KZPalette.DECOR_BODY)  # 左腿
		draw_rect(Rect2(dx + 50, fy - 21, 4, 21), KZPalette.DECOR_BODY) # 右腿
		var scr := Color("#1d3a44") if i == 0 else Color("#3a2c1a")
		draw_rect(Rect2(dx + 20, fy - 44, 20, 14), KZPalette.DECOR_BODY)  # 显示器壳
		draw_rect(Rect2(dx + 22, fy - 42, 16, 10), scr)                   # 屏
		draw_line(Vector2(dx + 23, fy - 40), Vector2(dx + 36, fy - 40),
				Color(KZPalette.NEON_CYAN if i == 0 else KZPalette.WINDOW_AMBER, 0.35), 1.0)
		draw_rect(Rect2(dx + 28, fy - 30, 4, 4), KZPalette.DECOR_BODY)    # 支架
	# 墙相框 ×3：暗框 + 内芯 + 一点挂画色
	for i in range(3):
		var fx := _x0() + (9.0 + 9.0 * i) * TS
		var fy2 := _y0() + 36.0 + (6.0 if i % 2 == 1 else 0.0)
		draw_rect(Rect2(fx, fy2, 14, 17), KZPalette.DECOR_BODY)
		draw_rect(Rect2(fx, fy2, 14, 17), KZPalette.DECOR_EDGE, false, 1.0)
		draw_rect(Rect2(fx + 3, fy2 + 3, 8, 11), KZPalette.BACKDROP_SEAM)
		draw_rect(Rect2(fx + 5, fy2 + 6, 4, 4),
				Color(KZPalette.WINDOW_CITY_A, 0.4))


## ---------- 服务器厅 ----------
func _draw_server_hall() -> void:
	var fy := _floor_y()
	# 机柜列：26px 宽 × 150px 高，近黑壳 + 面板 + 外轮廓 + 每 8px 一排 LED（绿/红交替闪烁）
	var blink := int(_phase * 2.0)
	var rack_idx := 0
	var rx := _x0() + 3.0 * TS
	while rx < _x0() + _w() - 2.0 * TS:
		draw_rect(Rect2(rx, fy - 150, 26, 150), KZPalette.DECOR_BODY)
		draw_rect(Rect2(rx + 3, fy - 147, 20, 144), KZPalette.DECOR_FACE)
		draw_rect(Rect2(rx, fy - 150, 26, 150), KZPalette.DECOR_EDGE, false, 1.0)
		draw_line(Vector2(rx + 1, fy - 149), Vector2(rx + 1, fy - 2),
				KZPalette.BACKDROP_HI, 1.0)
		# 柜顶状态灯条：整柜一缕暗绿（随相位明灭，机柜集群感）
		var top_on := (blink + rack_idx) % 4 != 3
		draw_rect(Rect2(rx + 4, fy - 153, 18, 3),
				Color(KZPalette.LED_GREEN, 0.55 if top_on else 0.12))
		# 面板分隔横线
		for sy in range(int(fy - 140), int(fy - 8), 16):
			draw_line(Vector2(rx + 3, sy), Vector2(rx + 23, sy),
					KZPalette.BACKDROP_SEAM, 1.0)
		# LED 点：每排两粒，相位错开闪烁（武士零式机柜灯）
		var led_i := 0
		for sy in range(int(fy - 138), int(fy - 6), 8):
			var on1 := (blink + led_i + rack_idx) % 3 != 0
			var on2 := (blink + led_i * 2 + rack_idx) % 4 == 0
			var c1: Color = KZPalette.LED_GREEN if on1 else Color(KZPalette.LED_GREEN, 0.18)
			var c2: Color = KZPalette.LED_RED if on2 else Color(KZPalette.LED_RED, 0.12)
			draw_rect(Rect2(rx + 6, sy, 2, 2), c1)
			draw_rect(Rect2(rx + 11, sy, 2, 2), c2)
			led_i += 1
		rack_idx += 1
		rx += 7.0 * TS
	# 顶部走线槽：横干 + 到各机柜的垂线
	var cy := _y0() + 20.0
	draw_rect(Rect2(_x0() + 8, cy, _w() - 16, 4), KZPalette.PIPE.darkened(0.15))
	draw_line(Vector2(_x0() + 8, cy), Vector2(_x0() + _w() - 8, cy),
			KZPalette.PIPE_HI.darkened(0.4), 1.0)
	rx = _x0() + 3.0 * TS + 13.0
	while rx < _x0() + _w() - 2.0 * TS:
		draw_line(Vector2(rx, cy + 4), Vector2(rx, fy - 150),
				KZPalette.PIPE.darkened(0.25), 2.0)
		rx += 7.0 * TS


## ---------- 休息室 ----------
func _draw_break_room() -> void:
	var fy := _floor_y()
	# 售货机：机身 + 暗青橱窗（呼吸辉光）+ 货品横排 + 取货口 + 脚底小光池
	var vx := _x0() + 5.0 * TS
	var glow := 0.22 + 0.10 * sin(_phase * 1.6)
	draw_rect(Rect2(vx, fy - 58, 28, 58), KZPalette.DECOR_BODY)
	draw_rect(Rect2(vx + 3, fy - 54, 15, 40), Color(KZPalette.VEND_GLOW, glow))
	for gy in range(int(fy - 48), int(fy - 20), 9):
		draw_line(Vector2(vx + 4, gy), Vector2(vx + 16, gy),
				Color(KZPalette.NEON_CYAN, glow * 0.5), 1.0)
	draw_rect(Rect2(vx + 20, fy - 50, 5, 12), KZPalette.BACKDROP_SEAM)   # 取货/投币区
	draw_rect(Rect2(vx + 4, fy - 10, 20, 6), KZPalette.BACKDROP_SEAM)    # 底部取货口
	draw_line(Vector2(vx, fy - 58), Vector2(vx + 28, fy - 58), KZPalette.DECOR_EDGE, 2.0)
	draw_rect(Rect2(vx - 8, fy - 2, 44, 3), Color(KZPalette.NEON_CYAN, glow * 0.35))
	# 长沙发：底座 + 靠背 + 双扶手 + 坐垫分缝
	var cx := _x0() + 18.0 * TS
	draw_rect(Rect2(cx, fy - 16, 72, 16), KZPalette.DECOR_BODY)
	draw_rect(Rect2(cx, fy - 34, 72, 18), KZPalette.DECOR_FACE)
	draw_rect(Rect2(cx - 6, fy - 30, 8, 30), KZPalette.DECOR_BODY)
	draw_rect(Rect2(cx + 70, fy - 30, 8, 30), KZPalette.DECOR_BODY)
	draw_line(Vector2(cx, fy - 34), Vector2(cx + 72, fy - 34), KZPalette.DECOR_EDGE, 2.0)
	draw_line(Vector2(cx + 24, fy - 32), Vector2(cx + 24, fy - 16),
			KZPalette.BACKDROP_SEAM, 1.0)
	draw_line(Vector2(cx + 48, fy - 32), Vector2(cx + 48, fy - 16),
			KZPalette.BACKDROP_SEAM, 1.0)
	# 墙海报（暗框 + 一条品红斜纹）
	var px := _x0() + 30.0 * TS
	draw_rect(Rect2(px, _y0() + 34, 18, 24), KZPalette.DECOR_FACE)
	draw_rect(Rect2(px, _y0() + 34, 18, 24), KZPalette.DECOR_EDGE, false, 1.0)
	draw_line(Vector2(px + 3, _y0() + 52), Vector2(px + 15, _y0() + 40),
			Color(KZPalette.NEON_MAGENTA, 0.28), 2.0)


## ---------- 核心前厅 ----------
func _draw_antechamber() -> void:
	var fy := _floor_y()
	# 大导管：双横管（8px 主管 + 5px 副管）沿墙贯通 + 抱箍 + 下行弯头
	var y1 := _y0() + 30.0
	var y2 := _y0() + 46.0
	draw_rect(Rect2(_x0(), y1, _w(), 8), KZPalette.PIPE)
	draw_rect(Rect2(_x0(), y2, _w(), 5), KZPalette.PIPE.darkened(0.3))
	draw_line(Vector2(_x0(), y1), Vector2(_x0() + _w(), y1),
			KZPalette.PIPE_HI.darkened(0.25), 1.0)
	draw_line(Vector2(_x0(), y2), Vector2(_x0() + _w(), y2),
			KZPalette.PIPE_HI.darkened(0.45), 1.0)
	var px := _x0() + 6.0 * TS
	while px < _x0() + _w() - 4.0 * TS:
		draw_rect(Rect2(px, y1 - 1, 3, 10), KZPalette.PIPE_HI.darkened(0.3))  # 抱箍
		if int((px - _x0()) / TS) % 18 == 6:
			# 下行弯头：主管垂直到地板
			draw_rect(Rect2(px + 6, y1 + 8, 6, fy - y1 - 8), KZPalette.PIPE.darkened(0.2))
			draw_line(Vector2(px + 6, y1 + 8), Vector2(px + 6, fy),
					KZPalette.PIPE_HI.darkened(0.4), 1.0)
		px += 6.0 * TS
	# 警示纹带：贴地板上沿，8px 斜纹交替（靠门侧两段）
	for seg in [Vector2(_x0() + 55.0 * TS, 9.0 * TS), Vector2(_x0() + 2.0 * TS, 6.0 * TS)]:
		_draw_warn_band(seg.x, fy - 12, seg.y)
	# 近核心侧（右端）红色脉冲辉光：多层径向叠加
	var pulse := 0.05 + 0.035 * (0.5 + 0.5 * sin(_phase * 1.8))
	var gx := _x0() + _w() - 40.0
	var gy := fy - 60.0
	for i in range(3):
		var r := 90.0 - i * 26.0
		draw_rect(Rect2(gx - r * 0.5, gy - r * 0.4, r, r * 0.8),
				Color(KZPalette.DOOR_LOCKED, pulse * (1.0 - i * 0.25)))


## ---------- 塔心 ----------
func _draw_tower_core() -> void:
	var fy := _floor_y()
	# 核心圆柱剪影：出口后方的大圆罐（暗体 + 红缘光脉冲 + 上下管口）
	var core_x := _x0() + 52.0 * TS
	var pulse := 0.10 + 0.07 * (0.5 + 0.5 * sin(_phase * 1.8))
	draw_rect(Rect2(core_x, _y0() + 10, 54, fy - _y0() - 10), KZPalette.DECOR_BODY)
	draw_rect(Rect2(core_x + 4, _y0() + 14, 46, fy - _y0() - 18), KZPalette.DECOR_FACE)
	draw_rect(Rect2(core_x - 2, _y0() + 10, 2, fy - _y0() - 10),
			Color(KZPalette.DOOR_LOCKED, pulse))
	draw_rect(Rect2(core_x + 54, _y0() + 10, 2, fy - _y0() - 10),
			Color(KZPalette.DOOR_LOCKED, pulse))
	draw_rect(Rect2(core_x + 20, _y0(), 14, 12), KZPalette.PIPE.darkened(0.3))
	# 竖向管束：三组 3 管并列（从顶到底）
	for gx: float in [_x0() + 6.0 * TS, _x0() + 20.0 * TS, _x0() + 36.0 * TS]:
		for k in range(3):
			var px: float = gx + k * 7.0
			draw_rect(Rect2(px, _y0(), 4, fy - _y0()), KZPalette.PIPE.darkened(0.15))
			draw_line(Vector2(px, _y0()), Vector2(px, fy),
					KZPalette.PIPE_HI.darkened(0.4), 1.0)
	# 警示纹带：核心基座与出口侧
	_draw_warn_band(core_x - 6, fy - 12, 66.0)
	_draw_warn_band(_x0() + 60.0 * TS, fy - 12, 8.0 * TS)


## ---------- 楼梯间 ----------
func _draw_stairwell() -> void:
	# 顶部横管 + 管箍
	var y1 := _y0() + 16.0
	draw_rect(Rect2(_x0(), y1, _w(), 6), KZPalette.PIPE.darkened(0.15))
	draw_line(Vector2(_x0(), y1), Vector2(_x0() + _w(), y1),
			KZPalette.PIPE_HI.darkened(0.35), 1.0)
	var px := _x0() + 5.0 * TS
	while px < _x0() + _w() - 3.0 * TS:
		draw_rect(Rect2(px, y1 - 1, 3, 8), KZPalette.PIPE_HI.darkened(0.35))
		px += 8.0 * TS
	# 通风格栅 ×2：暗框 + 三条横百叶
	for i in range(2):
		var vx := _x0() + (8.0 + 14.0 * i) * TS
		var vy := _y0() + 52.0
		draw_rect(Rect2(vx, vy, 20, 14), KZPalette.DECOR_BODY)
		draw_rect(Rect2(vx, vy, 20, 14), KZPalette.DECOR_EDGE, false, 1.0)
		for k in range(3):
			draw_line(Vector2(vx + 3, vy + 3 + k * 4), Vector2(vx + 17, vy + 3 + k * 4),
					KZPalette.BACKDROP_SEAM, 2.0)
	# 暗青小标牌（楼层号位）
	var sx := _x0() + _w() - 6.0 * TS
	draw_rect(Rect2(sx, _y0() + 40, 12, 16), KZPalette.DECOR_FACE)
	draw_rect(Rect2(sx, _y0() + 40, 12, 16), KZPalette.DECOR_EDGE, false, 1.0)
	draw_line(Vector2(sx + 3, _y0() + 46), Vector2(sx + 9, _y0() + 46),
			Color(KZPalette.NEON_CYAN, 0.30), 2.0)


## 警示纹带：x 起 w 宽 12px 高，8px 斜纹段交替（琥珀重压暗 / 近黑）
func _draw_warn_band(x: float, y: float, w: float) -> void:
	draw_rect(Rect2(x, y, w, 12), KZPalette.WARN_DARK)
	var sx := x
	var flip := false
	while sx < x + w:
		var seg := minf(8.0, x + w - sx)
		if flip:
			# 斜纹：平行四边形读作斜杠
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx, y + 12), Vector2(sx + seg, y + 12),
				Vector2(sx + seg + 4, y), Vector2(sx + 4, y)]), KZPalette.WARN_STRIPE)
		flip = not flip
		sx += 8.0
	draw_rect(Rect2(x, y, w, 12), KZPalette.DECOR_EDGE, false, 1.0)
