extends SceneTree
## 真正经过菜单输入回调切场景，不能用suppress_external_actions掩盖移树后空viewport。
const SESSION := preload("res://scripts/run_session.gd")
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for mouse_mode in [false, true]:
		var menu: Node3D = load("res://scenes/surveillance_menu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		await process_frame
		var event: InputEvent
		if mouse_mode:
			var click := InputEventMouseButton.new()
			click.pressed = true
			click.button_index = MOUSE_BUTTON_LEFT
			# 必须点明确开始按钮；屏幕中心/监控画面不再被当作危险的隐形开始热区。
			click.position = menu.canvas_to_screen(0, menu.START_BUTTON.get_center())
			event = click
		else:
			var key := InputEventKey.new()
			key.pressed = true
			key.keycode = KEY_ENTER
			event = key
		menu._unhandled_input(event)
		for frame in 4:
			await process_frame
		var loaded := current_scene != null and current_scene.get_node_or_null("Game") != null
		passed += int(loaded)
		failed += int(not loaded)
		print("PASS " if loaded else "FAIL ", "鼠标确认安全切关" if mouse_mode else "回车确认安全切关")
		if loaded:
			var game: Node2D = current_scene.get_node("Game")
			game.set_physics_process(false)
			game.music.stop()
			game.action_audio.stop_all()
		await create_timer(0.2).timeout
		var old_scene := current_scene
		current_scene = null
		old_scene.queue_free()
		await process_frame
		SESSION.reset_for_tests()
	print("MENU_SCENE_INPUT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
