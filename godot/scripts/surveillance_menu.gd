class_name SurveillanceMenu
extends Node3D
## 单台工业CRT开始菜单：四频道都在同一玻璃屏内切换，实体外框始终保留。
## 只创建一个SubViewport，不实例化Game，避免污染关卡静态状态。

signal run_requested(difficulty: String)
signal quit_requested

const SESSION := preload("res://scripts/run_session.gd")
const CRT_SHADER := preload("res://shaders/menu_crt_fault.gdshader")
const WALL_SHADER := preload("res://shaders/menu_wall_screen.gdshader")

const PAGE_START := 0
const PAGE_DIFFICULTY := 1
const PAGE_CONTROLS := 2
const PAGE_EXIT := 3
const PAGE_COUNT := 4
const SCREEN_SIZE := Vector2i(640, 360)
const START_BUTTON := Rect2(426, 282, 198, 56)
const DIFFICULTY_CONFIRM := Rect2(130, 291, 380, 42)
const CONTROLS_RETURN := Rect2(444, 326, 172, 27)
const EXIT_CONFIRM := Rect2(132, 281, 376, 47)
const CASE_FACE_SIZE := Vector2(3.82, 2.40)
const CASE_FACE_Z := 0.58

@export var suppress_external_actions := false
@export var crt_faults_enabled := true
@export_range(0.0, 1.0, 0.01) var crt_fault_strength := 0.46
@export_range(7.0, 14.0, 0.1) var crt_fault_interval_min := 7.0
@export_range(7.0, 14.0, 0.1) var crt_fault_interval_max := 14.0
@export_range(0.14, 0.28, 0.01) var crt_fault_duration_min := 0.14
@export_range(0.14, 0.28, 0.01) var crt_fault_duration_max := 0.24
@export var crt_fault_seed := 9306

var selected_page := PAGE_START
var selected_difficulty := "easy"
var selected_level := 0
var monitor_count := 0
var subviewport_count := 0
var camera_motion_distance := 0.0

var _camera: Camera3D
var _monitor_nodes: Array[Node3D] = []
var _screen_canvases: Array[Control] = []
var _screen_materials: Array[ShaderMaterial] = []
var _status_lights: Array[OmniLight3D] = []
var _led_materials: Array[StandardMaterial3D] = []
var _camera_targets: Array[Transform3D] = []
var _hovered_page := -1
var _difficulty_notice_time := 0.0
var _transition_serial := 0
var _navigation: MenuGuide
var _fault_rng := RandomNumberGenerator.new()
var _fault_wait := 9.0
var _fault_elapsed := 0.0
var _fault_duration := 0.20
var _fault_page := -1
var _fault_serial := 0
var _idle_time := 0.0
var _wall_screens: Array[ShaderMaterial] = []


class MenuGuide extends Control:
	## 独立于CRT故障的持续导航；屏幕内文字变形时也不会失去操作提示。
	## 2026-09-30 重做：左上故障风大标题（RGB 分离 + 间歇切片抖动）、霓虹斜切频道标签、右上状态芯片。
	var menu: Node3D
	var font: SystemFont
	var bold: SystemFont
	var elapsed := 0.0
	const TITLES := ["开始", "难度", "操作", "退出"]
	const CODES := ["01", "02", "03", "04"]
	const ACCENTS := [Color("#55dcd5"), Color("#e7bc78"), Color("#91d1a4"), Color("#e89196")]
	const NEON_PINK := Color("#ff3d8b")
	const NEON_CYAN := Color("#3df2ff")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
		bold = SystemFont.new()
		bold.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
		bold.font_weight = 900
		bold.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]

	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()

	func tab_rect(index: int) -> Rect2:
		var view := get_viewport_rect().size
		return Rect2(view.x * .5 - 330.0 + index * 166.0, view.y - 100.0, 154.0, 38.0)

	func tab_at(point: Vector2) -> int:
		for index in 4:
			if tab_rect(index).has_point(point):
				return index
		return -1

	func _glitch_text(at: Vector2, text: String, size: int, color: Color, use_font: Font) -> void:
		# 每 3.1 秒一次 0.12 秒的强故障：横向抖动 + 更大 RGB 分离；平时只有 1~2px 的色差。
		var phase := fmod(elapsed, 3.1)
		var hit := phase < 0.12
		var split := 5.0 if hit else 1.6 + sin(elapsed * 3.0) * 0.6
		var jitter := Vector2((sin(elapsed * 97.0) * 7.0) if hit else 0.0, 0)
		draw_string(use_font, at + jitter + Vector2(-split, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(NEON_PINK, 0.75))
		draw_string(use_font, at - jitter + Vector2(split, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(NEON_CYAN, 0.75))
		draw_string(use_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

	func _draw() -> void:
		if font == null or menu == null:
			return
		var view := get_viewport_rect().size
		var accent: Color = ACCENTS[menu.selected_page]
		# 四周暗角：把视线收拢到中央 CRT，标题和标签压在暗底上更清楚
		for i in 14:
			var a := 0.055 * (14 - i) / 14.0
			draw_rect(Rect2(0, i * 7, view.x, 7), Color(0, 0, 0, a * 2.4))
			draw_rect(Rect2(0, view.y - (i + 1) * 7, view.x, 7), Color(0, 0, 0, a * 2.0))
			draw_rect(Rect2(i * 9, 0, 9, view.y), Color(0, 0, 0, a * 1.6))
			draw_rect(Rect2(view.x - (i + 1) * 9, 0, 9, view.y), Color(0, 0, 0, a * 1.6))
		draw_rect(Rect2(20, 16, 360, 76), Color(0.01, 0.02, 0.03, 0.55))
		# 左上标题块
		draw_rect(Rect2(28, 22, 5, 64), NEON_PINK)
		_glitch_text(Vector2(44, 62), "凯露尔", 44, Color("#f2f7f5"), bold)
		var zc := "ZERO  CORRIDOR"
		draw_string(bold, Vector2(214, 50), zc, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, NEON_CYAN)
		draw_string(font, Vector2(214, 70), "零号回廊 · 监控网络接入", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#9fb3b1"))
		var line_w := 170.0 + 30.0 * sin(elapsed * 1.7)
		draw_rect(Rect2(44, 78, line_w, 2), Color(NEON_CYAN, 0.8))
		draw_rect(Rect2(44 + line_w + 6, 78, 18, 2), Color(NEON_PINK, 0.9))
		# 右上状态芯片：当前关卡 / 难度 / 生命
		var context: String = SESSION.LEVEL_NAMES[menu.selected_level] + "   " + SESSION.name_for_difficulty(menu.selected_difficulty) 			+ " · %d HP" % SESSION.health_for_difficulty(menu.selected_difficulty)
		var context_w := font.get_string_size(context, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var chip := Rect2(view.x - context_w - 74, 26, context_w + 44, 30)
		draw_rect(chip, Color("#071217d8"))
		draw_rect(chip, Color(accent, 0.7), false, 1.5)
		var blink := 1.0 if fmod(elapsed, 1.2) < 0.8 else 0.25
		draw_circle(chip.position + Vector2(15, 15), 4, Color("#ff4060", blink))
		draw_string(font, chip.position + Vector2(28, 20), context, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#dfe9e6"))
		# 底部斜切霓虹频道标签
		for index in 4:
			var rect := tab_rect(index)
			var active: bool = index == menu.selected_page
			var col: Color = ACCENTS[index]
			var slant := 12.0
			var poly := PackedVector2Array([rect.position + Vector2(slant, 0), Vector2(rect.end.x, rect.position.y),
				rect.end - Vector2(slant, 0), Vector2(rect.position.x, rect.end.y)])
			draw_colored_polygon(poly, Color(col, 0.22) if active else Color("#081015d0"))
			var outline := poly.duplicate()
			outline.append(poly[0])
			draw_polyline(outline, Color(col, 0.95) if active else Color(col, 0.28), 2.0 if active else 1.0)
			if active:
				# 选中标签：下方发光条 + 呼吸光晕
				var glow := 0.35 + 0.25 * sin(elapsed * 4.0)
				draw_rect(Rect2(rect.position.x + slant, rect.end.y + 4, rect.size.x - slant * 2, 3), Color(col, 0.9))
				draw_rect(Rect2(rect.position.x + slant, rect.end.y + 7, rect.size.x - slant * 2, 4), Color(col, glow * 0.4))
			var code_color: Color = col if active else Color("#5d7073")
			draw_string(bold, rect.position + Vector2(26, 25), CODES[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, code_color)
			draw_string(bold, rect.position + Vector2(56, 26), TITLES[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color("#f4faf8") if active else Color("#8a9c9d"))
		var hints := [
			"A/D ←→ 换频道    ↑↓ 选择关卡    ENTER 开始    鼠标点击按钮",
			"A/D 换频道    ↑↓ 循环选择三档难度    ENTER 确认并返回（不会开局）",
			"A/D 换频道    ENTER / ESC 返回开始    游戏内 Esc 暂停 / 再按原地继续",
			"A/D 换频道    ENTER 确认退出    ESC 返回开始"]
		var hint: String = hints[menu.selected_page]
		var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1 , 13).x
		draw_string(font, Vector2((view.x - hint_w) * .5, view.y - 30), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9fb1ad"))


class MonitorCanvas extends Control:
	## 唯一640×360画布保持同一资源，只更新频道内容，再贴回同一3D屏幕。
	var page := 0
	var focused := false
	var hovered := false
	var difficulty := "easy"
	var level_choice := 0
	var elapsed := 0.0
	var notice_time := 0.0
	var font: SystemFont
	var bold: SystemFont
	var previews := {}          ## 场景前缀 → 关卡实拍（assets/menu/preview_*.png，由游戏内截图生成）
	var _shown_level := -1
	var _switch_t := 9.0        ## 切换关卡后的故障过渡计时

	const INK := Color("#071116")
	const PAPER := Color("#d8f3ee")
	const MUTED := Color("#66898b")
	const CYAN := Color("#35d5d2")
	const AMBER := Color("#e4a94e")
	const RED := Color("#e15468")
	const GREEN := Color("#78d5a3")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
		bold = SystemFont.new()
		bold.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
		bold.font_weight = 900
		bold.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
		for scene: String in SESSION.LEVEL_SCENES:
			var key := scene.get_file().substr(0, 3)
			var path := "res://assets/menu/preview_%s.png" % key
			if ResourceLoader.exists(path):
				previews[key] = load(path)

	func _process(delta: float) -> void:
		elapsed += delta
		notice_time = maxf(0.0, notice_time - delta)
		if level_choice != _shown_level:
			_shown_level = level_choice
			_switch_t = 0.0
		_switch_t += delta
		queue_redraw()

	static func level_meta(index: int) -> Dictionary:
		var key: String = SESSION.LEVEL_SCENES[index].get_file().substr(0, 3)
		var table := {"m06": {"tag": "夜间屋顶 · 高空跑酷", "boss": false},
			"m07": {"tag": "节奏 BOSS · BEAT WARDEN", "boss": true},
			"m01": {"tag": "检疫设施 · 协议清剿", "boss": false},
			"m04": {"tag": "时差货运 · 时停解谜", "boss": false}}
		var meta: Dictionary = table.get(key, {"tag": "", "boss": false}).duplicate()
		meta["key"] = key
		return meta

	func _draw() -> void:
		var accent := _accent()
		draw_rect(Rect2(Vector2.ZERO, size), INK)
		_draw_camera_grid(accent)
		_draw_header(accent)
		match page:
			PAGE_START:
				_draw_start(accent)
			PAGE_DIFFICULTY:
				_draw_difficulty(accent)
			PAGE_CONTROLS:
				_draw_controls(accent)
			PAGE_EXIT:
				_draw_exit(accent)
		_draw_scanlines(accent)

	func _accent() -> Color:
		match page:
			PAGE_DIFFICULTY:
				return AMBER
			PAGE_CONTROLS:
				return GREEN
			PAGE_EXIT:
				return RED
			_:
				return CYAN

	func _draw_camera_grid(accent: Color) -> void:
		for x in range(0, int(size.x), 40):
			draw_line(Vector2(x, 45), Vector2(x, size.y), Color(accent, 0.035), 1.0)
		for y in range(45, int(size.y), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(accent, 0.035), 1.0)
		# 日常只保留很弱扫光；明显故障由屏幕材质间歇触发，不能让菜单一直像坏信号。
		var sweep_y := 50.0 + fposmod(elapsed * 43.0 + page * 71.0, 286.0)
		draw_rect(Rect2(0, sweep_y, size.x, 4), Color(accent, 0.010))

	func _draw_header(accent: Color) -> void:
		draw_rect(Rect2(0, 0, size.x, 44), Color("#081418"))
		draw_rect(Rect2(0, 42, size.x, 2), Color(accent, 0.75 if focused else 0.3))
		for i in 6:
			var x := 330.0 + i * 9.0
			draw_colored_polygon(PackedVector2Array([Vector2(x, 42), Vector2(x + 5, 42), Vector2(x + 13, 30), Vector2(x + 8, 30)]),
				Color(accent, 0.25))
		var rec_alpha := 1.0 if fmod(elapsed, 1.0) < 0.62 else 0.28
		draw_circle(Vector2(22, 21), 6, Color(RED, rec_alpha))
		draw_circle(Vector2(22, 21), 10, Color(RED, rec_alpha * 0.18))
		_text(Vector2(36, 28), "REC", 15, PAPER, true)
		_text(Vector2(84, 27), "K-00 // ZERO CORRIDOR NET", 12, MUTED)
		_text(Vector2(400, 27), "CH %02d/04" % (page + 1), 12, accent, true)
		var frames := int(fposmod(elapsed * 24.0, 24.0))
		var seconds := int(elapsed) % 60
		var minutes := (int(elapsed) / 60) % 60
		var code := "23:%02d:%02d:%02d" % [47 + minutes, seconds, frames]
		_text(Vector2(506, 27), code, 13, accent, true)

	func _draw_start(accent: Color) -> void:
		# 左：所选关卡的实拍监控画面（慢摇镜 + 切换故障）；右：纵向关卡卡片 + 开始按钮。
		var meta := level_meta(level_choice)
		var boss: bool = meta.boss
		var feed_accent := RED if boss else accent
		var feed := Rect2(16, 54, 400, 225)
		draw_rect(feed.grow(2), Color(feed_accent, 0.55))
		draw_rect(feed, Color("#02080a"))
		var tex: Texture2D = previews.get(meta.key)
		if tex != null:
			var zoom := 1.14
			var src_size := Vector2(tex.get_size()) / zoom
			var span := Vector2(tex.get_size()) - src_size
			var src := Rect2(Vector2(span.x * (0.5 + 0.5 * sin(elapsed * 0.16)), span.y * (0.5 + 0.5 * sin(elapsed * 0.11))), src_size)
			if _switch_t < 0.35:
				# 切换关卡：画面切成横条错位 + 红青分离 + 雪花，0.35 秒内收敛
				var k := 1.0 - _switch_t / 0.35
				var strips := 9
				for i in strips:
					var h := feed.size.y / strips
					var off := sin(i * 12.9 + elapsed * 60.0) * 26.0 * k
					var dst := Rect2(feed.position.x, feed.position.y + i * h, feed.size.x, h)
					var sub := Rect2(src.position + Vector2(off, i * src.size.y / strips), Vector2(src.size.x, src.size.y / strips))
					draw_texture_rect_region(tex, dst, sub, Color(1, 1, 1, 1.0 - k * 0.3))
					draw_texture_rect_region(tex, Rect2(dst.position + Vector2(6 * k, 0), dst.size), sub, Color(1, 0.2, 0.3, 0.35 * k))
					draw_texture_rect_region(tex, Rect2(dst.position - Vector2(6 * k, 0), dst.size), sub, Color(0.2, 0.9, 1, 0.35 * k))
				for n in int(90 * k):
					var nx := fposmod(sin(n * 91.7 + elapsed * 40.0) * 999.0, feed.size.x - 6)
					var ny := fposmod(cos(n * 47.3 + elapsed * 33.0) * 999.0, feed.size.y - 3)
					draw_rect(Rect2(feed.position + Vector2(nx, ny), Vector2(6, 2)), Color(1, 1, 1, 0.5 * k))
			else:
				draw_texture_rect_region(tex, feed, src)
		# 监控调色：整体偏冷 + 暗角
		draw_rect(feed, Color(feed_accent, 0.07))
		for i in 8:
			var a := 0.07 * (8 - i) / 8.0
			draw_rect(Rect2(feed.position.x, feed.position.y + i * 3, feed.size.x, 3), Color(0, 0, 0, a * 3))
			draw_rect(Rect2(feed.position.x + i * 3, feed.position.y, 3, feed.size.y), Color(0, 0, 0, a * 2))
			draw_rect(Rect2(feed.end.x - (i + 1) * 3, feed.position.y, 3, feed.size.y), Color(0, 0, 0, a * 2))
		# 底部信息带：大号关卡编号 + 名称 + 标签
		var band := Rect2(feed.position.x, feed.end.y - 62, feed.size.x, 62)
		for i in 12:
			draw_rect(Rect2(band.position.x, band.position.y + i * 5.2, band.size.x, 5.2), Color(0.0, 0.02, 0.03, 0.06 + i * 0.055))
		var title: String = SESSION.LEVEL_NAMES[level_choice]
		_text(band.position + Vector2(14, 46), title.substr(0, 2), 36, feed_accent, true)
		_text(band.position + Vector2(68, 31), title.substr(3), 21, PAPER, true)
		_text(band.position + Vector2(69, 51), String(meta.tag), 12, Color(PAPER, 0.75))
		# 取景框：四角括号 + 中央准星 + 录制信息
		var c := 16.0
		for corner: Vector2 in [feed.position + Vector2(8, 8), Vector2(feed.end.x - 8, feed.position.y + 8),
				Vector2(feed.position.x + 8, feed.end.y - 8), feed.end - Vector2(8, 8)]:
			var sx := 1.0 if corner.x < feed.get_center().x else -1.0
			var sy := 1.0 if corner.y < feed.get_center().y else -1.0
			draw_line(corner, corner + Vector2(c * sx, 0), Color(PAPER, 0.8), 2)
			draw_line(corner, corner + Vector2(0, c * sy), Color(PAPER, 0.8), 2)
		var mid := feed.get_center() + Vector2(0, -20)
		draw_arc(mid, 13, 0, TAU, 24, Color(PAPER, 0.28), 1)
		for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(mid + dir * 8, mid + dir * 19, Color(PAPER, 0.35), 1)
		var live := 1.0 if fmod(elapsed, 1.0) < 0.6 else 0.3
		draw_circle(feed.position + Vector2(24, 25), 4, Color(RED, live))
		_text(feed.position + Vector2(34, 30), "CAM-%02d  LIVE" % (level_choice + 1), 12, PAPER, true)
		_text(Vector2(feed.end.x - 70, feed.position.y + 30), "SIG %d%%" % (82 + int(6 * sin(elapsed * 2.1))), 12, feed_accent, true)
		if boss:
			# Boss 关：危险斜纹条滚动闪烁
			var warn := 0.55 + 0.45 * sin(elapsed * 6.0)
			var strip := Rect2(feed.position.x, feed.position.y + 42, feed.size.x, 18)
			draw_rect(strip, Color(0.3, 0.0, 0.03, 0.7 * warn))
			for i in 30:
				var x := strip.position.x + i * 14.0 + fposmod(elapsed * 30.0, 14.0) - 14.0
				if x > strip.position.x - 2 and x < strip.end.x - 12:
					draw_colored_polygon(PackedVector2Array([Vector2(x, strip.end.y), Vector2(x + 6, strip.end.y),
						Vector2(x + 12, strip.position.y), Vector2(x + 6, strip.position.y)]), Color(RED, 0.55 * warn))
			_text(Vector2(feed.get_center().x - 64, strip.end.y - 3), "WARNING · BOSS", 13, Color(1, 0.92, 0.92, warn), true)
		# 右：关卡卡片
		for index in SESSION.LEVEL_SCENES.size():
			var card := SurveillanceMenu.level_card_rect(index)
			var chosen := index == level_choice
			var card_meta := level_meta(index)
			var col: Color = RED if card_meta.boss else accent
			var level_name: String = SESSION.LEVEL_NAMES[index]
			if chosen:
				draw_rect(card, Color(col, 0.20))
				draw_rect(card, Color(col, 0.95), false, 2)
				draw_rect(Rect2(card.position, Vector2(5, card.size.y)), col)
				var sweep := fposmod(elapsed * 160.0, card.size.x + 60.0) - 30.0
				if sweep > 0 and sweep < card.size.x - 12:
					draw_rect(Rect2(card.position.x + sweep, card.position.y + 1, 10, card.size.y - 2), Color(1, 1, 1, 0.07))
				_text(Vector2(card.end.x - 20, card.position.y + card.size.y * 0.5 + 5), "◀", 12, col)
			else:
				draw_rect(card, Color("#08161b"))
				draw_rect(card, Color(col, 0.28), false, 1)
			_text(card.position + Vector2(13, card.size.y * 0.5 + 9), level_name.substr(0, 2), 22, col if chosen else Color(col, 0.45), true)
			_text(card.position + Vector2(48, card.size.y * 0.5 - 2), level_name.substr(3), 15, PAPER if chosen else MUTED, chosen)
			_text(card.position + Vector2(49, card.size.y * 0.5 + 13), String(card_meta.tag).get_slice(" · ", 0), 10,
				Color(col, 0.85) if chosen else Color(MUTED, 0.7))
		# 开始按钮：扫光 + 呼吸描边
		var button := START_BUTTON
		var pulse := 0.6 + 0.4 * sin(elapsed * 3.4)
		draw_rect(button, Color(accent, 0.30 if focused else 0.12))
		draw_rect(button.grow(3), Color(accent, 0.25 * pulse), false, 2)
		draw_rect(button, Color(accent, 0.95), false, 2)
		var shine := fposmod(elapsed * 220.0, button.size.x + 120.0) - 60.0
		if shine > 12 and shine < button.size.x - 20:
			draw_colored_polygon(PackedVector2Array([button.position + Vector2(shine, 0), button.position + Vector2(shine + 20, 0),
				button.position + Vector2(shine + 8, button.size.y), button.position + Vector2(shine - 12, button.size.y)]),
				Color(1, 1, 1, 0.14))
		_text(button.position + Vector2(22, 35), "▶ 开始行动", 20, PAPER, true)
		_text(button.position + Vector2(140, 35), "ENTER", 11, accent, true)
		# 左下：生存协议芯片 + 滚动字幕
		var chip := Rect2(16, 290, 400, 24)
		draw_rect(chip, Color("#0a1a20"))
		var diff_col: Color = {"easy": GREEN, "hard": AMBER, "zero": RED}.get(difficulty, accent)
		draw_rect(Rect2(chip.position, Vector2(4, chip.size.y)), diff_col)
		_text(chip.position + Vector2(14, 17), "生存协议", 12, MUTED)
		_text(chip.position + Vector2(76, 17), SESSION.name_for_difficulty(difficulty), 13, diff_col, true)
		for i in SESSION.health_for_difficulty(difficulty):
			draw_rect(Rect2(chip.position.x + 136 + i * 14, chip.position.y + 7, 10, 10), diff_col)
		_text(Vector2(chip.end.x - 128, chip.position.y + 17), "↑↓ 选关  ·  ←→ 换频道", 11, MUTED)
		var ticker := "   //  时间操控已授权  //  球棒近战协议  //  排风脊线夜间封锁  //  BEAT WARDEN 占领广播塔  //  回廊信号不稳定  "
		var ticker_w := font.get_string_size(ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tx := 16.0 - fposmod(elapsed * 38.0, ticker_w)
		var done := false
		for _loop in 3:
			for ch in ticker:
				var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				if tx >= 16.0 and tx + w <= 416.0:
					draw_string(font, Vector2(tx, 338), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(accent, 0.8))
				tx += w
				if tx > 416.0:
					done = true
					break
			if done:
				break
		draw_line(Vector2(16, 322), Vector2(416, 322), Color(accent, 0.25), 1)
		draw_line(Vector2(16, 345), Vector2(416, 345), Color(accent, 0.25), 1)

	func _draw_difficulty(accent: Color) -> void:
		_text(Vector2(30, 76), "生存协议 / DIFFICULTY", 20, PAPER)
		_text(Vector2(30, 98), "上下键或点击选择；确认难度不会直接开局", 12, MUTED)
		var details := ["5格生命，容错宽松", "3格生命，稳扎稳打", "1格生命，一击倒下"]
		var colors := [GREEN, AMBER, RED]
		for index in SESSION.DIFFICULTIES.size():
			var mode: String = SESSION.DIFFICULTIES[index]
			_draw_difficulty_card(SurveillanceMenu.difficulty_card_rect(index), mode,
				SESSION.name_for_difficulty(mode), "生命 %02d" % SESSION.health_for_difficulty(mode),
				details[index], colors[index])
		var locked := "已确认 · 返回开始屏" if notice_time > 0.0 else "确认难度并返回 / ENTER"
		draw_rect(DIFFICULTY_CONFIRM, Color(accent, .10))
		draw_rect(DIFFICULTY_CONFIRM, Color(accent, .66), false, 2)
		var width := font.get_string_size(locked, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_text(Vector2(DIFFICULTY_CONFIRM.get_center().x - width * .5, 318), locked, 15, PAPER)
		_text(Vector2(30, 344), "当前选择：%s / %d HP" % [SESSION.name_for_difficulty(difficulty),
			SESSION.health_for_difficulty(difficulty)], 13, PAPER)

	func _draw_difficulty_card(rect: Rect2, mode: String, title: String,
			hp: String, detail: String, color: Color) -> void:
		var selected := difficulty == mode
		draw_rect(rect, Color(color, 0.14) if selected else Color("#0a171c"))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 26)), Color(color, 0.85 if selected else 0.22))
		_text(rect.position + Vector2(12, 19), mode.to_upper(), 13, INK if selected else Color(color, 0.8), true)
		draw_rect(rect, Color(color, 0.95 if selected else 0.3), false, 3 if selected else 1)
		if selected:
			draw_rect(rect.grow(4), Color(color, 0.25 + 0.15 * sin(elapsed * 4.0)), false, 2)
		_text(rect.position + Vector2(16, 62), title, 25, PAPER if selected else MUTED, true)
		var hp_count := SESSION.health_for_difficulty(mode)
		for i in 5:
			var pip := Rect2(rect.position.x + 16 + i * 20, rect.position.y + 76, 14, 14)
			draw_rect(pip, color if i < hp_count else Color(color, 0.12))
		_text(rect.position + Vector2(118, 89), hp, 12, color)
		_text(rect.position + Vector2(16, 116), detail, 11, PAPER if selected else MUTED)
		_text(rect.position + Vector2(16, 142), "▶ 已选择" if selected else "○ 待命", 12, color if selected else MUTED, selected)

	func _draw_controls(accent: Color) -> void:
		_text(Vector2(30, 76), "操作归档 / CONTROL TAPE", 20, PAPER)
		_text(Vector2(30, 99), "纯球棒近战协议 · 无枪械 · 无滑铲", 12, accent)
		var rows := [
			["A / D", "移动"], ["W", "跳跃"], ["左键", "挥棒 / 击飞货箱"],
			["CTRL", "翻滚"], ["SHIFT", "冲刺 · 1.5 秒冷却"], ["双击 S", "下穿单向平台"],
			["RMB / 右键", "时间操控"], ["R + 左键", "按住R瞄准，左键投烟"]]
		for i in range(rows.size()):
			var y := 116.0 + i * 27.0
			var row_color := CYAN if i == rows.size() - 1 else accent
			draw_rect(Rect2(32, y, 112, 22), Color(row_color, 0.14))
			draw_rect(Rect2(32, y, 112, 22), Color(row_color, 0.58), false, 2)
			_text(Vector2(42, y + 16), rows[i][0], 12, PAPER)
			_text(Vector2(158, y + 17), rows[i][1], 13,
					PAPER if i == rows.size() - 1 else MUTED)

		# 右侧改成独立时停卡，关键容量与时间域关系不能埋在普通键位说明里。
		var chrono_card := Rect2(374, 116, 238, 166)
		draw_rect(chrono_card, Color("#08161b"))
		draw_rect(chrono_card, Color(CYAN, 0.72), false, 3)
		draw_rect(Rect2(chrono_card.position + Vector2(3, 3), Vector2(232, 27)), Color(CYAN, 0.10))
		_text(Vector2(390, 137), "RMB / 右键按住", 14, PAPER)
		_text(Vector2(506, 137), "CHRONO", 11, CYAN)
		var gauge_center := Vector2(421, 210)
		draw_circle(gauge_center, 34, Color("#0b2228"))
		draw_arc(gauge_center, 31, -PI * 0.5, PI * 1.5, 48, Color(CYAN, 0.90), 4)
		draw_arc(gauge_center, 24, -PI * 0.5, PI * 0.9, 36, Color(accent, 0.42), 2)
		_text(Vector2(402, 216), "2.0s", 15, PAPER)
		_text(Vector2(470, 179), "世界动态暂停", 14, PAPER)
		_text(Vector2(470, 207), "主角速度 × 55%", 12, CYAN)
		_text(Vector2(470, 234), "完整复充 5 秒", 12, AMBER)
		_text(Vector2(470, 259), "耗尽后松开再启动", 10, MUTED)
		_text(Vector2(32, 344), "Esc 暂停 / 再按原地继续", 12, accent)
		# 短倒带后重建场景，已激活中段检查点的续行状态由正式游戏宿主恢复。
		_text(Vector2(386, 301), "倒地后 · 任意新按键短倒带", 12, PAPER)
		_text(Vector2(386, 320), "中段检查点后从检查点续行", 12, MUTED)
		draw_rect(CONTROLS_RETURN, Color(accent, .08))
		draw_rect(CONTROLS_RETURN, Color(accent, .48), false, 1)
		_text(Vector2(464, 345), "返回开始 / ESC", 12, accent)

	func _draw_exit(accent: Color) -> void:
		_text(Vector2(30, 78), "断开监控链路 / EXIT", 20, PAPER)
		var center := Vector2(320, 185)
		for radius in [96.0, 73.0, 48.0]:
			draw_arc(center, radius, 0.0, TAU, 48, Color(accent, 0.18 + radius / 500.0), 3)
		var pulse := 0.55 + sin(elapsed * 3.2) * 0.2
		draw_circle(center, 17, Color(accent, pulse))
		draw_line(center + Vector2(0, -49), center + Vector2(0, -9), PAPER, 6)
		draw_rect(EXIT_CONFIRM, Color(accent, .12))
		draw_rect(EXIT_CONFIRM, Color(accent, .72), false, 2)
		_text(Vector2(198, 310), "确认断开 / ENTER", 18, accent)
		_text(Vector2(206, 337), "ESC 返回开始监控", 12, MUTED)

	func _draw_scanlines(accent: Color) -> void:
		# 扫描线只做低透明叠色，不能切断微软雅黑的细横画。
		for y in range(0, int(size.y), 4):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.055), 1)
		for y in range(2, int(size.y), 16):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(accent, 0.009), 1)
		var border := Color(_accent(), 0.88 if focused else (0.45 if hovered else 0.18))
		draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), border, false, 3)

	func _text(at: Vector2, value: String, font_size: int, color: Color, heavy := false) -> void:
		draw_string(bold if heavy else font, at.round(), value, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, color)


func _ready() -> void:
	# 正式关卡会隐藏鼠标；从关卡返回监控室时必须主动恢复指针。
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	selected_difficulty = _normalized_difficulty(String(SESSION.difficulty))
	selected_level = clampi(SESSION.start_level, 0, SESSION.LEVEL_SCENES.size() - 1)
	_build_dark_room()
	_build_camera()
	_build_monitors()
	var guide_layer := CanvasLayer.new()
	guide_layer.name = "MenuNavigationLayer"
	guide_layer.layer = 15
	add_child(guide_layer)
	_navigation = MenuGuide.new()
	_navigation.name = "PersistentGuide"
	_navigation.menu = self
	guide_layer.add_child(_navigation)
	_fault_rng.seed = crt_fault_seed
	_fault_wait = _next_fault_interval()
	_select_page(PAGE_START, true)
	set_process_input(true)


func _process(delta: float) -> void:
	if _camera == null or _camera_targets.is_empty():
		return
	var before := _camera.global_position
	var desired := _camera_targets[selected_page]
	var weight := 1.0 - exp(-delta * 5.8)
	_camera.global_transform = _camera.global_transform.interpolate_with(desired, weight)
	camera_motion_distance += before.distance_to(_camera.global_position)
	_difficulty_notice_time = maxf(0.0, _difficulty_notice_time - delta)
	_idle_time += delta
	_camera.h_offset = sin(_idle_time * 0.37) * 0.035
	_camera.v_offset = sin(_idle_time * 0.53 + 1.2) * 0.022
	_update_focus_lighting(delta)
	_advance_crt_fault(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# 确认可能立即切场景并移走菜单；必须先消费输入，不能切完再取旧viewport。
		get_viewport().set_input_as_handled()
		_handle_keycode(event.keycode)
	elif event is InputEventMouseMotion:
		_hovered_page = _monitor_at_screen(event.position)
		_sync_canvas_state()
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move_page(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move_page(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_mouse_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_select_page(PAGE_START)


func _handle_keycode(keycode: Key) -> void:
	match keycode:
		KEY_LEFT, KEY_A:
			_move_page(-1)
		KEY_RIGHT, KEY_D:
			_move_page(1)
		KEY_UP, KEY_W:
			if selected_page == PAGE_DIFFICULTY:
				_move_difficulty(-1)
			elif selected_page == PAGE_START:
				_set_level(posmod(selected_level - 1, SESSION.LEVEL_SCENES.size()))
		KEY_DOWN, KEY_S:
			if selected_page == PAGE_DIFFICULTY:
				_move_difficulty(1)
			elif selected_page == PAGE_START:
				_set_level(posmod(selected_level + 1, SESSION.LEVEL_SCENES.size()))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_page()
		KEY_ESCAPE:
			if selected_page == PAGE_START:
				_select_page(PAGE_EXIT)
			else:
				_select_page(PAGE_START)


func _move_page(delta: int) -> void:
	_select_page(posmod(selected_page + delta, PAGE_COUNT))


func _select_page(index: int, instant := false) -> void:
	selected_page = clampi(index, 0, PAGE_COUNT - 1)
	_transition_serial += 1
	_sync_canvas_state()
	if instant and not _camera_targets.is_empty():
		_camera.global_transform = _camera_targets[selected_page]


func _activate_page() -> void:
	match selected_page:
		PAGE_START:
			_request_run()
		PAGE_DIFFICULTY:
			# 难度确认只返回开始屏，绝不在此处开始游戏。
			_difficulty_notice_time = 0.9
			for canvas: MonitorCanvas in _screen_canvases:
				canvas.notice_time = 0.9
			_select_page(PAGE_START)
		PAGE_CONTROLS:
			_select_page(PAGE_START)
		PAGE_EXIT:
			_request_quit()


func _set_difficulty(mode: String) -> void:
	selected_difficulty = _normalized_difficulty(mode)
	_sync_canvas_state()


func _move_difficulty(delta: int) -> void:
	var index: int = SESSION.DIFFICULTIES.find(selected_difficulty)
	_set_difficulty(SESSION.DIFFICULTIES[posmod(index + delta, SESSION.DIFFICULTIES.size())])


func _set_level(index: int) -> void:
	selected_level = clampi(index, 0, SESSION.LEVEL_SCENES.size() - 1)
	SESSION.start_level = selected_level
	_sync_canvas_state()


func _request_run() -> void:
	run_requested.emit(selected_difficulty)
	if suppress_external_actions:
		return
	SESSION.begin_run(selected_difficulty)
	SESSION.start_level = selected_level
	var error := get_tree().change_scene_to_file(SESSION.selected_scene())
	if error != OK:
		push_error("无法进入所选关卡：%s" % error_string(error))


func _request_quit() -> void:
	quit_requested.emit()
	# 浏览器 iframe 没有安全的“退出应用”语义；Godot Web quit 可能让宿主
	# 把游戏视为已关闭，表现为标签页突然消失。Web 端返回开始频道即可。
	if OS.has_feature("web"):
		_select_page(PAGE_START)
		return
	if not suppress_external_actions:
		get_tree().quit()


func _handle_mouse_click(screen_position: Vector2) -> void:
	if _navigation != null:
		var tab := _navigation.tab_at(screen_position)
		if tab >= 0:
			_select_page(tab)
			return
	var hit := _monitor_at_screen(screen_position)
	if hit < 0:
		return
	# 失步时画面UV与按钮原坐标短暂分离；不排队、不猜GPU噪声逆映射，忽略本台屏内鼠标。
	# 最长0.28秒后自然恢复；底部导航先处理、键盘也仍响应，避免卡住菜单。
	if _fault_page == hit:
		return
	var canvas_point := _monitor_canvas_point(hit, screen_position)
	# 点击机壳只聚焦，不透过边框激活按钮；空白屏幕也不等价于开始/退出。
	if not Rect2(Vector2.ZERO, Vector2(SCREEN_SIZE)).has_point(canvas_point):
		return
	if selected_page == PAGE_DIFFICULTY:
		for index in SESSION.DIFFICULTIES.size():
			if difficulty_card_rect(index).has_point(canvas_point):
				_set_difficulty(SESSION.DIFFICULTIES[index])
				return
		if DIFFICULTY_CONFIRM.has_point(canvas_point):
			_activate_page()
	elif selected_page == PAGE_START:
		for index in SESSION.LEVEL_SCENES.size():
			if level_card_rect(index).has_point(canvas_point):
				_set_level(index)
				return
		if START_BUTTON.has_point(canvas_point):
			_activate_page()
	elif selected_page == PAGE_CONTROLS and CONTROLS_RETURN.has_point(canvas_point):
		_activate_page()
	elif selected_page == PAGE_EXIT and EXIT_CONFIRM.has_point(canvas_point):
		_activate_page()


## 关卡卡片在监控画面右侧纵向排列（2026-09-30 重做）；左侧是所选关卡的实拍监控画面。
static func level_card_rect(index: int) -> Rect2:
	var step := minf(56.0, 216.0 / maxf(1.0, SESSION.LEVEL_SCENES.size()))
	return Rect2(426, 54 + index * step, 198, step - 8.0)


static func difficulty_card_rect(index: int) -> Rect2:
	return Rect2(30 + index * 196, 118, 188, 156)


func canvas_to_screen(_page: int, point: Vector2) -> Vector2:
	# 统一真实平面正/反投影入口，测试与点击逻辑不另维护一份近似屏幕坐标。
	var screen: MeshInstance3D = _monitor_nodes[0].get_node("Screen")
	var dimensions: Vector2 = (screen.mesh as QuadMesh).size
	return _camera.unproject_position(screen.to_global(Vector3(
		(point.x / SCREEN_SIZE.x - .5) * dimensions.x,
		(.5 - point.y / SCREEN_SIZE.y) * dimensions.y, 0.0)))


func _monitor_canvas_point(_page: int, screen_position: Vector2) -> Vector2:
	# 用真实3D屏幕平面反投影，避免相机焦距/窗口大小变化后卡片点击跑偏。
	var screen: MeshInstance3D = _monitor_nodes[0].get_node("Screen")
	var inverse := screen.global_transform.affine_inverse()
	var origin := inverse * _camera.project_ray_origin(screen_position)
	var ray := inverse.basis * _camera.project_ray_normal(screen_position)
	if absf(ray.z) < 0.000001:
		return Vector2(INF, INF)
	var distance := -origin.z / ray.z
	if distance <= 0.0:
		return Vector2(INF, INF)
	var local := origin + ray * distance
	var size: Vector2 = (screen.mesh as QuadMesh).size
	return Vector2((local.x / size.x + 0.5) * SCREEN_SIZE.x, (0.5 - local.y / size.y) * SCREEN_SIZE.y)


func _monitor_at_screen(screen_position: Vector2) -> int:
	if _camera == null:
		return -1
	var best := -1
	var best_distance := INF
	for index in range(_monitor_nodes.size()):
		var monitor: Node3D = _monitor_nodes[index]
		if _camera.is_position_behind(monitor.global_position):
			continue
		var inverse := monitor.global_transform.affine_inverse()
		var ray_origin := inverse * _camera.project_ray_origin(screen_position)
		var ray_direction := inverse.basis * _camera.project_ray_normal(screen_position)
		if absf(ray_direction.z) < .000001:
			continue
		var ray_t := (CASE_FACE_Z - ray_origin.z) / ray_direction.z
		if ray_t <= 0.0:
			continue
		var local_hit := ray_origin + ray_direction * ray_t
		if absf(local_hit.x) > CASE_FACE_SIZE.x * .5 or absf(local_hit.y) > CASE_FACE_SIZE.y * .5:
			continue
		var distance := _camera.global_position.distance_squared_to(monitor.to_global(local_hit))
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _normalized_difficulty(mode: String) -> String:
	return SESSION.normalize_difficulty(mode)


func _sync_canvas_state() -> void:
	if _navigation != null:
		_navigation.queue_redraw()
	for index in range(_screen_canvases.size()):
		var canvas: MonitorCanvas = _screen_canvases[index]
		canvas.page = selected_page
		canvas.focused = true
		canvas.hovered = index == _hovered_page
		canvas.difficulty = selected_difficulty
		canvas.level_choice = selected_level
		canvas.notice_time = maxf(canvas.notice_time, _difficulty_notice_time)
		canvas.queue_redraw()


func _update_focus_lighting(delta: float) -> void:
	var weight := 1.0 - exp(-delta * 7.0)
	for index in range(_screen_materials.size()):
		var energy := 1.02
		var gain := float(_screen_materials[index].get_shader_parameter("focus_gain"))
		_screen_materials[index].set_shader_parameter("focus_gain", lerpf(gain, energy, weight))
		_status_lights[index].light_energy = lerpf(_status_lights[index].light_energy,
				0.72, weight)
		var accent: Color = MenuGuide.ACCENTS[selected_page]
		_status_lights[index].light_color = _status_lights[index].light_color.lerp(accent, weight)
		_led_materials[index].emission = _led_materials[index].emission.lerp(accent, weight)
		_led_materials[index].emission_energy_multiplier = lerpf(
				_led_materials[index].emission_energy_multiplier, 2.6, weight)


func _next_fault_interval() -> float:
	var low := clampf(crt_fault_interval_min, 7.0, 14.0)
	return _fault_rng.randf_range(low, clampf(crt_fault_interval_max, low, 14.0))


func trigger_crt_fault(_page := -1, duration := -1.0) -> void:
	# 专用验收入口同样服从开关；一次只污染一台屏幕，不修改Camera/机壳/导航。
	if not crt_faults_enabled or crt_fault_strength <= 0.0 or _screen_materials.is_empty():
		return
	_clear_crt_fault()
	_fault_page = 0 # 永远作用于唯一物理屏幕；_page只为旧调试调用保留形参兼容。
	_fault_serial += 1
	_fault_elapsed = 0.0
	var low := clampf(crt_fault_duration_min, .14, .28)
	var high := clampf(crt_fault_duration_max, low, .28)
	_fault_duration = _fault_rng.randf_range(low, high) if duration < 0.0 else clampf(duration, .14, .28)
	var material := _screen_materials[_fault_page]
	material.set_shader_parameter("fault_seed", float(_fault_serial * 11 + selected_page * 17))
	material.set_shader_parameter("fault_progress", 0.0)
	material.set_shader_parameter("fault_amount", crt_fault_strength)


func _clear_crt_fault() -> void:
	for material: ShaderMaterial in _screen_materials:
		material.set_shader_parameter("fault_amount", 0.0)
		material.set_shader_parameter("fault_progress", 0.0)
	_fault_page = -1
	_fault_elapsed = 0.0


func _advance_crt_fault(delta: float) -> void:
	if not crt_faults_enabled or crt_fault_strength <= 0.0:
		if _fault_page >= 0:
			_clear_crt_fault()
		return
	if _fault_page >= 0:
		_fault_elapsed += maxf(0.0, delta)
		if _fault_elapsed >= _fault_duration:
			_clear_crt_fault()
			_fault_wait = _next_fault_interval()
		else:
			_screen_materials[_fault_page].set_shader_parameter("fault_progress", _fault_elapsed / _fault_duration)
		return
	_fault_wait -= maxf(0.0, delta)
	if _fault_wait <= 0.0:
		trigger_crt_fault(0)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "FocusCamera"
	_camera.current = true
	_camera.fov = 40.0
	_camera.near = 0.05
	_camera.far = 40.0
	add_child(_camera)


func _build_dark_room() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "DarkRoomEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#020406")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#6a7f8c")
	environment.ambient_light_energy = 0.5
	# 2026-09-30 开始界面重做：辉光让霓虹灯条和监控墙发光；深蓝距离雾拉开纵深。
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_strength = 1.1
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.05
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.fog_enabled = true
	environment.fog_light_color = Color("#0b1a2a")
	environment.fog_density = 0.035
	world_environment.environment = environment
	add_child(world_environment)
	# 正面局部柔光照出灰绿机壳，环境仍暗；不把黑框问题伪装成全屏提曝光。
	var face_key := OmniLight3D.new()
	face_key.name = "ConsoleFaceKey"
	face_key.position = Vector3(0.0, 3.8, 4.6)
	face_key.omni_range = 15.0
	face_key.light_energy = 2.0
	face_key.light_color = Color("#d6ddd0")
	face_key.shadow_enabled = false
	add_child(face_key)

	_box(self, "BackWall", Vector3(18.0, 5.4, 0.28), Vector3(0, 2.5, -0.65), Color("#11191d"), 0.05)
	_box(self, "Floor", Vector3(19.0, 0.22, 9.0), Vector3(0, -0.14, 3.0), Color("#0b1013"), 0.7)
	_box(self, "Ceiling", Vector3(19.0, 0.18, 5.0), Vector3(0, 5.28, 1.0), Color("#080d10"), 0.8)
	# 长管、线槽与分段桌面提供暗室纵深，不靠全屏后处理伪造。
	for y in [0.46, 4.62]:
		_box(self, "WallRail", Vector3(18.0, 0.12, 0.16), Vector3(0, y, -0.39), Color("#283940"), 0.55)
	for x in [-6.9, -3.5, 0.0, 3.5, 6.9]:
		_box(self, "WallRib", Vector3(0.10, 4.0, 0.12), Vector3(x, 2.5, -0.38), Color("#223138"), 0.62)
	for x in [0.0]:
		_box(self, "ConsoleDesk", Vector3(3.68, 0.18, 1.15), Vector3(x, 0.62, 0.7), Color("#263333"), 0.72)
		_box(self, "DeskFootL", Vector3(0.16, 0.85, 0.65), Vector3(x - 1.2, 0.18, 0.55), Color("#0c1418"), 0.8)
		_box(self, "DeskFootR", Vector3(0.16, 0.85, 0.65), Vector3(x + 1.2, 0.18, 0.55), Color("#0c1418"), 0.8)
	_build_monitor_wall()
	_build_neon()
	_build_dust()
	for x in [-7.2, 0.0, 7.2]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 4.6, 2.0)
		lamp.omni_range = 5.2
		lamp.light_energy = 0.75
		lamp.light_color = Color("#7fa8aa") if x == 0.0 else Color("#b88755")
		lamp.shadow_enabled = false
		add_child(lamp)


## 监控墙：主 CRT 两侧与上方堆叠的小监视器，轮播关卡实拍 / 雪花 / 彩条；自发光进辉光。
func _build_monitor_wall() -> void:
	var feeds: Array[Texture2D] = []
	for scene: String in SESSION.LEVEL_SCENES:
		var path := "res://assets/menu/preview_%s.png" % scene.get_file().substr(0, 3)
		if ResourceLoader.exists(path):
			feeds.append(load(path))
	var tints := [Color("#3df2ff"), Color("#ff3d8b"), Color("#9dffb0"), Color("#ffb347")]
	var slots: Array[Vector3] = []
	for x in [-4.55, -3.3, 3.3, 4.55]:
		for y in [0.95, 1.95, 2.95, 3.95]:
			slots.append(Vector3(x + (0.08 if int(y) % 2 == 0 else -0.05), y, -0.28))
	for x in [-1.5, 0.0, 1.5]:
		slots.append(Vector3(x, 4.35, -0.42))
	var serial := 0
	for at in slots:
		serial += 1
		var unit := Node3D.new()
		unit.name = "WallMonitor%d" % serial
		unit.position = at
		unit.rotation_degrees.y = clampf(-at.x * 3.2, -14.0, 14.0)
		add_child(unit)
		_box(unit, "Case", Vector3(1.14, 0.86, 0.5), Vector3(0, 0, -0.1), Color("#15191d"), 0.55)
		_box(unit, "Bezel", Vector3(1.02, 0.74, 0.04), Vector3(0, 0, 0.16), Color("#07090b"), 0.8)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.92, 0.62)
		var screen := MeshInstance3D.new()
		screen.name = "WallScreen"
		screen.mesh = quad
		screen.position = Vector3(0, 0, 0.185)
		var material := ShaderMaterial.new()
		material.shader = WALL_SHADER
		var mode := 0
		if serial % 7 == 3:
			mode = 1
		elif serial % 11 == 5:
			mode = 2
		material.set_shader_parameter("mode", mode)
		material.set_shader_parameter("seed", float(serial) * 1.37)
		material.set_shader_parameter("tint", tints[serial % tints.size()])
		material.set_shader_parameter("energy", 0.95 if mode == 0 else 0.7)
		if not feeds.is_empty():
			material.set_shader_parameter("feed", feeds[serial % feeds.size()])
		screen.material_override = material
		unit.add_child(screen)
		_wall_screens.append(material)


## 霓虹灯条：桌沿粉色、墙面青色横条和两侧竖条；发光强度 > 1 触发辉光。
func _build_neon() -> void:
	var strips := [
		[Vector3(3.9, 0.04, 0.04), Vector3(0, 0.73, 1.28), Color("#ff3d8b")],
		[Vector3(18.0, 0.05, 0.05), Vector3(0, 4.88, -0.3), Color("#3df2ff")],
		[Vector3(18.0, 0.04, 0.04), Vector3(0, 0.3, -0.3), Color("#ff3d8b")],
		[Vector3(0.05, 4.2, 0.05), Vector3(-5.35, 2.6, -0.3), Color("#3df2ff")],
		[Vector3(0.05, 4.2, 0.05), Vector3(5.35, 2.6, -0.3), Color("#ff3d8b")]]
	for item in strips:
		var mesh := BoxMesh.new()
		mesh.size = item[0]
		var strip := MeshInstance3D.new()
		strip.name = "NeonStrip"
		strip.mesh = mesh
		strip.position = item[1]
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(item[2]) * 2.6
		strip.material_override = material
		add_child(strip)
	# 侧面彩色轮廓光：左粉右青，勾出 CRT 机壳边缘
	for spec in [[Vector3(-3.6, 1.6, 2.2), Color("#ff3d8b")], [Vector3(3.8, 3.6, 2.0), Color("#3df2ff")]]:
		var rim := OmniLight3D.new()
		rim.name = "NeonRim"
		rim.position = spec[0]
		rim.omni_range = 6.5
		rim.light_energy = 1.6
		rim.light_color = spec[1]
		rim.shadow_enabled = false
		add_child(rim)


## 空气中缓慢漂浮的发光尘埃。
func _build_dust() -> void:
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 45
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.position = Vector3(0, 2.4, 2.4)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(4.5, 2.4, 1.6)
	dust.direction = Vector3(0.2, 1, 0)
	dust.spread = 40.0
	dust.gravity = Vector3(0, 0.015, 0)
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.08
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.008, 0.008)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 0.95, 1.0, 0.4)
	quad.material = material
	dust.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	dust.color_ramp = fade
	add_child(dust)


func _build_monitors() -> void:
	# 四个菜单频道共用这一台实体CRT，不能靠藏掉另外三台来假装只剩一个外框。
	var monitor := Node3D.new()
	monitor.name = "ArchiveCRT"
	monitor.position = Vector3(0.0, 2.35, 0.36)
	add_child(monitor)
	_monitor_nodes.append(monitor)
	_build_monitor_case(monitor, PAGE_START, Color("#35d5d2"))
	monitor_count = _monitor_nodes.size()
	subviewport_count = _screen_canvases.size()
	var screen: MeshInstance3D = monitor.get_node("Screen")
	var screen_center := screen.global_position
	var micro_focus := [Vector3.ZERO, Vector3(.018, 0, .012), Vector3(-.012, .008, .018), Vector3(.012, -.004, .008)]
	for index in PAGE_COUNT:
		# 仅厘米级微聚焦，仍是同一机壳；不再横跨不同电视或让框体离开画面。
		var camera_position: Vector3 = screen_center + monitor.global_basis.z * 4.85 \
			+ monitor.global_basis.x * .46 + Vector3(0, .16, 0) + micro_focus[index]
		var focus_center := monitor.to_global(Vector3(0.0, -0.02, 0.42))
		var target := Transform3D(Basis.IDENTITY, camera_position).looking_at(focus_center, Vector3.UP)
		_camera_targets.append(target)


func _build_monitor_case(monitor: Node3D, page: int, accent: Color) -> void:
	_box(monitor, "Housing", Vector3(3.76, 2.34, 0.84), Vector3(0, 0, -0.12), Color("#3a4448"), 0.55)
	_box(monitor, "InnerBezel", Vector3(3.22, 1.90, 0.10), Vector3(-.22, .16, .35), Color("#111b1b"), 0.88)
	for x in [-1.84, 1.84]:
		_box(monitor, "SideGuard", Vector3(0.13, 2.38, .32), Vector3(x, 0, .41), Color("#56626a"), .5)
	_box(monitor, "TopGuard", Vector3(3.60, .13, .32), Vector3(0, 1.14, .41), Color("#6c7880"), .5)
	_box(monitor, "BottomGuard", Vector3(3.60, .25, .36), Vector3(0, -1.08, .40), Color("#2c3438"), .6)
	# 前唇凸出到z=.58，而玻璃z=.415，靠真实几何形成内凹，不能用平面黑框替代。
	for x in [-1.78, 1.34]:
		_box(monitor, "RecessSide", Vector3(.10, 1.88, .22), Vector3(x, .16, .47), Color("#30423e"), .78)
	for y in [-.75, 1.08]:
		_box(monitor, "RecessEdge", Vector3(3.08, .09, .22), Vector3(-.22, y, .47), Color("#354941"), .76)
	_box(monitor, "ControlPanel", Vector3(.37, 1.94, .25), Vector3(1.60, .08, .44), Color("#434d52"), .55)
	_knob(monitor, "TuningKnob", Vector3(1.61, .57, .65), .105, .12)
	_knob(monitor, "VolumeKnob", Vector3(1.61, .22, .65), .075, .11)
	for index in 6:
		_box(monitor, "SpeakerSlot", Vector3(.235, .032, .018), Vector3(1.60, -.17 - index * .09, .582), Color("#172722"), .9)
	_box(monitor, "ServicePlate", Vector3(.86, .14, .02), Vector3(-1.12, -1.05, .59), Color("#d1cbb3"), .82)
	var plate := Label3D.new()
	plate.name = "ChannelNameplate"
	plate.text = "K-00 / ARCHIVE"
	plate.font_size = 26
	plate.pixel_size = .0019
	plate.modulate = Color("#22322c")
	plate.outline_size = 0
	plate.no_depth_test = false
	plate.position = Vector3(-1.12, -1.05, .607)
	monitor.add_child(plate)
	for x in [-1.70, 1.71]:
		for y in [-1.10, 1.12]:
			_box(monitor, "CaseScrew", Vector3(.036, .036, .03), Vector3(x, y, .59), Color("#b1b4a3"), .4)
	_box(monitor, "Stand", Vector3(.64, .42, .57), Vector3(0, -1.35, -.02), Color("#3f514b"), .74)
	_box(monitor, "StandBase", Vector3(1.68, .13, 1.02), Vector3(0, -1.55, .10), Color("#526058"), .75)

	var viewport := SubViewport.new()
	viewport.name = "CRTViewport"
	viewport.size = SCREEN_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas := MonitorCanvas.new()
	canvas.name = "MonitorCanvas"
	canvas.page = page
	canvas.position = Vector2.ZERO
	canvas.size = Vector2(SCREEN_SIZE)
	viewport.add_child(canvas)
	_screen_canvases.append(canvas)

	var quad := QuadMesh.new()
	quad.size = Vector2(3.00, 1.6875)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.position = Vector3(-.22, .16, .415)
	var screen_material := ShaderMaterial.new()
	screen_material.shader = CRT_SHADER
	screen_material.set_shader_parameter("screen_image", viewport.get_texture())
	screen_material.set_shader_parameter("focus_gain", .62)
	screen_material.set_shader_parameter("fault_amount", 0.0)
	screen.material_override = screen_material
	monitor.add_child(screen)
	_screen_materials.append(screen_material)

	var led_material := _material(Color("#091012"), 0.3, 0.65)
	led_material.emission_enabled = true
	led_material.emission = accent
	led_material.emission_energy_multiplier = 0.45
	var led_mesh := BoxMesh.new()
	led_mesh.size = Vector3(0.20, 0.08, 0.05)
	var led := MeshInstance3D.new()
	led.name = "StatusLED"
	led.mesh = led_mesh
	led.material_override = led_material
	led.position = Vector3(1.20, -1.07, .61)
	monitor.add_child(led)
	_led_materials.append(led_material)

	var screen_light := OmniLight3D.new()
	screen_light.name = "ScreenGlow"
	screen_light.position = Vector3(0, 0, 1.05)
	screen_light.omni_range = 3.1
	screen_light.light_color = accent
	screen_light.light_energy = 0.18
	screen_light.shadow_enabled = false
	monitor.add_child(screen_light)
	_status_lights.append(screen_light)
	var case_fill := OmniLight3D.new()
	case_fill.name = "CaseFillLight"
	case_fill.position = Vector3(-1.5, 1.35, 1.55)
	case_fill.omni_range = 3.8
	case_fill.light_color = Color("#ccd7bb")
	case_fill.light_energy = .72
	case_fill.shadow_enabled = false
	monitor.add_child(case_fill)


func _knob(parent: Node3D, node_name: String, at: Vector3, radius: float, depth: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = depth
	cylinder.radial_segments = 16
	var knob := MeshInstance3D.new()
	knob.name = node_name
	knob.mesh = cylinder
	knob.position = at
	knob.rotation_degrees.x = 90
	knob.material_override = _material(Color("#293a33"), .62, .1)
	parent.add_child(knob)
	_box(parent, node_name + "Tick", Vector3(.02, radius * .72, .012), at + Vector3(0, radius * .30, depth * .5 + .009),
		Color("#d4d6bc"), .72)


func _box(parent: Node3D, node_name: String, box_size: Vector3, at: Vector3,
		color: Color, roughness: float) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = box_size
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _material(color, roughness, 0.12)
	parent.add_child(mesh)
	return mesh


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
