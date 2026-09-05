extends SceneTree
## 史莱姆爆裂测试：液滴粒子必须沿受力方向喷出，并在飞行后请求墙面油漆。

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
	print("== SlimeBurst direction and lifecycle ==")
	var scene_path := "res://scenes/fx/slime_burst.tscn"
	if not ResourceLoader.exists(scene_path):
		ok(false, "存在可复用的史莱姆爆裂场景", scene_path)
		_finish()
		return

	var packed := load(scene_path) as PackedScene
	var burst = packed.instantiate()
	get_root().add_child(burst)
	await process_frame

	var paint_events: Array = []
	var finish_events: Array = []
	burst.paint_requested.connect(func(pos: Vector2, direction: Vector2, power: float, seed: int) -> void:
		paint_events.append([pos, direction, power, seed]))
	burst.finished.connect(func(effect) -> void: finish_events.append(effect))
	var force := Vector2(3.0, -1.0).normalized()
	burst.position = Vector2(240.4, 180.6)
	burst.play(1.0, force, 6703)
	var stats: Dictionary = burst.debug_stats()

	ok(stats["layers"] == 3, "三层液体粒子", str(stats))
	ok(stats["particles"] == 74, "每次爆裂共 74 个液体粒子", str(stats))
	ok(stats["direction"].dot(force) > 0.999, "记录受力方向", str(stats["direction"]))
	var jets := burst.get_node("LiquidJets") as CPUParticles2D
	ok(jets.direction.dot(force) > 0.999, "高速液柱沿受力方向喷射", str(jets.direction))

	await create_timer(0.18).timeout
	ok(paint_events.size() == 1, "液滴飞行后只请求一次墙面涂料", str(paint_events.size()))
	if paint_events.size() == 1:
		ok(paint_events[0][1].dot(force) > 0.999, "墙面涂料继承同一受力方向")
	await create_timer(0.90).timeout
	ok(finish_events.size() == 1, "真实 SceneTree 生命周期只完成一次", str(finish_events.size()))
	ok(not burst.active and not burst.visible, "完成后停用等待对象池复用")
	burst.queue_free()
	await process_frame

	_finish()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
