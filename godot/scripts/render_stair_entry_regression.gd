extends SceneTree
## 正式三段钢梯真窗口验证：正常走梯、贴地冲刺、低空入口截停、随后不跳恢复上行。
## 只截图真实 game.tscn 渲染与 Player.step 结果，不使用 headless 空纹理。

const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/mobility-collision-20260905"
const DT := 1.0 / 60.0
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("楼梯视觉验收必须真窗口")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var player: KairullPlayer = game.player
	game.set_physics_process(false)
	player.auto_input = false
	player.hp = 999
	game.hud.visible = false
	for minion: Node2D in game.minions:
		minion.process_mode = Node.PROCESS_MODE_DISABLED
	for stair_index in game.level.stairs.size():
		var stair: Dictionary = game.level.stairs[stair_index]
		var dir := int(stair["rise_dir"])
		var entry_x := float(stair["left_c"]) * 32.0
		if dir < 0:
			entry_x += float(stair["steps"]) * 32.0
		var start := Vector2(entry_x - float(dir) * 20.0,
				float(stair["bottom_row"]) * 32.0 - 8.0)
		var move_key := KEY_D if dir > 0 else KEY_A
		_reset_player(player, start)
		for frame in range(10):
			player.step(DT)
		player.keys = {move_key: true}
		for frame in range(27):
			player.step(DT)
		_check(player._standing_on_stair(), "正常走梯需站在踏面")
		await _shot(game, "stair%d-01-walk" % (stair_index + 1))
		_reset_player(player, start)
		for frame in range(10):
			player.step(DT)
		player.keys = {move_key: true, KEY_SHIFT: true}
		for frame in range(4):
			player.step(DT)
		_check(player.dashing() and player._standing_on_stair(), "地面冲刺沿梯抬升")
		await _shot(game, "stair%d-02-ground-dash" % (stair_index + 1))
		# 复现修复前的8px低空入口状态；不把 on_ground 伪装成地面态。
		_reset_player(player, start)
		player.vy = 4.0
		player.set_state("gun_jump_air")
		player.keys = {move_key: true, KEY_SHIFT: true}
		for frame in range(7):
			player.step(DT)
		_check((player.position.x - entry_x) * float(dir) <= 0.0
				or player._standing_on_stair(), "低空冲刺不能进入梯下")
		await _shot(game, "stair%d-03-low-air-stop" % (stair_index + 1))
		player.keys = {move_key: true}
		for frame in range(30):
			player.step(DT)
		_check(player._standing_on_stair(), "截停后只按方向键恢复走梯")
		await _shot(game, "stair%d-04-resume-walk" % (stair_index + 1))
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
	boot.free()
	await process_frame
	print("STAIR_ENTRY_RENDER_RESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _reset_player(player: KairullPlayer, at: Vector2) -> void:
	player.reset_to_spawn()
	player.position = at
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = false
	player.keys.clear()
	player._prev_keys.clear()
	player.dash_cooldown_t = 0.0
	player.roll_cooldown_t = 0.0
	player.set_state("gun_idle")


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)


func _shot(game: Node2D, stem: String) -> void:
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	if game.bg != null:
		game.bg._process(0.0)
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := OUT.path_join(stem + ".png")
	var err := image.save_png(path)
	_check(err == OK, "截图保存失败：" + path)
	print("STAIR_SHOT ", path, " pos=", game.player.position,
			" grounded=", game.player.on_ground, " state=", game.player.state)
