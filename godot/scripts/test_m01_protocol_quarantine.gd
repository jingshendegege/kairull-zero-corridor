extends SceneTree
## 正式第一关运行时合同：boot 配置、混合敌人、显式美术层、清场出口与退出还原。
## 跑法：Godot --headless --path godot --script scripts/test_m01_protocol_quarantine.gd

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_reset_statics()
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var level: CorridorLevel = game.level
	game.player.auto_input = false
	game.player.hp = 999
	# 本测试只验证逻辑；在产生清场门闩声前禁音，避免即时退出留下音频 playback。
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()

	print("== 正式第一关数据接线 ==")
	ok(ProjectSettings.get_setting("application/run/main_scene", "") \
			== "res://scenes/surveillance_menu.tscn", "项目默认启动监控菜单，第一关由菜单显式进入")
	ok(level.map_w == DATA.MAP_WIDTH and level.map_h == DATA.MAP_HEIGHT,
			"运行时尺寸与 LDtk 编译数据一致", "%dx%d" % [level.map_w, level.map_h])
	ok(level.spawn == Vector2(4 * 32 + 16, 28 * 32 - 0.1), "唯一出生点已解析",
			str(level.spawn))
	ok(level.exit_point == Vector2(274 * 32 + 16, 23 * 32 - 0.1), "扩展流程的唯一出口已解析",
			str(level.exit_point))
	ok(level.rooms.size() == 10, "十段正式空间已注册", str(level.rooms.size()))
	var room_contract := true
	var room_ids := {}
	for room: Dictionary in level.rooms:
		room_contract = room_contract and room["rect"] is Rect2i \
				and not String(room.get("room_id", "")).is_empty() \
				and not String(room.get("decor_profile", "")).is_empty()
		room_ids[String(room.get("room_id", ""))] = true
	ok(room_contract and room_ids.size() == 10,
			"房间使用稳定 id + 显式 decor_profile，不按名称猜装饰")
	ok(level.door_spawns.is_empty(), "第一关不用可被位移技能绕过的硬门")
	ok(level.stairs.size() == 3 and level.stairs[0] == {
		"left_c": 52, "bottom_row": 28, "steps": 10, "rise_dir": 1,
	}, "保留原十级钢梯，并新增下行与上联钢梯", str(level.stairs))
	var checkpoints: Array = []
	for room: Dictionary in level.rooms:
		if room.has("checkpoint_cell"):
			checkpoints.append(room["checkpoint_cell"])
	ok(checkpoints == [[111, 22], [215, 22]], "两处安全检查点通过房间元数据传入运行时")

	print("== 纯球棒与混合敌人 ==")
	ok(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED,
			"玩家仍为纯球棒：枪械/滑铲关闭")
	ok(game.minions.size() == 20, "二十名敌人按 LDtk 刷点生成", str(game.minions.size()))
	var gunner_count := 0
	var melee_count := 0
	var enemies_off_stairs := true
	for minion: Node2D in game.minions:
		if minion is GruntGunner:
			gunner_count += 1
		elif minion is FreightInspector:
			melee_count += 1
		var cell: Vector2i = minion.get_meta("spawn_cell")
		for stair: Dictionary in level.stairs:
			if cell.x >= int(stair["left_c"]) and cell.x < int(stair["left_c"]) + int(stair["steps"]) \
					and cell.y >= int(stair["bottom_row"]) - int(stair["steps"]) / 2 - 1 \
					and cell.y < int(stair["bottom_row"]):
				enemies_off_stairs = false
	ok(gunner_count == 9 and melee_count == 11, "9 枪手 + 11 近战巡检员",
			"gunner=%d melee=%d" % [gunner_count, melee_count])
	ok(enemies_off_stairs, "敌人不刷在开放楼梯范围")
	var cargo_cells: Array[Vector2i] = []
	for entity: Dictionary in DATA.ENTITIES:
		if String(entity["kind"]) == "BatCargo":
			cargo_cells.append(Vector2i(int(entity["cell"][0]), int(entity["cell"][1])))
	ok(cargo_cells.size() == 11 and cargo_cells.has(Vector2i(28, 27))
			and cargo_cells.has(Vector2i(40, 27)),
			"十一只货箱保留原教学位置，并覆盖新增战斗房", str(cargo_cells))
	var cargo_spawn_count := 0
	for prop_spawn: Dictionary in level.prop_spawns:
		if String(prop_spawn["kind"]) == "bat_cargo":
			cargo_spawn_count += 1
	ok(cargo_spawn_count == 11, "C 标记接入道具刷点，不计入二十敌清场数")
	var cargo_lanes_clear := true
	for cell_x in range(28, 48):
		cargo_lanes_clear = cargo_lanes_clear \
				and level.tile_at(cell_x, 27) == "." \
				and level.tile_at(cell_x, 26) == "." \
				and level.tile_at(cell_x, 28) == "#"
	ok(cargo_lanes_clear, "货箱到枪手/巡检员之间保持同层净空，不被旧基座截断")
	var optional_walkway_ok := true
	for cell_x in range(41, 48):
		optional_walkway_ok = optional_walkway_ok and level.tile_at(cell_x, 25) == "="
	ok(optional_walkway_ok, "后段单向维护步道提供96px高路，保留下方战斗线")

	print("== 黑暗剖面与语义美术 ==")
	ok(game.quarantine_architecture != null and game.wall_backdrop == null,
			"正式 M01 使用专用语义后景，不误用旧 M02 WallBackdrop")
	ok(game.room_lights == null and game.decor_nodes.is_empty(),
			"不创建按房名路由的旧装饰/灯光")
	ok(game.quarantine_foreground != null, "LDtk 稀疏前景已接到角色上层")
	var art: QuarantineArchitecture = game.quarantine_architecture
	ok(art.room_count == 10 and art.landmark_count == 10,
			"十房间与十类建筑语义全部登记",
			"rooms=%d landmarks=%d" % [art.room_count, art.landmark_count])
	ok(DATA.SEMANTIC_IDS["Architecture"].has("ShaftStatusDisplay")
			and not DATA.SEMANTIC_IDS["Architecture"].has("CoolantPipeBank")
			and art.shaft_display_dynamic_channel_count == 3,
			"维护井使用动态状态大屏：扫描线、波形和诊断仪表三路动画")
	ok(art.light_count == DATA.SEMANTIC_LAYERS["Lights"].size(),
			"灯具数量来自 LDtk Lights 语义层", str(art.light_count))
	ok(art.foreground_cell_count > 0, "近景梁/管/链/格栅有明确预算")
	ok(art.has_visible_backdrop_at(5.5 * 32, 22.5 * 32), "可玩房间内有墙面")
	ok(not art.has_visible_backdrop_at(40.5 * 32, 5.5 * 32),
			"不可达房间外维持黑暗包裹")
	ok(art.outside_color == Color("#05070b"), "剖面虚空为固定近黑色")
	ok(art.stair_semantics_valid and art.stair_semantic_cell_count == 30,
			"OpenStair 三十格斜线语义与三段楼梯高度场精确一致")
	ok(art.stair_visual_count == 3 and art.stair_tread_count == 30
			and art.stair_stringer_count == 6,
			"三段正式梯共有三十块踏板和六条承重斜梁")
	ok(art.stair_shadow_wedge_count == 3
			and art.stair_shadow_transition_band_count == 12
			and art.service_void_transition_band_count == 4
			and art.room_boundary_transition_band_count == 4,
			"梯下、维护暗区与地图外沿均使用四级像素过渡")
	# 取中段踏板：角色身体上方不吃黑，穿过三档过渡后才进入全黑核心。
	var shadow_x := (52.0 + 5.5) * 32.0
	var shadow_edge_y := 28.0 * 32.0 + 6.0 - 5.5 * 16.0
	var darkness_samples := PackedFloat32Array([
		art.stair_darkness_alpha_at(Vector2(shadow_x, shadow_edge_y - 40.0)),
		art.stair_darkness_alpha_at(Vector2(shadow_x, shadow_edge_y - 27.0)),
		art.stair_darkness_alpha_at(Vector2(shadow_x, shadow_edge_y - 17.0)),
		art.stair_darkness_alpha_at(Vector2(shadow_x, shadow_edge_y - 6.0)),
		art.stair_darkness_alpha_at(Vector2(shadow_x, shadow_edge_y + 8.0)),
	])
	var darkness_monotonic := darkness_samples[0] < darkness_samples[1] \
			and darkness_samples[1] < darkness_samples[2] \
			and darkness_samples[2] < darkness_samples[3] \
			and darkness_samples[3] < darkness_samples[4]
	ok(darkness_monotonic and darkness_samples[0] == 0.0
			and darkness_samples[4] == 1.0,
			"梯下黑暗在 32px 内单调过渡，不突兀", str(darkness_samples))
	var middle_surface_y := 28.0 * 32.0 - 6.0 * 16.0
	ok(art.stair_darkness_alpha_at(Vector2(shadow_x, middle_surface_y - 26.0)) == 0.0,
			"梯面上方 26px 已离开后景过渡带")
	var landing_x := (62.0 + 0.5) * 32.0
	var landing_edge_y := 28.0 * 32.0 - 10.0 * 16.0 + 6.0
	ok(art.stair_darkness_alpha_at(Vector2(landing_x, landing_edge_y + 8.0)) == 1.0
			and art.stair_darkness_alpha_at(Vector2(landing_x, landing_edge_y - 40.0)) == 0.0,
			"高端黑楔收进平台下方，与不可达暗区连续衔接")
	ok(art.get_index() < level.get_index() and level.get_index() < game.player.get_index()
			and art.z_index <= level.z_index and art.z_index <= game.player.z_index,
			"梯下黑暗依次位于楼板和角色后方，保留跳穿可读性")
	# 独立构造向左升镜像，不改变正式地图；同时覆盖左侧接口和暗部收口。
	var mirror_level := CorridorLevel.new()
	mirror_level.stairs = [{"left_c": 52, "bottom_row": 28, "steps": 10, "rise_dir": -1}]
	var mirror_arch_cells: Array = []
	for i in range(10):
		var mirror_rank := 10 - i
		var mirror_row := floori((28.0 * 32.0 - mirror_rank * 16.0) / 32.0)
		mirror_arch_cells.append([52 + i, mirror_row, 6])
	var mirror_art := QuarantineArchitecture.new()
	mirror_art.setup(mirror_level, {"Architecture": mirror_arch_cells},
			{"Architecture": {"OpenStair": 6}})
	var mirror_high_edge_y := 28.0 * 32.0 - 10.0 * 16.0 + 6.0
	ok(mirror_art.stair_semantics_valid
			and mirror_art.stair_darkness_alpha_at(
					Vector2((52.0 - 0.5) * 32.0, mirror_high_edge_y + 8.0)) == 1.0,
			"向左升镜像的踏板语义与高端暗部衔接保持对称")
	ok(mirror_level._quarantine_stair_tile_index("=", 51, 23) == 4
			and mirror_level._quarantine_stair_tile_index("=", 62, 23) == -1
			and mirror_level._quarantine_stair_tile_index("#", 52, 28) == 10
			and mirror_level._quarantine_stair_tile_index("#", 62, 28) == 10,
			"向左升楼梯镜像使用左侧无端帽接口和同一薄地板投影")
	mirror_art.free()
	mirror_level.free()
	ok(CorridorLevel.active_tileset_path.ends_with("tileset_quarantine.png"),
			"正式关卡使用独立高质感地板图集")
	var atlas_source: TileSetAtlasSource = level.tilemap.tile_set.get_source(0)
	ok(atlas_source.has_tile(Vector2i(10, 0)), "检疫图集已注册梯下薄地板 tile 10")
	var stair_floor_skin_ok := true
	for cell_x in range(52, 63):
		stair_floor_skin_ok = stair_floor_skin_ok \
				and level.tile_at(cell_x, 28) == "#" \
				and level._tile_coord("#", cell_x, 28) == Vector2i(10, 0)
	ok(stair_floor_skin_ok
			and level.tile_at(62, 23) == "="
			and level._tile_coord("=", 62, 23) == Vector2i(4, 0),
			"楼梯下方只换薄梁皮肤，上端接口去掉多余端帽")
	ok(level.tile_at(51, 28) == "#"
			and level._tile_coord("#", 51, 28) == Vector2i(1, 0)
			and level.tile_at(63, 23) == "#"
			and level._tile_coord("#", 63, 23) == Vector2i(1, 0),
			"楼梯范围外的上下层实体地板保持原材质")
	ok(level._tile_coord("#", 0, level.map_h - 1) == Vector2i(2, 0)
			and level._tile_coord("#", 15, 11) == Vector2i(1, 0),
			"世界外壳压黑、可玩房间顶沿仍保留材质")

	print("== 清场闸门与主线流转 ==")
	ok(CorridorLevel.active_exit_requires_boss and game._exit_gated(),
			"全关敌人未清时出口锁定")
	ok(game.red_boss == null, "第一关不额外刷 Boss")
	ok(CorridorLevel.active_next_scene.is_empty(),
			"终点不再自动切到尚未重做的旧 M02")
	for minion: Node2D in game.minions:
		minion.take_hit(minion.position.x, 1)
	for i in range(4):
		await physics_frame
	ok(not game._exit_gated(), "二十敌全灭后出口解锁")

	boot.free()
	for i in range(3):
		await process_frame
	print("== 退出还原 ==")
	ok(CorridorLevel.active_map.is_empty() and CorridorLevel.active_rooms.is_empty()
			and CorridorLevel.active_stairs.is_empty(), "地图/房间/楼梯恢复默认")
	ok(CorridorLevel.active_art_style.is_empty()
			and CorridorLevel.active_semantic_layers.is_empty()
			and CorridorLevel.active_semantic_ids.is_empty(), "专用美术语义恢复默认")
	ok(CorridorLevel.active_tileset_path.is_empty()
			and not CorridorLevel.active_exit_requires_boss
			and CorridorLevel.active_next_scene.is_empty(), "图集/出口/转场恢复默认")

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _reset_statics() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_stairs = []
	CorridorLevel.active_art_style = ""
	CorridorLevel.active_semantic_layers = {}
	CorridorLevel.active_semantic_ids = {}
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_title = ""
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_campaign_mode = false
	CorridorLevel.active_restart_scene = ""
	GameBackground.active_cfg = []
