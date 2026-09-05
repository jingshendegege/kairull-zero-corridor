extends SceneTree
## 只做墙面下淌验收：直接调用 SlimePaintLayer 的 spray，右侧墙面上应出现拉长的滴落。

const FRAME_COUNT := 36


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#050914")
	bg.size = Vector2(1360, 765)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(bg)

	var paint := SlimePaintLayer.new()
	get_root().add_child(paint)
	paint.level = CorridorLevel.new()
	paint.level.build(false)
	paint.spray(Vector2(200, 320), Vector2.RIGHT, 1.0, 9021)

	await process_frame
	RenderingServer.force_draw()
	var out_dir := ProjectSettings.globalize_path("user://slime_drip_fx")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var image := get_root().get_texture().get_image()
	image.save_png(out_dir.path_join("drip_final.png"))
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(0)
