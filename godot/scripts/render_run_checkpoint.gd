extends SceneTree
## 三关唯一检查点真窗口巡检；前置敌人清除为明确fixture，不宣称真实战斗打通。
## 激活仍经过宿主_update_campaign_progress和Session快照接口，不直接改beacon.activated。
const SESSION := preload("res://scripts/run_session.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/single-crt-checkpoint-20260906"
const SCENES := ["m01_protocol_quarantine", "m04_chrono_freight", "m05_vertical_freight"]
const EXPECTED_CLEARS := [10, 22, 24]
var checks := 0
var failed := 0
var records: Array = []


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)


func _place(game: Node2D, at: Vector2) -> void:
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
	game._sync_temporal_projection()


func _shot(stem: String) -> void:
	for _index in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(1360, 765), stem + "真窗尺寸正确")
	var path := OUT.path_join(stem + ".png")
	check(image.save_png(path) == OK, stem + "截图成功")
	print("RUN_CHECKPOINT_SHOT ", path)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("检查点外观必须真窗口，拒绝headless截图")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = root.size
	root.title = "Single checkpoint / true-window visual QA"
	DirAccess.make_dir_recursive_absolute(OUT)
	for index in SCENES.size():
		await _review(index)
	var report := FileAccess.open(OUT.path_join("检查点位置-真窗口巡检数据.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failed": failed,
		"display": DisplayServer.get_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"fixture_note": "按生成required_clear_rooms模拟前段已清，不宣称实际战斗通关；激活由生产宿主完成。",
		"checkpoints": records}, "\t"))
	report.close()
	SESSION.reset_for_tests()
	await create_timer(.15).timeout
	print("RUN_CHECKPOINT_RENDER_RESULT: ", checks, " checks, ", failed, " failed")
	quit(0 if failed == 0 and records.size() == 3 else 1)


func _review(index: int) -> void:
	SESSION.begin_run("hard")
	var scene_path: String = "res://scenes/" + SCENES[index] + ".tscn"
	var boot := load(scene_path).instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	var game := boot.get_node("Game") as Node2D
	game.player.auto_input = false
	game.hud.visible = false
	game.action_audio_enabled = false
	game._sfx.clear()
	if game.action_audio != null:
		game.action_audio.stop_all()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	_freeze(boot)
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	var beacon: Node2D = game._checkpoint_beacons[int(config.room_index)]
	var grid_hash := JSON.stringify(game.level.grid).sha256_text()
	var prefix := "检查点-%02d" % (index + 1)
	check(game._checkpoint_beacons.size() == 1, prefix + "只创建唯一运行时终端")
	check(game.player.hp == SESSION.max_health(), prefix + "保持所选困难生命，不擅改难度")
	check(game.level.solid_at(beacon.position.x, beacon.position.y + 1.0), prefix + "终端底座接触静态支撑")
	_place(game, beacon.position + Vector2(-72, 0))
	game._update_campaign_progress(0.0)
	check(not beacon.unlocked and not beacon.activated and SESSION.checkpoint.is_empty(),
		prefix + "前置未清即使站近也保持锁定")
	await _shot(prefix + "-01-前段未清-锁定")
	var cleared := 0
	for enemy: Node2D in game.minions:
		var spawn_cell: Vector2i = enemy.get_meta("spawn_cell", Vector2i(-1, -1))
		var owner: int = game.level.room_at(spawn_cell.x * 32 + 16, spawn_cell.y * 32 + 16)
		if owner in config.required_clear_rooms:
			enemy.dead = true
			enemy.visible = false
			cleared += 1
	check(cleared == EXPECTED_CLEARS[index], prefix + "fixture仅清指定前段%d敌" % EXPECTED_CLEARS[index])
	_place(game, beacon.position + Vector2(-104, 0))
	game._update_campaign_progress(0.0)
	check(beacon.unlocked and not beacon.activated and SESSION.checkpoint.is_empty(), prefix + "前置全清但未靠近时只提示可记录")
	await _shot(prefix + "-02-前段已清-等待靠近")
	_place(game, beacon.position)
	game._update_campaign_progress(0.0)
	check(beacon.activated and game._checkpoint_index == int(config.room_index), prefix + "脚底走近由生产逻辑实际激活")
	check(SESSION.checkpoint_for(scene_path).get("id", "") == config.id, prefix + "真实会话收到正确地图/检查点快照")
	check(SESSION.checkpoint_for(scene_path).get("defeated", []).size() == EXPECTED_CLEARS[index], prefix + "保存仅含前段清敌进度")
	check(game.player.spawn == beacon.position and game.player.on_ground, prefix + "原地记录后仍稳定落脚")
	beacon._process(.71)
	await _shot(prefix + "-03-已记录-主角站终端中心")
	check(JSON.stringify(game.level.grid).sha256_text() == grid_hash, prefix + "三态巡检没有改变地图几何")
	records.append({"scene": scene_path, "id": config.id, "room_index": config.room_index,
		"cell": config.cell, "position": str(beacon.position), "required_clear_rooms": config.required_clear_rooms,
		"cleared_fixture_count": cleared, "activated": beacon.activated, "map_grid_unchanged": true})
	boot.free()
	await create_timer(.2).timeout
