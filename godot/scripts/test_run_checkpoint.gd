extends SceneTree
## 三关真实入口→解锁中段点→死亡短回放→change_scene重建；局部摆位只用于设置测试条件。
const SESSION := preload("res://scripts/run_session.gd")
const SNAPSHOT := preload("res://scripts/run_checkpoint.gd")
var passed := 0
var failed := 0
var game: Node2D

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func _prepare() -> void:
	game = current_scene.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.set_physics_process(false)
	game.player.keys.clear()
	game.player._prev_keys.clear()
	game.action_audio_enabled = false
	game._sfx.clear()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	game.action_audio.stop_all()

func _run() -> void:
	for mode in SESSION.DIFFICULTIES:
		SESSION.begin_run(mode)
		check(SESSION.difficulty == mode and SESSION.max_health() == {"easy":5,"hard":3,"zero":1}[mode],
				"会话难度%s精确映射生命" % mode)
	SESSION.begin_run("invalid")
	check(SESSION.difficulty == "easy" and SESSION.max_health() == 5, "无效难度安全回简单")
	for index in SESSION.LEVEL_SCENES.size():
		await _test_map(index, SESSION.DIFFICULTIES[index])
	SESSION.reset_for_tests()
	check(CorridorLevel.active_checkpoints.is_empty(), "三入口卸载都清active_checkpoints静态量")
	print("RUN_CHECKPOINT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))

func _at(point: Vector2) -> void:
	game.player.position = point
	game.player.on_ground = true
	game.player.vx = 0.0
	game.player.vy = 0.0
	game._update_room_state()

func _dead_count() -> int:
	var count := 0
	for enemy: Node2D in game.minions:
		count += int(enemy.dead)
	return count

func _enemy_room(enemy: Node2D) -> int:
	var cell: Vector2i = enemy.get_meta("spawn_cell")
	return game.level.room_at(cell.x * 32 + 16, cell.y * 32 + 16)

func _test_map(index: int, mode: String) -> void:
	var scene: String = SESSION.LEVEL_SCENES[index]
	SESSION.begin_run(mode)
	SESSION.start_level = index
	var boot: Node2D = load(scene).instantiate()
	root.add_child(boot)
	current_scene = boot
	_prepare()
	var prefix := "M%d/%s " % [index + 1, mode]
	var entrance: Vector2 = game.level.spawn
	check(game.player.hp == SESSION.max_health(), prefix + "真实入口5/3/1生命正确")
	check(game._checkpoint_beacons.size() == 1 and game._checkpoint_index == -1 \
			and SESSION.checkpoint.is_empty(), prefix + "唯一检查点未激活，不继承旧挑战")
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	var beacon: Node2D = game._checkpoint_beacons[int(config.room_index)]
	var point: Vector2 = beacon.position
	var required: Array = config.required_clear_rooms
	_at(point)
	game.player.hp = 1
	game.time_charge.energy = .1
	game._update_campaign_progress(0.0)
	check(game._checkpoint_index == -1 and not beacon.unlocked and game.player.hp == 1,
			prefix + "提前站到终端不存档或偷补血")
	var to_clear: Array[Node2D] = []
	var later_enemy: Node2D
	for enemy: Node2D in game.minions:
		if required.has(_enemy_room(enemy)):
			to_clear.append(enemy)
		elif later_enemy == null:
			later_enemy = enemy
	check(to_clear.size() == [10,22,24][index], prefix + "解锁前置是半程10/22/24敌")
	for enemy in to_clear:
		enemy.dead = true
	to_clear[-1].dead = false
	game._update_campaign_progress(0.0)
	check(game._checkpoint_index == -1, prefix + "前段剩最后一敌仍不能存档")
	to_clear[-1].dead = true
	var later_position: Vector2 = later_enemy.position
	later_enemy.position = point + Vector2(50,0)
	game._update_campaign_progress(0.0)
	check(game._checkpoint_index == -1, prefix + "终端贴脸有追兵时不生成危险复活点")
	later_enemy.position = later_position
	# 快照前消耗一箱；烟雾取走一罐并携带，之后的消耗会在重开时回到这里。
	var old_prop: Node2D = game.props[0]
	old_prop.dead = true
	var old_prop_key: String = old_prop.get_meta("checkpoint_key")
	var future_prop: Node2D = game.props[1]
	var future_prop_key: String = future_prop.get_meta("checkpoint_key")
	var smoke_count := 0
	if game.smoke_tactics != null:
		var pickup: Dictionary = game.smoke_tactics.pickups[0]
		_at(pickup.position)
		check(game.smoke_tactics.try_pickup(game.player), prefix + "实际拾取烟雾后再记录携带状态")
		_at(point)
		smoke_count = game.smoke_tactics.pickups.size()
	var snipers: Array[Node2D] = []
	for hazard: Node2D in game.tactical_hazards:
		if hazard.hazard_type == "auto_sniper":
			snipers.append(hazard)
	var ruined_key := ""
	var later_sniper_key := ""
	if not snipers.is_empty():
		snipers[0].take_hit(snipers[0].position.x - 10)
		ruined_key = SNAPSHOT.hazard_key(snipers[0])
		if snipers.size() > 1:
			later_sniper_key = SNAPSHOT.hazard_key(snipers[1])
	var carried: bool = game.player.carried_smoke
	game._run_elapsed = 88.0
	game.time_charge.energy = .9
	game.player.keys = {MOUSE_BUTTON_RIGHT: true}
	game._physics_process(1.0 / 60.0)
	check(game.time_charge.active and game._temporal_paused and is_equal_approx(game.music.pitch_scale, .78),
			prefix + "真实右键先进入时停，再在终端记录")
	game._update_campaign_progress(0.0)
	check(game._checkpoint_index == int(config.room_index) and beacon.activated \
			and game.player.spawn == point, prefix + "前段清场后靠近正式激活唯一中段点")
	check(game.player.hp == SESSION.max_health() and game.time_charge.energy == 2.0,
			prefix + "激活时生命与时停容量补满")
	check(game.time_charge.active and game._temporal_paused, prefix + "时停内补能保留active和一致的世界暂停状态")
	game.player.keys.clear()
	game._physics_process(0.0)
	check(not game.time_charge.active and not game._temporal_paused \
			and not game.player.time_focus_active() and game.music.pitch_scale == 1.0,
			prefix + "激活后立即松右键，世界/主角/音乐正常恢复，不永久冻结")
	var saved := SESSION.checkpoint_for(scene)
	check(saved.defeated.size() == to_clear.size() and saved.signature == SNAPSHOT.signature(),
			prefix + "保存已清名单和完整源地图签名")
	check(saved.carried_smoke == carried and saved.spent_props.has(old_prop_key),
			prefix + "快照同时保存消耗箱和烟雾背包")
	var copy := SESSION.checkpoint_for(scene)
	copy.defeated.clear()
	check(SESSION.checkpoint_for(scene).defeated.size() == to_clear.size(), prefix + "读出的快照深拷贝不反改会话")
	check(SESSION.checkpoint_for("res://scenes/not_this_map.tscn").is_empty(), prefix + "跨关快照不被读取")
	var stairs_before: Array = CorridorLevel.active_stairs.duplicate(true)
	CorridorLevel.active_stairs[0]["steps"] += 1
	check(not SNAPSHOT.restore(game, saved), prefix + "只改楼梯几何也拒绝旧快照，不仅检查ASCII")
	CorridorLevel.active_stairs = stairs_before
	var rooms_before: Array = CorridorLevel.active_rooms.duplicate(true)
	CorridorLevel.active_rooms[0]["rect"] = Rect2i(0,0,1,1)
	check(not SNAPSHOT.restore(game, saved), prefix + "只改房间归属也拒绝旧快照")
	CorridorLevel.active_rooms = rooms_before
	var mode_before: String = SESSION.difficulty
	SESSION.difficulty = "easy" if mode_before != "easy" else "zero"
	check(SESSION.checkpoint_for(scene).is_empty(), prefix + "同关不同难度不套旧快照")
	SESSION.difficulty = mode_before
	game.player.hp = 1
	game.time_charge.energy = .25
	game._update_campaign_progress(1.0)
	check(game.player.hp == 1 and game.time_charge.energy == .25 and SESSION.checkpoint_for(scene).elapsed == 88.0,
			prefix + "反复站点不刷生命/能量，不覆盖原存点")
	var music_id: int = game.music.get_instance_id()
	await create_timer(.12).timeout
	game.music.play(7.0)
	await create_timer(.12).timeout
	var playback_id: int = game.music.get_stream_playback().get_instance_id()
	# 存点后的变化只留在失败场景，不能混进下次重生。
	later_enemy.dead = true
	var later_cell: Vector2i = later_enemy.get_meta("spawn_cell")
	future_prop.dead = true
	if game.smoke_tactics != null:
		game.player.set_carried_smoke(false)
		var pickup: Dictionary = game.smoke_tactics.pickups[0]
		_at(pickup.position)
		game.smoke_tactics.try_pickup(game.player)
		game.player.set_carried_smoke(false)
		game.smoke_tactics.deploy_cloud(point)
	if snipers.size() > 1:
		snipers[1].take_hit(snipers[1].position.x - 10)
	for lift: Node2D in game.moving_lifts:
		lift.advance(2.0)
	game.enemy_bullets.append({"x":point.x,"y":point.y-50,"vx":2000.0,"vy":0.0,"life":2.0})
	_at(point + Vector2(120,0))
	for cycle in 2:
		var old_scene_id: int = current_scene.get_instance_id()
		game.player.force_death(game.player.position.x - 40)
		check(game.time_phase == "dying", prefix + "第%d次沿用原死亡惯性入口" % (cycle+1))
		game._begin_rewind()
		check(game.REWIND_DURATION == .65 and game.INTERFERENCE_DURATION == .36,
				prefix + "检查点不延长原短倒带或替换电视故障")
		game._advance_rewind(game.REWIND_DURATION + game.INTERFERENCE_DURATION + .01)
		for frame in 4:
			await process_frame
		_prepare()
		await create_timer(.12).timeout
		check(current_scene.get_instance_id() != old_scene_id and game._checkpoint_index == int(config.room_index),
				prefix + "第%d次真正重建场景后应用检查点" % (cycle+1))
		check(game.player.position.distance_to(point) < 1.0 and game.player.spawn == point \
				and game.player.position.distance_to(entrance) > 40.0,
				prefix + "重生在存点而不是旧入口")
		check(not game.player.dead and game.player.hp == SESSION.max_health() and game.time_charge.energy == 2.0,
				prefix + "重生生命按所选难度补满，时停满能")
		check(_dead_count() == to_clear.size() and game.run_progress().enemies_defeated == to_clear.size(),
				prefix + "只保留存点前清敌，不丢分母或带回后半失败击杀")
		var later_alive := false
		var old_spent := false
		var future_restored := false
		for enemy: Node2D in game.minions:
			if enemy.get_meta("spawn_cell") == later_cell:
				later_alive = not enemy.dead
			if enemy.dead:
				check(not enemy.visible and enemy.get_meta("checkpoint_cleared",false), prefix + "已清敌隐去并退出步进")
		for prop: Node2D in game.props:
			if prop.get_meta("checkpoint_key") == old_prop_key:
				old_spent = prop.dead and not prop.visible
			if prop.get_meta("checkpoint_key") == future_prop_key:
				future_restored = not prop.dead
		check(later_alive and old_spent and future_restored, prefix + "后半敌箱恢复，前半已耗箱不复制")
		if game.smoke_tactics != null:
			check(game.smoke_tactics.pickups.size() == smoke_count and game.player.carried_smoke == carried,
					prefix + "烟补给及背包回到存点状态而非整图补满")
			check(game.smoke_tactics.clouds.is_empty() and game.smoke_tactics.grenades.is_empty(),
					prefix + "失败烟云/飞行手雷不继承")
		for hazard: Node2D in game.tactical_hazards:
			var key := SNAPSHOT.hazard_key(hazard)
			if key == ruined_key:
				check(hazard.dead, prefix + "存点前已毁狙击保持残骸")
			if not later_sniper_key.is_empty() and key == later_sniper_key:
				check(not hazard.dead and hazard.shot_count == 0, prefix + "存点后损坏狙击重置无预瞄残留")
		check(game.enemy_bullets.is_empty() and game._corpse_impacts.is_empty(), prefix + "失败高速弹/尸体任务不残留")
		check(game.music.get_instance_id() == music_id \
				and game.music.get_stream_playback().get_instance_id() == playback_id \
				and game.music.get_playback_position() >= 7.0,
				prefix + "同一BGM与Playback连续播放，不play/seek重置")
		check(SESSION.attempt == cycle+2 and SESSION.checkpoint_for(scene).elapsed == 88.0,
				prefix + "轮次增加但存点深拷贝不被失败/重载污染")
	# 明确新开局/退出清存点，不把另一次挑战接到旧半程。
	SESSION.leave_run()
	check(SESSION.checkpoint.is_empty(), prefix + "返回菜单语义清空本次检查点")
	current_scene.free()
	current_scene = null
	await create_timer(.15).timeout
	SESSION.reset_for_tests()
