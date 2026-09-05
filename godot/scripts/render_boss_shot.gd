extends SceneTree
## 一次性截图：玩家与 Boss 同框
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var player: KairullPlayer = scene.player
	player.auto_input = false
	# 把玩家挪到 Boss 附近
	var boss: KairullBoss = scene.boss
	player.position = Vector2(boss.position.x - 260, 19 * 32 - 0.1)
	player.aim_override = boss.position
	for i in range(40):
		player.step(1.0 / 60)
		scene._physics_process(1.0 / 60)
	scene._process(1.0 / 60)
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://shot_boss.png"
	img.save_png(path)
	print("截图 -> ", ProjectSettings.globalize_path(path))
	print("boss state=", boss.state, " hp=", boss.hp, " frame=", boss.frame)
	quit(0)
