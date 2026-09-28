extends Node2D
class_name BeatStageFx
## 05 节拍广播塔：随拍驱动的舞台实景层（Claude 美术，2026-09-28）。
## 放在 game 下、level 之前：地面瓦片盖住光束末端，角色/Boss/音符都在它前面。
## 只读 BeatArena 的拍位与状态（_pulse_beat / state / frozen / boss.hp），不参与任何判定。
## 背景层（本节点）：LED 频谱墙、音箱塔 + 鼓动振膜、霓虹招牌、摇头灯、舞台台口。
## 右侧 Boss 身后刻意留空，并给 Boss 一束专属白色顶光。
## 叠加层（子节点 Glow，ADD 混合）：追光灯束与落地光斑、激光扇、Boss 喇叭冲击波、强拍闪光、LED 辉光。
## 边跑边打（用户要求）：战斗中场景以音符同速向左滚动——视差背景（GameBackground.extra_scroll）、
## 路过的灯杆/音箱塔/护栏、以及地形之前的跑道层（BeatRunway：滚动地面 + 上下层之间的隔板）。

const ART := "res://assets/boss/beat_warden/"
const LED_POS := Vector2(1480, 216)
const LED_SIZE := Vector2(736, 352)
const LED_FRAME := 10.0
const EQ_BARS := 46
const SPOT_XS := [1180.0, 1340.0, 1500.0, 1660.0, 1820.0, 1980.0, 2140.0, 2300.0, 2460.0]
const SPOT_Y := 128.0
const RUN_SPEED := 520.0         ## = 谱面 note_speed_px：音符相当于钉在世界里，主角迎着它们跑
const LANE_FOOT := 36.0          ## 与 BeatArena.LANE_FOOT 一致：隔板顶面 = 上层音符中心 + 36
## 段落主色 / 副色 / 能量
const LOOK := {
	"idle": [Color("3a5aff"), Color("7a3aff"), 0.28],
	"count": [Color("3fd8ff"), Color("8f7aff"), 0.45],
	"intro": [Color("3fd8ff"), Color("8f7aff"), 0.55],
	"verse": [Color("b06cff"), Color("3fd8ff"), 0.72],
	"build": [Color("ff9a3f"), Color("ff3f94"), 0.8],
	"drop": [Color("ff3f94"), Color("3fd8ff"), 1.0],
	"finale": [Color("ffc84a"), Color("ff3f94"), 1.0],
	"end": [Color("ffffff"), Color("ffc84a"), 0.6],
}
## 5×7 点阵字（LED 墙上的倒数与提示）
const FONT := {
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
}

var game: Node2D
var arena: Node2D
var glow: Node2D
var _t := 0.0
var _beat := 0.0
var _kick := 0.0
var _section := "idle"
var _hit_flash := 0.0
var _last_hp := -1
var _floor_y := 736.0
var _tex := {}
var runway: Node2D
var scroll_x := 0.0
var run_speed := 0.0
var _divider_alpha := 0.0


func setup(host: Node2D, beat_arena: Node2D) -> void:
	game = host
	arena = beat_arena
	_floor_y = float(arena.config.floor_y)
	for key in ["stage_led_mask", "stage_speaker", "stage_woofer", "stage_spot", "stage_neon"]:
		_tex[key] = load(ART + key + ".png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow = Node2D.new()
	glow.name = "Glow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.draw.connect(_draw_glow)
	add_child(glow)
	# 跑道层放在地形之后、主角之前：盖住静态地面瓦片，不挡角色/音符
	runway = Node2D.new()
	runway.name = "BeatRunway"
	runway.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	runway.draw.connect(_draw_runway)
	game.add_child(runway)
	game.move_child(runway, game.player.get_index())


func _process(dt: float) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var frozen: bool = arena.frozen
	if not frozen:
		_t += dt
		_hit_flash = maxf(0.0, _hit_flash - dt * 4.0)
	var state: String = arena.state
	if state == "playing" or state == "count_in":
		_beat = float(arena._pulse_beat)
	elif state == "waiting":
		_beat = _t * 0.9
	elif not frozen:
		_beat += dt * 2.2
	_kick = exp(-fposmod(_beat, 1.0) * 6.0)
	_section = _section_for(state)
	var hp: int = arena.boss.hp
	if _last_hp >= 0 and hp < _last_hp:
		_hit_flash = 1.0
		if _last_hp - hp >= 3 and game.has_method("add_camera_shake"):
			game.add_camera_shake(Vector2.LEFT, 0.15)
	_last_hp = hp
	var running: bool = arena.rhythm_lock and state in ["count_in", "playing"]
	if not frozen:
		run_speed = move_toward(run_speed, RUN_SPEED if running else 0.0, RUN_SPEED * 1.5 * dt)
		scroll_x += run_speed * dt
		_divider_alpha = move_toward(_divider_alpha, 1.0 if state != "waiting" or arena.rhythm_lock else 0.0, dt * 3.0)
	if game.bg != null:
		game.bg.extra_scroll = scroll_x
	queue_redraw()
	glow.queue_redraw()
	runway.queue_redraw()


func _section_for(state: String) -> String:
	match state:
		"waiting":
			return "idle"
		"count_in":
			return "count"
		"dying", "defeated":
			return "end"
	var name := "intro"
	for section: Dictionary in arena.conductor.chart.sections:
		if _beat >= float(section.from_beat):
			name = String(section.name)
	return name if LOOK.has(name) else "drop"


func _look() -> Array:
	return LOOK[_section]


func _energy() -> float:
	var e: float = _look()[2]
	if _section == "build":   # 蓄力段：能量随小节爬升
		e = lerpf(0.6, 1.0, clampf((_beat - 96.0) / 16.0, 0.0, 1.0))
	return e


# ------------------------------------------------------------------ 背景层
func _draw() -> void:
	if arena == null:
		return
	var look := _look()
	var energy := _energy()
	# 舞台台口：LED 墙下的深色升降台 + 顶边灯线
	var deck := Rect2(LED_POS.x - 40, LED_POS.y + LED_SIZE.y, LED_SIZE.x + 80, _floor_y - LED_POS.y - LED_SIZE.y)
	draw_rect(deck, Color("0b0716"))
	draw_rect(Rect2(deck.position, Vector2(deck.size.x, 3)), Color(look[0], 0.5 + 0.5 * _kick))
	for x in range(int(deck.position.x) + 24, int(deck.end.x), 48):
		draw_rect(Rect2(x, deck.position.y + 14, 20, 4), Color(look[1], 0.25 + 0.5 * _kick * energy))
	_draw_led(look, energy)
	_draw_passing_props(look, energy)
	# 霓虹招牌：随拍亮，待机时偶发接触不良闪烁
	var neon: Texture2D = _tex.stage_neon
	var bright := 0.8 + 0.2 * _kick
	if _section == "idle":
		bright = 0.15 if sin(_t * 37.0) > 0.9 or sin(_t * 5.3) > 0.97 else 0.75
	draw_texture(neon, Vector2(LED_POS.x + LED_SIZE.x * 0.5 - neon.get_width() * 0.5, LED_POS.y - 58), Color(1, 1, 1, bright))
	# 摇头灯本体
	var spot: Texture2D = _tex.stage_spot
	for x: float in SPOT_XS:
		draw_texture(spot, Vector2(x - 14, SPOT_Y))


func _draw_led(look: Array, energy: float) -> void:
	var inner := Rect2(LED_POS + Vector2.ONE * LED_FRAME, LED_SIZE - Vector2.ONE * LED_FRAME * 2.0)
	draw_rect(inner, Color("120a22"))
	var text := _led_text()
	if text != "":
		_draw_led_text(inner, text, look)
	else:
		var bar_w := 12.0
		var step := inner.size.x / EQ_BARS
		for i in EQ_BARS:
			var bass := 1.0 - float(i) / EQ_BARS * 0.6
			var wobble := absf(sin(i * 0.9 + _beat * 1.7)) * (0.5 + 0.5 * sin(i * 0.37 - _beat * 0.9))
			var h := clampf(energy * (0.2 + 0.6 * _kick * bass + 0.35 * wobble), 0.04, 1.0) * inner.size.y
			var x := inner.position.x + i * step + 2.0
			var bottom := inner.end.y
			# 低段主色 → 高段副色，顶端白色峰值
			var low := minf(h, inner.size.y * 0.45)
			draw_rect(Rect2(x, bottom - low, bar_w, low), look[0])
			if h > low:
				var mid := minf(h, inner.size.y * 0.75) - low
				draw_rect(Rect2(x, bottom - low - mid, bar_w, mid), look[0].lerp(look[1], 0.5))
				if h > low + mid:
					draw_rect(Rect2(x, bottom - h, bar_w, h - low - mid), look[1])
			draw_rect(Rect2(x, bottom - h - 8, bar_w, 4), Color(1, 1, 1, 0.9))
	if _hit_flash > 0.0:
		draw_rect(inner, Color(1, 1, 1, 0.55 * _hit_flash))
	draw_texture(_tex.stage_led_mask, LED_POS)


func _led_text() -> String:
	match _section:
		"idle":
			return "READY"
		"count":
			return ["3", "2", "1", "GO"][clampi(floori(_beat), 0, 3)]
		"end":
			return "CLEAR!"
	return ""


func _draw_led_text(inner: Rect2, text: String, look: Array) -> void:
	var px := 24.0 if text.length() <= 2 else 16.0
	var width := text.length() * 6.0 * px - px
	var origin := inner.get_center() - Vector2(width, 7.0 * px) * 0.5
	var col: Color = look[0].lerp(Color.WHITE, 0.35 * _kick)
	if _section == "idle":
		col = Color(look[0], 0.45 + 0.35 * (0.5 + 0.5 * sin(_t * 3.0)))
	for k in text.length():
		var rows: Array = FONT.get(text[k], FONT["O"])
		for r in rows.size():
			var row: String = rows[r]
			for c in row.length():
				if row[c] == "1":
					draw_rect(Rect2(origin + Vector2((k * 6 + c) * px, r * px), Vector2(px, px)), col)


## 路过的布景：护栏（连续）、灯杆（每 320px）、音箱塔（每 1280px），随 scroll_x 向左流动。
## Boss 身后（右侧 300px）不画，避免同色系淹没 Boss。
func _draw_passing_props(look: Array, energy: float) -> void:
	var left := float(arena.config.stage_rect[0])
	var right: float = arena.boss.position.x - 150.0
	# 护栏：两根横杆 + 立柱
	var rail := Color("1c1530")
	draw_rect(Rect2(left, _floor_y - 34, right - left, 3), rail)
	draw_rect(Rect2(left, _floor_y - 18, right - left, 3), rail)
	draw_rect(Rect2(left, _floor_y - 35, right - left, 1), Color(look[0], 0.35))
	var x := left - fposmod(scroll_x, 48.0)
	while x < right:
		if x >= left:
			draw_rect(Rect2(x, _floor_y - 36, 3, 36), Color("150f24"))
		x += 48.0
	# 音箱塔
	x = left - fposmod(scroll_x + 400.0, 1280.0)
	while x < right:
		if x + 112.0 > left and x + 112.0 < right:
			_draw_speaker(Vector2(x, _floor_y - 224.0), energy)
		x += 1280.0
	# 灯杆：细杆 + 顶部随拍灯头
	x = left - fposmod(scroll_x, 320.0) + 160.0
	while x < right:
		if x > left:
			draw_rect(Rect2(x - 2, _floor_y - 300, 4, 300), Color("120c1f"))
			draw_rect(Rect2(x - 8, _floor_y - 306, 16, 7), Color("2a2344"))
			draw_rect(Rect2(x - 6, _floor_y - 300, 12, 2), Color(look[1], 0.4 + 0.6 * _kick))
		x += 320.0


## 跑道层（在地形之前）：滚动的舞台地面 + 上下两层之间的隔板走道。
func _draw_runway() -> void:
	if arena == null:
		return
	var look := _look()
	var left := float(arena.config.stage_rect[0])
	var right := left + float(arena.config.stage_rect[2])
	# 地面：深色钢板 + 顶边灯线 + 滚动接缝 + 向左流动的虚线灯
	runway.draw_rect(Rect2(left, _floor_y, right - left, 32), Color("120b20"))
	runway.draw_rect(Rect2(left, _floor_y, right - left, 2), Color(look[0], 0.6 + 0.4 * _kick))
	var x := left - fposmod(scroll_x, 64.0)
	while x < right:
		if x >= left:
			runway.draw_rect(Rect2(x, _floor_y + 2, 2, 30), Color("07040d"))
			runway.draw_rect(Rect2(x + 2, _floor_y + 2, 1, 30), Color("241a3a"))
		x += 64.0
	x = left - fposmod(scroll_x, 128.0)
	while x < right:
		if x >= left:
			runway.draw_rect(Rect2(x + 40, _floor_y + 14, 36, 3), Color(look[1], 0.3 + 0.4 * _kick))
		x += 128.0
	if _divider_alpha <= 0.0:
		return
	# 隔板：上层站位面（上层音符中心下方 LANE_FOOT），从舞台左缘延伸到 Boss 前
	var a := _divider_alpha
	var top := float(arena.config.lane_air_y) + LANE_FOOT
	var end_x: float = arena.boss.position.x - 140.0
	runway.draw_rect(Rect2(left, top, end_x - left, 8), Color(Color("2a2344"), a))
	runway.draw_rect(Rect2(left, top, end_x - left, 2), Color(look[0].lerp(Color.WHITE, 0.3 * _kick), a))
	runway.draw_rect(Rect2(left, top + 8, end_x - left, 1), Color(Color("07040d"), a))
	runway.draw_rect(Rect2(left, top + 20, end_x - left, 2), Color(Color("3a3350"), a * 0.8))
	x = left - fposmod(scroll_x, 32.0)
	var flip := posmod(floori(scroll_x / 32.0), 2) == 1
	while x < end_x:
		var x0 := maxf(x, left)
		var x1 := minf(x + 32.0, end_x)
		if x1 > x0:
			var y0 := top + 9.0 if not flip else top + 20.0
			var y1 := top + 20.0 if not flip else top + 9.0
			runway.draw_line(Vector2(x0, y0), Vector2(x1, y1), Color(Color("3a3350"), a * 0.8), 2.0)
		flip = not flip
		x += 32.0
	# 隔板边沿的追逐灯：每 64px 一盏，随拍点亮
	x = left - fposmod(scroll_x, 64.0) + 32.0
	while x < end_x:
		if x > left:
			runway.draw_rect(Rect2(x - 3, top + 3, 6, 3), Color(look[1], a * (0.35 + 0.65 * _kick)))
		x += 64.0
	runway.draw_rect(Rect2(end_x - 6, top - 6, 6, 28), Color(Color("3a3350"), a))


func _draw_speaker(top_left: Vector2, energy: float) -> void:
	draw_texture(_tex.stage_speaker, top_left)
	var woofer: Texture2D = _tex.stage_woofer
	var s := 1.0 + 0.12 * _kick * energy
	for cy in [62.0, 174.0]:
		draw_set_transform(top_left + Vector2(56, cy), 0.0, Vector2(s, s))
		draw_texture(woofer, -woofer.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ 叠加层（ADD）
func _draw_glow() -> void:
	if arena == null:
		return
	var look := _look()
	var energy := _energy()
	var drop := _section in ["drop", "finale"]
	var strobe := _kick
	if _section == "build":   # 蓄力段频闪逐小节加密：1 → 1/2 → 1/4 → 1/8 拍
		var sub: float = [1.0, 0.5, 0.25, 0.125][clampi(floori((_beat - 96.0) / 4.0), 0, 3)]
		strobe = exp(-fposmod(_beat, sub) / sub * 6.0)
	# 追光灯束
	var speed: float = {"idle": 0.12, "count": 0.2, "intro": 0.2, "verse": 0.3, "build": 0.45, "drop": 0.55, "finale": 0.7, "end": 0.3}[_section]
	var amp := 0.18 + 0.32 * energy
	for i in SPOT_XS.size():
		var origin := Vector2(SPOT_XS[i], SPOT_Y + 20)
		var angle := sin(_beat * PI * speed + i * 0.8) * amp * (1.0 if i % 2 == 0 else -1.0)
		var swap := drop and posmod(floori(_beat / 4.0), 2) == 1
		var col: Color = look[(i + (1 if swap else 0)) % 2]
		var alpha := 0.07 + 0.16 * strobe * energy
		_beam(origin, angle, 0.085, Color(col, alpha))
		_beam(origin, angle, 0.03, Color(col.lerp(Color.WHITE, 0.5), alpha * 0.9))
		var hit_x := origin.x + tan(angle) * (_floor_y - origin.y)
		_ellipse(Vector2(hit_x, _floor_y - 4), Vector2(58, 9), Color(col, alpha * 1.6))
		glow.draw_circle(origin + Vector2(0, -2), 7.0, Color(col, 0.35 + 0.5 * strobe))
	# Boss 专属顶光：白色主光柱 + 脚下光斑，保证 Boss 在任何段落都从背景里跳出来
	var boss_pos: Vector2 = arena.boss.position
	var key := Color(look[0].lerp(Color.WHITE, 0.7), 0.1 + 0.08 * _kick)
	var top := Vector2(boss_pos.x, SPOT_Y + 8)
	glow.draw_polygon(PackedVector2Array([top + Vector2(-18, 0), top + Vector2(18, 0),
			Vector2(boss_pos.x + 170, _floor_y), Vector2(boss_pos.x - 170, _floor_y)]),
			PackedColorArray([key, key, Color(key, key.a * 0.5), Color(key, key.a * 0.5)]))
	_ellipse(Vector2(boss_pos.x, _floor_y - 4), Vector2(170, 12), Color(key, key.a * 1.8))
	# 激光扇（drop / finale）：LED 墙两上角各 7 条，扇面随小节摆动
	if drop:
		for side in [-1.0, 1.0]:
			var src := Vector2(LED_POS.x + (0.0 if side < 0 else LED_SIZE.x), LED_POS.y + 6)
			for k in 7:
				var a: float = PI * 0.5 + side * (0.25 + k * 0.16) + sin(_beat * PI * 0.25) * 0.35 * side
				var col: Color = look[1] if k % 2 == 0 else look[0]
				glow.draw_line(src, src + Vector2(cos(a), sin(a)) * 1100.0, Color(col, 0.28 + 0.4 * _kick), 2.0)
	# Boss 喇叭冲击波：每拍一圈（drop 起每半拍）
	if _section not in ["idle", "end"]:
		var center: Vector2 = arena.boss.position + Vector2(2, -78)   # Boss 近侧低音喇叭（朝左翻转后）
		var rings := [fposmod(_beat, 1.0)]
		if drop:
			rings.append(fposmod(_beat + 0.5, 1.0))
		for p: float in rings:
			glow.draw_arc(center, 40.0 + p * 560.0, 0.0, TAU, 64, Color(look[1], (1.0 - p) * 0.3 * energy), 4.0)
	# 强拍闪光：drop 每小节首拍，finale 每拍
	var wash := 0.0
	if _section == "drop" and posmod(floori(_beat), 4) == 0:
		wash = 0.16 * _kick
	elif _section == "finale":
		wash = 0.1 * _kick
	elif _section == "build":
		wash = 0.05 * strobe * energy
	if wash > 0.0:
		var rect: Array = arena.config.stage_rect
		glow.draw_rect(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])), Color(look[0], wash))
	# 霓虹招牌辉光：同一张贴图用段落主色 ADD 叠一层（待机时跟随接触不良闪烁）
	var neon: Texture2D = _tex.stage_neon
	var neon_pos := Vector2(LED_POS.x + LED_SIZE.x * 0.5 - neon.get_width() * 0.5, LED_POS.y - 58)
	var neon_glow := 0.35 + 0.5 * _kick
	if _section == "idle":
		neon_glow = 0.0 if sin(_t * 37.0) > 0.9 or sin(_t * 5.3) > 0.97 else 0.4
	glow.draw_texture(neon, neon_pos, Color(look[0].lerp(Color("ff5aa8"), 0.5), neon_glow))
	# LED 墙辉光
	glow.draw_rect(Rect2(LED_POS - Vector2(12, 12), LED_SIZE + Vector2(24, 24)),
			Color(look[0], 0.05 + 0.08 * _kick * energy + 0.2 * _hit_flash))


func _beam(origin: Vector2, angle: float, half_width: float, col: Color) -> void:
	var length := (_floor_y - origin.y) / maxf(0.2, cos(angle)) + 40.0
	var a := origin + Vector2(sin(angle - half_width), cos(angle - half_width)) * length
	var b := origin + Vector2(sin(angle + half_width), cos(angle + half_width)) * length
	var fade := Color(col, col.a * 0.35)
	glow.draw_polygon(PackedVector2Array([origin, a, b]), PackedColorArray([col, fade, fade]))


func _ellipse(center: Vector2, radius: Vector2, col: Color) -> void:
	var points := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	glow.draw_colored_polygon(points, col)
