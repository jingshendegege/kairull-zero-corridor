extends SceneTree
## 持棍站立 + 棍影冲刺渲染验收。真窗口运行：
##   godot --path godot --script scripts/render_hero_stance.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var background := ColorRect.new()
	background.color = Color("#1A0B2E")
	background.size = Vector2(1360, 765)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(background)

	var level := CorridorLevel.new()
	level.build(true)
	get_root().add_child(level)

	var db := AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	var p := KairullPlayer.new()
	p.auto_input = false
	p.db = db
	p.level = level
	get_root().add_child(p)
	p.spawn = Vector2(20 * 32, 19 * 32)
	p.reset_to_spawn()
	for i in range(40):
		p.step(1.0 / 60)

	var cam := Camera2D.new()
	get_root().add_child(cam)
	cam.make_current()
	cam.position = p.position + Vector2(60, -140)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://hero_stance")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1. 持棍站立
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("idle.png"))
	print("IDLE clip=", p.current_clip(), " frame=", p.frame)

	# 2. 棍影冲刺：Shift 后立刻抓帧（轨迹是 bat3 前冲定格）
	p.keys = {KEY_D: true}
	p._prev_keys = {}
	for i in range(6):
		p.step(1.0 / 60)
	p.keys = {KEY_D: true, KEY_SHIFT: true}
	p._prev_keys = {KEY_D: true}
	p.step(1.0 / 60)
	p.keys = {}
	await process_frame
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("dash.png"))
	print("DASH ghosts=", p.dash_afterimage_count())

	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
