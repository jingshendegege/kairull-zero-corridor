extends SceneTree
## 正式击杀接线：真实世界惯性、一次接地尘、同款枪手、时停和回退；数学弹道另由201项solver测试覆盖。
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func _run() -> void:
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	root.add_child(boot)
	var game: Node2D = boot.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	# BGM不属于本测试，保留播放到末尾的真实音频等待，避免初建同帧play/stop制造MP3线程假泄漏。
	game.action_audio_enabled = false
	game._sfx.clear()
	var enemy: Node2D = game.minions[0]
	var start: Vector2 = enemy.position
	var before_alive: int = game._enemies().size()
	game.player.position = start - Vector2(70, 0)
	game.player.face = 1
	game._on_player_bat_swung(enemy.body_rect().grow(1.0), 0)
	check(enemy.dead and game._enemies().size() == before_alive - 1, "球棒当场击杀，不等腾空落地才扣清敌数")
	check(game._corpse_impacts.size() == 1 and game.debug_enemy_knockback_count() == 1 \
			and game._enemy_knockbacks.is_empty(), "真实球棒只登记一个惯性任务，不能叠加旧水平位移")
	_advance(game, enemy, 0.14)
	check(start.y - enemy.position.y > 20.0 and start.y - enemy.position.y < 25.0 \
			and enemy.corpse_lift == 0.0, "尸体根位置真实离地约23px，不叠加旧美术lift", str(enemy.position - start))
	check(enemy.position.x > start.x + 65.0, "小抛物线向前飞行时保留横向动量")
	check(enemy.corpse_ground_projected and enemy.corpse_ground_valid \
			and absf(enemy.corpse_ground_y - start.y) < 0.5,
			"飞行阴影投向真实地面，不跟着根坐标浮起")
	check(game.fx_layer.corpse_dust_stats().total == 0, "空中不提前冒落地尘")
	var motion: RefCounted = game._corpse_impacts[0].motion
	var age: float = game._corpse_impacts[0].motion.elapsed
	var frozen_position: Vector2 = enemy.position
	game.timeline_enabled = true
	game.player.keys = {MOUSE_BUTTON_RIGHT: true}
	game._physics_process(0.08)
	check(game.time_charge.active and is_equal_approx(game._corpse_impacts[0].motion.elapsed, age) \
			and enemy.position == frozen_position, "时停冻结尸体实际位置与弹道时钟，不提前落尘")
	game.player.keys.clear()
	game._physics_process(0.01)
	check(not game.time_charge.active and game._corpse_impacts[0].motion.elapsed > age, "时停结束继续原轨迹")
	game.timeline_enabled = false
	for _i in 80:
		if motion.landed:
			break
		_advance(game, enemy, 1.0 / 120.0)
	check(game.fx_layer.corpse_dust_stats().total == 1, "首次落地生成且仅生成一个尘土实例")
	var dust: Node2D = game.fx_layer._corpse_dust_active[0]
	var dust_anchor: Vector2 = dust.position
	check(dust_anchor.distance_to(motion.landing_position) < 0.6 \
			and absf(dust_anchor.y - (start.y + 0.1)) < 0.6,
			"灰尘生成在求解器首次真实接地点，保留独立世界锚")
	_advance(game, enemy, 0.04)
	check(start.y - enemy.position.y > 0.0 and start.y - enemy.position.y < 5.0 \
			and motion.bounce_count == 1, "第一次落地后真实根坐标轻弹不到5px且只弹一次")
	check(enemy.position.x > dust_anchor.x + 8.0 and dust.position == dust_anchor,
			"尸体接地后继续有惯性向前，灰尘留在首次落点而不追着尸体跑")
	_advance(game, enemy, 0.6)
	check(absf(enemy.position.y - start.y) < 0.4 and game._corpse_impacts.is_empty(),
			"轻弹和摩擦滑行结束后落稳并回收任务")
	check(game.fx_layer.corpse_dust_stats().total == 1, "回弹落地不再重复生成尘爆")
	check(absf(enemy.position.x - start.x - 210.6) < 3.0,
			"首段真实惯性约211px，明显比旧94px更远", str(enemy.position.x - start.x))
	var gunner: Node2D
	for item: Node2D in game.minions:
		if item is GruntGunner:
			gunner = item
			break
	gunner.position = start
	gunner.take_hit(gunner.position.x - 50.0)
	game._start_corpse_impact(gunner, 2, 1.0)
	_advance(game, gunner, 0.14)
	check(start.y - gunner.position.y > 20.0 and gunner.position.x > start.x + 80.0 \
			and gunner.corpse_lift == 0.0, "枪手同款真实小抛物线，强击横向冲量更大")
	game.corpse_impact_enabled = false
	game._update_enemy_knockbacks(0.01)
	check(gunner.corpse_lift == 0.0 and game._corpse_impacts.is_empty() \
			and absf(gunner.position.y - start.y) < 0.4, "回退开关立即清曲线并安全收尾到地面，不留悬空尸体")
	var fallback_start: Vector2 = gunner.position
	game._start_enemy_knockback(gunner, Vector2.RIGHT, 0, true)
	check(game._enemy_knockbacks.size() == 1 and game._corpse_impacts.is_empty(),
			"关闭新惯性后新命中回退到旧水平模式，不丢失击退")
	_advance(game, gunner, 0.5)
	check(absf(gunner.position.x - fallback_start.x - 94.4) < 1.0 \
			and absf(gunner.position.y - fallback_start.y) < 0.4,
			"回退模式保留旧94px水平击退，便于A/B比较")
	game.corpse_impact_enabled = true
	var unsupported := GruntGunner.new()
	root.add_child(unsupported)
	unsupported.position = start - Vector2(0, 100)
	var airborne_start: Vector2 = unsupported.position
	unsupported.take_hit(0)
	game._start_corpse_impact(unsupported, 0, 1.0)
	check(game._corpse_impacts.size() == 1, "空中死亡也登记真实弹道，不再要求发射时已经着地")
	var dust_before: int = game.fx_layer.corpse_dust_stats().total
	_advance(game, unsupported, 0.4)
	check(unsupported.position.x > airborne_start.x + 150.0 \
			and unsupported.position.y > airborne_start.y + 20.0,
			"空中尸体沿受力方向飞出并受重力下落", str(unsupported.position - airborne_start))
	check(game.fx_layer.corpse_dust_stats().total == dust_before,
			"尚未落到真实地面，空中弹道不能提前冒落地尘")
	unsupported.free()
	game._update_enemy_knockbacks(0.0)
	check(game._corpse_impacts.is_empty(), "空中尸体提前销毁后回收WeakRef任务")
	var barrel_target: Node2D = game.minions[2]
	var barrel := PropBarrel.new()
	barrel.position = barrel_target.position
	game._on_barrel_exploded(barrel)
	check(barrel_target.dead and game._corpse_impacts.size() > 0, "爆炸击杀同样接入真实惯性小抛物线")
	var follows_explosion_corpse := false
	for effect: Node in game.fx_layer.get_children():
		if effect is WoundBloodSpray and effect.active and effect._follow_target_ref != null:
			follows_explosion_corpse = follows_explosion_corpse or effect._follow_target_ref.get_ref() == barrel_target
	check(follows_explosion_corpse, "爆炸击杀的伤口喷口跟随实际飞出的尸体")
	barrel.free()
	game._clear_corpse_impacts()
	game._start_corpse_impact(gunner, 0, 1.0)
	_advance(game, gunner, 0.05)
	game._on_player_fell_out()
	check(game._corpse_impacts.is_empty() and gunner.corpse_lift == 0.0 \
			and game.fx_layer.corpse_dust_stats().active == 0, "旧跌落重置一并清除尸体表现和灰尘")
	game._start_corpse_impact(gunner, 0, 1.0)
	_advance(game, gunner, 0.14)
	game.timeline_enabled = true
	game._begin_rewind()
	var rewind_age: float = game._corpse_impacts[0].motion.elapsed
	game._physics_process(0.1)
	check(game.time_phase == "rewinding" and game._corpse_impacts[0].motion.elapsed == rewind_age \
			and game.fx_layer.corpse_dust_stats().active == 0, "倒带只读姿态，不推进尸体或再次制造尘土")
	game._clear_corpse_impacts()
	game.fx_layer.clear_explosions()
	await create_timer(0.20).timeout
	boot.free()
	await create_timer(0.15).timeout  # 音频销毁回收发生在混音线程，给它真实时间而非一个极短空帧。
	check(not is_instance_valid(gunner), "场景销毁同时清除尸体节点")
	print("CORPSE_IMPACT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func _advance(game: Node2D, target: Node2D, duration: float) -> void:
	var left := duration
	while left > 0.000001:
		var dt := minf(left, 1.0 / 60.0)
		target.step(dt)
		# 总入口内部已推进新惯性，不能再手动_update_corpse_impacts导致双倍时间/距离。
		game._update_enemy_knockbacks(dt)
		left -= dt
