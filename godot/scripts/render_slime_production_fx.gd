extends SceneTree
## 正式版本验收：左侧普通受击弱液丝，右侧死亡完整液幕；两者都写入起点墙漆。

const FRAME_COUNT := 45


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var background := ColorRect.new()
	background.color = Color("#050914")
	background.size = Vector2(1360, 765)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(background)

	# 真实关卡：左右两排 panel 各挂一段真实墙体，ribbon 液滴才能真正撞墙。
	var level := CorridorLevel.new()
	level.build(true)
	get_root().add_child(level)

	var hit_world := _make_panel(Vector2.ZERO)
	var death_world := _make_panel(Vector2(680, 0))
	get_root().add_child(hit_world)
	get_root().add_child(death_world)
	var hit_paint := SlimePaintLayer.new()
	var death_paint := SlimePaintLayer.new()
	# paint 也挂 root，和 ribbon 同一坐标系
	get_root().add_child(hit_paint)
	get_root().add_child(death_paint)
	hit_paint.level = level
	death_paint.level = level

	var packed := load("res://scenes/fx/slime_ribbon_burst.tscn") as PackedScene
	var hit := packed.instantiate() as SlimeRibbonBurst
	var death := packed.instantiate() as SlimeRibbonBurst
	# ribbon 直接挂 root，position 即全局坐标，确保撞到左边界墙（x<32）
	hit.level = level
	death.level = level
	hit.position = Vector2(220, 300)
	death.position = Vector2(880, 520)
	get_root().add_child(hit)
	get_root().add_child(death)
	# 两侧都向左打：受击版撞左墙，死亡版也向左打（从右侧 (880,520) 起飞）
	# 注意死亡 ribbon 位移大、飞行 1.08 秒，走 ~700px 能撞左墙。
	var hit_direction := Vector2(-1.0, -0.06).normalized()
	var death_direction := Vector2(-1.0, 0.30).normalized()   ## 稍微向下偏，便于液滴坠墙
	hit.paint_requested.connect(func(pos: Vector2, dir: Vector2, power: float,
			seed: int, weak: bool) -> void:
		hit_paint.spray(pos, dir, power * 0.45, seed))
	death.paint_requested.connect(func(pos: Vector2, dir: Vector2, power: float,
			seed: int, weak: bool) -> void:
		death_paint.spray(pos, dir, power, seed))
	# 撞墙信号：液丝/液滴真实命中时在精确撞点长出 BD 式污渍。
	hit.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		hit_paint.add_impact_splat(pos, radius, slot, weak, 7100 + slot, on_wall))
	death.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		death_paint.add_impact_splat(pos, radius, slot, weak, 7200 + slot, on_wall))

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	_make_label("普通受击 · 弱化液丝", Vector2(38, 24), Color("#75dce9"), 22, font)
	_make_label("3 条短液丝 / 4 颗小液滴 / 小型起点喷漆", Vector2(38, 54), Color("#9ab0c9"), 13, font)
	_make_label("敌人死亡 · 完整液幕", Vector2(718, 24), Color("#ff78b4"), 22, font)
	_make_label("主液幕撕裂 / 5 条拉丝 / 11 颗重液滴 / 完整墙漆", Vector2(718, 54), Color("#9ab0c9"), 13, font)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://slime_production_fx")
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("baseline.png"))

	var hit_seed := 8301
	var death_seed := 8302
	hit_paint.stamp_origin_burst(hit.position, hit_direction, 0.22, hit_seed, true)
	death_paint.stamp_origin_burst(death.position, death_direction, 1.0, death_seed, false)
	hit.play(0.22, hit_direction, hit_seed, true)
	death.play(1.0, death_direction, death_seed, false)
	var hit_trauma := 0.52 * 0.22
	var death_trauma := 0.52
	var shake_time := 0.0
	for i in FRAME_COUNT:
		await process_frame
		shake_time += 1.0 / 30.0
		hit_trauma = maxf(0.0, hit_trauma - (1.0 / 30.0) * 2.35)
		death_trauma = maxf(0.0, death_trauma - (1.0 / 30.0) * 2.35)
		hit_world.position = _shake_offset(hit_direction, hit_trauma, shake_time)
		death_world.position = Vector2(680, 0) + _shake_offset(death_direction, death_trauma, shake_time)
		RenderingServer.force_draw()
		var image := get_root().get_texture().get_image()
		var path := out_dir.path_join("frame_%03d.png" % i)
		var err := image.save_png(path)
		if err != OK:
			push_error("保存预览帧失败：%s err=%s" % [path, err])
			quit(1)
			return

	print("HIT_STATS: ", hit.debug_stats())
	print("DEATH_STATS: ", death.debug_stats())
	print("HIT_PAINT: ", hit_paint.splat_count())
	print("DEATH_PAINT: ", death_paint.splat_count())
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)


func _shake_offset(direction: Vector2, trauma: float, time: float) -> Vector2:
	var envelope := trauma * trauma
	var kick := -direction * trauma * 11.0
	var jitter := Vector2(sin(time * 73.0) * 8.0,
			sin(time * 97.0 + 1.3) * 5.5) * envelope
	return (kick + jitter).round()


func _make_panel(base_position: Vector2) -> Node2D:
	var world := Node2D.new()
	world.position = base_position
	var panel := ColorRect.new()
	panel.color = Color("#0a1221")
	panel.position = Vector2(18, 88)
	panel.size = Vector2(644, 572)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(panel)
	var wall := ColorRect.new()
	wall.color = Color("#17283f")
	wall.position = Vector2(18, 88)
	wall.size = Vector2(644, 572)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(wall)
	for i in 8:
		var seam := Line2D.new()
		seam.points = PackedVector2Array([
			Vector2(18, 118 + i * 67), Vector2(662, 118 + i * 67)])
		seam.width = 1.0
		seam.default_color = Color(0.29, 0.45, 0.62, 0.22)
		world.add_child(seam)
	return world


func _make_label(text: String, position: Vector2, color: Color, size: int, font: Font) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_size", 2)
	get_root().add_child(label)
