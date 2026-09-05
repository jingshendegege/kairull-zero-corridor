extends SceneTree
## 血迹与地图交互：喷溅落在真实表面（带分类），血泊贴地成形。

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
	print("== 血迹 × 地图表面 ==")
	var level := CorridorLevel.new()
	get_root().add_child(level)
	level.build(false)

	var paint := SlimePaintLayer.new()
	paint.level = level
	get_root().add_child(paint)

	# 向左墙喷血：落点必须在左边界墙（x<=40），表面分类为 wall，颜色为红系
	var n := paint.blood_spray(Vector2(120, 300), Vector2.LEFT, 1.2, 42)
	ok(n >= 2, "喷溅产生多束血痕", str(n))
	var wall_hit := false
	var red := false
	for s in paint.splats:
		if s["solid_contact"] and Vector2(s["center"]).x <= 40.0:
			wall_hit = true
			if s["surface"].get("kind", "") == "wall":
				red = s["color"].r > 0.45 and s["color"].g < 0.35
	ok(wall_hit, "血痕落在左墙面上（x<=40）")
	ok(red, "撞墙血痕为红系且分类为 wall")

	# 血泊：从空中垂直下投，落在地面顶（row 19 → y≈608+），分类 floor
	paint.blood_pool(Vector2(600, 500), 1.0, 77)
	var pool: Dictionary = paint.splats.back()
	var pc := Vector2(pool["center"])
	ok(pc.y >= 607.0 and pc.y <= 645.0, "血泊落在地面顶面", str(pc))
	ok(pool["surface"].get("kind", "") == "floor", "血泊表面分类为 floor",
		str(pool["surface"]))
	ok(pool["color"] == SlimePaintLayer.BLOOD_MAIN, "血泊为暗红主色")

	# 台阶上方的血泊：落在单向台面（r16 c43-44 → y≈512+）
	paint.blood_pool(Vector2(43.5 * 32, 300), 1.0, 78)
	var pool2: Dictionary = paint.splats.back()
	var pc2 := Vector2(pool2["center"])
	ok(pc2.y >= 511.0 and pc2.y <= 545.0, "血泊落在台阶台面", str(pc2))
	ok(pool2["surface"].get("kind", "") == "platform", "台面分类为 platform",
		str(pool2["surface"]))

	_finish()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
