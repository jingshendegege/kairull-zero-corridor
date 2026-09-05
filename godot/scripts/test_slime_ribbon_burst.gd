extends SceneTree
## 连续液幕正式特效：死亡版与弱化受击版的结构/生命周期合同。

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
	print("== SlimeRibbonBurst full / weak ==")
	var scene_path := "res://scenes/fx/slime_ribbon_burst.tscn"
	if not ResourceLoader.exists(scene_path):
		ok(false, "存在正式连续液幕场景", scene_path)
		_finish()
		return
	var packed := load(scene_path) as PackedScene
	var force := Vector2(3.0, -1.0).normalized()

	var death = packed.instantiate()
	get_root().add_child(death)
	await process_frame
	var death_paint_events: Array = []
	var death_finished: Array = []
	death.paint_requested.connect(func(pos: Vector2, direction: Vector2, power: float,
			seed: int, weak: bool) -> void:
		death_paint_events.append([pos, direction, power, seed, weak]))
	death.finished.connect(func(effect) -> void: death_finished.append(effect))
	death.play(1.0, force, 8201, false)
	var death_stats: Dictionary = death.debug_stats()
	ok(death_stats["streams"] == 5, "死亡版五条连续拉丝", str(death_stats))
	ok(death_stats["droplets"] == 11, "死亡版十一颗重液滴", str(death_stats))
	ok(not death_stats["weak"], "死亡版使用完整强度")
	ok(death_stats["direction"].dot(force) > 0.999, "死亡液幕继承受力方向")
	await create_timer(0.20).timeout
	ok(death_paint_events.size() == 1 and not death_paint_events[0][4],
			"死亡液柱飞行后只请求一次完整远端墙漆", str(death_paint_events.size()))
	await create_timer(1.15).timeout
	ok(death_finished.size() == 1 and not death.active, "死亡版完成后回池")
	death.queue_free()
	await process_frame

	var hit = packed.instantiate()
	get_root().add_child(hit)
	await process_frame
	var hit_finished: Array = []
	hit.finished.connect(func(effect) -> void: hit_finished.append(effect))
	hit.play(0.36, force, 8202, true)
	var hit_stats: Dictionary = hit.debug_stats()
	ok(hit_stats["streams"] == 3, "受击版仅三条短液丝", str(hit_stats))
	ok(hit_stats["droplets"] == 4, "受击版仅四颗小液滴", str(hit_stats))
	ok(hit_stats["weak"] and hit_stats["duration"] < death_stats["duration"],
			"受击版持续时间显著短于死亡版", str(hit_stats))
	await create_timer(0.62).timeout
	ok(hit_finished.size() == 1 and not hit.active, "弱化受击版按短生命周期结束")
	hit.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
