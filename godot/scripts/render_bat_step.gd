extends SceneTree
## 首击突进虚影渲染验收：起手后立刻抓帧，原地应留攻击前姿态的彩色残影。
##   godot --path godot --script scripts/render_bat_step.gd

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
	cam.position = p.position + Vector2(0, -140)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://bat_step")
	DirAccess.make_dir_recursive_absolute(out_dir)

	p.keys = {MOUSE_BUTTON_LEFT: true}
	p._prev_keys = {}
	p.step(1.0 / 60)   # 起手：突进 + 留虚影
	p.keys = {}
	p.step(1.0 / 60)
	await process_frame
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("step.png"))
	print("STEP ghosts=", p.dash_afterimage_count(), " frame=", p.frame)

	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
