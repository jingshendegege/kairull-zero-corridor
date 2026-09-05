extends SceneTree
## 死亡惯性是世界空间小抛物线：用独立小地图验证，绝不写回生产地图生成器。
const MOTION := preload("res://scripts/death_inertia.gd")
const HALF_W := 12.0
const BODY_H := 48.0
const FLOOR_Y := 512.0
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func _run() -> void:
	_test_launch_and_lifecycle()
	_test_flat_ballistics()
	_test_large_dt()
	_test_wall_and_door()
	_test_ceiling()
	_test_one_way_platform()
	_test_stairs()
	_test_platform_exit()
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	print("DEATH_INERTIA_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func _level(floor_row := 16, solids: Array[Rect2i] = [],
		platforms: Array[Rect2i] = [], stairs: Array[Dictionary] = []) -> CorridorLevel:
	var rows := PackedStringArray()
	for y in 32:
		var row := ""
		for x in 80:
			var ch := "#" if y == floor_row else "."
			for r in solids:
				if r.has_point(Vector2i(x, y)):
					ch = "#"
			for r in platforms:
				if r.has_point(Vector2i(x, y)):
					ch = "="
			row += ch
		rows.append(row)
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_stairs = stairs
	var result := CorridorLevel.new()
	result.build(false)
	return result


func _simulate(motion, level: CorridorLevel, dt := 1.0 / 60.0,
		duration := 2.0, doors: Array = []) -> Dictionary:
	var left := duration
	var events := 0
	var min_y: float = motion.position.y
	var first_landing := Vector2(INF, INF)
	var first_time := INF
	while left > 0.000001:
		var step_dt := minf(left, dt)
		if motion.advance(step_dt, level, HALF_W, BODY_H, doors):
			events += 1
			if events == 1:
				first_landing = motion.landing_position
				first_time = motion.elapsed
		min_y = minf(min_y, motion.position.y)
		left -= step_dt
	return {"events": events, "min_y": min_y, "first_landing": first_landing,
			"first_time": first_time, "position": motion.position}


func _test_launch_and_lifecycle() -> void:
	print("== 启动与有限生命周期 ==")
	var motion = MOTION.new()
	check(motion.get_class() == "RefCounted", "求解器为无节点RefCounted，不引入逐尸体场景节点")
	var level := _level()
	var origin := Vector2(600, FLOOR_Y - 0.1)
	motion.launch(origin, 1.0, 0)
	check(motion.position == origin and motion.active and not motion.landed,
			"launch不瞬移，立即激活且未伪造落地")
	check(motion.velocity.x >= 500.0 and motion.velocity.y < -250.0,
			"初速度包含明显水平冲量和小向上冲量")
	check(not motion.advance(-1.0, level, HALF_W, BODY_H) and motion.position == origin \
			and motion.elapsed == 0.0, "负dt不倒走，不制造接地事件")
	check(not motion.advance(0.0, level, HALF_W, BODY_H) and motion.position == origin,
			"零dt不移动")
	_simulate(motion, level)
	check(not motion.active and motion.grounded and motion.landed,
			"平地最终落稳停机，保留已落地记录")
	var rest: Vector2 = motion.position
	check(not motion.advance(10.0, level, HALF_W, BODY_H) and motion.position == rest,
			"结束后再次advance不移动、不重发尘土事件")
	motion.launch(origin, -1.0, 2)
	check(motion.active and not motion.landed and motion.bounce_count == 0 \
			and motion.elapsed == 0.0 and motion.position == origin,
			"复用launch清掉旧落地、反弹及计时状态")
	check(motion.velocity.x < -600.0, "复用后方向与强击档正确")
	level.free()
	level = _level(-1)
	motion.launch(Vector2(600, 100), 1.0)
	_simulate(motion, level, 1.0 / 60.0, 4.0)
	check(not motion.active and not motion.landed and motion.elapsed <= 3.02,
			"无底虚空最多3秒停任务，不伪造落地")
	check(motion.position.y > 1500.0 and not motion.grounded and not motion.ground_valid,
			"无地面持续受重力，不能停在原高度")
	level.free()


func _test_flat_ballistics() -> void:
	print("== 左右、三档与30/60/120fps真实弹道 ==")
	var level := _level()
	var origin := Vector2(1000, FLOOR_Y - 0.1)
	var positions: Dictionary = {}
	for fps in [30, 60, 120]:
		var last_distance := 0.0
		for stage in 3:
			var right_distance := 0.0
			for direction in [1.0, -1.0]:
				var motion = MOTION.new()
				motion.launch(origin, direction, stage)
				var initial_speed: float = absf(motion.velocity.x)
				# 180ms已越过小抛物线顶点，惯性不应像旧ease-out那样耗掉大半。
				_simulate(motion, level, 1.0 / fps, 0.18)
				check(motion.velocity.y > 0.0 and absf(motion.velocity.x) > initial_speed * 0.80,
						"%dfps档%d方向%d顶点后仍保留80%%以上横速" % [fps, stage, int(direction)])
				motion.launch(origin, direction, stage)
				var result := _simulate(motion, level, 1.0 / fps)
				var distance: float = (motion.position.x - origin.x) * direction
				var height: float = origin.y - result.min_y
				if fps == 60 and direction > 0.0:
					print("PROFILE stage=%d distance=%.3fpx height=%.3fpx first_land=%.3fs" \
							% [stage, distance, height, result.first_time])
				check(distance >= 175.0 and distance <= 300.0,
						"%dfps档%d方向%d击飞约6至9格" % [fps, stage, int(direction)], str(distance))
				check(height >= 18.0 and height <= 27.0,
						"%dfps档%d方向%d小抛物线峰高约23px" % [fps, stage, int(direction)], str(height))
				check(result.events == 1 and motion.bounce_count == 1,
						"%dfps档%d方向%d仅一次落尘、一次轻弹" % [fps, stage, int(direction)])
				check(motion.grounded and absf(motion.position.y - FLOOR_Y) < 0.4 \
						and absf(motion.velocity.x) < 0.1 and not motion.active,
						"%dfps档%d方向%d落稳不穿单格地板" % [fps, stage, int(direction)])
				check(result.first_time > 0.26 and result.first_time < 0.36,
						"%dfps档%d方向%d首次接地为真实飞行约0.3秒" % [fps, stage, int(direction)])
				check(motion.landing_position == result.first_landing \
						and absf(motion.landing_position.y - FLOOR_Y) < 0.4,
						"%dfps档%d方向%d首次灰尘锚点不被后续滑行覆盖" % [fps, stage, int(direction)])
				if direction > 0.0:
					right_distance = distance
				else:
					check(absf(distance - right_distance) < 0.2,
							"%dfps档%d左右对称" % [fps, stage])
				positions["%d/%d/%d" % [fps, stage, int(direction)]] = motion.position
			check(right_distance > last_distance + 15.0,
					"%dfps档%d更强冲量带来更远距离" % [fps, stage])
			last_distance = right_distance
	for stage in 3:
		for direction in [-1, 1]:
			var reference: Vector2 = positions["120/%d/%d" % [stage, direction]]
			for fps in [30, 60]:
				var sample: Vector2 = positions["%d/%d/%d" % [fps, stage, direction]]
				check(sample.distance_to(reference) < 1.2,
						"%dfps与120fps档%d方向%d终点一致" % [fps, stage, direction])
	level.free()


func _test_large_dt() -> void:
	print("== 卡顿帧拆步 ==")
	var level := _level()
	var origin := Vector2(600, FLOOR_Y - 0.1)
	var regular = MOTION.new()
	var large = MOTION.new()
	regular.launch(origin, 1.0, 2)
	large.launch(origin, 1.0, 2)
	_simulate(regular, level, 1.0 / 120.0, 1.0)
	check(large.advance(1.0, level, HALF_W, BODY_H), "1秒卡顿帧仍返回首次落地事件")
	check(large.position.distance_to(regular.position) < 1.2 and large.bounce_count == 1,
			"大dt自动子步，轨迹与120fps一致且只反弹一次")
	check(large.landing_position.distance_to(regular.landing_position) < 1.2,
			"大dt保留真实首次接地点而非帧末位置")
	check(not large.advance(1.0, level, HALF_W, BODY_H), "卡顿帧之后不重报落地")
	level.free()


func _test_wall_and_door() -> void:
	print("== 墙与锁门扫掠 ==")
	var level := _level(16, [Rect2i(25, 7, 1, 9)])
	for dt in [1.0 / 120.0, 1.0 / 30.0, 1.0]:
		var motion = MOTION.new()
		motion.launch(Vector2(720, FLOOR_Y - 0.1), 1.0, 2)
		_simulate(motion, level, dt)
		check(motion.position.x + HALF_W < 800.0 and motion.position.x > 760.0,
				"dt%.4f右向撞墙止于墙前，不穿薄墙" % dt, str(motion.position))
		motion.launch(Vector2(910, FLOOR_Y - 0.1), -1.0, 2)
		_simulate(motion, level, dt)
		check(motion.position.x - HALF_W > 832.0 and motion.position.x < 870.0,
				"dt%.4f左向撞墙止于墙前" % dt, str(motion.position))
	var remote = MOTION.new()
	remote.launch(Vector2(250, FLOOR_Y - 0.1), 1.0)
	_simulate(remote, level)
	var remote_end: Vector2 = remote.position
	level.free()
	level = _level()
	remote.launch(Vector2(250, FLOOR_Y - 0.1), 1.0)
	_simulate(remote, level)
	check(remote.position.distance_to(remote_end) < 0.2,
			"路径之外的远墙不能提前误挡惯性")
	var door := RoomDoor.new()
	door.position = Vector2(780, FLOOR_Y)
	var motion = MOTION.new()
	motion.launch(Vector2(650, FLOOR_Y - 0.1), 1.0, 2)
	_simulate(motion, level, 1.0, 2.0, [door])
	check(motion.position.x + HALF_W < door.body_rect().position.x \
			and motion.position.x > 710.0, "大dt锁门挡尸体，不先穿入再推出", str(motion.position))
	door.locked = false
	motion.launch(Vector2(650, FLOOR_Y - 0.1), 1.0, 2)
	_simulate(motion, level, 1.0, 2.0, [door])
	check(motion.position.x > door.body_rect().end.x + HALF_W,
			"已解锁门不挡尸体")
	door.free()
	level.free()


func _test_ceiling() -> void:
	print("== 低顶约束 ==")
	var level := _level(16, [Rect2i(8, 13, 40, 1)])
	var motion = MOTION.new()
	motion.launch(Vector2(600, FLOOR_Y - 0.1), 1.0)
	var clear := true
	for _i in 120:
		motion.advance(1.0 / 120.0, level, HALF_W, BODY_H)
		clear = clear and motion.position.y - BODY_H >= 448.0 - 0.2
	check(clear, "小抛物线碰低顶就停上冲，不把头送入实体顶板")
	check(motion.grounded and motion.position.y > 511.0,
			"顶板碰撞后仍回到地面")
	level.free()


func _test_one_way_platform() -> void:
	print("== 单向平台 ==")
	var level := _level(20, [], [Rect2i(8, 12, 24, 1)])
	var motion = MOTION.new()
	motion.launch(Vector2(420, 401.0), 1.0)
	var result := _simulate(motion, level)
	check(result.min_y < 384.0 and result.min_y > 370.0,
			"脚从平台下方向上穿越，不把单向台误当实心顶板", str(result.min_y))
	check(result.events == 1 and absf(motion.landing_position.y - 384.0) < 0.4,
			"下降时接在平台顶部，首次落尘锚y384")
	check(motion.grounded and absf(motion.position.y - 384.0) < 0.4,
			"回弹滑行后停在平台上而非低层地面")
	level.free()


func _test_stairs() -> void:
	print("== 楼梯接地 ==")
	for direction in [-1, 1]:
		# 两侧相反楼梯使用独立高度场，验证穿越下落踏面后接住尸体。
		var stairs: Array[Dictionary] = [{"left_c": 20, "bottom_row": 16,
				"steps": 8, "rise_dir": direction}]
		var level := _level(16, [], [], stairs)
		var start := Vector2(600 if direction > 0 else 936, FLOOR_Y - 0.1)
		var motion = MOTION.new()
		motion.launch(start, float(direction), 1)
		var result := _simulate(motion, level)
		# 前缘在起飞初段先碰到16px梯面侧壁，真实动量应被挡；不能为爬梯而瞬移。
		check(result.events == 1 and absf(motion.landing_position.y - FLOOR_Y) < 0.4,
				"方向%d起飞高度不足时侧撞梯口，落回入口地板" % direction,
				str(motion.landing_position))
		check((motion.position.x < 632.0 if direction > 0 else motion.position.x > 904.0) \
				and motion.grounded, "方向%d侧撞停在梯前，没有穿入梯下" % direction, str(motion.position))
		check(motion.position.x * direction > start.x * direction + 20.0,
				"方向%d远处梯面不误挡，先推进到实际侧面才消掉横速" % direction)
		# 另从梯上方发射，让下降段真正跨过踏面，不能只测侧撞就声称楼梯能接地。
		motion.launch(Vector2(650 if direction > 0 else 886, 400), float(direction), 0)
		result = _simulate(motion, level)
		check(result.events == 1 and motion.landing_position.y < 449.0,
				"方向%d高于踏面的小抛物线下降时被楼梯接住" % direction, str(motion.landing_position))
		check(motion.position.y <= motion.landing_position.y + 0.4 and motion.grounded,
				"方向%d接阶后余速侧撞更高阶也不穿梯" % direction, str(motion.position))
		check(motion.position.y < FLOOR_Y - 32.0,
				"方向%d真实脚底锚留在楼梯上，非仅把尸体画到楼梯上" % direction)
		level.free()


func _test_platform_exit() -> void:
	print("== 余速越平台边缘自然跌落 ==")
	var level := _level(20, [], [Rect2i(8, 12, 8, 1)])
	var motion = MOTION.new()
	motion.launch(Vector2(300, 383.9), 1.0, 2)
	var first := Vector2(INF, INF)
	var events := 0
	var airborne_beyond_edge := false
	for _i in 240:
		if motion.advance(1.0 / 120.0, level, HALF_W, BODY_H):
			events += 1
			if events == 1:
				first = motion.landing_position
		if motion.position.x - HALF_W > 512.1 and motion.position.y > 390.0 \
				and motion.position.y < 630.0:
			airborne_beyond_edge = airborne_beyond_edge or not motion.grounded
	check(first.y < 384.4 and first.y > 383.5,
			"先真正落到上层短平台，不能直接跳过第一次接地", str(first))
	check(airborne_beyond_edge, "落后余速越缘，脚下无支撑时自然下落而非悬空滑行")
	check(motion.position.y > 639.0 and motion.grounded,
			"越缘后重新由下层地面接住", str(motion.position))
	check(events == 1 and motion.landing_position == first and motion.bounce_count == 1,
			"二次落地不重发主尘爆、不再次弹跳、不覆盖首次接地点")
	level.free()
