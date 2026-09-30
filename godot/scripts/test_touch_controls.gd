extends SceneTree
## 手机触屏层：真实场景 + 合成触摸事件，验证虚拟键注入与原键盘/鼠标读取一致。
const SESSION := preload("res://scripts/run_session.gd")
var passed := 0
var failed := 0
var touch: CanvasLayer


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func tap(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	touch._input(event)
	await process_frame


func button_pos(name: String) -> Vector2:
	for button: Array in touch.buttons():
		if button[0] == name:
			return button[3]
	return Vector2(-999, -999)


func _run() -> void:
	touch = root.get_node("TouchControls")
	check(touch != null and not touch.touch_mode and touch.layout() == "", "autoload present and hidden until a real touch")
	SESSION.begin_run("easy")
	var boot: Node = load("res://scenes/m06_exhaust_ridge.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	for i in 3:
		await process_frame
	var game: Node2D = boot.get_node("Game")
	game.set_physics_process(false)
	check(touch.layout() == "", "desktop play: no touch buttons")
	await tap(0, Vector2(700, 300), true)
	await tap(0, Vector2(700, 300), false)
	check(touch.touch_mode and touch.layout() == "field", "first touch in a level shows the field layout")
	await tap(1, button_pos("right"), true)
	check(Input.is_key_pressed(KEY_D), "holding ▶ presses D")
	await tap(2, button_pos("attack"), true)
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_D), "attack presses left mouse while ▶ is still held (multi-touch)")
	await tap(2, button_pos("attack"), false)
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_D), "releasing attack keeps D held")
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = button_pos("left")
	touch._input(drag)
	await process_frame
	check(Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_D), "sliding the thumb from ▶ to ◀ switches direction")
	await tap(1, button_pos("left"), false)
	check(not Input.is_key_pressed(KEY_A), "lifting the thumb releases direction")
	game.player._collect_input()
	check(game.player.keys.is_empty(), "player polling sees no stuck keys")
	touch._process(0.0)
	check(game.player.aim_override != null and not Input.emulate_mouse_from_touch, "in-level: smoke aims forward, touch no longer emulates mouse")
	await tap(3, button_pos("pause"), true)
	await tap(3, button_pos("pause"), false)
	check(game.pause_controller.active and touch.layout() == "", "pause button opens the pause menu and hides the pad")
	touch._process(0.0)
	check(Input.emulate_mouse_from_touch, "pause menu: taps act as mouse clicks")
	game.pause_controller.resume_game()
	await process_frame
	# 实体键盘按下 → 退出触屏模式
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	touch._input(key)
	check(not touch.touch_mode and game.player.aim_override == null, "a physical key press leaves touch mode")
	boot.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	# 节奏 Boss：上半屏上层、下半屏下层，双指 = 双键
	SESSION.begin_run("easy")
	boot = load("res://scenes/m07_beat_tower.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	for i in 3:
		await process_frame
	game = boot.get_node("Game")
	game.beat_arena._engage_rhythm()
	await tap(0, Vector2(300, 200), true)
	check(touch.layout() == "rhythm" and Input.is_key_pressed(KEY_W) and not Input.is_key_pressed(KEY_S),
		"rhythm: top half = upper lane (W)")
	await tap(1, Vector2(1100, 600), true)
	check(Input.is_key_pressed(KEY_W) and Input.is_key_pressed(KEY_S), "rhythm: bottom half = lower lane; both = dual notes")
	await tap(0, Vector2(300, 200), false)
	await tap(1, Vector2(1100, 600), false)
	check(not Input.is_key_pressed(KEY_W) and not Input.is_key_pressed(KEY_S), "rhythm: releasing clears both lanes")
	var music := root.get_node_or_null("ContinuousLevelMusic")
	boot.queue_free()
	current_scene = null
	await process_frame
	if music != null:
		music.stop()
	SESSION.reset_for_tests()
	print("TOUCH_CONTROLS_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
