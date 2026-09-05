extends SceneTree
## 撞墙瘫渍演示：一面简单墙 + 死亡液爆直接拍上去，展现 lemon-hit-wall 效果。

const FRAME_COUNT := 40

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0a1221")
	bg.size = Vector2(1360, 765)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(bg)

	# 简单竖直墙体（x<180）
	var wall := ColorRect.new()
	wall.color = Color("#17283f")
	wall.position = Vector2(0, 0)
	wall.size = Vector2(180, 765)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(wall)
	# 墙面的砖缝
	for i in 12:
		var seam := Line2D.new()
		seam.points = PackedVector2Array([Vector2(0, 60 + i * 60), Vector2(180, 60 + i * 60)])
		seam.width = 1.0
		seam.default_color = Color(0.15, 0.22, 0.32, 0.55)
		get_root().add_child(seam)

	# 关卡碰撞：用 CorridorLevel 的左边界 # 墙当碰撞源，
	# 但视觉墙用我们自己画的 ColorRect；通过 Ribbon 的 level 接入。
	var level := CorridorLevel.new()
	level.build(false)
	get_root().add_child(level)

	var paint := SlimePaintLayer.new()
	paint.level = level
	get_root().add_child(paint)

	var packed := load("res://scenes/fx/slime_ribbon_burst.tscn") as PackedScene
	var burst := packed.instantiate() as SlimeRibbonBurst
	burst.level = level
	burst.position = Vector2(340, 380)
	get_root().add_child(burst)
	burst.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
			on_wall: bool, weak: bool) -> void:
		paint.add_impact_splat(pos, radius, slot, weak, randi(), on_wall))

	await process_frame
	burst.play(1.0, Vector2.LEFT, 7701, false)

	var out_dir := ProjectSettings.globalize_path("user://slime_d_impact_demo")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for i in FRAME_COUNT:
		await process_frame
		RenderingServer.force_draw()
		var img := get_root().get_texture().get_image()
		img.save_png(out_dir.path_join("frame_%03d.png" % i))

	print("PAINT: ", paint.splat_count(), "  SATELLITES: ", paint.debug_satellite_count())
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)


func _exit_tree() -> void:
	pass
