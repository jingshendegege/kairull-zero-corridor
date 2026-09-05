extends SceneTree
## Ribbon 撞墙验证：液丝/液滴真实撞上实体墙后，paint layer 在精确撞点长撞击印。

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
	var level := CorridorLevel.new()
	get_root().add_child(level)
	level.build(false)

	var paint := SlimePaintLayer.new()
	paint.level = level
	get_root().add_child(paint)

	var packed := load("res://scenes/fx/slime_ribbon_burst.tscn") as PackedScene
	var burst := packed.instantiate() as SlimeRibbonBurst
	burst.level = level
	get_root().add_child(burst)
	# 撞墙信号直接落到 paint layer，绕开 fx_layer/host 的无头装配。
	burst.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		paint.add_impact_splat(pos, radius, slot, weak, 9900 + slot, on_wall))

	# 紧贴左边界墙（x<32 是一列 #），向左打死亡液幕，必然有液丝/液滴撞墙。
	# 播多个 seed：撞墙依赖流丝实际轨迹与摆动相位，单 seed 可能恰好擦过墙。
	var hit_seeds := [5555, 1234, 7777, 4242, 8888, 9021]
	var impacts := 0
	burst.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		impacts += 1)
	for s in hit_seeds:
		burst.position = Vector2(220, 300)
		burst.play(1.0, Vector2.LEFT, s, false)
		# headless 下 process_frame 的 dt 很短（真实耗时驱动），需要多次迭代才覆盖完整喷射时长。
		for i in 400:
			await process_frame
			if burst.elapsed > burst.duration:
				break

	var stats: Array = paint.debug_centers()
	ok(stats.size() >= 1, "撞墙产生了撞击印", str(stats.size()))
	if stats.size() >= 1:
		var any_wall := false
		for center in stats:
			# 撞点必须确实贴墙
			if Vector2(center).x <= 40.0:
				any_wall = true
		ok(any_wall, "撞击印落在墙面上（x<=40）")
		ok(paint.debug_satellite_count() >= 3, "撞击印带卫星小液点",
				str(paint.debug_satellite_count()))
	burst.queue_free()
	paint.queue_free()
	level.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
