extends SceneTree
## 墙面污渍测试：受击/死亡的方向性喷溅 + 撞墙 BD 式撞击印（放射印+卫星点）。
## 本层不做流淌/下淌动画，污渍生成即定型。

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
	print("== SlimePaintLayer 方向性喷溅 ==")
	var paint := SlimePaintLayer.new()
	get_root().add_child(paint)
	await process_frame
	paint.level = CorridorLevel.new()
	paint.level.build(false)

	# 死亡级喷射打在左侧实体墙上：喷溅中心应命中墙面。
	paint.spray(Vector2(118, 260), Vector2.LEFT, 1.0, 6702)
	ok(paint.debug_solid_contact_count() >= 1, "至少一块喷溅命中并黏住实体墙",
			str(paint.debug_solid_contact_count()))

	# 弱化受击：远端涂料显著少于死亡版。
	var weak_paint := SlimePaintLayer.new()
	get_root().add_child(weak_paint)
	await process_frame
	weak_paint.level = paint.level
	var weak_added := weak_paint.spray(Vector2(118, 260), Vector2.LEFT, 0.18, 6706)
	ok(weak_added <= 3, "弱化受击远端涂料数量显著少于死亡版", str(weak_added))

	print("== 撞墙 BD 式污渍 ==")
	var impact_paint := SlimePaintLayer.new()
	get_root().add_child(impact_paint)
	await process_frame
	impact_paint.level = paint.level
	var before := impact_paint.splat_count()
	impact_paint.add_impact_splat(Vector2(90, 200), 6.0, 0, false, 7101, true)
	ok(impact_paint.splat_count() == before + 1, "撞墙后新增一块撞击印")
	## 撞墙瘫渍固定带 3 颗卫星点 + 2 道静态流痕
	ok(impact_paint.debug_satellite_count() == 5, "撞墙瘫渍含 3 卫星点+2 流痕",
			str(impact_paint.debug_satellite_count()))
	# 弱化受击的撞印整体缩小：再加一颗并对比尺寸。
	impact_paint.add_impact_splat(Vector2(90, 320), 6.0, 0, true, 7102, true)
	ok(impact_paint.splat_count() == before + 2, "弱化受击也产生撞击印")
	ok(impact_paint.debug_satellite_count() == 10, "弱化撞墙瘫渍同样带卫星点+流痕")

	weak_paint.queue_free()
	impact_paint.queue_free()
	paint.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
