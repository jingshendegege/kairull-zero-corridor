extends SceneTree
## 尸体视觉适配合同：抬升不动碰撞，血口跟随，倒带不触发新的落地特效。

const TIMELINE := preload("res://scripts/attempt_timeline.gd")
var passed := 0
var failed := 0

class TimelinePlayer extends Node2D:
	func capture_timeline_pose() -> Dictionary:
		return {"position": position}
	func apply_timeline_pose(pose: Dictionary) -> void:
		position = pose["position"]

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
		enemy.position = Vector2(240.0, 320.0)
		_test_actor(enemy, source.get_file())
		_test_wound(enemy, host)
	_test_timeline(host)
	host.free()
	await process_frame
	print("CORPSE_VISUAL_ADAPTER_RESULT: %s (%d passed, %d failed)" % [
			"PASS" if failed == 0 else "FAIL", passed, failed])
	quit(0 if failed == 0 else 1)

func _test_actor(enemy: Node2D, label: String) -> void:
	var standing_body: Rect2 = enemy.body_rect()
	var standing_sprite: Vector2 = enemy._sprite.position
	var standing_shadow: Vector2 = enemy._shadow.scale
	var standing_alpha: float = enemy._shadow.modulate.a
	check(enemy.take_hit(180.0) and enemy.dead and enemy.frame == 0,
			label + " 致死立即结算且死亡帧仍从零开始")
	var death_sprite: Vector2 = enemy._sprite.position
	var ground_shadow: Vector2 = enemy._shadow.position
	var death_shadow: Vector2 = enemy._shadow.scale
	var death_alpha: float = enemy._shadow.modulate.a
	enemy.set_corpse_lift(-6.0)
	check(enemy.corpse_lift == 0.0 and enemy._sprite.position == death_sprite,
			label + " 负高度钳零且原死亡视觉不变")
	enemy.set_corpse_lift(26.0)
	check(enemy.position == Vector2(240, 320) and enemy.body_rect() == standing_body,
			label + " 视觉抬升不改变根位置和身体判定")
	check(enemy._sprite.position == death_sprite - Vector2(0, 26),
			label + " 本体精确抬高26像素")
	check(enemy._sprite.position == enemy._outline.position
			and enemy._sprite.position == enemy._rim.position,
			label + " 本体描边轮廓光共享偏移")
	check(enemy._shadow.position == ground_shadow and enemy._shadow.scale.x < death_shadow.x
			and enemy._shadow.modulate.a < death_alpha,
			label + " 阴影留在地面并轻缩淡")
	check(enemy.wound_anchor_world() == standing_body.get_center() - Vector2(0, 26),
			label + " 伤口锚点跟随视觉高度")
	for i in 8:
		enemy._sync_sprite()
	check(enemy._sprite.position == death_sprite - Vector2(0, 26) and enemy.frame == 0,
			label + " 重复同步没有累计漂移或推进动画")
	enemy.set_corpse_lift(0.0)
	check(enemy._sprite.position == death_sprite and enemy._shadow.scale == death_shadow
			and is_equal_approx(enemy._shadow.modulate.a, death_alpha),
			label + " 落回零高度完全恢复原视觉")
	enemy.set_corpse_lift(26.0)
	enemy.dead = false
	enemy._set_state("idle")
	enemy._sync_sprite()
	check(enemy.corpse_lift == 0.0 and enemy._sprite.position == standing_sprite
			and enemy._shadow.scale == standing_shadow
			and is_equal_approx(enemy._shadow.modulate.a, standing_alpha),
			label + " 恢复活体清理高度并恢复原站姿")
	enemy.set_corpse_lift(15.0)
	check(enemy.wound_anchor_world() == standing_body.get_center(),
			label + " 活体接口忽略尸体高度")
	enemy.take_hit(180.0)
	check(enemy.corpse_lift == 0.0, label + " 新一轮死亡清零残留视觉高度")

func _test_wound(enemy: Node2D, host: TimelineHost) -> void:
	var wound := WoundBloodSpray.new()
	host.fx_layer.add_child(wound)
	wound.global_position = enemy.body_rect().get_center()
	wound.play(1.0, Vector2.RIGHT, 1905, true, Color("#ff4fa3"), enemy)
	var drops: Array[Vector2] = wound.debug_droplet_world_positions()
	enemy.set_corpse_lift(20.0)
	wound._process(0.0)
	check(wound.global_position == enemy.wound_anchor_world().round(),
			"伤口喷口优先采用视觉锚点")
	check(wound.debug_droplet_world_positions() == drops,
			"身体上抬不会拖动已经发射的世界血滴")
	wound.stop()
	wound.free()

func _test_timeline(host: TimelineHost) -> void:
	var timeline := TIMELINE.new()
	for enemy: Node2D in host.minions:
		enemy.set_corpse_lift(10.0)
	timeline.record(host, 0.0, true)
	for enemy: Node2D in host.minions:
		enemy.position.x += 100.0
		enemy.set_corpse_lift(30.0)
	timeline.record(host, 1.0, true)
	check(float(timeline.frames[0]["enemies"][0]["corpse_lift"]) == 10.0
			and float(timeline.frames[1]["enemies"][1]["corpse_lift"]) == 30.0,
			"快照分别记录两类敌人的独立尸体高度")
	var effects_before := host.fx_layer.get_child_count()
	var blood_before: int = host.paint_layer.blood_wall_manager._serial
	timeline.apply_rewind(host, sqrt(0.5))
	for enemy: Node2D in host.minions:
		check(is_equal_approx(enemy.corpse_lift, 20.0) and enemy.position == Vector2(290, 320),
				"倒带高度与位置连续插值，不依赖敌人动画帧")
	timeline.apply_rewind(host, 0.0)
	check(host.minions[0].corpse_lift == 30.0 and host.minions[1].corpse_lift == 30.0,
			"倒带零进度还原最后一帧尸体高度")
	check(host.fx_layer.get_child_count() == effects_before
			and host.paint_layer.blood_wall_manager._serial == blood_before,
			"姿态回放不生成灰尘血迹或额外特效节点")
	# 生死切换取最近离散采样；即使附近的死亡高度非零，生前也必须站稳。
	for actor: Dictionary in timeline.frames[0]["enemies"]:
		actor["dead"] = false
		actor["state"] = "idle"
		actor["corpse_lift"] = 0.0
	timeline.apply_rewind(host, sqrt(0.75))
	for enemy: Node2D in host.minions:
		check(not enemy.dead and enemy.corpse_lift == 0.0
				and enemy.wound_anchor_world() == enemy.body_rect().get_center(),
				"回到生前时忽略相邻死帧高度，站姿与喷口不悬空")
	# 旧录像没有此新增字段时仍可回放，不强求所有敌人实现抬升接口。
	for snapshot: Dictionary in timeline.frames:
		for actor: Dictionary in snapshot["enemies"]:
			actor.erase("corpse_lift")
	timeline.apply_rewind(host, 0.0)
	check(host.minions[0].corpse_lift == 0.0 and host.minions[1].corpse_lift == 0.0,
			"兼容缺少尸体高度字段的既有录像")
