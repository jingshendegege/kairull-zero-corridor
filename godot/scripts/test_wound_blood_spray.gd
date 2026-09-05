extends SceneTree
## 伤口小喷血的无头逻辑测试：方向、连续发射、数量、人物跟随与回池停用。


class FollowTarget:
	extends Node2D

	func body_rect() -> Rect2:
		# 模拟正式敌人“脚底为 position”的世界矩形接口。
		return Rect2(position.x - 12.0, position.y - 48.0, 24.0, 48.0)

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
	print("== WoundBloodSpray ==")
	var scene_path := "res://scenes/fx/wound_blood_spray.tscn"
	ok(ResourceLoader.exists(scene_path), "伤口小喷血场景存在", scene_path)
	var packed := load(scene_path) as PackedScene
	ok(packed != null, "伤口小喷血场景可加载")
	if packed == null:
		_finish()
		return

	# 测试通过场景动态调用，避免首次导入前全局 class_name 缓存尚未刷新。
	var effect = packed.instantiate()
	get_root().add_child(effect)
	await process_frame
	ok(not effect.active and not effect.visible and not effect.is_processing(),
			"新实例默认停用，不产生对象池空转")

	var finished_events: Array = []
	effect.finished.connect(func(done) -> void: finished_events.append(done))
	var target := FollowTarget.new()
	target.position = Vector2(140.0, 200.0)
	get_root().add_child(target)
	var target_center := target.body_rect().get_center()
	effect.global_position = target_center
	var input_direction := Vector2(4.0, -3.0)
	var test_color := Color("#d92855")
	effect.play(1.0, input_direction, 4101, false, test_color, target)
	var normal_start: Dictionary = effect.debug_stats()
	ok(effect.active and effect.visible and effect.is_processing(), "play 启用显示与 process")
	ok(effect.global_position == target_center.round(), "发射点从敌人身体中心起步",
			str(effect.global_position))
	ok(bool(normal_start["following"]), "播放时弱引用跟随目标")
	ok(Vector2(normal_start["direction"]).is_normalized(), "喷射方向已归一化",
			str(normal_start["direction"]))
	ok(Vector2(normal_start["direction"]).dot(input_direction.normalized()) > 0.999,
			"小血滴继承实际受击方向")
	ok(is_equal_approx(float(normal_start["duration"]), effect.normal_duration),
			"普通喷血使用可调生命周期", str(normal_start["duration"]))
	ok(normal_start["color"] == test_color, "接入层可传入主喷溅同色相")

	# 喷口跟着敌人 body_rect 中心移动，已飞出的血滴保留世界弹道。
	var drops_before_move: Array[Vector2] = effect.debug_droplet_world_positions()
	target.position += Vector2(36.0, -8.0)
	target_center = target.body_rect().get_center()
	effect._process(0.0)
	var drops_after_move: Array[Vector2] = effect.debug_droplet_world_positions()
	ok(effect.global_position == target_center.round(), "目标移动后喷口跟随 body_rect 中心",
			"emitter=%s target=%s" % [effect.global_position, target_center])
	ok(_same_positions(drops_before_move, drops_after_move),
			"喷口平移不会拖动已发射血滴",
			"before=%s after=%s" % [drops_before_move, drops_after_move])

	# 分两段推进，确认血滴不是首帧一次性全部生成。
	effect._process(0.09)
	var normal_mid_a: Dictionary = effect.debug_stats()
	effect._process(0.09)
	var normal_mid_b: Dictionary = effect.debug_stats()
	ok(int(normal_mid_a["emitted"]) > int(normal_start["emitted"]),
			"普通模式在伤口附近持续发射", str(normal_mid_a))
	ok(int(normal_mid_b["emitted"]) > int(normal_mid_a["emitted"]),
			"后续时间片仍会产生新血滴", str(normal_mid_b))

	# 目标在播放期间被删除也不应留下悬空引用或中断余下弹道。
	target.queue_free()
	await process_frame
	effect._process(0.0)
	var detached: Dictionary = effect.debug_stats()
	ok(effect.active and not bool(detached["following"]),
			"跟随目标 queue_free 后安全脱离并继续播放", str(detached))

	effect._process(effect.normal_duration)
	var normal_finished: Dictionary = effect.debug_stats()
	var normal_emitted := int(normal_finished["emitted"])
	ok(normal_emitted >= 16 and normal_emitted <= 28,
			"普通档最终喷血量在 16..28 范围", str(normal_emitted))
	ok(normal_finished["color"] == test_color, "普通档全程保留传入色相")
	ok(not effect.active and not effect.visible and not effect.is_processing(),
			"普通生命周期结束后停止并关闭 process")
	ok(finished_events.size() == 1 and finished_events[0] == effect,
			"自然结束只发出一次 finished")

	# 同一实例直接重播，覆盖对象池取出后的状态复位与致命/强攻击配置。
	var strong_color := Color("#ff8a4c")
	effect.play(1.3, Vector2.ZERO, 4102, true, strong_color)
	var strong_start: Dictionary = effect.debug_stats()
	ok(strong_start["strong"], "强/致命模式已启用")
	ok(Vector2(strong_start["direction"]) == Vector2.RIGHT,
			"零方向安全回退为向右")
	ok(is_equal_approx(float(strong_start["duration"]), effect.strong_duration)
			and float(strong_start["duration"]) > effect.normal_duration,
			"强喷血生命周期长于普通档", str(strong_start["duration"]))
	ok(strong_start["color"] == strong_color, "强档仍使用接入层传入的单色族")
	effect._process(0.18)
	var strong_mid: Dictionary = effect.debug_stats()
	ok(int(strong_mid["emitted"]) > normal_emitted,
			"强模式在相同时间窗口发射更多小血滴", str(strong_mid))
	effect._process(effect.strong_duration)
	var strong_finished: Dictionary = effect.debug_stats()
	var strong_emitted := int(strong_finished["emitted"])
	ok(strong_emitted >= 28 and strong_emitted <= 48,
			"强档最终喷血量在 28..48 范围", str(strong_emitted))
	ok(float(strong_emitted) >= float(normal_emitted) * 1.5,
			"强档总量至少是普通档 1.5 倍",
			"normal=%d strong=%d" % [normal_emitted, strong_emitted])
	ok(strong_finished["color"] == strong_color, "强档全程保留传入色相")
	ok(finished_events.size() == 2 and finished_events[1] == effect,
			"强档自然结束也只发出一次 finished")

	# 第三次播放专门覆盖 stop 对跟随引用的清理。
	var stop_target := FollowTarget.new()
	stop_target.position = Vector2(260.0, 220.0)
	get_root().add_child(stop_target)
	effect.global_position = stop_target.body_rect().get_center()
	effect.play(1.0, Vector2.RIGHT, 4103, false, test_color, stop_target)
	effect._process(0.05)
	var before_stop: Dictionary = effect.debug_stats()
	ok(bool(before_stop["following"]), "回池前确实处于跟随状态")
	var elapsed_before_stop := float(before_stop["elapsed"])
	var emitted_before_stop := int(before_stop["emitted"])
	effect.stop()
	var stopped_immediately: Dictionary = effect.debug_stats()
	ok(not effect.active and not effect.visible and not effect.is_processing()
			and not bool(stopped_immediately["following"]),
			"手动 stop 安全回池并清空跟随弱引用")
	# 即使测试手工调用 _process，停用实例也必须保持完全静止。
	effect._process(0.20)
	var stopped: Dictionary = effect.debug_stats()
	ok(is_equal_approx(float(stopped["elapsed"]), elapsed_before_stop)
			and int(stopped["emitted"]) == emitted_before_stop,
			"stop 后不再推进或发射", str(stopped))
	ok(finished_events.size() == 2, "手动 stop 不误发自然结束信号")

	stop_target.queue_free()
	effect.queue_free()
	await process_frame
	_finish()


func _same_positions(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
