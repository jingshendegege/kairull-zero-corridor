extends SceneTree
## bat2 横挥弧光对齐验证：定格中段帧。
##   godot --path godot --script scripts/render_bat2_slash.gd

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
	cam.position = p.position + Vector2(40, -140)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://bat2_slash")
	DirAccess.make_dir_recursive_absolute(out_dir)

	p._start_bat(1)   # 直接进第二段横挥
	for i in range(6):
		p.step(1.0 / 60)
	await process_frame
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("bat2_mid.png"))
	print("BAT2 frame=", p.frame, " progress=", p._bat_progress())

	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
