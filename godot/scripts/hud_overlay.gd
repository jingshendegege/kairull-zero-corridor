extends Control
class_name GameHudOverlay
## HUD 的绘制部分（准星 + 中央提示 + 心形血条 + 残敌计数 + 开场 VHS 标题卡 + 过关卡）。
## CanvasLayer 不是 CanvasItem 不能 _draw，绘制必须挂在这个 Control 子节点上。
## 默认视图极简：开发文字块在 hud.gd 侧按 F 调试开关显隐，这里常驻的只有
## 心形血条 / 残敌计数 / 准星，开场 2.8s 叠加录像带风标题卡。

const NEON_CYAN := Color("#7ec8ff")
const NEON_PINK := Color("#ff4fa3")
const AMBER := Color("#ffd166")
const INTRO_TIME := 2.8          ## 开场标题卡时长（秒）
const HELP_FADE_START := 12.0    ## 底部操作说明淡出起点（hud.gd 侧实现）

## 过关卡尺寸策略：宽度按标题实测宽度自适应（文字两侧各留 PAD_X），
## 短标题保底 MIN_W 不至于缩成小方块；副标题同样参与宽度核算。
const CLEAR_CARD_MIN_W := 360.0
const CLEAR_CARD_PAD_X := 30.0
const CLEAR_CARD_H := 110.0
const CLEAR_TITLE_SIZE := 40
const CLEAR_SUB_SIZE := 14

## 房间卡尺寸策略：与过关卡同款——宽度按房间名/副标题实测宽度自适应
## （文字两侧各留 PAD_X），短名保底 MIN_W；高固定。
const ROOM_CARD_MIN_W := 280.0
const ROOM_CARD_PAD_X := 24.0
const ROOM_CARD_H := 54.0
const ROOM_CARD_NAME_SIZE := 20
const ROOM_CARD_SUB_SIZE := 12

var hud: GameHud

var _last_alive := -1            ## 残敌计数上一帧值（减员时脉冲）
var _counter_pulse := 0.0
var _room_card_name := ""        ## 房间卡（底部居中，进房 1.6s）
var _room_card_sub := ""
var _room_card_until := 0.0
var _room_clear_t := -1.0        ## 当前房间清零时刻（CLEAR 停留后淡出）


## 进入新房间：底部居中小卡（房间名 + 敌人 x/N），1.6s
func show_room_card(room_name: String, alive: int, total: int) -> void:
	_room_card_name = room_name
	_room_card_sub = ("敌人 %d/%d" % [alive, total]) if total > 0 else "安全区域"
	_room_card_until = Time.get_ticks_msec() / 1000.0 + 1.6
	_room_clear_t = -1.0
	_last_alive = -1   ## 换房后计数脉冲基线重置


## Backspace 重置：房间卡与 CLEAR 淡出一起复位
func reset_room_card() -> void:
	_room_card_until = 0.0
	_room_clear_t = -1.0
	_last_alive = -1


func _process(dt: float) -> void:
	if _counter_pulse > 0.0:
		_counter_pulse -= dt
	queue_redraw()


func _draw() -> void:
	if hud == null or hud.host == null:
		return
	var p: KairullPlayer = hud.host.player
	# 准星：瞄准时红色加粗，平时蓝色小准星
	var m := get_viewport().get_mouse_position()
	var aiming: bool = p != null and p.aiming
	var c := Color(1.0, 0.42, 0.45) if aiming else NEON_CYAN
	var lw := 2.0 if aiming else 1.4
	var rr := 10.0 if aiming else 8.0
	draw_arc(m, rr, 0, TAU, 24, c, lw)
	draw_line(m + Vector2(-rr - 5, 0), m + Vector2(-4, 0), c, lw)
	draw_line(m + Vector2(4, 0), m + Vector2(rr + 5, 0), c, lw)
	draw_line(m + Vector2(0, -rr - 5), m + Vector2(0, -4), c, lw)
	draw_line(m + Vector2(0, 4), m + Vector2(0, rr + 5), c, lw)
	var font := hud.get_theme_font()
	if p != null:
		_draw_hearts(p)
	_draw_enemy_counter(font)
	_draw_room_card(font)
	_draw_intro_card(font)
	_draw_clear_card(font)
	# 中央提示
	if hud.msg_active():
		draw_string(font, Vector2(680, 84), hud._msg,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1, 0.82, 0.4, 0.95))
	# 换弹进度条（屏幕中下方）：背景槽 + 进度 + 剩余秒数
	if p != null and p.reloading:
		var bw := 260.0
		var ratio: float = 1.0 - p.reload_t / KairullPlayer.RELOAD_TIME
		var origin := Vector2(680 - bw / 2, 640)
		draw_rect(Rect2(origin, Vector2(bw, 14)), Color(0.08, 0.1, 0.16, 0.85))
		draw_rect(Rect2(origin, Vector2(bw * ratio, 14)), Color(0.5, 0.8, 1.0))
		draw_rect(Rect2(origin, Vector2(bw, 14)), Color(0.75, 0.85, 1.0), false, 1.0)
		draw_string(font, origin + Vector2(bw / 2, -8), "换弹 %.1fs" % p.reload_t,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.75, 0.88, 1.0))


## 心形血条：左上霓虹小 pip，品红实心 = 当前 HP，暗描边 = 已损。
## 10px 像素心（两行圆头 + 收尖底），下面压一条细辉光。
func _draw_hearts(p: KairullPlayer) -> void:
	var origin := Vector2(14, 14)
	var hp_max := hud.player_hp_capacity(p)
	for i in hp_max:
		var hp := origin + Vector2(i * 16.0, 0)
		var filled: bool = i < p.hp
		var heart := PackedVector2Array([
			hp + Vector2(5, 1), hp + Vector2(8, 0), hp + Vector2(10, 2),
			hp + Vector2(10, 4), hp + Vector2(5, 9), hp + Vector2(0, 4),
			hp + Vector2(0, 2), hp + Vector2(2, 0),
		])
		if filled:
			draw_colored_polygon(heart, NEON_PINK)
			# 1px 高亮点
			draw_rect(Rect2(hp + Vector2(2, 2), Vector2(2, 2)), Color(1, 0.75, 0.88))
		else:
			draw_polyline(heart + PackedVector2Array([heart[0]]),
					Color(NEON_PINK.r, NEON_PINK.g, NEON_PINK.b, 0.30), 1.0)
	# 细辉光线
	draw_line(origin + Vector2(-2, 13), origin + Vector2(hp_max * 16.0, 13),
			Color(NEON_PINK.r, NEON_PINK.g, NEON_PINK.b, 0.18), 1.0)


## 残敌计数：右上青色霓虹芯片。有房间表的图（M02）按当前房间计数
## `残敌 x/N`，0 敌房间不显示；清零后 `CLEAR` 停留 1.2s 再淡出。
## 无房间表的旧图保持全图计数（残敌 04 / 12 → CLEAR 常驻）。
func _draw_enemy_counter(font: Font) -> void:
	var total := 0
	var alive := 0
	var per_room: bool = hud.host.level != null and not hud.host.level.rooms.is_empty()
	if per_room:
		var ri: int = hud.host.current_room
		if ri < 0:
			return
		total = hud.host.room_total_count(ri)
		if total <= 0:
			return   ## 安全房间不显示计数芯片
		alive = hud.host.room_alive_count(ri)
	else:
		total = hud.host.minions.size()
		if total == 0:
			return
		for mn in hud.host.minions:
			if is_instance_valid(mn) and not mn.dead:
				alive += 1
	if _last_alive < 0:
		_last_alive = alive
	if alive != _last_alive:
		_counter_pulse = 0.30
		_last_alive = alive
	# 清零态：CLEAR 停留 1.2s 后淡出（仅房间模式；旧图保持常驻 CLEAR）
	var clear_alpha := 1.0
	if alive == 0 and per_room:
		var now := Time.get_ticks_msec() / 1000.0
		if _room_clear_t < 0.0:
			_room_clear_t = now
		var k: float = (now - _room_clear_t) / 1.2
		if k >= 1.0:
			return
		clear_alpha = 1.0 - k
	elif alive > 0:
		_room_clear_t = -1.0
	var pulse_k: float = clampf(_counter_pulse / 0.30, 0.0, 1.0)
	var text := "CLEAR" if alive == 0 else "残敌 %02d / %02d" % [alive, total]
	var col := NEON_CYAN if alive > 0 else AMBER
	col.a = (0.75 + 0.25 * pulse_k) * clear_alpha
	var chip := Vector2(150, 26)
	var origin := Vector2(1360 - chip.x - 12, 10)
	var grow := 2.0 * pulse_k
	draw_rect(Rect2(origin - Vector2(grow, grow), chip + Vector2(grow, grow) * 2),
			Color(0.05, 0.09, 0.16, 0.72 * clear_alpha))
	draw_rect(Rect2(origin - Vector2(grow, grow), chip + Vector2(grow, grow) * 2),
			col, false, 1.2)
	draw_string(font, origin + Vector2(chip.x * 0.5, 18), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 13, col)


## 房间卡：底部居中小卡（复用标题卡样式，缩小版），进房 1.6s，尾段下滑淡出。
## 文字摆位与过关卡同款修复：draw_string 的 CENTER 对齐只在给定 width 内生效，
## width=-1 时实际左对齐（曾导致文字偏右溢出卡框）——这里实测字符串宽，
## 显式左对齐摆到水平中心；卡宽按文字自适应（room_card_size）。
func _draw_room_card(font: Font) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _room_card_until:
		return
	var remain: float = _room_card_until - now
	var alpha: float = clampf(remain / 0.4, 0.0, 1.0)   ## 尾段 0.4s 淡出
	var slide: float = (1.0 - alpha) * (1.0 - alpha) * 20.0
	var center := Vector2(680, 660 + slide)
	var card := room_card_size(font, _room_card_name, _room_card_sub)
	var origin := center - card * 0.5
	draw_rect(Rect2(origin, card), Color(0.05, 0.04, 0.10, 0.78 * alpha))
	draw_rect(Rect2(origin, card),
			Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.55 * alpha), false, 1.2)
	var nw := font.get_string_size(_room_card_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_CARD_NAME_SIZE).x
	var sw2 := font.get_string_size(_room_card_sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_CARD_SUB_SIZE).x
	draw_string(font, Vector2(center.x - nw * 0.5, center.y - 6), _room_card_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_CARD_NAME_SIZE,
			Color(0.94, 0.96, 1.0, alpha))
	draw_string(font, Vector2(center.x - sw2 * 0.5, center.y + 18), _room_card_sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_CARD_SUB_SIZE,
			Color(NEON_PINK.r, NEON_PINK.g, NEON_PINK.b, 0.85 * alpha))


## 房间卡尺寸：max(房间名宽, 副标题宽) + 2*PAD_X，保底 MIN_W；高固定。
## 抽成独立函数供无头测试直接断言（无需真绘制）。
func room_card_size(font: Font, room_name: String, sub: String) -> Vector2:
	var nw := font.get_string_size(room_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_CARD_NAME_SIZE).x
	var sw := font.get_string_size(sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_CARD_SUB_SIZE).x
	var w := maxf(ROOM_CARD_MIN_W, maxf(nw, sw) + 2.0 * ROOM_CARD_PAD_X)
	return Vector2(w, ROOM_CARD_H)


## 开场 VHS 标题卡（前 2.8s）：左上琥珀 REC 时间戳（闪烁）+
## 中左大标题 M01 旧城区 / kicker，一道扫描线扫过标题，尾段滑出淡出。
func _draw_intro_card(font: Font) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0 - hud.level_start_t
	if t < 0.0 or t >= INTRO_TIME:
		return
	var out_t: float = clampf((t - (INTRO_TIME - 0.6)) / 0.6, 0.0, 1.0)
	var alpha := 1.0 - out_t
	var slide := out_t * out_t * 48.0   ## 尾段向左滑出
	# 左上 REC 时间戳（录像带日期未知感 + 红点闪烁）
	var blink: bool = fmod(t * 2.2, 1.0) < 0.62
	var stamp := "1988.??.??  23:47  REC %s" % ("●" if blink else " ")
	draw_string(font, Vector2(14 - slide, 44), stamp,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(AMBER.r, AMBER.g, AMBER.b, 0.85 * alpha))
	# 标题区（中左）
	var title := CorridorLevel.active_title
	if title.is_empty():
		title = "M01 旧城区"
	var base := Vector2(96 - slide, 332)
	draw_string(font, base + Vector2(2, -58), "KAIRULL · ZERO CORRIDOR",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.75 * alpha))
	draw_string(font, base, title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(0.94, 0.96, 1.0, alpha))
	# 标题下细线
	draw_line(base + Vector2(2, 16), base + Vector2(240, 16),
			Color(NEON_PINK.r, NEON_PINK.g, NEON_PINK.b, 0.55 * alpha), 1.5)
	# 扫描线：0.7s~1.5s 之间从标题上方扫到下方一次（跟踪杂讯感）
	var scan_t: float = clampf((t - 0.7) / 0.8, 0.0, 1.0)
	if t >= 0.7 and t <= 1.5:
		var sy: float = base.y - 46.0 + scan_t * 76.0
		draw_rect(Rect2(base.x - 8, sy, 300, 2),
				Color(0.85, 0.95, 1.0, 0.5 * alpha * (1.0 - scan_t * 0.5)))
		draw_rect(Rect2(base.x - 8, sy + 3, 300, 1),
				Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.25 * alpha))


## 过关卡：中央大号 <关卡名> CLEAR（琥珀霓虹框），与残敌芯片的 CLEAR 态呼应。
## 卡宽按标题/副标题实测宽度自适应：owner 截图里 "M02 数据塔 CLEAR" 曾溢出
## 固定 360px 卡框——现在用 font.get_string_size 量字符串，文字两侧各留
## CLEAR_CARD_PAD_X，短标题保底 CLEAR_CARD_MIN_W。
func _draw_clear_card(font: Font) -> void:
	if not hud.host.level_cleared:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.75 + 0.25 * sin(t * 2.6)
	var title := CorridorLevel.active_title
	if title.is_empty():
		title = "M01 旧城区"
	var title_text := title + " CLEAR"
	var sub_text := "回廊区段已肃清 · Backspace 重置"
	var center := Vector2(680, 330)
	var card := clear_card_size(font, title_text, sub_text)
	var origin := center - card * 0.5
	draw_rect(Rect2(origin, card), Color(0.05, 0.04, 0.10, 0.82))
	draw_rect(Rect2(origin, card), Color(AMBER.r, AMBER.g, AMBER.b, 0.85 * pulse), false, 2.0)
	draw_rect(Rect2(origin + Vector2(5, 5), card - Vector2(10, 10)),
			Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.35), false, 1.0)
	# 注意：draw_string 的 CENTER 对齐只在给定 width 内生效，width=-1 时实际左对齐
	# （owner 截图"文字比框宽"的真凶之一）。这里显式按实测宽度左对齐摆到水平中心。
	var tw := font.get_string_size(title_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLEAR_TITLE_SIZE).x
	var sw := font.get_string_size(sub_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLEAR_SUB_SIZE).x
	draw_string(font, Vector2(center.x - tw * 0.5, center.y - 8), title_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLEAR_TITLE_SIZE,
			Color(AMBER.r, AMBER.g, AMBER.b, 0.95))
	draw_string(font, Vector2(center.x - sw * 0.5, center.y + 30), sub_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLEAR_SUB_SIZE,
			Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.8))


## 过关卡尺寸：max(标题宽, 副标题宽) + 2*PAD_X，保底 MIN_W；高固定。
## 抽成独立函数供无头测试直接断言（无需真绘制）。
func clear_card_size(font: Font, title_text: String, sub_text: String) -> Vector2:
	var tw := font.get_string_size(title_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLEAR_TITLE_SIZE).x
	var sw := font.get_string_size(sub_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLEAR_SUB_SIZE).x
	var w := maxf(CLEAR_CARD_MIN_W, maxf(tw, sw) + 2.0 * CLEAR_CARD_PAD_X)
	return Vector2(w, CLEAR_CARD_H)
