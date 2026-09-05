extends SceneTree
## 诊断：球棒模式 idle/run 时角色脚底与地面的像素关系
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var player: KairullPlayer = scene.player
	player.auto_input = false
	player.switch_weapon("bat")
	player.position = Vector2(800, 19 * 32 - 0.1)
	player.vy = 0.0
	for i in range(60):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("diag_bat_idle")
	player.keys = {KEY_D: true}
	for i in range(40):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("diag_bat_run")
	# 对照：枪模式静止
	player.keys = {}
	player.switch_weapon("gun")
	for i in range(20):
		player.step(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	await _shot("diag_gun_aim")
	print("cam_tl=", scene.cam_tl, " player.pos=", player.position)
	quit(0)

func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	img.save_png(path)
	print("截图 -> ", ProjectSettings.globalize_path(path))
