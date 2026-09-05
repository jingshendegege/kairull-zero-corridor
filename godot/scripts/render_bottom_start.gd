extends SceneTree
const SESSION := preload("res://scripts/run_session.gd")
func _init() -> void:
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(1)
		return
	SESSION.begin_run("zero")
	var boot: Node2D=load("res://scenes/m05_vertical_freight.tscn").instantiate()
	root.add_child(boot)
	current_scene=boot
	var game: Node2D=boot.get_node("Game")
	game.player.auto_input=false
	for tick in 6:
		game.player.step(1.0/60.0) # 无输入真实物理落稳；auto_input=false时不会自动推进角色。
	for frame in 12: await process_frame
	game.pause_controller.pause_game()
	game.pause_controller.ui.hide_menu() # 只隐藏测试截图遮罩，世界仍按生产主暂停冻结。
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var out:="C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/bottom-start-sniper-20260906/"
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out+"第三关-井底出生.png")
	var valid: bool=game.player.position.distance_to(Vector2(74*32+16,105*32-.1))<1.0 \
		and game.player.on_ground and game.current_room==game.level.room_at(game.level.spawn.x,game.level.spawn.y-1)
	print("BOTTOM_START_GUI_RESULT: ","PASS" if valid else "FAIL")
	boot.free()
	SESSION.reset_for_tests()
	await create_timer(.2,true).timeout
	quit(int(not valid))
