extends SceneTree
## 世界惯性视觉合同：根节点实际移动，本体不二次抬升，阴影投地，倒带仅回读姿态。

const TIMELINE := preload("res://scripts/attempt_timeline.gd")
var passed := 0
var failed := 0

class TimelinePlayer extends Node2D:
	var ground_y := 0.0
	var ground_valid := false
	var last_pose: Dictionary = {}
	func capture_timeline_pose() -> Dictionary:
		return {"position": position, "ground_y": ground_y, "ground_valid": ground_valid}
	func apply_timeline_pose(pose: Dictionary) -> void:
		last_pose = pose.duplicate(true)
		position = pose["position"]
		ground_y = float(pose.get("ground_y", 0.0))
		ground_valid = bool(pose.get("ground_valid", false))

class TimelineHost extends Node2D:
	var minions: Array[Node2D] = []
	var props: Array[Node2D] = []
	var player := TimelinePlayer.new()
	var cam := Camera2D.new()
	var cam_tl := Vector2.ZERO
	var enemy_bullets: Array[Dictionary] = []
	var paint_layer := SlimePaintLayer.new()
	var fx_layer := Node2D.new()
	func _init() -> void:
		add_child(player)
		add_child(cam)
		add_child(paint_layer)
		add_child(fx_layer)

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func _run() -> void:
	var host := TimelineHost.new()
	root.add_child(host)
	host.process_mode = Node.PROCESS_MODE_DISABLED
	for source in ["res://scripts/grunt.gd", "res://scripts/freight_inspector.gd"]:
		var enemy: Node2D = load(source).new()
		host.add_child(enemy)
		host.minions.append(enemy)
		_test_actor(enemy, source.get_file(), host)
	_test_timeline(host)
	host.free()
	await process_frame
	print("DEATH_INERTIA_VISUAL_RESULT: %s (%d passed, %d failed)" % [
			"PASS" if failed == 0 else "FAIL", passed, failed])
	quit(0 if failed == 0 else 1)

func _test_actor(enemy: Node2D, label: String, host: Node2D) -> void:
	enemy.position = Vector2(240, 320)
	enemy.take_hit(100.0)
	var baseline: Vector2 = enemy._sprite.position
	var base_shadow_scale: Vector2 = enemy._shadow.scale
	var body: Rect2 = enemy.body_rect()
	enemy.set_corpse_lift(20.0)
	enemy.position += Vector2(120, -30)
	enemy.set_corpse_ground(320.0)
	check(enemy.corpse_lift == 0.0 and enemy.corpse_ground_projected and enemy.corpse_ground_valid,
			label + " 惯性接入清掉旧视觉抬升")
	check(enemy.position == Vector2(360, 290) and enemy.body_rect().position == body.position + Vector2(120, -30),
			label + " 根节点和身体判定真实前移120并离地30")
	check(enemy._sprite.position == baseline and enemy._outline.position == baseline and enemy._rim.position == baseline,
			label + " 三层本体仍用原基线，不二次上抬")
	check(is_equal_approx(enemy._shadow.global_position.y, 319.0) and enemy._shadow.visible,
			label + " 阴影留在真实地面")
	check(enemy._shadow.scale.x < base_shadow_scale.x,
			label + " 离地阴影轻缩")
	check(enemy.wound_anchor_world() == enemy.body_rect().get_center(),
			label + " 伤口随真实身体中心移动")
	var wound := WoundBloodSpray.new()
	host.add_child(wound)
	wound.global_position = enemy.wound_anchor_world()
	wound.play(1.0, Vector2.RIGHT, 29051, true, Color("#ff4fa3"), enemy)
	var old_drops := wound.debug_droplet_world_positions()
	enemy.position += Vector2(20, -5)
	enemy.set_corpse_ground(320.0)
	wound._process(0.0)
	check(wound.global_position == enemy.wound_anchor_world().round(),
			label + " 飞行中的续喷口继续跟随")
	check(wound.debug_droplet_world_positions() == old_drops,
			label + " 已喷出的血滴不会被整束带走")
	wound.stop()
	wound.free()
	for i in 8:
		enemy._sync_sprite()
	check(enemy._sprite.position == baseline and is_equal_approx(enemy._shadow.global_position.y, 319.0),
			label + " 重复同步不漂移")
	enemy.set_corpse_ground(0.0, false)
	check(not enemy._shadow.visible and enemy._sprite.position == baseline,
			label + " 无承接地面仅隐藏阴影，不隐藏尸体")
	enemy.position.y = 320.0
	enemy.set_corpse_ground(320.0)
	check(enemy._shadow.position == Vector2(0, -1) and enemy._shadow.scale == base_shadow_scale,
			label + " 落地影子恢复原尺度和接触基线")
	enemy.set_corpse_lift(12.0)
	check(not enemy.corpse_ground_projected and enemy._sprite.position == baseline - Vector2(0, 12),
			label + " 旧抬升API仍可独立使用")
	enemy.set_corpse_ground(360.0)
	enemy.dead = false
	enemy._set_state("idle")
	enemy._sync_sprite()
	check(not enemy.corpse_ground_projected and not enemy.corpse_ground_valid and enemy.corpse_lift == 0.0
			and enemy._shadow.visible and enemy._shadow.position == Vector2(0, -1),
			label + " 恢复活体清除死亡投影")
	enemy.set_corpse_ground(999.0)
	enemy.take_hit(100.0)
	check(not enemy.corpse_ground_projected and not enemy.corpse_ground_valid,
			label + " 新一次致死不能继承旧投影")

func _test_timeline(host: TimelineHost) -> void:
	var timeline := TIMELINE.new()
	for enemy: Node2D in host.minions:
		enemy.position = Vector2(240, 290)
		enemy.set_corpse_ground(320.0)
	host.player.position = Vector2(50, 300)
	host.player.ground_y = 320.0
	host.player.ground_valid = true
	timeline.record(host, 0.0, true)
	for enemy: Node2D in host.minions:
		enemy.position = Vector2(400, 270)
		enemy.set_corpse_ground(340.0)
	host.player.position = Vector2(150, 260)
	host.player.ground_y = 340.0
	timeline.record(host, 1.0, true)
	check(timeline.frames[0]["enemies"][0]["corpse_ground_y"] == 320.0
			and timeline.frames[1]["enemies"][1]["corpse_ground_projected"], "快照记录投地Y与模式")
	var effect_count := host.fx_layer.get_child_count()
	var blood_serial: int = host.paint_layer.blood_wall_manager._serial
	timeline.apply_rewind(host, sqrt(0.5))
	for enemy: Node2D in host.minions:
		check(enemy.position == Vector2(320, 280) and enemy.corpse_ground_y == 330.0 and enemy.corpse_lift == 0.0,
				"敌人位置与地面高度同时间插值")
		check(is_equal_approx(enemy._shadow.global_position.y, 329.0), "倒带阴影仍投在插值地面上")
	check(host.player.position == Vector2(100, 280) and host.player.ground_y == 330.0,
			"主角位置与投影地面同时间插值")
	timeline.apply_rewind(host, 0.0)
	check(host.minions[0].position == Vector2(400, 270) and host.minions[0].corpse_ground_y == 340.0,
			"末帧位置与投影精确恢复")
	check(effect_count == host.fx_layer.get_child_count() and blood_serial == host.paint_layer.blood_wall_manager._serial,
			"倒带不重发落尘血迹")
	# 无效地面不参与高度插值，不能制造一条从地面通向0的假阴影。
	for actor: Dictionary in timeline.frames[0]["enemies"]:
		actor["corpse_ground_valid"] = false
		actor["corpse_ground_y"] = 0.0
	timeline.frames[0]["player"]["ground_valid"] = false
	timeline.frames[0]["player"]["ground_y"] = 0.0
	timeline.apply_rewind(host, sqrt(0.25))
	check(host.minions[0].corpse_ground_y == 340.0 and host.player.ground_y == 340.0,
			"跨无效地面样本时使用最近有效姿态而非虚假插值")
	timeline.apply_rewind(host, sqrt(0.75))
	check(not host.minions[0]._shadow.visible and not host.player.ground_valid,
			"无承接地面样本保持阴影隐藏")
	for actor: Dictionary in timeline.frames[0]["enemies"]:
		actor["dead"] = false
		actor["state"] = "idle"
	timeline.apply_rewind(host, 1.0)
	check(not host.minions[0].corpse_ground_projected and host.minions[0]._shadow.visible,
			"回到生前清死亡投影并恢复站立阴影")
	for snapshot: Dictionary in timeline.frames:
		for actor: Dictionary in snapshot["enemies"]:
			actor.erase("corpse_ground_y")
			actor.erase("corpse_ground_valid")
			actor.erase("corpse_ground_projected")
	timeline.apply_rewind(host, 0.0)
	check(not host.minions[0].corpse_ground_projected and host.minions[0]._shadow.visible,
			"缺少新字段的旧录像安全回退")
