extends SceneTree
## 单色族液爆验收：左侧枪械击杀液幕，右侧棒球棍近战打击（星芒+冲击环）。
## 两侧都写入真实墙漆，液滴撞墙/撞地在精确撞点留渍。

const FRAME_COUNT := 45


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var background := ColorRect.new()
	background.color = Color("#050914")
	background.size = Vector2(1360, 765)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(background)

	var level := CorridorLevel.new()
	level.build(true)
	get_root().add_child(level)

	var gun_world := _make_panel(Vector2.ZERO)
	var bat_world := _make_panel(Vector2(680, 0))
	get_root().add_child(gun_world)
	get_root().add_child(bat_world)
	var gun_paint := SlimePaintLayer.new()
	var bat_paint := SlimePaintLayer.new()
	get_root().add_child(gun_paint)
	get_root().add_child(bat_paint)
	gun_paint.level = level
	bat_paint.level = level

	var packed := load("res://scenes/fx/slime_ribbon_burst.tscn") as PackedScene
	var gun := packed.instantiate() as SlimeRibbonBurst
	var bat := packed.instantiate() as SlimeRibbonBurst
	gun.level = level
	bat.level = level
	gun.position = Vector2(300, 320)
	bat.position = Vector2(940, 340)
	get_root().add_child(gun)
	get_root().add_child(bat)
	var gun_direction := Vector2(-1.0, 0.18).normalized()
	var bat_direction := Vector2(-1.0, -0.28).normalized()   ## 棍击上挑
	var hue_g := SlimeRibbonBurst.hue_for_seed(8301)
	var hue_b := SlimeRibbonBurst.hue_for_seed(8302)
	gun.paint_requested.connect(func(pos: Vector2, dir: Vector2, power: float,
			seed: int, weak: bool) -> void:
		gun_paint.spawn_spatter(pos, dir, power, seed, hue_g, 34))
	bat.paint_requested.connect(func(pos: Vector2, dir: Vector2, power: float,
			seed: int, weak: bool) -> void:
		bat_paint.spawn_spatter(pos, dir, power, seed, hue_b, 44))
	gun.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		gun_paint.add_impact_splat(pos, radius, slot, weak, 7100 + slot, on_wall,
				hue_g.darkened(0.12)))
	bat.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		bat_paint.add_impact_splat(pos, radius, slot, weak, 7200 + slot, on_wall,
				hue_b.darkened(0.12)))

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	_make_label("枪械击杀 · 单色族液幕", Vector2(38, 24), hue_g.lightened(0.35), 22, font)
	_make_label("白闪核心 / 5 条同族拉丝 / 11 颗液滴 / 同色墙漆", Vector2(38, 54), Color("#9ab0c9"), 13, font)
	_make_label("棒球棍近战 · 星芒冲击", Vector2(718, 24), hue_b.lightened(0.35), 22, font)
	_make_label("8 向星芒 / 冲击环 / 收紧扇面 / 更重震屏", Vector2(718, 54), Color("#9ab0c9"), 13, font)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://bat_fx")
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("baseline.png"))

	var gun_seed := 8301
	var bat_seed := 8302
	gun.play(1.0, gun_direction, gun_seed, false)
	bat.play(1.0, bat_direction, bat_seed, false, true)
	# 定格星芒瞬间：暂停自动推进，手动把时钟拨到 0.03s 再抓帧
	# （渲染循环里存 PNG 很慢，真实 dt 一晃就超过 0.14s 的星芒寿命）
	gun.set_process(false)
	bat.set_process(false)
	gun._process(0.03)
	bat._process(0.03)
	await process_frame
	RenderingServer.force_draw()
	get_root().get_texture().get_image().save_png(out_dir.path_join("frame_star.png"))
	gun.set_process(true)
	bat.set_process(true)
	var gun_trauma := 0.52
	var bat_trauma := 0.52 * 1.35
	var shake_time := 0.0
	for i in FRAME_COUNT:
		await process_frame
		shake_time += 1.0 / 30.0
		gun_trauma = maxf(0.0, gun_trauma - (1.0 / 30.0) * 2.35)
		bat_trauma = maxf(0.0, bat_trauma - (1.0 / 30.0) * 2.35)
		gun_world.position = _shake_offset(gun_direction, gun_trauma, shake_time)
		bat_world.position = Vector2(680, 0) + _shake_offset(bat_direction, bat_trauma, shake_time)
		RenderingServer.force_draw()
		var image := get_root().get_texture().get_image()
		var err := image.save_png(out_dir.path_join("frame_%03d.png" % i))
		if err != OK:
			push_error("保存预览帧失败 err=%s" % err)
			quit(1)
			return

	print("GUN_STATS: ", gun.debug_stats())
	print("BAT_STATS: ", bat.debug_stats())
	print("GUN_PAINT: ", gun_paint.splat_count())
	print("BAT_PAINT: ", bat_paint.splat_count())
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
