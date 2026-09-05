extends SceneTree
## 新关入口、清场要求、分段唤醒与退出还原合同。机关/烟雾细节由各自专项验证。

const DATA := preload("res://generated/m04_chrono_freight_data.gd")
const SESSION := preload("res://scripts/run_session.gd")
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
	var boot := load("res://scenes/m04_chrono_freight.tscn").instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	var game := boot.get_node("Game") as Node2D
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.keys.clear()
	game.action_audio_enabled = false
	if game.action_audio != null:
		game.action_audio.stop_all()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	game._sfx.clear()
	var level: CorridorLevel = game.level
	check(level.map_w == 460 and level.map_h == 36, "新关实际装载460×36")
	check(level.spawn == Vector2(144.0, 1023.9), "新关唯一出生点c4/r31")
	check(level.exit_point == Vector2(14544.0, 863.9), "新关唯一出口c454/r26")
	check(level.rooms.size() == 14 and level.stairs.size() == 5, "十四房与五楼梯接入运行时")
	check(CorridorLevel.active_title == "02 时差货运场", "显示第二关名，不暴露避让历史试作的技术编号")
	check(CorridorLevel.active_restart_scene == "res://scenes/m04_chrono_freight.tscn", "死亡/重开回到新关自身")
	check(CorridorLevel.active_next_scene.is_empty(), "不会自动跳入旧M02/M03试作")
	check(CorridorLevel.active_campaign_mode and game.timeline_enabled, "正式时间循环模式启用")
	check(CorridorLevel.active_tactical_objects == DATA.TACTICAL_OBJECTS, "15战术对象从LDtk原样接入（含2货梯）")
	check(CorridorLevel.active_encounter_boundaries == [4, 8], "安全连接房只分段唤醒")
	check(game._campaign_boundaries == [4, 8], "遭遇分段边界与新增单一记录台相互独立")
	check(game._checkpoint_beacons.size() == 1 and game._checkpoint_index == -1,
			"仅一处记录台且开局未激活，未清前半不能从中途恢复")
	check(level.door_spawns.is_empty(), "空间不依赖会被位移绕过的软硬门")
	check(game.minions.size() == 38, "38名敌人真实实例化，机关不计入杀敌总数")
	var gunner_count := 0
	var melee_count := 0
	var first_segment := 0
	for enemy: Node2D in game.minions:
		gunner_count += int(enemy is GruntGunner)
		melee_count += int(enemy is FreightInspector)
		first_segment += int(game._campaign_enemy_released(enemy))
	check(gunner_count == 19 and melee_count == 19, "19枪手＋19近战巡检员", str([gunner_count, melee_count]))
	check(first_segment == 10, "开局只放行首段10敌，不唤醒全图38敌", str(first_segment))
	game._campaign_frontier = 5
	var second_segment := 0
	for enemy: Node2D in game.minions:
		second_segment += int(game._campaign_enemy_released(enemy))
	check(second_segment == 22, "跨静音维修间仅放行中段12敌", str(second_segment))
	game._campaign_frontier = 9
	var all_released := 0
	for enemy: Node2D in game.minions:
		all_released += int(game._campaign_enemy_released(enemy))
	check(all_released == 38, "跨安全观察间才放行后段16敌")
	var cargo_count := 0
	for prop: Dictionary in level.prop_spawns:
		cargo_count += int(prop["kind"] == "bat_cargo")
	check(cargo_count == 20, "20只可击飞货箱，不计入敌人数")
	check(CorridorLevel.active_exit_requires_boss, "出口继续要求清空关卡，不触碰空出口就跳关")
	check(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED, "纯球棒/翻滚/冲刺不回退成枪械或滑铲")
	check(game.player.hp == 5 and game.player.max_hp == 5, "简单模式仍是5血")
	check(game.quarantine_architecture != null and game.quarantine_foreground != null,
		"地标、楼梯剖面和前景层已接入，非空白碰撞图")
	check(game.quarantine_architecture.stair_semantics_valid and game.quarantine_architecture.stair_tread_count == 50,
		"视觉楼梯和物理高度场共用50格语义")
	check(is_instance_valid(game.music) and game.music.get_parent() == root,
		"死亡重开连续音乐播放器仍在场景树根")
	# 给真实音频线程一个短启动/退出周期，不把即刻quit的旧资源告警冒充逻辑失败。
	await create_timer(0.20).timeout
	boot.free()
	await create_timer(0.20).timeout
	check(CorridorLevel.active_map.is_empty() and CorridorLevel.active_rooms.is_empty()
		and CorridorLevel.active_stairs.is_empty(), "退出清空地图/房间/楼梯静态配置")
	check(CorridorLevel.active_tactical_objects.is_empty() and CorridorLevel.active_encounter_boundaries.is_empty(),
		"退出清空新道具与遭遇边界，不污染旧关")
	check(CorridorLevel.active_semantic_layers.is_empty() and CorridorLevel.active_art_style.is_empty(),
		"退出恢复语义美术静态配置")
	check(not CorridorLevel.active_campaign_mode and CorridorLevel.active_restart_scene.is_empty(),
		"退出不残留新关整场重置配置")
	SESSION.reset_for_tests()
	print("M04_BOOT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
