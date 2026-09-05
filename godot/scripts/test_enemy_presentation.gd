extends SceneTree
## 表现与伤害时钟分离：慢呼吸/跑步，攻击窗口不变；彩血保持数量与独立粒子上限。

const INSPECTOR := preload("res://scripts/freight_inspector.gd")
var passed := 0
var failed := 0

func ok(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _init() -> void:
	call_deferred("_run")

func _frame(enemy: Node2D, animation: String) -> int:
	if enemy is GruntGunner:
		return enemy._animation_frame(animation)
	return enemy._anim_frame(enemy._anims[animation])

func _run() -> void:
	var gunner := GruntGunner.new()
	var inspector: Node2D = INSPECTOR.new()
	get_root().add_child(gunner)
	get_root().add_child(inspector)
	for enemy: Node2D in [gunner, inspector]:
		var label := "枪手" if enemy == gunner else "巡检员"
		enemy.state = "idle"
		enemy._anim_clock = 0.49
		ok(_frame(enemy, "idle") == 0, label + "呼吸首帧至少停留约0.5秒")
		enemy._anim_clock = 0.51
		ok(_frame(enemy, "idle") == 1, label + "呼吸以2fps前进")
		var count: int = enemy._anims["idle"]["frames"]
		enemy._anim_clock = (float(count) + 0.01) / 2.0
		ok(_frame(enemy, "idle") == count - 2, label + "呼吸末帧平顺往返不跳首帧")
		enemy.state = "run"
		enemy._anim_clock = 0.16
		ok(_frame(enemy, "run") == 0, label + "跑步首帧不会12fps快速跳动")
		enemy._anim_clock = 0.17
		ok(_frame(enemy, "run") == 1, label + "跑步6fps")
		enemy.state = "alert"
		var poses: Dictionary = {}
		for tick in enemy.ALERT_TICKS:
			enemy.frame = tick
			poses[_frame(enemy, "alert")] = true
		ok(poses.size() == 2 and poses.has(0) and poses.has(int(enemy._anims["alert"]["frames"]) - 1),
			label + "警戒延长起势/就绪两姿停留")
		ok(enemy.ALERT_TICKS == 18, label + "索敌逻辑时长不变")
		enemy.state = "dead"
		enemy.frame = 18
		ok(_frame(enemy, "death") == 2 and enemy.DEATH_TICKS == 54, label + "倒地六帧放慢到0.9秒")
		enemy.frame = 90
		ok(_frame(enemy, "death") == 5, label + "倒地末帧停住不循环")
		ok(enemy._sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, label + "保持nearest")
	inspector.state = "attack"
	var aim_poses := {}
	gunner.state = "aim"
	for tick in gunner.AIM_TICKS:
		gunner.frame = tick
		aim_poses[_frame(gunner, "aim")] = true
	ok(aim_poses.size() == 2, "枪手举枪减少为两个长停留姿势，开火窗口不改")
	var recover_poses := {}
	inspector.state = "recover"
	for tick in inspector.RECOVER_TICKS:
		inspector.frame = tick
		recover_poses[_frame(inspector, "recover")] = true
	ok(recover_poses.size() == 2, "巡检员收招减少切帧，不延长逻辑后摇")
	inspector.state = "attack"
	inspector.dead = false
	for tick in [1, 2, 6, 7]:
		inspector.frame = tick
		ok(inspector.attack_active() == (tick >= 2 and tick <= 6), "巡检员有效窗原样 tick%d" % tick)
	ok(inspector.WINDUP_TICKS == 26 and inspector.ATTACK_TICKS == 8 and inspector.RECOVER_TICKS == 33,
		"近战前摇/攻击/后摇不变")
	ok(gunner.AIM_TICKS == 27 and gunner.FIRE_SHOT_TICK == 5 and gunner.FIRE_TICKS == 17,
		"枪手瞄准和出弹帧不变")
	inspector.take_hit(0.0)
	inspector.hitstop = 0.30
	for i in 10:
		inspector.step(1.0 / 60.0)
	ok(inspector.frame == 10 and _frame(inspector, "death") > 0,
		"巡检员击退锁AI时尸体仍继续倒下")
	var wound := WoundBloodSpray.new()
	get_root().add_child(wound)
	wound.play(1.0, Vector2.RIGHT, 401, true, Color.CYAN)
	ok(wound.droplet_alpha(0.4) == 1.0, "小血滴前段保留实色")
	ok(wound.droplet_alpha(0.65) > wound.droplet_alpha(0.85) and wound.droplet_alpha(1.0) == 0.0,
		"小血滴后段连续淡出")
	for i in 100:
		wound._emit_droplet()
	ok(wound.debug_stats()["live_droplets"] == 64, "单伤口实例硬上限64滴")
	wound.stop()
	ok(not wound.is_processing(), "血滴回池停用process")
	var burst := SlimeRibbonBurst.new()
	get_root().add_child(burst)
	burst.play(1.0, Vector2(1, -0.2), 403, false, true)
	ok(burst.debug_stats()["streams"] == 5 and burst.debug_stats()["droplets"] == 11,
		"优化轮廓不减少5束11滴主喷血量")
	var stamps: Array = []
	burst.paint_requested.connect(func(_p, _d, _w, _s, _k): stamps.append(true))
	burst._process(0.14)
	ok(stamps.is_empty(), "墙血快照不早于原时刻")
	burst._process(0.02)
	burst._process(0.2)
	ok(stamps.size() == 1, "0.15秒墙血快照仅一次")
	gunner.free()
	inspector.free()
	wound.free()
	burst.free()
	await process_frame
	print("TEST_RESULT: %s (%d passed, %d failed)" % ["PASS" if failed == 0 else "FAIL", passed, failed])
	quit(0 if failed == 0 else 1)
