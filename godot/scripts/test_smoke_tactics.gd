extends SceneTree
## 烟雾弹：单格补给/定点抛物线/连续碰撞/世界时钟/遮蔽/输入视觉的有界回归。

const SMOKE := preload("res://scripts/smoke_tactics.gd")
var _pass := 0
var _fail := 0

class TestTerrain extends Node2D:
	var floor_y := 500.0
	var walls: Array[Rect2] = []
	var platform_y := INF
	var stairs_y := INF
	func solid_at(x: float, y: float) -> bool:
		for rect in walls:
			if rect.has_point(Vector2(x, y)):
				return true
		return y >= floor_y or is_platform(x, y)
	func is_platform(_x: float, y: float) -> bool:
		return y >= platform_y and y < platform_y + 32.0
	func stair_surface_crossed(_x: float, from_y: float, to_y: float) -> float:
		return stairs_y if from_y <= stairs_y and to_y >= stairs_y else INF

class TestActor extends Node2D:
	var carried_smoke := false
	var dead := false
	var face := 1
	var low := false
	var covered := false
	var aim_held := false
	var target := Vector2(500, 490)
	func set_carried_smoke(value: bool) -> void:
		carried_smoke = value and not dead
	func set_smoke_cover(value: bool) -> void:
		covered = value
	func rolling() -> bool:
		return low
	func _aim_point() -> Vector2:
		return target
	func smoke_aiming() -> bool:
		return carried_smoke and not dead and aim_held
	func hurtbox_rect() -> Rect2:
		return Rect2(position - Vector2(17, 82), Vector2(34, 82))

class TestDoor extends Node2D:
	var locked := true
	func body_rect() -> Rect2:
		return Rect2(300, 0, 12, 500)

class DynamicObstacle extends Node2D:
	var locked := true
	var size := Vector2(12, 200)
	func body_rect() -> Rect2:
		return Rect2(position, size)

class OutlineProbe extends "res://scripts/smoke_tactics.gd":
	var outline_build_calls := 0
	func _cloud_outline_points(center: Vector2) -> PackedVector2Array:
		outline_build_calls += 1
		return super._cloud_outline_points(center)


func _init() -> void:
	call_deferred("_run")


func ok(value: bool, label: String, detail := "") -> void:
	if value:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _run() -> void:
	_test_math()
	_test_pickup()
	_test_flight_and_collisions()
	_test_cloud_cover()
	_test_wide_cloud_consistency()
	_test_dynamic_outline_cache()
	_test_bounds()
	_test_player_edges_and_visuals()
	await process_frame
	print("\nSMOKE_TACTICS_RESULT: %d PASS, %d FAIL" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _system() -> Array:
	var terrain := TestTerrain.new()
	var actor := TestActor.new()
	actor.position = Vector2(180, 499.9)
	var system := SMOKE.new()
	get_root().add_child(actor)
	get_root().add_child(system)
	system.setup(terrain, [], actor)
	return [system, actor, terrain]


func _free_parts(parts: Array) -> void:
	for part in parts:
		part.free()


func _test_math() -> void:
	var system := SMOKE.new()
	var origin := Vector2(200, 300)
	for target in [Vector2(500, 420), Vector2(-100, 300), Vector2(200, 100),
			Vector2(200, 300), Vector2(9000, -3000)]:
		var result: Dictionary = system.trajectory(origin, target)
		var duration := float(result["duration"])
		var velocity: Vector2 = result["velocity"]
		var landing := origin + velocity * duration + Vector2(0, 0.5 * SMOKE.GRAVITY * duration * duration)
		ok(landing.distance_to(result["target"]) < 0.001, "抛物线准确到达鼠标/截断目标", str(target))
		ok(origin.distance_to(result["target"]) <= SMOKE.MAX_THROW_RANGE + 0.001, "投掷总射程不超过420px")
		ok(duration >= SMOKE.MIN_FLIGHT_TIME and duration <= SMOKE.MAX_FLIGHT_TIME, "飞行时间有界")
		ok(velocity.is_finite(), "同点和垂直瞄准不产生NaN")
	system.free()


func _test_pickup() -> void:
	var parts := _system()
	var system: Node2D = parts[0]
	var actor: TestActor = parts[1]
	var terrain: TestTerrain = parts[2]
	var first: Node2D = system.spawn_pickup(actor.position)
	var second: Node2D = system.spawn_pickup(actor.position + Vector2(8, 0))
	ok(is_instance_valid(first) and is_instance_valid(second), "地图脚底补给生成两个独立可见罐体")
	ok(system.try_pickup(actor) and actor.carried_smoke, "靠近自动拾取一颗")
	ok(system.pickups.size() == 1 and not is_instance_valid(first), "拾取只回收命中的一颗")
	ok(not system.try_pickup(actor) and system.pickups.size() == 1, "满槽不吞其他落物")
	actor.set_carried_smoke(false)
	actor.dead = true
	ok(not system.try_pickup(actor), "死亡不拾取")
	actor.dead = false
	actor.position.x = 400
	ok(not system.try_pickup(actor), "超过拾取距离不吸附")
	actor.position.x = 205
	terrain.walls = [Rect2(195, 450, 3, 50)]
	ok(not system.try_pickup(actor) and system.pickups.size() == 1, "隔墙相近仍不能拾取")
	terrain.walls.clear()
	ok(system.try_pickup(actor), "同侧无遮挡恢复正常拾取")
	ok(system.pickups.is_empty(), "两颗都只在成功拾取时消耗")
	_free_parts(parts)


func _test_flight_and_collisions() -> void:
	var parts := _system()
	var system: Node2D = parts[0]
	var actor: TestActor = parts[1]
	var terrain: TestTerrain = parts[2]
	ok(not system.throw_from(actor, Vector2(450, 480)), "空槽不能凭空投掷")
	actor.set_carried_smoke(true)
	ok(system.throw_from(actor, Vector2(450, 480)), "成功创建世界弹体")
	ok(not actor.carried_smoke and system.grenades.size() == 1, "弹体创建成功才消费携带槽")
	var frozen: Dictionary = system.grenades[0].duplicate(true)
	system.step(0)
	ok(system.grenades[0] == frozen and system.clouds.is_empty(), "时停0dt不飞行不引爆")
	system.step(0.3)
	ok(system.grenades.size() == 1 and system.grenades[0]["position"].y < frozen["position"].y,
			"前半程有明显小抛物线上扬")
	system.step(0.7)
	ok(system.grenades.is_empty() and system.clouds.size() == 1, "到鼠标目标引爆并回收弹体")
	ok(absf(system.clouds[0]["position"].x - 450.0) < 0.1, "无遮挡投掷横向落点与鼠标一致")
	system.clear_effects()
	terrain.walls = [Rect2(300, 0, 3, 500)]
	actor.set_carried_smoke(true)
	system.throw_from(actor, Vector2(520, 480))
	system.step(1.0)
	ok(system.clouds.size() == 1 and system.clouds[0]["position"].x < 300.0, "3px墙长dt连续扫掠不穿墙")
	system.clear_effects()
	terrain.walls = [Rect2(185, 440, 20, 30)]
	actor.set_carried_smoke(true)
	ok(not system.throw_from(actor, Vector2(400, 480)) and actor.carried_smoke, "手部已进墙时拒绝投掷且不吞弹")
	terrain.walls.clear()
	var door := TestDoor.new()
	system.doors = [door]
	system.throw_from(actor, Vector2(500, 480))
	system.step(1.0)
	ok(system.clouds[0]["position"].x < 298.0, "闭门阻挡弹体")
	system.clear_effects()
	door.locked = false
	actor.set_carried_smoke(true)
	system.throw_from(actor, Vector2(500, 480))
	system.step(1.0)
	ok(absf(system.clouds[0]["position"].x - 500.0) < 0.1, "开门后可正常向后方投掷")
	system.doors.clear()
	door.free()
	system.clear_effects()
	terrain.platform_y = 384
	var up: Dictionary = system._sweep(Vector2(250, 430), Vector2(250, 360))
	var down: Dictionary = system._sweep(Vector2(250, 360), Vector2(250, 430))
	ok(not up["hit"] and down["hit"], "单向平台向上放行向下碰撞")
	terrain.platform_y = INF
	terrain.stairs_y = 420
	down = system._sweep(Vector2(250, 400), Vector2(250, 450))
	up = system._sweep(Vector2(250, 450), Vector2(250, 400))
	ok(down["hit"] and not up["hit"], "开放楼梯下落释烟上升不挡")
	terrain.stairs_y = INF
	down = system._sweep(Vector2(250, 450), Vector2(250, 530))
	ok(down["hit"] and down["position"].y < terrain.floor_y, "薄地面连续碰撞在地板上方释烟")
	actor.low = true
	ok(system.hand_position(actor).y == actor.position.y - 22.0, "翻滚投掷使用降低的手部高度")
	_free_parts(parts)


func _test_cloud_cover() -> void:
	var parts := _system()
	var system: Node2D = parts[0]
	var actor: TestActor = parts[1]
	var terrain: TestTerrain = parts[2]
	system.deploy_cloud(Vector2(220, 480))
	ok(not system.contains_point(Vector2(220, 440)), "刚出生完全透明阶段不出现隐藏免伤")
	system.step(0.2)
	ok(system.contains_point(Vector2(220, 440)), "展开后烟心受到遮蔽")
	ok(not system.contains_point(Vector2(220 + SMOKE.SMOKE_RADIUS + 20, 440)), "新三倍范围之外不遮蔽")
	ok(system.contains_actor(actor), "人物受击框中心进入烟雾获得可判定状态")
	actor.dead = true
	ok(not system.contains_actor(actor), "死亡尸体不冒充活人烟内状态")
	actor.dead = false
	ok(system.blocks_segment(Vector2(30, 440), Vector2(500, 440)), "穿过烟区的枪手/狙击视线被遮挡")
	ok(not system.blocks_segment(Vector2(30, 100), Vector2(500, 100)), "远离烟区的视线不受影响")
	ok(system.blocks_segment(Vector2(220, 440), Vector2(220, 440)), "零长度视线稳定判定无除零")
	ok(not system.blocks_segment(Vector2(20, 40), Vector2(20, 40)), "烟外零长度视线不误命中")
	terrain.walls = [Rect2(250, 300, 6, 200)]
	ok(not system.contains_point(Vector2(280, 440)), "烟区逻辑不越过实体墙赋予免伤")
	ok(system.contains_point(Vector2(235, 440)), "墙前同侧仍可用")
	var age := float(system.clouds[0]["age"])
	system.step(0)
	ok(system.clouds[0]["age"] == age, "世界时停同时冻结烟的有效时长")
	system.step(4.55)
	ok(not system.contains_point(Vector2(220, 440)), "接近全透明的消散末端及时移除遮蔽")
	system.step(0.1)
	ok(system.clouds.is_empty(), "4.8秒寿命终止自动回收")
	_free_parts(parts)


func _test_wide_cloud_consistency() -> void:
	var parts := _system()
	var system: Node2D = parts[0]
	var terrain: TestTerrain = parts[2]
	terrain.floor_y = INF
	system.deploy_cloud(Vector2(500, 300))
	system.step(0.2)
	var cloud: Dictionary = system.clouds[0]
	var center: Vector2 = cloud["position"]
	var outline: PackedVector2Array = cloud["outline_points"]
	ok(SMOKE.SMOKE_RADIUS == 112.0 * 3.0, "左右半径各为原版三倍336px")
	ok(SMOKE.SMOKE_VERTICAL_RADIUS == 96.0 and SMOKE.SMOKE_DURATION == 4.8 \
			and SMOKE.MAX_THROW_RANGE == 420.0, "只加横向烟范围，不加高度/寿命/投距")
	for sign_x in [-1.0, 1.0]:
		var extension := center + Vector2(sign_x * 280.0, 0)
		ok(system.contains_point(extension), "左右旧半径以外280px属于有效烟区:" + str(sign_x))
		ok(Geometry2D.is_point_in_polygon(extension, outline), "扩大后的保护点同时落在可见薄烟轮廓内:" + str(sign_x))
		ok(system.blocks_segment(extension + Vector2(0, -12), extension + Vector2(0, 12)),
				"边部短枪线遮蔽与点保护一致:" + str(sign_x))
		ok(system.contains_point(center + Vector2(sign_x * 336.0, 0)), "336px水平临界点仍受保护:" + str(sign_x))
		var outside := center + Vector2(sign_x * 337.0, 0)
		ok(not system.contains_point(outside) \
				and not system.blocks_segment(outside + Vector2(0, -6), outside + Vector2(0, 6)),
				"337px外侧点及枪线均不受保护:" + str(sign_x))
	for sign_y in [-1.0, 1.0]:
		ok(system.contains_point(center + Vector2(0, sign_y * 96.0)), "垂直半径96px边界保持:" + str(sign_y))
		var outside := center + Vector2(0, sign_y * 97.0)
		ok(not system.contains_point(outside) and not system.blocks_segment(outside - Vector2(3, 0), outside + Vector2(3, 0)),
				"高度97px外仍无免伤/遮视线:" + str(sign_y))
	ok(not system.contains_point(center + Vector2(320, 80)), "三倍宽仍为椭圆而非整块大矩形免伤")
	terrain.walls = [Rect2(center + Vector2(80, -200), Vector2(4, 400))]
	var blocked_outline: PackedVector2Array = system._cloud_outline_points(center)
	ok(system.contains_point(center + Vector2(60, 0)) \
			and not system.contains_point(center + Vector2(160, 0)), "扩大烟仍只保护墙前同侧")
	ok(Geometry2D.is_point_in_polygon(center + Vector2(60, 0), blocked_outline) \
			and not Geometry2D.is_point_in_polygon(center + Vector2(160, 0), blocked_outline),
			"可见底雾轮廓同样在墙前截断，不能隔墙显示假掩护")
	terrain.walls.clear()
	var door := TestDoor.new()
	system.doors = [door]
	system._update_cloud_outline(cloud)
	var left_point := center + Vector2(-280, 0)
	ok(not system.contains_point(left_point) \
			and not Geometry2D.is_point_in_polygon(left_point, cloud["outline_points"]),
			"闭门同时切断加宽保护和缓存底烟")
	var closed_key := int(cloud["outline_key"])
	door.locked = false
	system._update_cloud_outline(cloud)
	ok(closed_key != cloud["outline_key"] and system.contains_point(left_point) \
			and Geometry2D.is_point_in_polygon(left_point, cloud["outline_points"]),
			"开门即时刷新缓存与保护，不留新增隐形烟带")
	system.doors.clear()
	door.free()
	_free_parts(parts)


func _test_dynamic_outline_cache() -> void:
	var terrain := TestTerrain.new()
	terrain.floor_y = INF
	var near := DynamicObstacle.new()
	var far := DynamicObstacle.new()
	var center := Vector2(500, 252)
	near.position = center + Vector2(80, -100)
	far.position = center + Vector2(10000, -100)
	var system := OutlineProbe.new()
	get_root().add_child(system)
	system.setup(terrain, [near, far], null)
	system.deploy_cloud(center + Vector2(0, 48))
	system.step(0.2)
	var cloud: Dictionary = system.clouds[0]
	var build_calls := system.outline_build_calls
	var original_key := int(cloud["outline_key"])
	var exposed_after_move := center + Vector2(100, 0)
	ok(not system.contains_point(exposed_after_move) \
			and not Geometry2D.is_point_in_polygon(exposed_after_move, cloud["outline_points"]),
			"动态遮挡初始位置同步切断保护与可见薄烟")
	var profile_start := Time.get_ticks_usec()
	for index in 600:
		far.position += Vector2(3, 2)
		system._update_cloud_outline(cloud)
	var profile_ms := (Time.get_ticks_usec() - profile_start) / 1000.0
	ok(system.outline_build_calls == build_calls and cloud["outline_key"] == original_key,
			"远方电梯连续600帧移动，当前烟轮廓零次重建")
	print("SMOKE_CACHE_PROFILE far_frames=600 outline_rebuilds=0 key_checks_ms=%.3f" % profile_ms)
	near.position.x += 32
	system._update_cloud_outline(cloud)
	ok(system.outline_build_calls == build_calls + 1 and cloud["outline_key"] != original_key,
			"附近电梯位置变但locked不变，轮廓仍刷新")
	ok(system.contains_point(exposed_after_move) \
			and Geometry2D.is_point_in_polygon(exposed_after_move, cloud["outline_points"]),
			"移动后刚露出的空间保护与薄烟一起恢复，不留旧裁切孔")
	var moved_key := int(cloud["outline_key"])
	near.position.x += 1
	system._update_cloud_outline(cloud)
	ok(system.outline_build_calls == build_calls + 1 and cloud["outline_key"] == moved_key,
			"附近电梯同一4px量化桶内微移不重复64条射线")
	near.size.x += 4
	system._update_cloud_outline(cloud)
	ok(system.outline_build_calls == build_calls + 2 and cloud["outline_key"] != moved_key,
			"附近动态body_rect尺寸改变也使缓存失效")
	near.position.y += 240
	system._update_cloud_outline(cloud)
	var escaped_key := int(cloud["outline_key"])
	ok(system.outline_build_calls == build_calls + 3 \
			and Geometry2D.is_point_in_polygon(center + Vector2(280, 0), cloud["outline_points"]),
			"遮挡离开该烟AABB时重建一次，旧孔完整消失")
	near.position.y += 20
	far.size += Vector2(20, 40)
	system._update_cloud_outline(cloud)
	ok(system.outline_build_calls == build_calls + 3 and cloud["outline_key"] == escaped_key,
			"全部位于远方后，继续移动或缩放不失效当前烟缓存")
	far.position = center + Vector2(-100, -100)
	system._update_cloud_outline(cloud)
	ok(system.outline_build_calls == build_calls + 4 \
			and not system.contains_point(center + Vector2(-280, 0)) \
			and not Geometry2D.is_point_in_polygon(center + Vector2(-280, 0), cloud["outline_points"]),
			"原远方电梯进入烟AABB时立即参与动态轮廓遮挡")
	ok(SMOKE.SMOKE_RADIUS == 336.0 and SMOKE.SMOKE_VERTICAL_RADIUS == 96.0 \
			and SMOKE.SMOKE_OUTLINE_OBSTACLE_QUANTUM == 4.0,
			"动态缓存修复不回退三倍横向范围，视觉量化误差限4px")
	system.free()
	terrain.free()
	near.free()
	far.free()


func _test_bounds() -> void:
	var parts := _system()
	var system: Node2D = parts[0]
	var actor: TestActor = parts[1]
	for index in 20:
		system.spawn_pickup(Vector2(100 + index * 5, 499.9))
	ok(system.pickups.size() == SMOKE.MAX_PICKUPS, "地图意外重复创建补给也受16颗上限保护")
	for index in 9:
		system.deploy_cloud(Vector2(180 + index * 10, 480))
	ok(system.clouds.size() == SMOKE.MAX_CLOUDS, "持续烟最多4片按最旧优先回收")
	ok(system.clouds[0]["position"].x == 230.0, "超限只保留最新四片烟")
	for _index in 4:
		actor.set_carried_smoke(true)
		system.throw_from(actor, Vector2(420, 480))
	actor.set_carried_smoke(true)
	ok(not system.throw_from(actor, Vector2(420, 480)) and actor.carried_smoke,
			"时停最多四枚未飞行手雷超限不吞携带物")
	system.clear_effects()
	ok(system.grenades.is_empty() and system.clouds.is_empty(), "短倒带清空烟雾与飞行弹体")
	ok(system.pickups.size() == 16 and not actor.carried_smoke, "短倒带保留地上补给但清携带槽")
	actor.set_carried_smoke(true)
	system.update_aim_preview()
	ok(not system._preview_visible, "仅携带不按R时不显示抛物线")
	actor.aim_held = true
	system.update_aim_preview()
	ok(system._preview_visible and system._preview.size() >= 2, "有弹且按住R才显示鼠标抛物线")
	actor.aim_held = false
	system.update_aim_preview()
	ok(not system._preview_visible, "松开R立即隐藏抛物线但不消耗携带物")
	actor.aim_held = true
	actor.set_carried_smoke(false)
	system.update_aim_preview()
	ok(not system._preview_visible, "空槽隐藏整条预览防止永久遮挡")
	system.clear()
	ok(system.pickups.is_empty() and system.get_child_count() == 0, "全清回收所有补给节点")
	_free_parts(parts)


func _test_player_edges_and_visuals() -> void:
	var previous_map := CorridorLevel.active_map
	var previous_stairs := CorridorLevel.active_stairs
	var rows := PackedStringArray()
	for y in 20:
		rows.append("#".repeat(60) if y == 14 else ".".repeat(60))
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_stairs = []
	var input_level := CorridorLevel.new()
	input_level.build(false)
	var db := AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
			"res://assets/clips/hero/hero_atlas.json"])
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = db
	player.level = input_level
	player.spawn = Vector2(400, 447.9)
	get_root().add_child(player)
	player.on_ground = true
	player._sync_sprite()
	var events: Array[Vector2] = []
	var swings: Array[int] = []
	player.smoke_throw_requested.connect(func(target: Vector2): events.append(target))
	player.bat_swing_started.connect(func(stage: int): swings.append(stage))
	player.aim_override = Vector2(777, 222)
	player.keys = {KEY_R: true}
	player._handle_edges()
	ok(events.is_empty() and not player.smoke_aiming(), "玩家空槽R不瞄准、不投掷，也不恢复枪械")
	player.set_carried_smoke(true)
	player._handle_edges()
	ok(events.is_empty() and player.smoke_aiming(), "有弹单按R只进入瞄准，不立即投出")
	var preview := SMOKE.new()
	get_root().add_child(preview)
	preview.setup(input_level, [], player)
	preview.update_aim_preview()
	ok(preview._preview_visible, "真实玩家按住R通过公开smoke_aiming驱动预览")
	player.keys.clear()
	preview.update_aim_preview()
	ok(not preview._preview_visible and player.carried_smoke, "真实玩家松R隐藏预览并保留背包")
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys.clear()
	player._handle_edges()
	ok(player.batting() and player.carried_smoke and events.is_empty(), "有弹但不按R时左键仍是正常球棒")
	for state_name in ["gun_idle", "run", "gun_jump_air", "roll", "dash", "bat1"]:
		player.reset_to_spawn()
		player.on_ground = true
		player.state = state_name
		player.set_carried_smoke(true)
		player.keys = {KEY_R: true}
		player._prev_keys.clear()
		var previous := events.size()
		var previous_swings := swings.size()
		player._handle_edges()
		ok(events.size() == previous, "R在%s只瞄准，不提前消费" % state_name)
		player._prev_keys = player.keys.duplicate()
		player.keys[MOUSE_BUTTON_LEFT] = true
		player._bat_input_buffer_t = 0.06
		player.bat_queued = true
		player._handle_edges()
		ok(events.size() == previous + 1 and events.back() == Vector2(777, 222), "按R左键在%s中使用鼠标目标确认" % state_name)
		ok(swings.size() == previous_swings and player._bat_input_buffer_t == 0.0 and not player.bat_queued,
				"%s确认投掷不挥棒、不留爆发缓冲、不排连招" % state_name)
		player._prev_keys = player.keys.duplicate()
		player.keys[MOUSE_BUTTON_RIGHT] = true
		player._handle_edges()
		ok(events.size() == previous + 1, "持续R和鼠标左右键不自动连投:%s" % state_name)
		ok(player.carried_smoke, "请求信号本身不消耗背包:%s" % state_name)
	# 宿主会在信号中同步清背包；本帧仍须保留throw_consumed，不能因此又落进球棒分支。
	var consume_smoke := func(_target: Vector2): player.set_carried_smoke(false)
	player.smoke_throw_requested.connect(consume_smoke)
	player.reset_to_spawn()
	player.on_ground = true
	player.set_carried_smoke(true)
	player.keys = {KEY_R: true, MOUSE_BUTTON_LEFT: true}
	player._prev_keys.clear()
	var before_confirm := events.size()
	var before_swing := swings.size()
	player._handle_edges()
	ok(events.size() == before_confirm + 1 and not player.carried_smoke and not player.batting() \
			and swings.size() == before_swing, "成功消耗背包后本帧左键仍只投不击打")
	player._prev_keys = player.keys.duplicate()
	player._handle_edges()
	ok(events.size() == before_confirm + 1 and swings.size() == before_swing, "空槽后继续按住左键也不自动补挥")
	player.keys = {KEY_R: true}
	player._prev_keys = player.keys.duplicate()
	player.keys[MOUSE_BUTTON_LEFT] = true
	player._handle_edges()
	ok(player.batting() and swings.size() == before_swing + 1 and events.size() == before_confirm + 1,
			"没携带烟时新一记R+左键照常挥棒，不凭空投掷")
	for action in [KEY_W, KEY_SHIFT, KEY_CTRL]:
		player.reset_to_spawn()
		player.on_ground = true
		player.set_carried_smoke(true)
		player.keys = {KEY_R: true, MOUSE_BUTTON_LEFT: true, action: true}
		player._prev_keys.clear()
		player._handle_edges()
		var action_ok := player.vy == player.JUMP if action == KEY_W else player.dashing() if action == KEY_SHIFT else player.rolling()
		ok(not player.carried_smoke and action_ok, "投掷确认不吞同帧跳跃/冲刺/翻滚按键:" + str(action))
	player.smoke_throw_requested.disconnect(consume_smoke)
	preview.free()
	player.reset_to_spawn()
	player.on_ground = true
	player.state = "gun_idle"
	player.set_carried_smoke(true)
	ok(player._smoke_carry_ui.visible, "有弹头顶只显示可辨识罐体")
	ok(not player._smoke_carry_ui.get_script().source_code.contains("draw_string("),
			"携带图标绘制不包含R或其他字符文本")
	ok(player._smoke_carry_ui.position.y < player._dash_cooldown_ui.position.y - 24,
			"携带UI和冲刺CD纵向错开")
	player.set_time_focus(true)
	var material: Material = player._sprite.material
	player.set_smoke_cover(true)
	var silhouette: Color = player._sprite.self_modulate
	ok(player.smoke_cover_active() and silhouette.r < 0.10 and silhouette.g < 0.15 \
			and silhouette.b < 0.18 and is_equal_approx(silhouette.a, 1.0), "烟内人物是不透明深蓝黑剪影，不再淡成透明影")
	var smoke_outline: Color = player._outline_mat.get_shader_parameter("outline_color")
	ok(smoke_outline.r > 0.5 and smoke_outline.g > 0.85 and smoke_outline.b > 0.85,
			"深色主角外围保留浅青轮廓以辨认位置")
	ok(player._sprite.material == material and player.time_focus_active(), "烟内不覆盖时停高亮材质与减速状态")
	player.invuln_t = 0.1
	player._sync_sprite()
	ok(is_equal_approx(player._sprite.modulate.a, 0.45) and player._sprite.self_modulate == silhouette,
			"深色剪影下依然由原modulate.a独立受伤闪烁")
	ok(is_equal_approx(player._outline.modulate.a, player._sprite.modulate.a) \
			and player.OUTLINE_SHADER_CODE.contains("outline_color * outline_vertex_color"),
			"真描边使用顶点调制色而非透明纹理Alpha，且同步受伤闪烁")
	player.invuln_t = 0.0
	var health := player.hp
	player.take_damage(1, player.position.x - 10)
	ok(player.hp == health - 1, "烟视觉接口不能误免疫近战或陷阱伤害")
	player.set_smoke_cover(false)
	ok(player._sprite.self_modulate == Color.WHITE and player._sprite.material == material,
			"离烟恢复原本人物色彩而不是清除时停")
	var restored_outline: Color = player._outline_mat.get_shader_parameter("outline_color")
	ok(restored_outline.is_equal_approx(Color(0.09, 0.05, 0.14, 1.0)),
			"出烟还原原深紫描边，不把烟内浅青轮廓带出去")
	player.set_time_focus(false)
	player.set_smoke_cover(true)
	player._sync_sprite()
	ok(player._sprite.material == null and player._sprite.self_modulate == silhouette,
			"正常时间烟内同样是深色剪影，不依赖时停材质伪造")
	player.state = "dash"
	player._update_dash_visual(0.0)
	var dash_material: Material = player._sprite.material
	player.set_smoke_cover(false)
	player.set_smoke_cover(true)
	ok(player._sprite.material == dash_material and dash_material == player._dash_material,
			"进出烟不能替换正在运行的冲刺材质")
	player.state = "gun_idle"
	player._update_dash_visual(0.0)
	ok(SMOKE.SMOKE_BASE_OPACITY > 0.17 and SMOKE.SMOKE_BASE_OPACITY < 0.4 \
			and SMOKE.SMOKE_LOBE_OPACITY > 0.12 and SMOKE.SMOKE_LOBE_OPACITY < 0.25,
			"烟底和团簇浓度明确提高但仍保留透视层次")
	player.set_smoke_cover(true)
	player.force_death(player.position.x - 10)
	ok(not player.carried_smoke and not player._smoke_carry_ui.visible, "死亡立即清携带图标")
	ok(not player.smoke_cover_active() and not player.time_focus_active(), "死亡清烟视觉和时停仍走原死亡惯性")
	var count := events.size()
	player._prev_keys.clear()
	player.carried_smoke = true
	player._handle_edges()
	ok(events.size() == count, "死亡后R不投掷")
	player.reset_to_spawn()
	ok(not player.carried_smoke and not player._smoke_carry_ui.visible, "整关重开不留旧携带物")
	ok(not player.GUN_ENABLED and not player.SLIDE_ENABLED, "枪械和旧滑铲保持禁用")
	player.free()
	input_level.free()
	CorridorLevel.active_map = previous_map
	CorridorLevel.active_stairs = previous_stairs
