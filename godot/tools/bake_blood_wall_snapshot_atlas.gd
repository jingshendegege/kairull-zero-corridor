extends SceneTree
## 离线烘焙现有 SlimeRibbonBurst 的冻结帧，避免运行时 SubViewport 回读。
## 输出是 6 格共享图集；正式血迹只读取 Alpha，颜色仍由 shader 参数控制。

const BURST_SCENE := preload("res://scenes/fx/slime_ribbon_burst.tscn")
const CELL_SIZE := Vector2i(320, 192)
const VARIANT_COUNT := 6
const SNAPSHOT_TIME := 0.15
const BASE_DIRECTION := Vector2(1.0, -0.18)
const IMPACT_PIVOT := Vector2(40.0, 96.0)
const OUTPUT_PATH := "res://assets/vfx/blood_wall_snapshot.png"


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var viewport := SubViewport.new()
	viewport.name = "BloodSnapshotBakeViewport"
	viewport.size = Vector2i(CELL_SIZE.x * VARIANT_COUNT, CELL_SIZE.y)
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	var world := Node2D.new()
	viewport.add_child(world)
	for i in VARIANT_COUNT:
		var burst: SlimeRibbonBurst = BURST_SCENE.instantiate()
		world.add_child(burst)
		burst.position = Vector2(i * CELL_SIZE.x, 0) + IMPACT_PIVOT
		# 0.8 的近战倍率会得到内部 power=1，便于运行时按实际 power 缩放。
		burst.play(0.8, BASE_DIRECTION.normalized(), 9101 + i * 97, false, true)
		var bake_steps := ceili(SNAPSHOT_TIME * 60.0)
		for _step in bake_steps:
			burst._process(1.0 / 60.0)
		burst.set_process(false)

	# SubViewport 在 dummy/headless 渲染器没有 frame_post_draw；真实 OpenGL
	# 窗口连续让出三帧即可完成离屏画布，避免烘焙脚本永久等待。
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var output_abs := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_abs.get_base_dir())
	var error := image.save_png(output_abs)
	if error != OK:
		push_error("血迹快照图集保存失败：%s" % error_string(error))
		quit(1)
		return
	print("BLOOD_SNAPSHOT_ATLAS: %s (%dx%d)" % [
		output_abs, image.get_width(), image.get_height()])
	quit(0)
