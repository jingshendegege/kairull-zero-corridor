extends SceneTree
## 像素粒子爆炸的无头冒烟测试：结构、生命周期与对象池复用。

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
	print("== PixelExplosion ==")
	var packed := load("res://scenes/fx/pixel_explosion.tscn") as PackedScene
	ok(packed != null, "爆炸场景可加载")
	var effect := packed.instantiate() as PixelExplosion
	get_root().add_child(effect)
	await process_frame

	effect.position = Vector2(12.4, 34.7)
	effect.play(1.25)
	var stats := effect.debug_stats()
	ok(effect.active and effect.visible, "播放后处于激活状态")
	ok(effect.position == Vector2(12, 35), "世界位置对齐像素网格", str(effect.position))
	ok(is_equal_approx(effect.scale.x, 1.25), "强度控制整体尺寸", str(effect.scale))
	ok(stats["layers"] == 3, "三层引擎粒子", str(stats))
	ok(stats["particles"] == 66, "每次爆炸共 66 个粒子", str(stats))
	ok(effect.get_node("Sparks") is CPUParticles2D, "高速火花使用 CPUParticles2D")
	ok(effect.get_node("EnergyFragments") is CPUParticles2D, "能量碎片使用 CPUParticles2D")
	ok(effect.get_node("EnergySmoke") is CPUParticles2D, "余烟使用 CPUParticles2D")

	# 手工推进只用于无头测试；正常游戏由 _process 驱动。
	effect._process(PixelExplosion.TOTAL_LIFETIME + 0.01)
	ok(not effect.active and not effect.visible, "生命周期结束后停用")
	effect.queue_free()
	await process_frame

	print("== GameFxLayer pool ==")
	var layer := GameFxLayer.new()
	get_root().add_child(layer)
	await process_frame
	var first := layer.spawn_explosion(Vector2(100.2, 200.8), 1.0)
	ok(first.active and first.position == Vector2(100, 201), "特效层可按世界坐标生成")
	first._process(PixelExplosion.TOTAL_LIFETIME + 0.01)
	ok(layer.explosion_pool_size() == 1, "播放结束回收到对象池")
	var second := layer.spawn_explosion(Vector2(300, 240), 0.8)
	ok(second == first, "下一次爆炸复用同一实例")
	ok(layer.explosion_pool_size() == 0, "复用时从池中取出")
	layer.clear_explosions()
	ok(not second.active and layer.explosion_pool_size() == 1, "清场时停止并回收活动爆炸")
	layer.queue_free()
	await process_frame

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
