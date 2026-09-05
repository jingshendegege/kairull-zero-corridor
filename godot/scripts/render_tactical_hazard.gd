extends SceneTree
## 独立器械外观真窗口验收；实际关卡手感仍由主线跑图验收，不使用headless截图。
const HAZARD := preload("res://scripts/tactical_hazard.gd")
var hazards: Array = []
var heroes: Array = []
var level: CorridorLevel

class Backdrop extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1360, 768), Color("#091119"))
		for x in range(40, 1320, 32):
			draw_rect(Rect2(x, 140, 30, 224), Color("#1e2d38"))
			draw_line(Vector2(x, 142), Vector2(x, 362), Color("#2f424c"))
		draw_rect(Rect2(40, 365, 1280, 25), Color("#283b47"))
		draw_line(Vector2(40, 365), Vector2(1320, 365), Color("#a9bec4"), 2)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(42, 90), "TACTICAL SIGNALS / WARNING > COMMIT > SAFE WINDOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#e0e9e6"))
		for entry in [[50, "01  AUTO SNIPER"], [500, "02  HIGH LASER"], [945, "03  INDUSTRIAL PRESS"]]:
			draw_string(font, Vector2(entry[0], 440), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#8ed1ce"))
			draw_string(font, Vector2(50, 500), "3s tracking / 0.5s lock / 3s cooldown", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#bac9cc"))
		draw_string(font, Vector2(500, 500), "Low roll clears 54px beam", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#bac9cc"))
		draw_string(font, Vector2(945, 500), "1.1s warning / 1.35s safe", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#bac9cc"))


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("机关外观验收必须真窗口")
		quit(1)
		return
	root.size = Vector2i(1360, 768)
	root.content_scale_size = Vector2i(1360, 768)
	var scene := Node2D.new()
	root.add_child(scene)
	scene.add_child(Backdrop.new())
	level = CorridorLevel.new()
	level.grid = PackedStringArray()
	for row in 28:
		level.grid.append("#".repeat(44) if row == 24 else ".".repeat(44))
	level.map_w = 44
	level.map_h = 28
	level.world_w = 1408
	level.world_h = 896
	var db := AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json"])
	for x in [160.0, 620.0, 1020.0]:
		var hero := KairullPlayer.new()
		hero.db = db
		hero.level = level
		hero.spawn = Vector2(x, 365)
		hero.auto_input = false
		scene.add_child(hero)
		hero.set_process(false)
		hero.set_physics_process(false)
		hero._sync_sprite()
		heroes.append(hero)
	var configs := [{"type": "auto_sniper", "pos": [390, 365], "direction": [-1, 0]},
		{"type": "laser_gate", "pos": [570, 311], "floor_y": 365, "span": 160},
		{"type": "press", "pos": [1150, 177], "floor_y": 365, "width": 80}]
	for index in configs.size():
		var hazard := HAZARD.new()
		hazard.setup(configs[index], level)
		scene.add_child(hazard)
		hazard.set_armed(true)
		hazard.advance(0.016, heroes[index])
		hazard.advance(0.65, heroes[index])
		hazards.append(hazard)
	await _shot("warning")
	hazards[0].advance(2.36, heroes[0])
	hazards[1].advance(0.4, heroes[1])
	hazards[2].advance(0.5, heroes[2])
	hazards[2].advance(0.14, heroes[2])
	await _shot("active")
	hazards[0].advance(0.09, heroes[0])
	await _shot("locked_dim")
	hazards[0].deactivate_cleared()
	await _shot("cleared_disabled")
	scene.free()
	level.free()
	await process_frame
	print("TACTICAL_RENDER_RESULT: PASS")
	quit(0)


func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://tactical_hazard_%s.png" % label
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
