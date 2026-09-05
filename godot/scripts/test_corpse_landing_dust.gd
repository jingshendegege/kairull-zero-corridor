extends SceneTree
## 尸体落地尘：低幅度、池容量、时停继承和重开回收，不依赖截图判断逻辑。

const Dust := preload("res://scripts/corpse_landing_dust.gd")
const Fx := preload("res://scripts/fx_layer.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  ", label)
	else:
		_failed += 1
		print("  FAIL  ", label)


func _run() -> void:
	var dust := Dust.new()
	root.add_child(dust)
	ok(not dust.active and not dust.visible and not dust.is_processing(), "新建实例不空转")
	ok(dust.process_mode == Node.PROCESS_MODE_INHERIT, "处理模式继承父节点时停")
	ok(dust.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "保持 nearest 像素采样")
	var completed: Array = []
	dust.finished.connect(func(effect: Node2D) -> void: completed.append(effect))
	dust.global_position = Vector2(100.0, 200.0)
	dust.play(1.0, 1.0, 123)
	ok(dust.active and dust.visible and dust.is_processing(), "播放启用绘制和生命周期")
	ok(dust.debug_stats()["particles"] == 14 and dust.debug_stats()["size_min"] == 3
			and dust.debug_stats()["size_max"] == 6 and dust.debug_stats()["max_rects_per_particle"] == 3
			and is_equal_approx(dust.opacity, 0.72), "默认14颗3..6px扁尘簇，每粒最多3矩形且透明度0.72")
	ok(is_equal_approx(dust.duration, 0.32), "默认寿命0.32秒")
	var origin := dust.debug_particle_world_positions()
	var left := 0
	var right := 0
	for point in origin:
		if point.x < 100.0:
			left += 1
		if point.x > 100.0:
			right += 1
	ok(left == 7 and right == 7, "出生左右两侧均有灰尘")
	dust._process(0.12)
	var spread := dust.debug_particle_world_positions()
	var bounded := true
	var integer_points := true
	var expands_both_sides := true
	for i in spread.size():
		var point := spread[i]
		bounded = bounded and point.y <= 200.0 and point.y >= 190.0 and absf(point.x - 100.0) <= 35.0
		integer_points = integer_points and point == point.round()
		if origin[i].x < 100.0:
			expands_both_sides = expands_both_sides and point.x < origin[i].x
		else:
			expands_both_sides = expands_both_sides and point.x > origin[i].x
	ok(bounded, "落地尘贴地低抛且不进入地板")
	ok(integer_points, "灰尘绘制落点为整数像素")
	ok(expands_both_sides, "灰尘向两边展开而非单向喷血")
	var elapsed := dust.elapsed
	dust._process(-1.0)
	ok(is_equal_approx(dust.elapsed, elapsed), "负时间不倒播或延长灰尘")
	dust._process(1.0)
	ok(not dust.active and not dust.visible and not dust.is_processing(), "寿命结束关闭节点处理")
	ok(dust.debug_stats()["particles"] == 0, "寿命结束释放粒子字典")
	ok(completed.size() == 1 and completed[0] == dust, "完成只发一次回池信号")
	dust._process(1.0)
	ok(completed.size() == 1, "回池后不再重复通知完成")
	dust.play(-10.0, -1.0, 123)
	ok(dust.debug_stats()["particles"] == 10 and dust.debug_stats()["power"] == 0.5, "极低power安全下限10颗")
	ok(dust.debug_stats()["direction"] == -1.0, "向左受击方向可用")
	dust.play(100.0, 0.0, 123)
	ok(dust.debug_stats()["particles"] == 18 and dust.debug_stats()["power"] == 1.5, "极高power封顶18颗")
	ok(dust.debug_stats()["direction"] == 1.0, "零方向安全回退")
	dust.base_duration = 9.0
	dust.play()
	ok(dust.duration == 0.4, "Inspector越界也不超过0.4秒")
	dust.stop()
	ok(completed.size() == 1, "手动回收不误发自然完成")
	dust.free()

	var fx := Fx.new()
	fx.position = Vector2(21.0, 31.0)
	root.add_child(fx)
	var first := fx.spawn_corpse_landing_dust(Vector2(123.4, 245.6)) as Dust
	ok(first.global_position == Vector2(123.0, 246.0), "API传入世界落点而非父层局部坐标")
	ok(first.z_index == -2, "灰尘层级低于彩血与子弹")
	ok(fx.corpse_dust_stats()["total"] == 1 and fx.corpse_dust_stats()["active"] == 1, "管理器记录活跃灰尘")
	# 模拟正式右键时停：禁用父Fx，真实场景帧经过后灰尘寿命保持不变。
	fx.process_mode = Node.PROCESS_MODE_DISABLED
	var frozen_elapsed := first.elapsed
	await create_timer(0.04).timeout
	ok(is_equal_approx(first.elapsed, frozen_elapsed) and not first.can_process(), "父Fx时停后真实经过多帧仍冻结")
	fx.process_mode = Node.PROCESS_MODE_INHERIT
	await process_frame
	await process_frame
	ok(first.elapsed > frozen_elapsed, "解除时停后继续同一落地尘寿命")
	fx.clear_explosions()
	ok(fx.corpse_dust_stats()["active"] == 0 and fx.corpse_dust_stats()["pooled"] == 1, "统一重开清理入口回收灰尘")
	ok(not first.active and not first.is_processing(), "重开清理的节点完全停用")
	var replay := fx.spawn_corpse_landing_dust(Vector2(300.0, 400.0))
	ok(replay == first and first.elapsed == 0.0, "下一落点复用原节点并归零时间")
	for i in 11:
		fx.spawn_corpse_landing_dust(Vector2(300.0 + i, 400.0))
	ok(fx.corpse_dust_stats()["active"] == 12 and fx.corpse_dust_stats()["total"] == 12, "活跃节点最多12个")
	var oldest := fx.spawn_corpse_landing_dust(Vector2(500.0, 500.0))
	ok(oldest == first and oldest.global_position == Vector2(500.0, 500.0), "满池复用最旧活跃尘而不扩容")
	ok(fx.get_child_count() == 12 and fx.corpse_dust_stats()["total"] == 12, "连击峰值也不产生第13个节点")
	for i in 40:
		fx.spawn_corpse_landing_dust(Vector2(90000.0, 90000.0))
	ok(fx.get_child_count() == 12, "连续离屏请求仍严格有界")
	for child in fx.get_children():
		child._process(0.5)
	ok(fx.corpse_dust_stats()["active"] == 0 and fx.corpse_dust_stats()["pooled"] == 12, "全部离屏实例自然结束并回池")
	var all_stopped := true
	for child in fx.get_children():
		all_stopped = all_stopped and not child.is_processing()
	ok(all_stopped, "离屏回池节点不再运行逐帧工作")
	fx.clear_explosions()
	fx.clear_explosions()
	ok(fx.corpse_dust_stats()["pooled"] == 12, "重复重开清理不重复入池")
	fx.free()
	await process_frame
	print("=== %d 通过, %d 失败 ===" % [_passed, _failed])
	print("TEST_RESULT: " + ("PASS" if _failed == 0 else "FAIL"))
	quit(0 if _failed == 0 else 1)
