extends SceneTree
## 实机渲染像素爆炸逐帧预览；不能用 --headless，否则拿不到帧缓冲。
## 跑法需带 --fixed-fps 30，让保存 PNG 的耗时不改变粒子推进速度。
## 输出：user://pixel_explosion_preview/frame_000.png ...

const FRAME_COUNT := 32


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("#07101f")
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(1360, 765)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(backdrop)

	# 两条暗色参考线帮助观察冲击环半径，不参与正式游戏画面。
	var guides := Node2D.new()
	var horizontal := Line2D.new()
	horizontal.points = PackedVector2Array([Vector2(500, 382), Vector2(860, 382)])
	horizontal.width = 1.0
	horizontal.default_color = Color(0.18, 0.34, 0.52, 0.34)
	guides.add_child(horizontal)
	var vertical := Line2D.new()
	vertical.points = PackedVector2Array([Vector2(680, 210), Vector2(680, 554)])
	vertical.width = 1.0
	vertical.default_color = Color(0.18, 0.34, 0.52, 0.34)
	guides.add_child(vertical)
	get_root().add_child(guides)

	var packed := load("res://scenes/fx/pixel_explosion.tscn") as PackedScene
	var effect := packed.instantiate() as PixelExplosion
	effect.position = Vector2(680, 382)
	get_root().add_child(effect)
	await process_frame

	var out_dir := ProjectSettings.globalize_path("user://pixel_explosion_preview")
	DirAccess.make_dir_recursive_absolute(out_dir)
	effect.play(1.35)

	for i in FRAME_COUNT:
		await process_frame
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
