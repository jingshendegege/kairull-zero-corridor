extends SceneTree
## 彩虹史莱姆液爆实机预览：方向喷射、延迟墙面油漆、短促屏幕震荡。
## 跑法需带 --rendering-driver opengl3 --fixed-fps 30，不能用 --headless。

const FRAME_COUNT := 36


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node2D.new()
	get_root().add_child(world)

	var backdrop := ColorRect.new()
	backdrop.color = Color("#07101f")
	backdrop.size = Vector2(1360, 765)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(backdrop)

	# 右侧深色墙板用于观察液滴落点；正式游戏里由关卡 TileMap 充当墙面。
	var wall := ColorRect.new()
	wall.color = Color("#15243b")
	wall.position = Vector2(700, 92)
	wall.size = Vector2(520, 580)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(wall)
	for i in 8:
		var seam := Line2D.new()
		seam.points = PackedVector2Array([
			Vector2(700, 120 + i * 68), Vector2(1220, 120 + i * 68)])
		seam.width = 1.0
		seam.default_color = Color(0.23, 0.36, 0.52, 0.34)
		world.add_child(seam)

	var paint := SlimePaintLayer.new()
	paint.name = "SlimePaintLayer"
	world.add_child(paint)

	var packed := load("res://scenes/fx/slime_burst.tscn") as PackedScene
	var burst := packed.instantiate() as SlimeBurst
	burst.position = Vector2(590, 382)
	world.add_child(burst)
	burst.paint_requested.connect(func(pos: Vector2, direction: Vector2, power: float, seed: int) -> void:
		paint.spray(pos, direction, power, seed))
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://slime_burst_preview")
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.force_draw()
	var baseline := get_root().get_texture().get_image()
	var baseline_err := baseline.save_png(out_dir.path_join("baseline.png"))
	if baseline_err != OK:
		push_error("保存基准帧失败：err=%s" % baseline_err)
		quit(1)
		return

	var direction := Vector2(1.0, -0.18).normalized()
	burst.play(1.25, direction, 6704)
	var trauma := 0.68
	var shake_time := 0.0
	for i in FRAME_COUNT:
		await process_frame
		shake_time += 1.0 / 30.0
		trauma = maxf(0.0, trauma - (1.0 / 30.0) * 2.35)
		var envelope := trauma * trauma
		var kick := -direction * trauma * 11.0
		var jitter := Vector2(
			sin(shake_time * 73.0) * 8.0,
			sin(shake_time * 97.0 + 1.3) * 5.5) * envelope
		world.position = (kick + jitter).round()
		RenderingServer.force_draw()
		var image := get_root().get_texture().get_image()
		var path := out_dir.path_join("frame_%03d.png" % i)
		var err := image.save_png(path)
		if err != OK:
			push_error("保存预览帧失败：%s err=%s" % [path, err])
			quit(1)
			return

	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
