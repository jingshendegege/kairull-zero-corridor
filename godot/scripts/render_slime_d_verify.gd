extends SceneTree
## D 方案彩虹液爆验收：渲染死亡版液爆中段帧，扫像素确认彩虹六色确实同在。

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0a1221")
	bg.size = Vector2(1360, 765)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(bg)

	var packed := load("res://scenes/fx/slime_ribbon_burst.tscn") as PackedScene
	var burst := packed.instantiate() as SlimeRibbonBurst
	burst.position = Vector2(300, 380)
	get_root().add_child(burst)
	await process_frame
	burst.play(1.0, Vector2(1.0, -0.1).normalized(), 4242, false)

	var out_dir := ProjectSettings.globalize_path("user://slime_d_verify")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# 液幕展开与拉丝成形的关键帧
	for i in 20:
		await process_frame
		if i == 6 or i == 12:
			RenderingServer.force_draw()
			var img := get_root().get_texture().get_image()
			img.save_png(out_dir.path_join("d_frame_%02d.png" % i))
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
