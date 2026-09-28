extends SceneTree
## 血渍微粒碎片必须是可三角化多边形：地面压扁 + 取整后的退化多边形会让
## draw_colored_polygon 逐帧报 "triangulation failed"（实机一局上千条错误日志）。
## 跑法：godot --headless --path godot --script scripts/test_slime_fleck_polygons.gd
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	var level := CorridorLevel.new()
	get_root().add_child(level)
	level.build(false)
	var paint := SlimePaintLayer.new()
	paint.level = level
	get_root().add_child(paint)
	var total := 0
	var bad := 0
	# 多方向、多种子：向下打地面（压扁碎片最容易退化）、向两侧打墙
	for seed in range(1, 121):
		var dir: Vector2 = [Vector2(0.3, 1.0), Vector2(-0.4, 1.0), Vector2.LEFT, Vector2.RIGHT][seed % 4]
		paint.spawn_spatter(Vector2(40 * 32, 14 * 32), dir, 1.4, seed * 7919, SlimePaintLayer.SPRAY_MAIN, 30)
		for fleck: Dictionary in paint.flecks:
			var poly: PackedVector2Array = fleck["polygon"]
			total += 1
			if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
				bad += 1
		paint.flecks.clear()
	print("FLECK_POLYGONS: total=%d degenerate=%d" % [total, bad])
	check(total > 500, "喷溅实际产生了足量碎片（%d）" % total)
	check(bad == 0, "所有碎片多边形都可三角化（退化 %d）" % bad)
	paint.free()
	level.free()
	print("SLIME_FLECK_POLYGONS_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
