extends SceneTree
## 第三关差异化接线验收：真正菜单入场、上下空间唤醒、长梯时停、烟内失锁和本关死亡重载。
## 战斗fixture仅局部摆位，不修改生产代码，也不宣称真人通关或取代既有静态贯通/四梯接驳测试。

const SESSION := preload("res://scripts/run_session.gd")
const DATA := preload("res://generated/m05_vertical_freight_data.gd")
const SCENE := "res://scenes/m05_vertical_freight.tscn"
const DT := 1.0 / 60.0
var _pass := 0
var _fail := 0
var game: Node2D
var player: KairullPlayer
var smoke: Node2D
var _hub := Vector2.ZERO
var _initial_smoke_id := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	_pass += int(value)
	_fail += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func _event(key: Key) -> InputEventKey:
	var result := InputEventKey.new()
	result.keycode = key
	result.pressed = true
	return result


func _prepare() -> void:
	game = current_scene.get_node("Game")
	player = game.player
	smoke = game.smoke_tactics
	current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	game.set_process(false)
	game.set_physics_process(false)
	player.auto_input = false
	player.keys.clear()
	game._sfx.clear()
	game.action_audio_enabled = false
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	if game.action_audio != null:
		game.action_audio.stop_all()


func _run() -> void:
	SESSION.reset_for_tests()
	var menu := load("res://scenes/surveillance_menu.tscn").instantiate() as Node3D
	root.add_child(menu)
	current_scene = menu
	check(menu.monitor_count == 1 and menu.subviewport_count == 1 and menu._monitor_nodes.size() == 1,
			"第三关开局也使用单台CRT，不依赖旧四台屏幕索引")
	menu._select_page(menu.PAGE_START, true)
	var select_level := InputEventMouseButton.new()
	select_level.button_index = MOUSE_BUTTON_LEFT
	select_level.pressed = true
	select_level.position = menu.canvas_to_screen(0, menu.level_card_rect(2).get_center())
	menu._unhandled_input(select_level)
	check(menu.selected_level == 2 and SESSION.selected_scene() == SCENE,
			"同一CRT真实第三关卡片点击选择垂直货运井")
	menu._unhandled_input(_event(KEY_RIGHT))
	menu._unhandled_input(_event(KEY_DOWN))
	menu._unhandled_input(_event(KEY_DOWN))
	menu._unhandled_input(_event(KEY_ENTER))
	check(menu.selected_difficulty == "zero" and menu.selected_page == menu.PAGE_START,
			"武士零难度确认仅返回同台开始频道，不抢先开局")
	var request_modes: Array[String] = []
	menu.run_requested.connect(func(mode: String): request_modes.append(mode))
	menu._unhandled_input(_event(KEY_ENTER))
	for _i in 12:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_node("Game"):
			_prepare()
			break
	check(request_modes == ["zero"] and is_instance_valid(current_scene) \
			and current_scene.scene_file_path == SCENE and current_scene.has_node("Game"),
			"确认开始通过菜单生产change_scene真正进入M05而非M04")
	if game == null:
		quit(1)
		return
	_hub = player.spawn
	_initial_smoke_id = smoke.get_instance_id()
	_test_structure()
	_test_vertical_awake()
	_test_long_lift_time_pause()
	_test_smoke_and_sniper()
	_test_clear_and_cargo()
	await _test_retry()
	current_scene.free()
	await create_timer(0.18).timeout
	check(CorridorLevel.active_encounter_policy.is_empty() and CorridorLevel.active_tactical_objects.is_empty(),
			"第三关卸载清空间策略与战术配置，不污染第一/第二关")
	SESSION.reset_for_tests()
	print("M05_TACTICS_INTEGRATION_RESULT: %d PASS / %d FAIL" % [_pass, _fail])
	quit(int(_fail > 0))


func _cargo_count() -> int:
	var count := 0
	for prop: Node2D in game.props:
		count += int(prop is PropBatCargo)
	return count


func _snipers() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for hazard: Node2D in game.tactical_hazards:
		if hazard.hazard_type == "auto_sniper":
			result.append(hazard)
	return result


func _supplies() -> int:
	# 中枢第1颗就在出生点，真实菜单进入可能已自动拿起；地上+单格携带才是正确资源守恒。
	return smoke.pickups.size() + int(player.carried_smoke)


func _test_structure() -> void:
	check(SESSION.start_level == 2 and SESSION.difficulty == "zero" and player.hp == 1 \
			and game.timeline_enabled, "第三关武士零档保持1血和原时间循环")
	check(game.level.map_w == 144 and game.level.map_h == 114 and game.level.rooms.size() == 20,
			"真实第三关144×114/20房，不是改名的第二长走廊")
	check(game.minions.size() == 52 and game.level.enemy_spawns.size() == 52 and _cargo_count() == 26,
			"52敌和26可击飞箱与新图实例一致")
	check(_supplies() == 8, "八处烟雾补给完整生成，出生自动拿起不视为丢失", str(_supplies()))
	check(game.tactical_hazards.size() == 13 and _snipers().size() == 4,
			"武士零档同样启用9普通机关+4限定重火线炮，不把升降平台算成自动炮")
	check(game.moving_lifts.size() == 4 and player.moving_platforms.size() == 4,
			"四座移动平台独立实例化并接入真实角色支撑")
	var long_range := true
	for lift: Node2D in game.moving_lifts:
		long_range = long_range and is_equal_approx(lift.bottom_y - lift.top_y, 576.0)
	check(long_range, "四座货梯都跨576px完整主楼层，而非短假平台")
	check(_hub == Vector2(74 * 32 + 16, 105 * 32 - 0.1) \
			and game.level.exit_point == Vector2(74 * 32 + 16, 15 * 32 - 0.1),
			"井底安全桥出生，逐层上攀至塔顶出口")
	check(CorridorLevel.active_encounter_policy == "same_floor_nearby" \
			and game._campaign_boundaries.is_empty() and game._checkpoint_beacons.size() == 1 \
			and game._checkpoint_index == -1, "纵向空间唤醒独立于单一未激活记录台，不套线性关卡解锁")
	check(CorridorLevel.active_restart_scene == SCENE and SESSION.selected_scene() == SCENE,
			"会话选择和地图重开入口同时指向M05")


func _place(point: Vector2) -> void:
	game._set_player_time_focus(false)
	game._set_temporal_nodes_paused(false)
	game.time_phase = "playing"
	game.time_charge.reset()
	player.reset_to_spawn()
	player.configure_max_health(5) # 多状态fixture临时5血，入口与重开另断言武士零仍是1血。
	player.position = point
	player.on_ground = true
	player.keys.clear()
	player._prev_keys.clear()
	player._sync_sprite()
	game._update_room_state()
	game.cam_tl = point - Vector2(500, 610)
	game.enemy_bullets.clear()
	game.level_cleared = false


func _awake() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for enemy: Node2D in game.minions:
		if game._campaign_enemy_released(enemy):
			result.append(enemy)
	return result


func _test_vertical_awake() -> void:
	check(_awake().is_empty(), "安全中枢不把整根114格高井内的52敌同时叫醒")
	_place(Vector2(121 * 32 + 16, 51 * 32 - 0.1))
	var middle := _awake()
	check(middle.size() == 4, "第一次接近中层右房只醒同层四敌", str(middle.size()))
	var wrong_floor := false
	for enemy in middle:
		wrong_floor = wrong_floor or (enemy.get_meta("spawn_cell") as Vector2i).y != 50
	check(not wrong_floor, "同X附近但隔一整楼板的敌人不被串层唤醒")
	_place(_hub)
	check(_awake().size() == middle.size(), "退回中枢不能让已醒追兵再次休眠")
	_place(Vector2(121 * 32 + 16, 87 * 32 - 0.1))
	var lower := _awake()
	check(lower.size() > middle.size() and lower.size() < 52,
			"未清前层或激活检查点也可直接下探，下面局部遭遇正常唤醒")
	var lower_room: int = game.current_room
	_place(_hub)
	_place(Vector2(121 * 32 + 16, 33 * 32 - 0.1))
	var upper := _awake()
	check(upper.size() > lower.size() and upper.size() < 52 and game.current_room != lower_room,
			"回中枢后可另选上联，向上新遭遇不受线性前进索引封锁")
	check(game._checkpoint_index == -1 and game._checkpoint_beacons.size() == 1,
			"上下空间唤醒本身不会激活唯一记录台，必须满足实际清场条件")
	var remembered := true
	for enemy in lower:
		remembered = remembered and game._campaign_enemy_released(enemy)
	check(remembered, "上联时已醒的下层敌人仍保持唤醒，不被换层重置")
	_place(_hub)


func _test_long_lift_time_pause() -> void:
	var lift: Node2D = game.moving_lifts[2]
	for _i in 720:
		if lift.state == "bottom_wait":
			break
		game._step_tactics(DT)
	_place(Vector2(lift.position.x, lift.position.y - 0.1))
	check(lift.supports_rider(player), "上联长梯局部fixture确实获得真实脚底支撑")
	for _i in 300:
		game._step_tactics(DT)
		player.step(DT)
		if lift.state == "up" and lift.phase_time > 0.8:
			break
	check(lift.state == "up" and lift.supports_rider(player) and player.position.y < _hub.y - 30,
			"经宿主实际承载上升，未靠直接修改相位摆到空中")
	var held_lift_position: Vector2 = lift.position
	var held_player_position := player.position
	var held_phase := float(lift.phase_time)
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	for _i in 30:
		game._physics_process(DT)
		player.step(DT)
	check(game.time_charge.active and lift.position == held_lift_position \
			and is_equal_approx(lift.phase_time, held_phase), "真实右键把576px长梯停在途中，不漏走世界时钟")
	check(player.position.distance_to(held_player_position) < 0.2 and player.on_ground \
			and lift.supports_rider(player), "停梯期间主角不下掉、不重复承载上一帧delta，支撑保持")
	player.keys.clear()
	game._physics_process(DT)
	player.step(DT)
	check(not game.time_charge.active and lift.position.y < held_lift_position.y \
			and lift.supports_rider(player), "松开右键平台从原相位继续，主角仍随梯上行")
	for _i in 360:
		game._step_tactics(DT)
		player.step(DT)
		if lift.state == "top_wait":
			break
	check(lift.state == "top_wait" and absf(player.position.y - (lift.top_y - 0.1)) < 1.1,
			"停启之后仍到达576px上站，未退回短梯或错误楼层")
	_place(_hub)


func _aim(sniper: Node2D) -> void:
	_place(sniper.position + sniper.direction * 300.0)
	game.current_room = int(sniper.get_meta("room_index"))
	game.cam_tl = (player.position + sniper.position) * 0.5 - Vector2(680, 600)


func _test_smoke_and_sniper() -> void:
	var sniper: Node2D = _snipers()[0]
	_aim(sniper)
	check(smoke.SMOKE_RADIUS == 336.0 and smoke.SMOKE_VERTICAL_RADIUS == 96.0 \
			and smoke.SMOKE_DURATION == 4.8 and smoke.MAX_THROW_RANGE == 420.0,
			"第三关复用同一三倍横向烟，不回退高度/寿命/投距")
	game._step_tactics(DT)
	check(sniper.state == "warning", "井底真实房间内的可见炮进入跟踪")
	smoke.deploy_cloud(player.position)
	game._step_tactics(0.2)
	check(sniper.state == "idle" and sniper.trace_end == Vector2.ZERO and sniper.shot_count == 0,
			"M05跟踪期进烟立即清红线/目标，不继续隔烟锁定")
	var hero_color: Color = player._sprite.self_modulate
	var hero_outline: Color = player._outline_mat.get_shader_parameter("outline_color")
	check(player.smoke_cover_active() and hero_color.r < 0.1 and is_equal_approx(hero_color.a, 1.0) \
			and hero_outline.g > 0.85, "第三关主角烟内也是不透明深剪影与浅青真轮廓")
	var enemy: Node2D = game.minions[0]
	var saved_position := enemy.position
	enemy.position = player.position + Vector2(80, 0)
	enemy._sync_sprite()
	game._refresh_smoke_cover()
	var enemy_tint: Color = enemy._sprite.self_modulate
	check(smoke.contains_actor(enemy) and enemy_tint.r < 0.1 and is_equal_approx(enemy_tint.a, 1.0),
			"同一井底烟区内敌人显示较暗剪影，不使用透明淡出代替")
	smoke.clear_effects()
	game._refresh_smoke_cover()
	check(player._sprite.self_modulate == Color.WHITE \
			and enemy._sprite.self_modulate == enemy._sprite.get_meta("smoke_base_tint"),
			"主角与敌人出烟同时恢复原美术")
	enemy.position = saved_position
	enemy._sync_sprite()
	game._step_tactics(DT)
	game._step_tactics(1.51)
	check(sniper.state == "locked" and sniper.shot_count == 0, "井底炮离烟后重新跟踪完整1.5秒才锁定")
	smoke.deploy_cloud(player.position)
	game._step_tactics(0.2)
	check(sniper.state == "idle" and sniper.last_target == Vector2.ZERO \
			and sniper.shot_count == 0 and game.enemy_bullets.is_empty(),
			"井底炮已锁定的最后半秒也会被烟立即取消，不补发子弹")
	smoke.clear_effects()
	game._step_tactics(DT)
	game._step_tactics(1.49)
	check(sniper.state == "warning" and sniper.shot_count == 0, "M05重新出烟1.49秒还未偷锁/偷射")
	game._step_tactics(0.02)
	game._step_tactics(0.49)
	check(sniper.state == "locked" and sniper.shot_count == 0, "新1.5秒结束后还要足额半秒锁向")
	game._step_tactics(0.02)
	check(sniper.shot_count == 1 and game.enemy_bullets.size() == 1,
			"重新完整1.5秒+半秒才经第三关宿主发出一颗高速弹")
	game.enemy_bullets.clear()


func _test_clear_and_cargo() -> void:
	var sniper: Node2D = _snipers()[0]
	var room_index := int(sniper.get_meta("room_index"))
	var room: Rect2i = game.level.rooms[room_index].rect
	var cleared: Array[Node2D] = []
	for enemy: Node2D in game.minions:
		if room.has_point(enemy.get_meta("spawn_cell")) and not enemy.dead:
			enemy.dead = true
			cleared.append(enemy)
	game._step_tactics(DT)
	check(not cleared.is_empty() and sniper.cleared_disabled and not sniper.armed,
			"井底房清敌后本房炮永久停机，不需要凑第53名器械敌人")
	for enemy in cleared:
		enemy.dead = false
	game._step_tactics(DT)
	check(sniper.cleared_disabled and not sniper.armed, "本轮已清房炮不会被下一帧空间激活重新叫醒")
	var target: Node2D = _snipers()[1]
	_aim(target)
	var cargo: PropBatCargo
	for prop: Node2D in game.props:
		if prop is PropBatCargo and not prop.dead:
			cargo = prop
			break
	var saved_cargo_position := cargo.position
	var launch_direction: float = -target.direction.x
	cargo.position = target.position + target.direction * 170.0 + Vector2(0, -1)
	player.position = cargo.position - Vector2(launch_direction * 48.0, 0)
	player.face = int(launch_direction)
	var lane := Rect2(Vector2(minf(cargo.position.x, target.position.x) - 80, target.position.y - 140), Vector2(330, 200))
	var shifted: Array[Dictionary] = []
	for enemy: Node2D in game.minions:
		if lane.intersects(enemy.body_rect()):
			shifted.append({"actor": enemy, "position": enemy.position})
			enemy.position.x -= 700.0
	var original_alive: int = game._enemies().size()
	var original_splats: int = game.paint_layer.splat_count()
	var original_effects: int = game.fx_layer.get_child_count()
	game._on_player_bat_swung(cargo.body_rect(), 1)
	check(cargo.flying and game._cargo_targets().has(target) and not game._enemies().has(target),
			"M05真实球棒把箱打向炮，炮只属于器械/货箱目标列表")
	for _i in 30:
		if cargo.dead:
			break
		game._physics_process(DT)
	check(cargo.dead and target.dead, "井底右房的真实飞箱沿路径击毁炮台")
	check(game.minions.size() == 52 and game._enemies().size() == original_alive,
			"击毁第三关炮不改变52个生物敌人的分母/存活统计")
	check(game.paint_layer.splat_count() == original_splats and game.fx_layer.get_child_count() == original_effects,
			"第三关器械毁坏保持金属火花，不生成生物血/尸体实例")
	for entry in shifted:
		entry.actor.position = entry.position
	cargo.position = saved_cargo_position


func _test_retry() -> void:
	_place(_hub)
	player.configure_max_health(1)
	# 取一处真实剩余补给后投出，失败场景确实有已消耗资源/现存烟，而非只重开空白现场。
	var supply_point: Vector2 = smoke.pickups[0]["position"]
	player.position = supply_point
	smoke.try_pickup(player)
	player.aim_override = supply_point + Vector2(120, -12)
	player.keys = {KEY_R: true}
	player._prev_keys.clear()
	player.step(DT)
	smoke.update_aim_preview()
	check(smoke.grenades.is_empty() and player.carried_smoke and smoke._preview_visible,
			"第三关按住R只瞄准，携带图标不会被立即消耗")
	player.keys[MOUSE_BUTTON_LEFT] = true
	player.step(DT)
	player.keys.clear()
	check(smoke.grenades.size() == 1 and not player.carried_smoke,
			"第三关按R左键确认经玩家/宿主成功消耗真实烟雾补给一次")
	check(not player.batting() and not player.bat_queued and player._bat_input_buffer_t == 0,
			"第三关投掷确认不同时挥棒或排连招")
	smoke.step(0.8)
	player.set_carried_smoke(true) # 额外fixture只验死亡清槽；重开仍必须回地图本身8个资源。
	var old_scene_id: int = current_scene.get_instance_id()
	var music_id: int = game.music.get_instance_id()
	await create_timer(0.15).timeout
	game.music.play(9.0)
	await create_timer(0.15).timeout
	var playback_id: int = game.music.get_stream_playback().get_instance_id()
	var before: float = game.music.get_playback_position()
	player.force_death(player.position.x - 60)
	check(game.time_phase == "dying" and not player.carried_smoke, "M05真正死亡清携带槽并保留惯性倒地流程")
	game._begin_rewind()
	check(smoke.clouds.is_empty() and smoke.grenades.is_empty(), "第三关短倒带清动态烟/手雷，不重演投掷")
	game._advance_rewind(game.REWIND_DURATION + game.INTERFERENCE_DURATION + 0.01)
	for _i in 12:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_scene_id \
				and current_scene.has_node("Game"):
			_prepare()
			break
	check(current_scene.scene_file_path == SCENE and current_scene.get_instance_id() != old_scene_id,
			"生产死亡回溯真正重载第三关，不退回M04或电视菜单")
	check(SESSION.start_level == 2 and SESSION.attempt == 2 and player.hp == 1 and not player.dead,
			"新轮恢复第三关选择、武士零1血和轮次，不继承fixture五血")
	check(game.minions.size() == 52 and game._enemies().size() == 52 and _cargo_count() == 26,
			"新轮重建52敌/26箱，不沿用已清房和碎箱")
	check(game.tactical_hazards.size() == 13 and _snipers().size() == 4 \
			and not _snipers()[0].cleared_disabled and not _snipers()[1].dead,
			"新轮四炮与九机关完整复位，已毁/停机设备重新按图生成")
	check(smoke.get_instance_id() != _initial_smoke_id and smoke.clouds.is_empty() \
			and smoke.grenades.is_empty() and _supplies() == 8,
			"新烟管理器恢复地图8资源（含出生自动拾取），没有旧烟/弹体残留")
	check(game.moving_lifts.size() == 4 and player.position.distance_to(_hub) < 2.0 \
			and _awake().is_empty(), "重开回中枢，四梯与空间唤醒重置而非保留远层追兵")
	await create_timer(0.15).timeout
	check(game.music.get_instance_id() == music_id \
			and game.music.get_stream_playback().get_instance_id() == playback_id,
			"M05重开仍复用同一BGM节点与AudioStreamPlayback")
	check(game.music.playing and game.music.get_playback_position() >= 9.0 \
			and game.music.get_playback_position() >= before - 0.05,
			"第三关死亡花屏后音乐进度不中断、不归零")
