extends SceneTree
## 墙面污渍可视化验收：真实关卡左边界墙，
## 上方受击弱化版、下方死亡完整版，液丝/液滴真实撞墙后长出 BD 式撞击印。

const FRAME_COUNT := 50   ## 30fps × 50 ≈ 1.7s，覆盖完整版 1.08s 的飞行

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level := CorridorLevel.new()
	get_root().add_child(level)
	level.build(true)   # 渲染真实 tilemap

	var paint := SlimePaintLayer.new()
	paint.level = level
	get_root().add_child(paint)

	var packed := load("res://scenes/fx/slime_ribbon_burst.tscn") as PackedScene
	var weak_burst := packed.instantiate() as SlimeRibbonBurst
	var full_burst := packed.instantiate() as SlimeRibbonBurst
	for b in [weak_burst, full_burst]:
		b.level = level
		get_root().add_child(b)
		b.paint_requested.connect(func(pos: Vector2, dir: Vector2, power: float,
				seed: int, weak: bool) -> void:
			paint.spray(pos, dir, power * (0.45 if weak else 1.0), seed))
		b.wall_impact.connect(func(pos: Vector2, radius: float, slot: int,
				on_wall: bool, weak: bool) -> void:
			paint.add_impact_splat(pos, radius, slot, weak, randi()))
	weak_burst.position = Vector2(220, 220)
	full_burst.position = Vector2(220, 430)
	weak_burst.play(0.36, Vector2.LEFT, 9201, true)
	full_burst.play(1.0, Vector2.LEFT, 9202, false)

	var out_dir := ProjectSettings.globalize_path("user://slime_runoff_fx")
	DirAccess.make_dir_recursive_absolute(out_dir)

	for i in FRAME_COUNT:
		await process_frame
		RenderingServer.force_draw()
		var image := get_root().get_texture().get_image()
		var path := out_dir.path_join("frame_%03d.png" % i)
		var err := image.save_png(path)
		if err != OK:
			push_error("保存帧失败：%s err=%s" % [path, err])
			quit(1)
			return

	print("SPLAT_COUNT: ", paint.splat_count())
	print("SATELLITES: ", paint.debug_satellite_count())
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
