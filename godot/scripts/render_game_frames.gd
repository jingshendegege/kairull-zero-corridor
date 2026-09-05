extends SceneTree
## 渲染验收截图（v2 交互：右键瞄准 / 水平开火 / 换弹 / 跳跃 / Boss）。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_game_frames.gd
## 输出：user://shot_*.png

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var player: KairullPlayer = scene.player
	player.auto_input = false

	# --- 镜头 1：右键精细瞄准 + 开枪 ---
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	player.aim_override = player.position + Vector2(280, -120)
	var saw_bullet := false
	for i in range(20):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
		if i == 12:
			var b: Dictionary = player.try_shoot()
			if not b.is_empty():
				scene._on_player_fired(b)
		if scene.bullets.size() >= 1:
			saw_bullet = true
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_aim_fire")
	ok(saw_bullet, "画面中有在飞子弹")
	ok(player.state == "aim" and player.face == 1, "右键瞄准朝右", player.state)
	ok(player.aim_deg > 10.0, "精细仰角生效", str(player.aim_deg))

	# --- 镜头 2：Shift 单次闪现（中间只留彩色轨迹，终点恢复本体） ---
	player.keys = {KEY_D: true}
	player.aim_override = player.position + Vector2(-500, -300)   # 鼠标在左后上方，不应影响
	player.step(1.0 / 60)
	scene._physics_process(1.0 / 60)
	var dash_from_x: float = player.position.x
	player.keys = {KEY_D: true, KEY_SHIFT: true}
	player.step(1.0 / 60)
	scene._physics_process(1.0 / 60)
	var dash_distance: float = player.position.x - dash_from_x
	# 再走 6 帧，让落点白闪结束；截图中只剩真实本体和中间轨迹。
	for i in range(6):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_dash")
	ok(player.state == "run" and player.face == 1, "奔跑朝右不受鼠标影响", player.state)
	ok(player.aim_deg == 0.0, "奔跑仰角恒 0")
	ok(dash_distance >= 4.0 * KairullPlayer.TS, "Shift 单帧完成闪现位移", str(dash_distance))
	ok(not player.dashing() and player.get_node("Sprite").material == null,
		"截图时本体已在终点恢复原色")
	ok(player.dash_afterimage_count() >= 5, "起点与终点之间保留连续路径轨迹",
		str(player.dash_afterimage_count()))
	player.reset_to_spawn()   # 清掉残影，避免污染后续滑铲/瞄准验收图

	# --- 镜头 3：滑铲循环 ---
	player.position = Vector2(64, 19 * 32 - 0.1)
	player.vy = 0.0
	player.keys = {KEY_D: true, KEY_CTRL: true}
	for i in range(40):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_slide")
	ok(player.state == "slide_loop", "滑铲循环状态", player.state)

	# --- 镜头 4：左下精细瞄准（翻面 + 俯角） ---
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	player.position = Vector2(400, 19 * 32 - 0.1)
	player.vy = 0.0
	for i in range(20):
		player.step(1.0 / 60)
	player.aim_override = player.position + Vector2(-160, 90)
	for i in range(10):
		player.step(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_aim_down_left")
	ok(player.face == -1, "瞄准时鼠标在左翻面")
	ok(player.aim_deg < 0.0, "瞄准俯角为负", str(player.aim_deg))

	# --- 镜头 5：换弹（动画 + 进度条 HUD） ---
	player.keys = {}
	player.gun_ammo = 2
	for i in range(20):
		player.step(1.0 / 60)
	player.start_reload()
	for i in range(24):   # 0.4s：截在 0.845057s 换弹动画中段
		player.step(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_reload")
	ok(player.reloading and player.state == "gun_reload", "换弹动画中", player.state)
	ok(player.reload_t > 0.3 and player.reload_t < 0.6, "换弹倒计时进行中",
		str(player.reload_t))

	# --- 镜头 6：枪械跳跃空中 ---
	player.keys = {KEY_W: true}
	player.step(1.0 / 60)
	player.keys = {}
	for i in range(15):
		player.step(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_gun_jump")
	ok(player.state == "gun_jump_air" and not player.on_ground, "跳跃空中", player.state)

	# --- 镜头 7：Boss 对峙（Red 贴脸连击） ---
	var boss: RedBoss = scene.red_boss
	player.position = Vector2(boss.position.x - 250, 19 * 32 - 0.1)
	player.vy = 0.0
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	player.aim_override = boss.position + Vector2(0, -60)
	for i in range(70):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("shot_boss_fight")
	ok(boss.state == "chase" or boss.state == "attack1" or boss.state == "attack2",
		"Red Boss 已逼近/出手", boss.state)

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("RENDER_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
