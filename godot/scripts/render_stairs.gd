extends SceneTree
## M03 楼梯渲染验收：真窗口跑 M03 demo，bot 走上楼梯，三阶段截图。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_stairs.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M03_STAIRS
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "none"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = "res://assets/clips/tileset_stairs.png"
	CorridorLevel.active_title = ""
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var player: KairullPlayer = scene.player
	for i in range(10):
		await physics_frame
	player.auto_input = false
	var dir := OS.get_environment("USERPROFILE") + "/AppData/Local/Temp/stairs_shots"
	DirAccess.make_dir_recursive_absolute(dir)

	# 阶段1：地面起步
	await RenderingServer.frame_post_draw
	get_root().get_viewport().get_texture().get_image().save_png(dir + "/stage1_ground.png")

	# 阶段2：走上 S 段（推进到 c17 附近）
	for f in range(70):
		player.keys.clear()
		player.keys[KEY_D] = true
		player.step(1.0 / 60.0)
		await physics_frame
	await RenderingServer.frame_post_draw
	get_root().get_viewport().get_texture().get_image().save_png(dir + "/stage2_on_stairs.png")

	# 阶段3：上到平台
	for f in range(25):
		player.keys.clear()
		player.keys[KEY_D] = true
		player.step(1.0 / 60.0)
		await physics_frame
	player.keys.clear()
	await RenderingServer.frame_post_draw
	get_root().get_viewport().get_texture().get_image().save_png(dir + "/stage3_platform.png")

	print("SAVED: " + dir)
	quit(0)
