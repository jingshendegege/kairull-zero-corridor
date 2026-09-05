extends SceneTree
## 扩展“协议检疫站”后半程美术合同；只验证语义接线与结构预算，不把无头绘制当视觉验收。
## 跑法：Godot --headless --path godot --script scripts/test_extended_art.gd

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")

var _pass := 0
var _fail := 0


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var art: QuarantineArchitecture = game.quarantine_architecture
	game.set_physics_process(false)
	# 尽早断开 BGM；若直到退出前才 stop，Dummy 音频驱动来不及释放 MP3 playback。
	_cleanup_audio(game)
	for i in range(3):
		await process_frame

	print("== 后半程房间与地标预算 ==")
	ok(game.level.map_w == 280 and game.level.map_h == 30,
			"扩展地图为 280×30", "%dx%d" % [game.level.map_w, game.level.map_h])
	ok(game.level.rooms.size() == 10, "十个正式房间已进入美术层", str(game.level.rooms.size()))
	ok(art.extended_profile_count == 7, "七个后半程 profile 均被识别",
			str(art.extended_profile_count))
	ok(art.extended_landmark_count == 7, "七个后半程主地标均有房内语义",
			str(art.extended_landmark_count))
	ok(art.rear_palette_count == 7, "七区墙色保持可辨而不复用一块灰墙",
			str(art.rear_palette_count))
	ok(art.archive_branch_lane_count == 2, "档案机有上下两条功能分流轨",
			str(art.archive_branch_lane_count))
	ok(art.service_bench_visual_count == 2, "两处检查点各有独立墙挂设备",
			str(art.service_bench_visual_count))
	ok(art.coolant_tank_visual_count == 3, "冷却下降区由三只重型储液罐主导",
			str(art.coolant_tank_visual_count))
	ok(art.freight_hoist_visual_count == 2, "货运交火区有两台收货吊秤",
			str(art.freight_hoist_visual_count))
	ok(art.containment_ring_visual_count == 1, "终战区有唯一隔离核心环",
			str(art.containment_ring_visual_count))

	print("== 重复语义按房间裁切 ==")
	var ids: Dictionary = DATA.SEMANTIC_IDS["Architecture"]
	var expected_landmarks := {
		"archive_sorter": "ArchiveSorter",
		"service_bay": "ServiceBench",
		"coolant_reservoir": "CoolantReservoir",
		"freight_crossfire": "FreightGantry",
		"relay_service": "ServiceBench",
		"containment_core": "ContainmentCore",
		"egress_lock": "ExitSeal",
	}
	var scoped_ok := true
	var scoped_service_bounds: Array[Rect2i] = []
	for room: Dictionary in game.level.rooms:
		var profile := String(room.get("decor_profile", ""))
		if not expected_landmarks.has(profile):
			continue
		var room_rect: Rect2i = room["rect"]
		var landmark_name: String = expected_landmarks[profile]
		var bounds := art._value_bounds_in_rect(
				"Architecture", int(ids.get(landmark_name, -1)), room_rect)
		scoped_ok = scoped_ok and bounds.size != Vector2i.ZERO \
				and room_rect.encloses(bounds)
		if landmark_name == "ServiceBench":
			scoped_service_bounds.append(bounds)
	ok(scoped_ok, "所有后段地标边界均收在所属房间内")
	ok(scoped_service_bounds.size() == 2
			and scoped_service_bounds[0].end.x < scoped_service_bounds[1].position.x,
			"复用 ServiceBench 不会跨 100 格连成巨型矩形", str(scoped_service_bounds))

	print("== 检查点净空与楼梯扩展 ==")
	var checkpoint_cells := [Vector2i(111, 22), Vector2i(215, 22)]
	var checkpoints_clear := true
	for cell in checkpoint_cells:
		checkpoints_clear = checkpoints_clear \
				and not _layer_has_cell(DATA.SEMANTIC_LAYERS["Architecture"], cell) \
				and not _layer_has_cell(DATA.SEMANTIC_LAYERS["ForegroundTiles"], cell)
	ok(checkpoints_clear, "两处真实灯塔脚下无建筑或近景假障碍")
	ok(art.stair_semantics_valid and art.stair_visual_count == 3,
			"三段楼梯全部由同一份 metadata 驱动绘制",
			"valid=%s visuals=%d" % [art.stair_semantics_valid, art.stair_visual_count])
	ok(art.stair_tread_count == 30 and art.stair_stringer_count == 6
			and art.stair_shadow_transition_band_count == 12,
			"三梯共有30踏板、6承重梁、12级阴影带",
			"treads=%d beams=%d bands=%d" % [art.stair_tread_count,
					art.stair_stringer_count, art.stair_shadow_transition_band_count])

	print("== 墙面明度与信号克制 ==")
	var rear_profiles := ["archive_sorter", "service_bay", "coolant_reservoir",
			"freight_crossfire", "relay_service", "containment_core", "egress_lock"]
	var luminance_ok := true
	for profile in rear_profiles:
		var color := art._profile_color(profile)
		var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
		luminance_ok = luminance_ok and luminance >= 0.18 and luminance <= 0.36
	ok(luminance_ok, "后段墙面维持18%–36%中暗明度，可承接彩色血迹")
	ok(art.light_count > 0 and art.light_count <= 40,
			"语义灯总量受控，不铺满霓虹", str(art.light_count))

	_cleanup_audio(game)
	boot.free()
	# MP3 playback 对象需跨数帧归还 AudioServer；单帧退出会产生测试自身的假泄漏。
	for i in range(3):
		await process_frame
	await create_timer(0.15).timeout
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _layer_has_cell(triples: Array, cell: Vector2i) -> bool:
	for raw in triples:
		if int(raw[0]) == cell.x and int(raw[1]) == cell.y:
			return true
	return false


func _cleanup_audio(game: Node2D) -> void:
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
