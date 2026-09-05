extends SceneTree
## 真窗口单体承载验收：真实player.step连续上行、停站、步行进入上层连廊。
const LIFT := preload("res://scripts/freight_lift.gd")
var player: KairullPlayer
var lift: Node2D
var level: CorridorLevel
var _long_lift := false
var _render_bottom_y := 640.0

class Backdrop extends Node2D:
	var bottom_level := 640.0
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1360, 1024 if bottom_level > 640.0 else 768), Color("#0b141b"))
		for x in range(160, 1184, 32):
			draw_rect(Rect2(x, 208, 30, bottom_level - 208.0), Color("#24343e"))
			draw_line(Vector2(x + 1, 209), Vector2(x + 1, bottom_level - 2.0), Color("#344953"))
		draw_rect(Rect2(160, bottom_level, 1024, 20), Color("#3b505a"))
		draw_line(Vector2(160, bottom_level), Vector2(1184, bottom_level), Color("#a0c0c7"), 2)
		draw_rect(Rect2(608, 384, 480, 18), Color("#38505c"))
		draw_line(Vector2(608, 384), Vector2(1088, 384), Color("#aed3d7"), 2)
		for x in range(616, 1080, 26):
			draw_line(Vector2(x, 389), Vector2(x + 14, 398), Color("#68757a"), 2)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(162, 110), "FREIGHT LIFT / TWO LEVEL CONNECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color("#d5e6e4"))
		if bottom_level > 640.0:
			draw_string(font, Vector2(162, 154), "576 PX / 18 TILES / LONG VERTICAL TRANSPORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#e1be80"))
			draw_line(Vector2(466, 384), Vector2(466, bottom_level), Color("#759299"), 1.0)
			for y in range(384, int(bottom_level) + 1, 32):
				draw_line(Vector2(461, y), Vector2(472, y), Color("#759299"), 1.0)
		draw_string(font, Vector2(676, 355), "UPPER MAINTENANCE WALKWAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#8edcd0"))
		draw_string(font, Vector2(170, bottom_level + 46.0), "2.8s travel  /  1.2s station dwell  /  Time stop freezes carrier", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#9fb9bf"))


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("货梯承载外观验收必须真窗口")
		quit(1)
		return
	_long_lift = "--long-lift" in OS.get_cmdline_user_args()
	_render_bottom_y = 960.0 if _long_lift else 640.0
	# 只改独立验收窗口尺寸，生产关卡Camera/像素缩放规则不动。
	root.size = Vector2i(1360, 1024 if _long_lift else 768)
	root.content_scale_size = root.size
	var scene := Node2D.new()
	root.add_child(scene)
	var background := Backdrop.new()
	background.bottom_level = _render_bottom_y
	scene.add_child(background)
	level = CorridorLevel.new()
	var rows := PackedStringArray()
	var map_rows := 36 if _long_lift else 24
	for y in map_rows:
		var row := "#".repeat(44) if y == int(_render_bottom_y / 32.0) else ".".repeat(44)
		if y == 12:
			row = ".".repeat(19) + "#".repeat(15) + ".".repeat(10)
		rows.append(row)
	level.grid = rows
	level.map_w = 44
	level.map_h = map_rows
	level.world_w = 1408
	level.world_h = map_rows * 32
	lift = LIFT.new()
	lift.setup({"pos": [560, _render_bottom_y], "top_y": 384, "width": 96}, level)
	scene.add_child(lift)
	var db := AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json"])
	player = KairullPlayer.new()
	player.db = db
	player.level = level
	player.spawn = Vector2(560, _render_bottom_y - 0.1)
	player.auto_input = false
	player.moving_platforms = [lift]
	scene.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.on_ground = true
	player._sync_sprite()
	await _shot("bottom")
	for _index in 156:
		_tick()
		await process_frame
	await _shot("riding_up")
	for _index in 90:
		_tick()
		await process_frame
	await _shot("upper_station")
	player.keys[KEY_D] = true
	for _index in 20:
		_tick()
		await process_frame
	player.keys.clear()
	await _shot("upper_walkway")
	var valid := player.position.x > 640.0 and absf(player.position.y - 383.9) < 0.2 and player.on_ground
	print("LIFT_RENDER_POSITION ", player.position, " GROUNDED ", player.on_ground)
	player.moving_platforms.clear()
	scene.free()
	level.free()
	await process_frame
	print("FREIGHT_LIFT_RENDER_RESULT: ", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)


func _tick() -> void:
	lift.advance(1.0 / 60.0)
	lift.carry_rider(player)
	player.step(1.0 / 60.0)


func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ("user://freight_lift_long_%s.png" if _long_lift else "user://freight_lift_%s.png") % label
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
