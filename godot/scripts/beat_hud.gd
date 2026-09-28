extends CanvasLayer
class_name BeatHud
## 05 节拍广播塔：节奏 Boss 战专用 HUD（Claude，2026-09-28 按用户要求重写 UI）。
## 双轨锁定期间替代通用 GameHud：顶部 Boss 分段血条 + 残影 + 段落/歌曲进度，左上像素心形血量与时停槽，
## 右上像素分数与准确率，中部弹跳 COMBO，判定字从对应层的判定环升起，判定环旁 W↑/S↓ 按键提示，
## 击破后弹出结算面板（评级 S/A/B/C、各判定数、最大连击、分数）。只读 BeatArena，不参与判定。

const LAYER := 8
const PX_FONT := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"0": ["01110", "10011", "10101", "10101", "10101", "11001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
	"%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
	".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
	"x": ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
	"^": ["00100", "01110", "10101", "00100", "00100", "00100", "00100"],
	"v": ["00100", "00100", "00100", "00100", "10101", "01110", "00100"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	" ": ["000", "000", "000", "000", "000", "000", "000"],
}
const HEART := ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
const RATING_LOOK := {
	"Perfect": ["PERFECT", Color("ffd84a"), Color("2a8ea8")],
	"Great": ["GREAT", Color("ff5aa8"), Color("4a1238")],
	"Hit": ["GOOD", Color("8ff8ff"), Color("16303e")],
	"Miss": ["MISS", Color("8a8aa0"), Color("1a1a24")],
}
const SECTION_COLOR := {"intro": Color("3fd8ff"), "verse": Color("b06cff"), "build": Color("ff9a3f"),
	"drop": Color("ff3f94"), "finale": Color("ffc84a")}
const INK := Color("0b0916")

var game: Node2D
var arena: Node2D
var canvas: Control
var _popups: Array[Dictionary] = []
var _lag_hp := 0.0
var _lag_delay := 0.0
var _combo_pop := 0.0
var _last_combo := 0
var _last_swing := 0
var _key_flash := {"air": 0.0, "ground": 0.0}
var _result_time := -1.0
var _t := 0.0


func setup(host: Node2D, beat_arena: Node2D) -> void:
	game = host
	arena = beat_arena
	layer = LAYER
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_hud)
	add_child(canvas)
	_lag_hp = float(arena.boss.max_hp)
	arena.rated.connect(_on_rated)
	visible = false


func _on_rated(value: String, lane: String) -> void:
	var y: float = arena.config.lane_air_y if lane == "air" else arena.config.lane_ground_y
	_popups.append({"value": value, "world": Vector2(float(arena.config.judge_x), y), "life": 0.55})
	if _popups.size() > 6:
		_popups.pop_front()


func _process(dt: float) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var frozen: bool = arena.frozen
	var step := 0.0 if frozen else dt
	_t += step
	var state: String = arena.state
	if state == "waiting" and _result_time >= 0.0:
		_result_time = -1.0
	if state in ["dying", "defeated"] and _result_time < 0.0 and arena.boss.dead:
		_result_time = 0.0
	if _result_time >= 0.0:
		var before := _result_time
		_result_time += dt
		# 结算面板期间压住通用 HUD，结束后交还并补一条出口提示
		if _result_time < 7.0:
			game.hud.visible = false
		elif before < 7.0:
			game.hud.visible = true
			game.hud.show_msg("BOSS 击破！前往右侧出口 >")
	visible = arena.rhythm_lock or (_result_time >= 0.0 and _result_time < 7.0)
	if not visible:
		_lag_hp = float(arena.boss.hp)
		return
	# 残影血条：受击后停 0.35s 再追到真实血量
	var hp := float(arena.boss.hp)
	if hp < _lag_hp:
		_lag_delay = maxf(0.0, _lag_delay - step)
		if _lag_delay <= 0.0:
			_lag_hp = maxf(hp, _lag_hp - 60.0 * step)
	else:
		_lag_hp = hp
		_lag_delay = 0.35
	if arena.combo != _last_combo:
		if arena.combo > _last_combo:
			_combo_pop = 1.0
		_last_combo = arena.combo
	_combo_pop = maxf(0.0, _combo_pop - step * 6.0)
	if arena.swing != _last_swing:
		_last_swing = arena.swing
		_key_flash[arena.player_lane] = 1.0
	for lane in _key_flash:
		_key_flash[lane] = maxf(0.0, _key_flash[lane] - step * 5.0)
	for pop: Dictionary in _popups:
		pop.life -= step
	_popups = _popups.filter(func(pop: Dictionary) -> bool: return pop.life > 0.0)
	canvas.queue_redraw()


# ------------------------------------------------------------------ 绘制
func _draw_hud() -> void:
	var size := canvas.get_viewport_rect().size
	if arena.rhythm_lock:
		_draw_boss_bar(size)
		_draw_player_panel()
		_draw_score(size)
		_draw_combo(size)
		_draw_lane_keys()
		_draw_popups()
	if _result_time >= 0.0:
		_draw_result(size)


func _section() -> String:
	var name := "intro"
	var beat: float = arena._pulse_beat
	for section: Dictionary in arena.conductor.chart.sections:
		if beat >= float(section.from_beat):
			name = String(section.name)
	return name


func _draw_boss_bar(size: Vector2) -> void:
	var w := 560.0
	var x0 := (size.x - w) * 0.5
	var y0 := 22.0
	var sec := _section()
	var sec_col: Color = SECTION_COLOR.get(sec, Color("ff3f94"))
	# 名牌
	canvas.draw_rect(Rect2(x0 - 4, y0 - 20, 226, 18), INK)
	canvas.draw_rect(Rect2(x0 - 4, y0 - 20, 4, 18), Color("ff3f94"))
	_px_text("BEAT WARDEN", Vector2(x0 + 6, y0 - 17), 2.0, Color("fff0f8"))
	var font: Font = game.hud.get_theme_font()
	canvas.draw_string(font, Vector2(x0 + 148, y0 - 5), "节拍监察官", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("c9b8ff"))
	# 段落牌 + 露核倍率
	var label := sec.to_upper()
	_px_text(label, Vector2(x0 + w - label.length() * 12.0 + 2, y0 - 17), 2.0, sec_col)
	if arena.conductor.finale_started() and fmod(_t, 0.6) < 0.4:
		_px_text("CORE x2", Vector2(x0 + w + 12, y0 + 4), 2.0, Color("8ff8ff"))
	# 血条框 + 12 段
	canvas.draw_rect(Rect2(x0 - 4, y0 - 2, w + 8, 22), INK)
	canvas.draw_rect(Rect2(x0 - 2, y0, w + 4, 18), Color("241c3c"))
	var max_hp := float(arena.boss.max_hp)
	var lag_w := w * clampf(_lag_hp / max_hp, 0.0, 1.0)
	var hp_w := w * clampf(float(arena.boss.hp) / max_hp, 0.0, 1.0)
	canvas.draw_rect(Rect2(x0, y0 + 2, lag_w, 14), Color("fff0f8"))
	canvas.draw_rect(Rect2(x0, y0 + 2, hp_w, 14), Color("c8246c"))
	canvas.draw_rect(Rect2(x0, y0 + 2, hp_w, 6), Color("ff5aa8"))
	canvas.draw_rect(Rect2(x0, y0 + 2, hp_w, 2), Color("ffb0d8"))
	for i in range(1, 12):
		canvas.draw_rect(Rect2(x0 + w * i / 12.0 - 1, y0 + 2, 2, 14), INK)
	# 歌曲进度（一遍 = loop_to_beat 拍）+ 段落刻度
	var total := float(arena.conductor.chart.loop_to_beat)
	var py := y0 + 24
	canvas.draw_rect(Rect2(x0, py, w, 3), Color("241c3c"))
	var prog := clampf(float(arena._pulse_beat) / total, 0.0, 1.0)
	canvas.draw_rect(Rect2(x0, py, w * prog, 3), sec_col)
	for section: Dictionary in arena.conductor.chart.sections:
		var sx := x0 + w * float(section.from_beat) / total
		canvas.draw_rect(Rect2(sx - 1, py - 2, 2, 7), SECTION_COLOR.get(String(section.name), Color.WHITE))


func _draw_player_panel() -> void:
	var p: Node2D = game.player
	var x0 := 20.0
	var y0 := 18.0
	canvas.draw_rect(Rect2(x0 - 6, y0 - 6, 40 + p.max_hp * 26.0, 58), Color(INK, 0.85))
	canvas.draw_rect(Rect2(x0 - 6, y0 - 6, 4, 58), Color("8ff8ff"))
	_px_text("HP", Vector2(x0 + 2, y0 + 2), 2.0, Color("8ff8ff"))
	for i in p.max_hp:
		var full: bool = i < p.hp
		var col := Color("ff5aa8") if full else Color("3a2a55")
		var flash: bool = full and p.invuln_t > 0.0 and fmod(_t, 0.15) < 0.07
		_heart(Vector2(x0 + 30 + i * 26.0, y0), 3.0, Color.WHITE if flash else col)
	# 时停槽
	var ratio: float = game.time_charge.ratio()
	var active: bool = game.time_charge.active
	var font: Font = game.hud.get_theme_font()
	canvas.draw_string(font, Vector2(x0 + 2, y0 + 42), "时停 右键", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c9b8ff"))
	canvas.draw_rect(Rect2(x0 + 70, y0 + 32, 120, 8), Color("241c3c"))
	canvas.draw_rect(Rect2(x0 + 70, y0 + 32, 120 * ratio, 8), Color("ffd84a") if active else Color("8f7aff"))


func _heart(pos: Vector2, px: float, col: Color) -> void:
	for r in HEART.size():
		for c in HEART[r].length():
			if HEART[r][c] == "1":
				canvas.draw_rect(Rect2(pos + Vector2(c, r) * px + Vector2(px, px) * 0.5, Vector2(px, px)), INK)
	for r in HEART.size():
		for c in HEART[r].length():
			if HEART[r][c] == "1":
				canvas.draw_rect(Rect2(pos + Vector2(c, r) * px, Vector2(px, px)), col)


func _draw_score(size: Vector2) -> void:
	var text := "%07d" % int(arena.score)
	var px := 4.0
	var w := text.length() * 6.0 * px
	var pos := Vector2(size.x - w - 24, 22)
	canvas.draw_rect(Rect2(pos.x - 10, 12, w + 22, 70), Color(INK, 0.85))
	canvas.draw_rect(Rect2(pos.x + w + 8, 12, 4, 70), Color("ffd84a"))
	_px_text("SCORE", Vector2(pos.x, 16), 2.0, Color("ffd84a"))
	_px_text(text, pos + Vector2(0, 12), px, Color.WHITE)
	_px_text("ACC %.1f%%" % (_accuracy() * 100.0), Vector2(pos.x, 70), 2.0, Color("c9b8ff"))


func _accuracy() -> float:
	var c: Dictionary = arena.counts
	var judged := int(c.Perfect) + int(c.Great) + int(c.Hit) + int(c.Miss)
	if judged == 0:
		return 1.0
	return (int(c.Perfect) + 0.7 * int(c.Great) + 0.4 * int(c.Hit)) / float(judged)


func _draw_combo(size: Vector2) -> void:
	if arena.combo < 2:
		return
	var text := str(arena.combo)
	var px := 8.0 + 2.0 * _combo_pop
	var w := text.length() * 6.0 * px - px
	var center := Vector2(size.x * 0.5 - 120.0, 250.0)
	_px_text("COMBO", center - Vector2(43, 34), 3.0, Color("ff5aa8"))
	_px_text(text, center - Vector2(w * 0.5, 0), px, Color.WHITE.lerp(Color("ffd84a"), _combo_pop))


func _screen(world: Vector2) -> Vector2:
	return game.get_viewport().get_canvas_transform() * world


func _draw_lane_keys() -> void:
	var judge_x := float(arena.config.judge_x)
	for lane in ["air", "ground"]:
		var y: float = arena.config.lane_air_y if lane == "air" else arena.config.lane_ground_y
		var at := _screen(Vector2(judge_x - 150.0, y))
		var on: bool = arena.player_lane == lane
		var flash: float = _key_flash[lane]
		var col := Color("8ff8ff") if lane == "air" else Color("ff5aa8")
		var alpha := 0.9 if on else 0.4
		var box := Rect2(at - Vector2(24, 16), Vector2(48, 32))
		canvas.draw_rect(box.grow(2), Color(INK, alpha))
		canvas.draw_rect(box, Color(col.lerp(Color.WHITE, flash), alpha * (0.35 + 0.65 * flash) if flash > 0.0 else alpha * 0.25))
		canvas.draw_rect(Rect2(box.position, Vector2(box.size.x, 2)), Color(col, alpha))
		_px_text("W^" if lane == "air" else "Sv", at - Vector2(11, 7), 2.0, Color(Color.WHITE, alpha))


func _draw_popups() -> void:
	for pop: Dictionary in _popups:
		var look: Array = RATING_LOOK.get(pop.value, RATING_LOOK["Hit"])
		var t: float = 1.0 - pop.life / 0.55
		var at := _screen(pop.world) + Vector2(-30, -58 - 26 * t)
		var alpha := clampf(pop.life / 0.2, 0.0, 1.0)
		var text: String = look[0]
		var px := 3.0 if text.length() > 5 else 3.5
		at.x -= text.length() * 6.0 * px * 0.5 - 30
		_px_text(text, at + Vector2(0, 2), px, Color(look[2], alpha))
		_px_text(text, at, px, Color(look[1], alpha))


func _draw_result(size: Vector2) -> void:
	var t := _result_time
	if t < 0.8:
		return   # 先让 Boss 爆炸演出播完
	var appear := clampf((t - 0.8) / 0.25, 0.0, 1.0)
	var fade := clampf((7.0 - t) / 0.5, 0.0, 1.0)
	var a := appear * fade
	var w := 560.0
	var h := 300.0
	var pos := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5 - 40 + (1.0 - appear) * 30.0)
	canvas.draw_rect(Rect2(pos - Vector2(4, 4), Vector2(w + 8, h + 8)), Color(INK, 0.92 * a))
	canvas.draw_rect(Rect2(pos, Vector2(w, h)), Color(Color("150f28"), 0.95 * a))
	canvas.draw_rect(Rect2(pos, Vector2(w, 4)), Color(Color("ff3f94"), a))
	canvas.draw_rect(Rect2(pos + Vector2(0, h - 4), Vector2(w, 4)), Color(Color("3fd8ff"), a))
	_px_text("CLEAR!", pos + Vector2(28, 24), 7.0, Color(Color("ffd84a"), a))
	var acc := _accuracy()
	var c: Dictionary = arena.counts
	var rank := "C"
	if acc >= 0.95 and int(c.Miss) == 0:
		rank = "S"
	elif acc >= 0.9:
		rank = "A"
	elif acc >= 0.75:
		rank = "B"
	var rank_col: Color = {"S": Color("ffd84a"), "A": Color("ff5aa8"), "B": Color("8ff8ff"), "C": Color("8a8aa0")}[rank]
	_px_text(rank, pos + Vector2(w - 120, 30) + Vector2(6, 6), 16.0, Color(INK, a))
	_px_text(rank, pos + Vector2(w - 120, 30), 16.0, Color(rank_col, a))
	var rows := [["PERFECT", int(c.Perfect), RATING_LOOK.Perfect[1]], ["GREAT", int(c.Great), RATING_LOOK.Great[1]],
			["GOOD", int(c.Hit), RATING_LOOK.Hit[1]], ["MISS", int(c.Miss), RATING_LOOK.Miss[1]]]
	for i in rows.size():
		var y := pos.y + 100 + i * 34.0
		_px_text(rows[i][0], Vector2(pos.x + 30, y), 3.0, Color(rows[i][2], a))
		_px_text(str(rows[i][1]), Vector2(pos.x + 200, y), 3.0, Color(Color.WHITE, a))
	_px_text("MAX COMBO", Vector2(pos.x + 300, pos.y + 168), 2.0, Color(Color("c9b8ff"), a))
	_px_text(str(arena.max_combo), Vector2(pos.x + 300, pos.y + 184), 4.0, Color(Color.WHITE, a))
	_px_text("SCORE", Vector2(pos.x + 300, pos.y + 222), 2.0, Color(Color("c9b8ff"), a))
	_px_text("%07d" % int(arena.score), Vector2(pos.x + 300, pos.y + 238), 4.0, Color(Color.WHITE, a))
	_px_text("ACC %.1f%%" % (acc * 100.0), Vector2(pos.x + 30, pos.y + h - 34), 2.0, Color(Color("c9b8ff"), a))


## 5×7 像素字（大写字母/数字/少量符号），每个"像素"是 px×px 方块，先画 1px 墨色阴影保证任何背景都可读。
func _px_text(text: String, pos: Vector2, px: float, col: Color) -> void:
	var x := pos.x
	var shadow := Color(INK, col.a)
	for pass_i in 2:
		x = pos.x
		for ch in text:
			var rows: Array = PX_FONT.get(ch, PX_FONT.get(ch.to_upper(), PX_FONT[" "]))
			for r in rows.size():
				var row: String = rows[r]
				for cc in row.length():
					if row[cc] == "1":
						var rect := Rect2(Vector2(x + cc * px, pos.y + r * px), Vector2(px, px))
						if pass_i == 0:
							canvas.draw_rect(Rect2(rect.position + Vector2(maxf(1.0, px * 0.34), maxf(1.0, px * 0.34)), rect.size), shadow)
						else:
							canvas.draw_rect(rect, col)
			x += (float(rows[0].length()) + 1.0) * px
