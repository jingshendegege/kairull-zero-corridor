extends SceneTree
## M05主暂停集成：使用真实墙钟跨physics帧，不用手动step(0)冒充SceneTree暂停。
## fixture仅安排初始搬运/抛投/狙击状态和前段已清，生产暂停、续行、BGM均走正式接线。
const SESSION := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/m05_vertical_freight.tscn"
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/pause-menu-20260906"
var game: Node2D
var boot: Node2D
var lift: Node2D
var cargo: PropBatCargo
var probe: AlwaysProbe
var passed := 0
var failed := 0
var completed := 0
var log_lines: Array[String] = []

class AlwaysProbe extends Node:
	var ticks := 0
	var physics_ticks := 0
	func _process(_dt: float) -> void:
		ticks += 1
	func _physics_process(_dt: float) -> void:
		physics_ticks += 1


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	var line := ("PASS " if value else "FAIL ") + label
	log_lines.append(line)
	print(line)


func _right_button(held: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = held
	event.position = Vector2(680, 382)
	Input.parse_input_event(event)


func _place(at: Vector2) -> void:
	game.player.position = at
	game.player.vx = 0.0
	game.player.vy = 0.0
	game.player.on_ground = true
	game.player.keys.clear()
	game.player._prev_keys.clear()
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	game.cam.reset_smoothing()
	game.cam.force_update_scroll()


func _snapshot() -> Dictionary:
	var lifts: Array = []
	for item: Node2D in game.moving_lifts:
		lifts.append([item.position, item.state, item.phase_time, item._clock, item.delta_y])
	var hazards: Array = []
	for item: Node2D in game.tactical_hazards:
		hazards.append([item.position, item.state, item.phase_time, item.armed, item.shot_count, item.aim_direction])
	var clouds: Array = []
	for cloud: Dictionary in game.smoke_tactics.clouds:
		clouds.append([cloud.id, cloud.position, cloud.age])
	var enemies: Array = []
	for enemy: Node2D in game.minions:
		enemies.append([enemy.position, enemy.state, enemy.frame, enemy.dead])
	var player: KairullPlayer = game.player
	return {"identity": [boot.get_instance_id(), current_scene.get_instance_id(), current_scene.scene_file_path, SESSION.attempt],
		"checkpoint": SESSION.checkpoint.duplicate(true),
		"player": [player.position, player.vx, player.vy, player.hp, player.state, player.frame,
			player.t, player.dash_cooldown_t, player.roll_cooldown_t, player.invuln_t, player._death_elapsed],
		"charge": [game.time_charge.active, game.time_charge.energy, game.time_charge.recovery_delay,
			game.time_charge.lockout, game.time_charge.require_release, player.time_focus_active(), game._temporal_paused],
		"phase": [game.time_phase, game._death_elapsed, game._rewind_elapsed, game.rewind_progress,
			game.glitch_progress, game._run_elapsed, game._checkpoint_index, game.level_cleared],
		"lifts": lifts, "hazards": hazards, "clouds": clouds,
		"grenades": game.smoke_tactics.grenades.duplicate(true),
		"cargo": [cargo.position, cargo.velocity, cargo.flight_time, cargo.flying, cargo.dead, cargo._flash],
		"bullets": game.enemy_bullets.duplicate(true), "enemies": enemies,
		"architecture": game.quarantine_architecture._phase}


func _music_identity() -> Array:
	var music: AudioStreamPlayer = game.music
	return [music.get_instance_id(), music.stream.get_instance_id(),
		music.get_stream_playback().get_instance_id() if music.has_stream_playback() else 0,
		music.pitch_scale, music.volume_db]


func _pause_wall_clock(label: String, release_right := false) -> Dictionary:
	var before := _snapshot()
	var music_identity := _music_identity()
	var music_time: float = game.music.get_playback_position()
	var ticks_before := probe.ticks
	var physics_before := probe.physics_ticks
	var mode_before := probe.process_mode
	game.pause_controller.pause_game()
	check(game.pause_controller.active and paused, label + "进入真实SceneTree.paused")
	check(game.pause_controller.process_mode == Node.PROCESS_MODE_ALWAYS \
		and game.pause_controller.ui is CanvasLayer \
		and game.pause_controller.ui.process_mode == Node.PROCESS_MODE_ALWAYS,
		label + "Controller与暂停UI保持ALWAYS")
	check(probe.process_mode == Node.PROCESS_MODE_DISABLED, label + "原ALWAYS世界探针临时DISABLED")
	check(game.music.stream_paused, label + "原BGM使用stream_paused而不是stop")
	if release_right:
		_right_button(false) # 暂停期间松开真实Input状态，不能让恢复后留下幽灵按住。
	var started := Time.get_ticks_usec()
	var engine_physics_before := Engine.get_physics_frames()
	# 初始fixture构造可能让当前帧delta较大；只等一次Timer可能把构造之前的dt也算进去。
	# 用独立墙钟截止反复await ALWAYS timer，保证真的在暂停中跨过220ms，不手工step世界。
	while Time.get_ticks_usec() - started < 220000:
		var remaining := float(220000 - (Time.get_ticks_usec() - started)) / 1000000.0
		await create_timer(clampf(remaining, .01, .05), true).timeout
	var elapsed_us := Time.get_ticks_usec() - started
	var physics_frames_elapsed := Engine.get_physics_frames() - engine_physics_before
	var timing_line := "%s wall=%.3fms physics_frames=%d" % [label, elapsed_us / 1000.0, physics_frames_elapsed]
	log_lines.append(timing_line)
	print("PAUSE_WALL_TIMING ", timing_line)
	check(elapsed_us >= 190000 and physics_frames_elapsed > 0,
		label + "真实墙钟跨过至少190ms及physics帧")
	var after := _snapshot()
	for key: String in before:
		check(before[key] == after[key], label + "冻结 " + key)
	check(probe.ticks == ticks_before and probe.physics_ticks == physics_before,
		label + "ALWAYS探针真实process/physics均未漏走")
	check(_music_identity() == music_identity, label + "BGM播放器/音轨/Playback指针与音量音高不变")
	check(absf(game.music.get_playback_position() - music_time) <= .035,
		label + "暂停BGM进度不前进（仅容忍音频缓冲误差）")
	game.pause_controller.resume_game()
	check(not game.pause_controller.active and not paused, label + "恢复不重建场景")
	check(probe.process_mode == mode_before, label + "恢复原ALWAYS模式而非一律INHERIT")
	check(not game.music.stream_paused and _music_identity() == music_identity,
		label + "同一Playback解除暂停，无play/seek/换音轨")
	before["probe_ticks_before_pause"] = ticks_before
	before["probe_physics_before_pause"] = physics_before
	completed += 1
	return before


func _run() -> void:
	SESSION.begin_run("hard")
	boot = load(SCENE).instantiate()
	root.add_child(boot)
	current_scene = boot
	game = boot.get_node("Game")
	game.action_audio_enabled = false
	game._sfx.clear()
	game.player.auto_input = true # 正常physics/input收集继续；只有真正SceneTree暂停才能冻结CD和动作。
	probe = AlwaysProbe.new()
	probe.name = "PauseWorldAlwaysProbe"
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	game.add_child(probe)
	check(game.pause_controller != null and game.player.hp == 3,
		"真实M05困难三血启动并创建生产暂停Controller")
	await create_timer(.08, true).timeout
	check(game.music.playing and game.music.has_stream_playback(), "BGM真实开始并持有Playback")
	# 明确fixture：先清下半区24敌，通过生产终端获得非空有效checkpoint，后续只验证暂停不会改它。
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	for enemy: Node2D in game.minions:
		var cell: Vector2i = enemy.get_meta("spawn_cell", Vector2i(-1, -1))
		var room: int = game.level.room_at(cell.x * 32 + 16, cell.y * 32 + 16)
		if room in config.required_clear_rooms:
			enemy.dead = true
			enemy.visible = false
	_place(game._checkpoint_beacons[int(config.room_index)].position)
	game._update_campaign_progress(0.0)
	check(not SESSION.checkpoint.is_empty() and SESSION.checkpoint.defeated.size() == 24,
		"fixture经正式激活得到24敌有效快照，供暂停字典不变检查")
	lift = game.moving_lifts[2]
	lift._clock = 2.4 # 仅安排初始上行位置，不用手动步进代替后续墙钟暂停。
	lift._set_pose_from_clock()
	lift.advance(1.0 / 60.0)
	_place(Vector2(lift.position.x, lift.position.y - .1))
	game.player.dash_cooldown_t = 1.1
	game.player.roll_cooldown_t = .9
	game.smoke_tactics.deploy_cloud(game.player.position + Vector2(-180, -44))
	game.player.set_carried_smoke(true)
	check(game.smoke_tactics.throw_from(game.player, game.player.position + Vector2(160, -60)),
		"fixture经生产throw_from建立飞行烟雾弹")
	cargo = game.props[0] as PropBatCargo
	cargo.position = game.player.position + Vector2(-120, -30)
	check(cargo.launch(1.0, 0), "fixture经生产launch建立飞行货箱")
	game.enemy_bullets.append({"x": game.player.position.x + 200.0, "y": game.player.position.y - 70.0,
		"vx": -500.0, "vy": 0.0, "life": 3.0, "damage_type": "gunshot"})
	await _test_moving_world()
	await _test_sniper_phase()
	await _test_time_stop_release()
	await _test_dying_representative()
	check(completed == 5, "五组真实暂停都执行至恢复，不把提前异常当成通过")
	_right_button(false)
	if game.pause_controller.active:
		game.pause_controller.resume_game()
	check(not paused, "测试退出前不遗留SceneTree.paused")
	boot.free()
	SESSION.reset_for_tests()
	await create_timer(.2, true).timeout
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := FileAccess.open(OUT.path_join("M05-暂停战术集成.txt"), FileAccess.WRITE)
	report.store_string("M05 real wall-clock pause integration\nFixture: initial lift/projectile phases and prerequisite enemy clears only.\n"
		+ "\n".join(log_lines) + "\nPAUSE_TACTICS_RESULT: %d PASS / %d FAIL\n" % [passed, failed])
	report.close()
	print("PAUSE_TACTICS_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_moving_world() -> void:
	check(lift.state == "up" and lift.supports_rider(game.player), "初态为真实货梯上行且脚底获得支撑")
	var before: Dictionary = await _pause_wall_clock("搬运/烟/弹/货箱")
	await create_timer(.06, true).timeout
	check(lift.position.y < before.lifts[2][0].y and lift.supports_rider(game.player), "恢复后上行货梯继续承载，不掉人或重复旧delta")
	check(game.smoke_tactics.clouds[0].age > before.clouds[0][2] \
		and game.smoke_tactics.clouds[0].age - before.clouds[0][2] < .14, "烟寿命只走恢复后时间，不补暂停的220ms")
	check(game.smoke_tactics.grenades.size() == 1 and game.smoke_tactics.grenades[0].age > before.grenades[0].age,
		"恢复后原手雷继续抛物线，不重置或复制")
	check(cargo.flight_time > before.cargo[2] and cargo.position != before.cargo[0], "恢复后原飞箱继续运动")
	check(game.enemy_bullets.size() == 1 and game.enemy_bullets[0].life < before.bullets[0].life,
		"恢复后原敌弹位置寿命继续")
	check(game.player.dash_cooldown_t < before.player[7] and before.player[7] - game.player.dash_cooldown_t < .14 \
		and game.player.roll_cooldown_t < before.player[8], "冲刺/翻滚CD只走恢复后时间，没有墙钟补扣")
	check(probe.ticks > before.probe_ticks_before_pause and probe.physics_ticks > before.probe_physics_before_pause,
		"ALWAYS探针恢复后确实继续处理，而非沿用暂停前非零计数")
	game.enemy_bullets.clear()
	game.smoke_tactics.clear_effects()
	cargo.flying = false
	cargo.dead = true
	cargo.visible = false


func _sniper() -> Node2D:
	for hazard: Node2D in game.tactical_hazards:
		if hazard.hazard_type == "auto_sniper" and hazard.room_id == "right_15":
			return hazard
	return null


func _test_sniper_phase() -> void:
	var sniper := _sniper()
	check(sniper != null, "第三关塔冠存在未清房自动狙击器")
	_place(sniper.position + sniper.direction * 300.0)
	game._step_tactics(.001)
	check(sniper.state == "warning", "真实当前房/视口/LOS允许狙击开始跟踪")
	sniper.phase_time = 1.0 # fixture只安排跟踪中段；暂停/恢复由真实SceneTree处理。
	await _pause_wall_clock("狙击warning")
	await create_timer(.05, true).timeout
	check(sniper.state == "warning" and sniper.phase_time > 1.0 and sniper.phase_time < 1.14,
		"恢复后狙击跟踪只推进实际恢复帧")
	sniper._track(game.player)
	sniper._change_state("locked")
	sniper.phase_time = .15
	var old_shots: int = sniper.shot_count
	await _pause_wall_clock("狙击locked")
	await create_timer(.05, true).timeout
	check(sniper.state == "locked" and sniper.phase_time > .15 and sniper.phase_time < .30 \
		and sniper.shot_count == old_shots, "锁向半秒不被暂停墙钟耗完，恢复后不抢先出弹")


func _test_time_stop_release() -> void:
	_right_button(true)
	await create_timer(.05, true).timeout
	check(game.time_charge.active and game._temporal_paused and game.player.time_focus_active(),
		"真实RMB开启时停，再进入主暂停测试")
	var before: Dictionary = await _pause_wall_clock("时停叠主暂停", true)
	check(game.time_charge.active, "主暂停恢复本身不取消已有时停状态")
	await create_timer(.06, true).timeout
	check(not game.time_charge.active and not game._temporal_paused and not game.player.time_focus_active(),
		"暂停期间松RMB，恢复后由统一时间入口正常解冻")
	check(game.time_charge.energy >= float(before.charge[1]) - .04 \
		and game.time_charge.energy <= float(before.charge[1]) + .001,
		"时停能量不补走暂停时间，也不跳过释放后的复充延迟")
	check(game.player.dash_cooldown_t >= maxf(0.0, float(before.player[7]) - .14),
		"时停叠主暂停没有额外扣冲刺CD")


func _test_dying_representative() -> void:
	game.enemy_bullets.clear()
	game.player.force_death(game.player.position.x - 40)
	check(game.time_phase == "dying" and game.player.dead, "代表阶段使用真实死亡入口进入dying")
	var before: Dictionary = await _pause_wall_clock("死亡惯性dying")
	await create_timer(.05, true).timeout
	check(game.time_phase == "dying" and game.player._death_elapsed > float(before.player[10]) \
		and game.player._death_elapsed - float(before.player[10]) < .14,
		"恢复死亡惯性从原进度继续，不在暂停期间播完倒地")
	check(game._temporal_paused, "恢复dying仍保留原死亡冻结世界，而非错误解除全部时间域")
