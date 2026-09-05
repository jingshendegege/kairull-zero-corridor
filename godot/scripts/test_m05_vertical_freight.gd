extends SceneTree
## 第三关入口/空间唤醒/单一检查点未激活/退出清理。局部位置只用于唤醒探针，不当作贯通。
const SESSION := preload("res://scripts/run_session.gd")
const DATA := preload("res://generated/m05_vertical_freight_data.gd")
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func _run() -> void:
	SESSION.begin_run("easy")
	var boot := load("res://scenes/m05_vertical_freight.tscn").instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	var game := boot.get_node("Game") as Node2D
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.action_audio_enabled = false
	game._sfx.clear()
	if game.action_audio != null:
		game.action_audio.stop_all()
	check(game.level.map_w == 144 and game.level.map_h == 114, "第三关真实装载144×114纵向图")
	check(game.level.spawn == Vector2(74 * 32 + 16, 105 * 32 - .1), "最底层安全桥出生")
	check(game.level.exit_point == Vector2(74 * 32 + 16, 15 * 32 - .1), "出口在塔顶而非地图最右端")
	check(CorridorLevel.active_title == "03 垂直货运井", "菜单与HUD显示第三关正式名")
	check(CorridorLevel.active_map == DATA.MAP_TEXT, "地图常量消费同一LDtk生成数据")
	check(CorridorLevel.active_encounter_policy == "same_floor_nearby" and game._campaign_boundaries.is_empty(),
		"自由上下探索采用空间唤醒，不套线性前进记录点")
	check(game.level.rooms.size() == 20 and game.level.stairs.size() == 6, "20房/6接梯实际建立")
	check(game.quarantine_architecture.stair_semantics_valid and game.quarantine_architecture.stair_tread_count == 72,
		"72踏面美术与物理语义匹配")
	check(game.minions.size() == 52, "52敌真实实例化")
	var cargo := 0
	var melee := 0
	var gunner := 0
	for item: Dictionary in game.level.prop_spawns:
		cargo += int(item["kind"] == "bat_cargo")
	for enemy: Node2D in game.minions:
		melee += int(enemy is FreightInspector)
		gunner += int(enemy is GruntGunner)
	check(cargo == 26 and melee == 26 and gunner == 26, "26箱＋26近战＋26枪手")
	check(game.moving_lifts.size() == 4 and game.player.moving_platforms.size() == 4, "四座长货梯实际接入玩家支撑")
	check(game.tactical_hazards.size() == 11, "简单模式9普通机关＋2炮，不启用另外2困难炮")
	check(game.smoke_tactics.pickups.size() == 8, "八处烟雾补给接入")
	check(game._checkpoint_beacons.size() == 1 and game._checkpoint_index == -1,
			"仅一处中途记录台，开局和上半未清时都未激活")
	var initial_awake := 0
	for enemy: Node2D in game.minions:
		initial_awake += int(game._campaign_enemy_released(enemy))
	check(initial_awake == 0, "中枢安全出生不唤醒远处/其他楼层守军", str(initial_awake))
	game.player.position = Vector2(121 * 32 + 16, 51 * 32 - .1)
	var room_awake := 0
	var wrong_floor := false
	for enemy: Node2D in game.minions:
		if game._campaign_enemy_released(enemy):
			room_awake += 1
			var cell: Vector2i = enemy.get_meta("spawn_cell")
			wrong_floor = wrong_floor or cell.y != 50
	check(room_awake == 4 and not wrong_floor, "接近中层右房仅唤醒本层四敌，不穿楼板索敌", str(room_awake))
	game.player.position = game.level.spawn
	var sticky := 0
	for enemy: Node2D in game.minions:
		sticky += int(game._campaign_enemy_released(enemy))
	check(sticky == 4, "已醒追兵返回枢纽后不突然冻结，其他48敌仍休眠")
	check(game.timeline_enabled and game.player.hp == 5 and game.music.get_parent() == root,
		"原时间循环/难度/连续音乐规则仍保留")
	check(CorridorLevel.active_restart_scene == "res://scenes/m05_vertical_freight.tscn"
		and CorridorLevel.active_next_scene.is_empty(), "重开回本关，不跳入旧试作")
	await create_timer(.20).timeout
	boot.free()
	await create_timer(.20).timeout
	check(CorridorLevel.active_map.is_empty() and CorridorLevel.active_stairs.is_empty()
		and CorridorLevel.active_tactical_objects.is_empty(), "卸载清空本关地图/梯/道具配置")
	check(CorridorLevel.active_encounter_policy.is_empty(), "卸载清空空间唤醒策略，不污染第二关")
	SESSION.reset_for_tests()
	print("M05_BOOT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
