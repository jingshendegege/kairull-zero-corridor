extends SceneTree
## 04 排风脊线高空索桥"冲刺 → 击杀刷新 → 再冲刺"连杀链的真实物理验收（Claude）。
## 路线内只输入按键并调用 Player.step / game._step_tactics，不改写坐标与速度。
## 跑法：godot --headless --path godot --script scripts/test_m06_parkour_chain.gd
const SESSION := preload("res://scripts/run_session.gd")
const DATA := preload("res://generated/m06_exhaust_ridge_data.gd")
const DT := 1.0 / 60.0
const DECK_ROW := 14          ## 桥面单向平台行；脚底 = row*32
const BASE_ROW := 20          ## 桥下基座地面
var game: Node2D
var player: KairullPlayer
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, "  feet=", player.position, " dash_cd=", player.dash_cooldown_t)


func place(c: int, row: int) -> void:
	player.reset_to_spawn()
	player.position = Vector2(c * 32 + 16, row * 32 - .1)
	player.on_ground = true
	player.invuln_t = 1000.0
	player.dash_cooldown_t = 0.0
	player.keys.clear()
	player._prev_keys.clear()
	for node: Node2D in game.dash_nodes:
		node.reset_transient()


func tick(keys: Dictionary) -> void:
	player.keys = keys
	player.step(DT)
	game._step_tactics(DT)


## 从当前桥段向右助跑，到边缘起跳；dash=true 时起跳后第 6 帧空中冲刺；越过 release_x 后松开方向键稳住落点。
func leap(edge_x: float, release_x: float, dash: bool) -> bool:
	var jumped := false
	var dashed := false
	var air_frames := 0
	for frame in 240:
		var keys := {}
		if player.position.x < release_x:
			keys[KEY_D] = true
		if not jumped and player.on_ground and player.position.x >= edge_x - 10.0:
			keys[KEY_W] = true
			jumped = true
		if jumped and not player.on_ground:
			air_frames += 1
			if dash and not dashed and air_frames == 6:
				keys[KEY_SHIFT] = true
				dashed = true
		tick(keys)
		if jumped and air_frames > 2 and player.on_ground:
			return true
	return false


func on_deck(x0_c: int, x1_c: int) -> bool:
	return absf(player.position.y - (DECK_ROW * 32 - .1)) < 1.0 \
			and player.position.x >= x0_c * 32 and player.position.x <= (x1_c + 1) * 32


func _run() -> void:
	SESSION.begin_run("easy")
	var boot: Node2D = load("res://scenes/m06_exhaust_ridge.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	game = boot.get_node("Game")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.action_audio_enabled = false
	game._sfx.clear()
	game.action_audio.stop_all()
	player = game.player
	player.auto_input = false

	# 1) 缺口必须冲刺：只起跳会掉到桥下基座
	place(219, DECK_ROW)
	leap(222 * 32, 99999.0, false)
	# 失手不致命：落到第二段桥下的备用台阶（row17）或基座，可直接再爬上去
	check(not on_deck(230, 235) and player.position.y > DECK_ROW * 32.0 + 32.0,
			"8 格缺口只靠普通跳上不了第二段桥（落到下方台阶/基座）")

	# 2) 起跳 + 空中冲刺落上第二段桥（松键稳住，不冲出 6 格桥面）
	place(219, DECK_ROW)
	var ok_leap := leap(222 * 32, 231 * 32, true)
	check(ok_leap and on_deck(230, 235), "起跳+空中冲刺落在第二段桥面")
	check(player.dash_cooldown_t > 0.0 or not game.dash_nodes.all(func(n: Node2D) -> bool: return n.lit),
			"刚冲刺过：冷却中，或途经冲刺节点被刷新（节点熄灭）")

	# 3) 击杀桥上敌人刷新冲刺（本关规则）
	player.dash_cooldown_t = DashRefillProbe.COOLDOWN
	var target: Node2D = null
	for enemy: Node2D in game.minions:
		var cell: Vector2i = enemy.get_meta("spawn_cell")
		if cell == Vector2i(232, 13):
			target = enemy
	check(target != null, "第二段桥上有近战守卫")
	if target != null:
		target.take_hit(player.position.x, 1)
		game._on_player_enemy_killed(target)
	check(player.dash_cooldown_t == 0.0, "击杀后冲刺冷却立即清零")

	# 4) 用刷新的冲刺跨第二个 8 格缺口到第三段桥
	var ok_leap2 := leap(236 * 32, 245 * 32, true)
	check(ok_leap2 and on_deck(244, 249), "刷新后的冲刺跨到第三段桥面")

	# 5) 备用路线：基座 → 台阶 → 桥面全靠普通跳（不计冲刺/节点）
	place(226, BASE_ROW)
	var steps_ok := true
	for target_c: int in [228, 231]:
		var target_row := 17 if target_c == 228 else DECK_ROW
		var jumped := false
		var landed := false
		for frame in 200:
			var keys := {}
			var dx: float = float(target_c) * 32.0 + 16.0 - player.position.x
			if absf(dx) > 4.0:
				keys[KEY_D if dx > 0 else KEY_A] = true
			if not jumped and player.on_ground and absf(dx) < 110.0:
				keys[KEY_W] = true
				jumped = true
			tick(keys)
			if jumped and player.on_ground and absf(player.position.y - (target_row * 32 - .1)) < 1.0:
				landed = true
				break
		steps_ok = steps_ok and landed
	check(steps_ok and player.dash_cooldown_t == 0.0, "桥下基座 → 台阶 → 桥面普通跳可达（不需冲刺）")

	await create_timer(.2).timeout
	boot.free()
	current_scene = null
	SESSION.reset_for_tests()
	await create_timer(.2).timeout
	print("M06_PARKOUR_CHAIN_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


class DashRefillProbe:
	const COOLDOWN := 1.5
