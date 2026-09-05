extends SceneTree
## 闪现与翻滚真窗口验收：检查慢速六格翻滚、时间型虚影与跟身冷却 UI。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_player_mobility.gd

var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var background := ColorRect.new()
	background.color = Color("#160b28")
	background.size = Vector2(1360, 765)
	get_root().add_child(background)

	var level := CorridorLevel.new()
	level.build(true)
	get_root().add_child(level)

	var db := AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = db
	player.level = level
	player.spawn = Vector2(20 * 32, 19 * 32)
	get_root().add_child(player)
	player.reset_to_spawn()
	for i in range(30):
		player.step(1.0 / 60.0)

	var camera := Camera2D.new()
	get_root().add_child(camera)
	camera.make_current()
	var out_dir := ProjectSettings.globalize_path("user://player_mobility")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 翻滚中段：放慢后约第 3 帧，应该同时看到本体和多张先后出生的虚影。
	player.keys = {KEY_D: true, KEY_CTRL: true}
	player._prev_keys = {}
	for i in range(10):
		player.step(1.0 / 60.0)
	camera.position = player.position + Vector2(0, -150)
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	get_root().get_texture().get_image().save_png(out_dir.path_join("roll_mid.png"))
	ok(player.rolling() and player.current_clip() == "hero_roll", "翻滚中段使用新图集",
			player.state)
	ok(player.dash_afterimage_count() >= 3, "翻滚中段有时间型虚影",
			str(player.dash_afterimage_count()))

	# 闪现中段：先清空旧虚影，再截取约一半路程，验证它不再是单帧瞬移。
	player.reset_to_spawn()
	for i in range(30):
		player.keys = {}
		player.step(1.0 / 60.0)
	player.keys = {KEY_D: true, KEY_SHIFT: true}
	player._prev_keys = {}
	for i in range(3):
		player.step(1.0 / 60.0)
	camera.position = player.position + Vector2(0, -150)
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	get_root().get_texture().get_image().save_png(out_dir.path_join("dash_mid.png"))
	ok(player.dashing(), "闪现中段仍在持续位移", player.state)
	ok(player.dash_afterimage_count() >= 3, "闪现中段有时间型虚影",
			str(player.dash_afterimage_count()))
	ok(player.dash_cooldown_ui_visible(), "闪现中段头顶显示 1.5 秒 CD")

	# 冲刺与残影结束后继续跑动，CD 提示仍跟随本体；冷却归零才隐藏。
	while player.dashing():
		player.keys = {KEY_D: true}
		player.step(1.0 / 60.0)
	for i in range(36):
		player.keys = {KEY_D: true}
		player.step(1.0 / 60.0)
	camera.position = player.position + Vector2(0, -150)
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	get_root().get_texture().get_image().save_png(
			out_dir.path_join("dash_cooldown_follow.png"))
	var dash_ui := player.get_node("DashCooldownUI") as Node2D
	ok(player.dash_cooldown_ui_visible() and dash_ui.get_parent() == player,
			"残影结束后 CD 提示仍跟随玩家")
	while player.dash_cooldown_t > 0.0:
		player.keys = {}
		player.step(1.0 / 60.0)
	ok(not player.dash_cooldown_ui_visible(), "1.5 秒冷却归零后 UI 隐藏")

	print("RENDER_RESULT: ", "PASS" if _fail == 0 else "FAIL")
	print("PREVIEW_DIR: ", out_dir)
	quit(0 if _fail == 0 else 1)
