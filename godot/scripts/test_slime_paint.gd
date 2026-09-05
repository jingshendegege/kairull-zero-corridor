extends SceneTree
## 史莱姆墙面涂料测试：喷溅中心必须跟随受力方向，而不是永远径向随机。

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
	print("== SlimePaintLayer direction ==")
	var script_path := "res://scripts/slime_paint_layer.gd"
	if not ResourceLoader.exists(script_path):
		ok(false, "存在可持久绘制的墙面涂料层", script_path)
		_finish()
		return

	var paint_script := load(script_path)
	var paint = paint_script.new()
	get_root().add_child(paint)
	await process_frame

	var origin := Vector2(300, 220)
	var added: int = paint.spray(origin, Vector2.RIGHT, 1.0, 6701)
	var centers: Array = paint.debug_centers()
	var mean := Vector2.ZERO
	for center in centers:
		mean += center
	if not centers.is_empty():
		mean /= centers.size()

	ok(added >= 6, "一次爆裂留下多块持久涂料", str(added))
	ok(paint.splat_count() == added, "涂料记录不会随瞬时粒子消失")
	ok(mean.x > origin.x + 45.0, "受力向右时涂料主体落在右侧", str(mean))

	print("== SlimePaintLayer origin burst ==")
	if not paint.has_method("stamp_origin_burst"):
		ok(false, "死亡爆点可立即留下喷射状背景颜料印")
		paint.queue_free()
		await process_frame
		_finish()
		return
	var before_origin_stamp: int = paint.splat_count()
	var origin_added: int = paint.stamp_origin_burst(origin, Vector2.RIGHT, 1.0, 6705, false)
	var all_centers: Array = paint.debug_centers()
	var furthest_x := origin.x
	for i in range(before_origin_stamp, all_centers.size()):
		furthest_x = maxf(furthest_x, Vector2(all_centers[i]).x)
	ok(origin_added >= 5, "死亡起点由主体颜料印和多条喷射痕组成", str(origin_added))
	ok(furthest_x >= origin.x + 48.0, "起始颜料印沿受力方向拉出长喷痕", str(furthest_x))
	var weak_distal_added: int = paint.spray(origin, Vector2.RIGHT, 0.10, 6706)
	ok(weak_distal_added <= 3, "弱化受击的远端颜料数量显著少于死亡版",
			str(weak_distal_added))

	print("== SlimePaintLayer wall contact ==")
	if not paint.has_method("debug_solid_contact_count"):
		ok(false, "液体轨迹可检测关卡实体墙面")
		paint.queue_free()
		await process_frame
		_finish()
		return
	var level := CorridorLevel.new()
	level.build(false)
	paint.level = level
	paint.spray(Vector2(118, 260), Vector2.LEFT, 1.0, 6702)
	ok(paint.debug_solid_contact_count() >= 1, "至少一块油漆命中并黏住实体墙",
			str(paint.debug_solid_contact_count()))
	level.free()
	paint.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
