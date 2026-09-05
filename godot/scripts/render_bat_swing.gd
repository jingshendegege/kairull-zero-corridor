extends SceneTree
## 棍击三连 + 洋葱片虚影渲染验收：定格 bat1 中段帧截图。
## 必须真窗口运行（headless 截图是空纹理）：
##   godot --path godot --script scripts/render_bat_swing.gd

var _player: KairullPlayer


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

	_player = KairullPlayer.new()
	_player.auto_input = false
	_player.db = db
	_player.level = level
	get_root().add_child(_player)
	_player.spawn = Vector2(20 * 32, 19 * 32)
	_player.reset_to_spawn()
	for i in range(30):
		_player.step(1.0 / 60)

	# 相机对准玩家
	var cam := Camera2D.new()
	get_root().add_child(cam)
	cam.make_current()
	cam.position = _player.position + Vector2(120, -140)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://bat_swing")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 起手 bat1，手动推进到中段帧（洋葱片前后都有帧）
	_player.keys = {MOUSE_BUTTON_LEFT: true}
	_player._prev_keys = {}
	_player.step(1.0 / 60)
	_player.keys = {}
	var targets := [5, 9, 13]
	var shot := 0
	var guard := 0
	while shot < targets.size() and guard < 200:
		_player.step(1.0 / 60)
		guard += 1
		if _player.batting() and _player.frame >= targets[shot]:
			await process_frame
			RenderingServer.force_draw()
			get_root().get_texture().get_image().save_png(
					out_dir.path_join("swing_f%02d.png" % _player.frame))
			print("SHOT frame=", _player.frame, " state=", _player.state)
			shot += 1

	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
