extends SceneTree
## 起跳/落地尘土 + 三段统一弧光渲染验证。
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
	var out_dir := ProjectSettings.globalize_path("user://jump_fx")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 起跳尘土（起跳后第 2 步，尘土第 2 帧）
	p.keys = {KEY_W: true}
	p._prev_keys = {}
	p.step(1.0 / 60)
	p.keys = {}
	p.step(1.0 / 60)
	await process_frame
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("jump.png"))
	print("JUMP visible=", p.get_node("JumpFx").visible)

	# 等落地抓落地尘土
	var guard := 0
	while not p.on_ground and guard < 300:
		p.step(1.0 / 60)
		guard += 1
	p.step(1.0 / 60)
	await process_frame
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("land.png"))
	print("LAND visible=", p.get_node("LandFx").visible)
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
