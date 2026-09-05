extends SceneTree
## 正式特效链集成测试：球棒主液幕、小伤口喷血、冻结墙渍与运行时回退互不串线。

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
	print("== Blood wall production integration ==")
	var packed := load("res://scenes/game.tscn") as PackedScene
	ok(packed != null, "正式游戏场景可加载")
	if packed == null:
		_finish()
		return

	var game = packed.instantiate()
	get_root().add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game._sfx.clear()

	var manager = game.paint_layer.blood_wall_manager
	ok(manager != null, "墙面快照管理器挂在世界污渍层内")
	ok(manager.get_parent() == game.paint_layer and manager.get_canvas_layer_node() == null,
			"持久血迹不是固定屏幕 CanvasLayer")
	ok(game.level.get_index() < game.paint_layer.get_index()
			and game.paint_layer.get_index() < game.player.get_index()
			and not manager.is_set_as_top_level(),
			"绘制顺序保持地形之后、角色之前，且继承世界变换")
	var initial_stats: Dictionary = manager.debug_stats()
	ok(int(initial_stats["active"]) == 0, "新关卡没有预生成墙渍")

	var wound_script := load("res://scripts/wound_blood_spray.gd")
	var hit_point: Vector2 = game.minions[0].body_rect().get_center()
	var hit_direction := Vector2(900.0, -220.0)
	var main_effect = game.fx_layer.spawn_bat_hit(hit_point, hit_direction, 1.35)
	var wounds := _active_wounds(game.fx_layer, wound_script)
	ok(wounds.size() == 1, "球棒命中同时生成独立伤口小喷血", str(wounds.size()))
	var wound = wounds[0] if not wounds.is_empty() else null
	if wound != null:
		var wound_stats: Dictionary = wound.debug_stats()
		ok(bool(wound_stats["strong"]), "致命档球棒命中使用强伤口喷血")
		ok(Vector2(wound_stats["direction"]).dot(hit_direction.normalized()) > 0.999,
				"伤口小喷血继承实际受击方向", str(wound_stats["direction"]))
		ok(Color(wound_stats["color"]) == main_effect.current_color,
				"主液幕与伤口小喷血使用同一色相")

	ok(manager.active_count() == 0, "冻结时刻之前不提前生成墙渍")
	var old_marks: int = game.paint_layer.splat_count() + game.paint_layer.fleck_count()
	# 完整球棒液幕在约 0.15 秒触发既有 paint_requested；手动推进保证测试确定性。
	main_effect._process(0.16)
	var after_paint: Dictionary = manager.debug_stats()
	ok(int(after_paint["active"]) == 1 and int(after_paint["visible"]) == 1,
			"主液幕前缘到位时只冻结一张墙面快照", str(after_paint))
	var slot: Dictionary = manager.debug_snapshot(0)
	var first_sprite := slot["sprite"] as Sprite2D
	ok(Vector2(slot["world_position"]) == hit_point.round(),
			"冻结快照保存在像素取整后的世界坐标", str(slot.get("world_position")))
	ok(not first_sprite.is_set_as_top_level(), "快照 Sprite 跟随世界与 Camera2D，而非屏幕固定")
	ok(Vector2(slot["direction"]).dot(hit_direction.normalized()) > 0.999,
			"快照保存归一化喷射方向")
	ok(Color(slot["color"]) == main_effect.current_color,
			"持久墙渍沿用本次命中的彩色血液，而非固定红色")
	var first_material := slot["material"] as ShaderMaterial
	ok(manager.dark_surface_lift_enabled
			and bool(first_material.get_shader_parameter("enable_dark_surface_lift"))
			and manager.dark_surface_lift_strength >= 0.45
			and manager.dark_surface_lift_strength <= 0.65,
			"正式链默认启用克制的暗墙彩色补偿")
	manager.set_dark_surface_lift_enabled(false)
	ok(not bool(first_material.get_shader_parameter("enable_dark_surface_lift")),
			"暗墙补色可运行时关闭并立即回到纯正片叠底")
	manager.set_dark_surface_lift_enabled(true)
	ok(float(slot["progress"]) > 0.0 and float(slot["progress"]) < 0.25,
			"快照保存主液幕冻结进度", str(slot.get("progress")))
	var new_marks: int = game.paint_layer.splat_count() + game.paint_layer.fleck_count()
	ok(new_marks > old_marks, "新增 Shader 墙渍没有替换既有真实落点碎渍",
			"before=%d after=%d" % [old_marks, new_marks])

	# 先让小喷血自然结束，验证回池节点没有空转。
	if wound != null:
		wound._process(wound.duration)
		ok(game.fx_layer.wound_pool_size() == 1 and not wound.active
				and not wound.is_processing(), "伤口小喷血自然结束后进入对象池并停用")

	# 完成并复用主液幕，覆盖信号只绑定一次以及池中不空转的合同。
	main_effect._process(main_effect.duration)
	ok(game.fx_layer.slime_pool_size() == 1 and not main_effect.active
			and not main_effect.is_processing(), "主液幕结束后回池并彻底关闭 process")

	# 走一次正式球棒命中链：新喷口随受击敌人滑移，已经冻结的彩色墙渍仍钉在命中点。
	var target: Node2D = game.minions[0]
	game.player.face = 1
	game.player.position.x = target.position.x - 120.0
	var production_hit_point: Vector2 = target.body_rect().get_center()
	var target_start_x := target.position.x
	game._on_player_bat_swung(target.body_rect(), 2)
	var production_wounds := _active_wounds(game.fx_layer, wound_script)
	var production_mains := _active_slime_ribbons(game.fx_layer)
	ok(production_wounds.size() == 1 and production_mains.size() == 1,
			"正式球棒链同时登记击退、主喷溅与伤口续喷")
	var production_wound = production_wounds[0] if not production_wounds.is_empty() else null
	var production_main = production_mains[0] if not production_mains.is_empty() else null
	var droplets_before: Array[Vector2] = []
	if production_wound != null:
		droplets_before = production_wound.debug_droplet_world_positions()
	game._update_enemy_knockbacks(0.09)
	if production_wound != null:
		production_wound._process(0.01)
		var emitter_error: float = production_wound.global_position.distance_to(
				target.body_rect().get_center().round())
		ok(emitter_error <= 1.0 and bool(production_wound.debug_stats()["following"]),
				"伤口喷口跟随被球棒击退的敌人身体中心", "error=%.2f" % emitter_error)
		var droplets_after: Array[Vector2] = production_wound.debug_droplet_world_positions()
		var old_drop_shift := droplets_before[0].distance_to(droplets_after[0]) \
				if not droplets_before.is_empty() and not droplets_after.is_empty() else 999.0
		ok(old_drop_shift < 8.0 and target.position.x - target_start_x > 30.0,
				"旧血滴保留世界弹道，不会跟尸体整束平移",
				"drop=%.2f target=%.2f" % [old_drop_shift, target.position.x - target_start_x])
	var snapshot_before_follow: int = manager.active_count()
	if production_main != null:
		production_main._process(0.16)
	var moving_slot: Dictionary = manager.debug_snapshot(snapshot_before_follow)
	var fixed_stain_position: Vector2 = moving_slot.get("world_position", Vector2.INF)
	game._update_enemy_knockbacks(0.30)
	if production_wound != null:
		production_wound._process(0.01)
	var moving_slot_after: Dictionary = manager.debug_snapshot(snapshot_before_follow)
	ok(fixed_stain_position == production_hit_point.round()
			and Vector2(moving_slot_after.get("world_position", Vector2.INF)) == fixed_stain_position,
			"敌人继续移动后，持久彩色墙渍仍固定在最初命中世界坐标")
	ok(game.debug_enemy_knockback_count() == 0,
			"球棒击退在短时缓出后停止，不留下持续漂移状态")
	if production_wound != null:
		production_wound._process(production_wound.duration)
	if production_main != null:
		production_main._process(production_main.duration)

	var serial_before_reuse := int(manager.debug_stats()["serial"])
	var reused_effect = game.fx_layer.spawn_bat_hit(hit_point + Vector2(24, 0),
			hit_direction, 1.35)
	var reused_wounds := _active_wounds(game.fx_layer, wound_script)
	ok(reused_effect == main_effect, "主液幕实例由对象池复用")
	ok(wound != null and reused_wounds.size() == 1 and reused_wounds[0] == wound,
			"伤口小喷血实例由对象池复用")
	reused_effect._process(0.16)
	var after_reuse: Dictionary = manager.debug_stats()
	ok(int(after_reuse["serial"]) == serial_before_reuse + 1,
			"复用液幕的一次冻结信号只生成一张快照", str(after_reuse))
	if wound != null:
		wound._process(wound.duration)
	reused_effect._process(reused_effect.duration)

	manager.set_persistent_enabled(false)
	var disabled_before: Dictionary = manager.debug_stats()
	var marks_before_disabled: int = (game.paint_layer.splat_count()
			+ game.paint_layer.fleck_count())
	var disabled_effect = game.fx_layer.spawn_bat_hit(hit_point, hit_direction, 1.35)
	disabled_effect._process(0.16)
	var disabled_after: Dictionary = manager.debug_stats()
	ok(int(disabled_after["active"]) == int(disabled_before["active"])
			and int(disabled_after["slots"]) == int(disabled_before["slots"])
			and int(disabled_after["serial"]) == int(disabled_before["serial"]),
			"关闭持久血迹后命中不再分配或覆盖快照", str(disabled_after))
	var marks_after_disabled: int = (game.paint_layer.splat_count()
			+ game.paint_layer.fleck_count())
	ok(marks_after_disabled > marks_before_disabled,
			"关闭新墙渍后既有真实落点碎渍仍继续工作",
			"before=%d after=%d" % [marks_before_disabled, marks_after_disabled])
	ok(not manager.visible and int(disabled_after["visible"]) == 0,
			"完全关闭开关会隐藏已有墙渍且可见统计归零")

	game.fx_layer.clear_explosions()
	ok(game.fx_layer.wound_pool_size() == 1 and (wound == null or not wound.is_processing()),
			"清场后活动小喷血安全回池")

	# 四条公开入口逐一验强弱档，防止致命状态与视觉 power 被混为一谈。
	game.fx_layer.spawn_slime_hit(hit_point, hit_direction, 0.22)
	var mode_wounds := _active_wounds(game.fx_layer, wound_script)
	ok(mode_wounds.size() == 1 and not bool(mode_wounds[0].debug_stats()["strong"]),
			"普通弱受击使用短伤口喷血")
	game.fx_layer.clear_explosions()
	game.fx_layer.spawn_slime_burst(hit_point, hit_direction, 1.0)
	mode_wounds = _active_wounds(game.fx_layer, wound_script)
	ok(mode_wounds.size() == 1 and bool(mode_wounds[0].debug_stats()["strong"]),
			"标准死亡液幕使用强伤口喷血")
	game.fx_layer.clear_explosions()
	game.fx_layer.spawn_bat_hit(hit_point, hit_direction, 1.10)
	mode_wounds = _active_wounds(game.fx_layer, wound_script)
	ok(mode_wounds.size() == 1 and not bool(mode_wounds[0].debug_stats()["strong"]),
			"非致命高连段球棒命中仍使用普通伤口喷血")
	game.fx_layer.clear_explosions()
	game.fx_layer.spawn_bat_hit(hit_point, hit_direction, 1.0, true)
	mode_wounds = _active_wounds(game.fx_layer, wound_script)
	ok(mode_wounds.size() == 1 and bool(mode_wounds[0].debug_stats()["strong"]),
			"爆炸桶等低 power 致死可显式覆盖为强伤口喷血")
	game.fx_layer.clear_explosions()
	_free_game(game)
	await process_frame
	_finish()


func _active_wounds(fx_layer: Node, wound_script: Script) -> Array:
	var found: Array = []
	for child in fx_layer.get_children():
		if child.get_script() == wound_script and child.active:
			found.append(child)
	return found


func _active_slime_ribbons(fx_layer: Node) -> Array:
	var found: Array = []
	for child in fx_layer.get_children():
		if child is SlimeRibbonBurst and child.active:
			found.append(child)
	return found


func _free_game(game) -> void:
	for audio in game._sfx_pool:
		audio.stop()
		audio.stream = null
	game._sfx.clear()
	game.queue_free()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
