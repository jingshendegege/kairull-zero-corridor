extends SceneTree
## 新菜单选择经真实输入进入长关，另验电梯世界时停与狙击原枪声接线。
const SESSION := preload("res://scripts/run_session.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/chrono-freight-20260905/"
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func screen_point(menu: Node3D, point: Vector2) -> Vector2:
	return menu.canvas_to_screen(0, point)


func _run() -> void:
	SESSION.reset_for_tests()
	var menu: Node3D = load("res://scenes/surveillance_menu.tscn").instantiate()
	menu.suppress_external_actions = true
	root.add_child(menu)
	current_scene = menu
	await process_frame
	check(menu.selected_level == 0 and SESSION.selected_scene().contains("m01_protocol"), "菜单保留第一关默认入口")
	menu._handle_keycode(KEY_DOWN)
	check(menu.selected_level == 1 and SESSION.selected_scene().contains("m04_chrono"), "开始页向下键选择第二长关")
	check(current_scene == menu and not SESSION.timeline_enabled, "选关本身不立即开局")
	menu._handle_mouse_click(screen_point(menu, Vector2(160, 240)))
	check(menu.selected_level == 0, "3D左卡片准确选择原第一关")
	menu._handle_mouse_click(screen_point(menu, Vector2(310, 240)))
	check(menu.selected_level == 1 and current_scene == menu, "3D右卡片准确选择新关而不误开始")
	menu._handle_mouse_click(screen_point(menu, Vector2(500, 240)))
	check(menu.selected_level == 2 and SESSION.selected_scene().contains("m05_vertical"), "第三张卡片选择真正纵向货运井")
	menu._handle_keycode(KEY_UP)
	check(menu.selected_level == 1, "上下选关遍历三张卡，能返回第二关")
	await snapshot("菜单-02-选择时差货运场.png")
	menu._select_page(2, true)
	await snapshot("菜单-R烟雾弹操作说明.png")
	menu._select_page(0, true)
	menu.suppress_external_actions = false
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	menu._unhandled_input(enter)
	for frame in 4:
		await process_frame
	var game: Node2D = current_scene.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	check(game.level.map_w == 460 and game.timeline_enabled, "确认后真正进入460列长关且时停开启")
	check(game.moving_lifts.size() == 2 and game.player.moving_platforms.size() == 2, "新关动态平台正确共享给主角")
	var lift: Node2D = game.moving_lifts[0]
	# 局部运动合同允许布置初始状态；全关无传送通行由独立跑图脚本验证。
	lift.advance(1.8)
	game.player.position = Vector2(lift.position.x, lift.position.y - 0.1)
	game.player.on_ground = true
	game.player.vy = 0.0
	var before: Vector2 = lift.position
	game.player.keys = {MOUSE_BUTTON_RIGHT: true}
	for frame in 8:
		game._physics_process(1.0 / 60.0)
		game.player.step(1.0 / 60.0)
	check(game.time_charge.active and lift.position == before, "真实时停入口使正在上行的货梯停止")
	check(game.player.on_ground and absf(game.player.position.y - lift.position.y + 0.1) < 0.6,
			"主角站在时停货梯上保持承载，不丢支撑")
	game.player.keys.clear()
	game._physics_process(1.0 / 60.0)
	game.player.step(1.0 / 60.0)
	check(not game.time_charge.active and lift.position.y < before.y, "解除时停电梯从原相位继续上升")
	check(absf(game.player.position.y - lift.position.y + 0.1) < 0.6, "恢复上升后仍连续带人")
	var voice_index: int = game._sfx_idx
	game._on_tactical_projectile(game.player.position + Vector2(120, -64), Vector2(-2700, 0), &"gunshot")
	check(game._sfx_pool[voice_index].stream.resource_path == "res://assets/sfx/gun/09_gunshot_remaining_1.wav",
			"狙击触发使用原锋利枪声，不走低增益合成enemy_shot")
	check(is_equal_approx(game._sfx_pool[voice_index].volume_db, 0.0), "狙击原声保持原增益")
	voice_index = game._sfx_idx
	game._on_tactical_sound(&"sniper_lock")
	check(game._sfx_pool[voice_index].stream.resource_path == "res://assets/sfx/gun/10_gunshot_empty.wav",
			"最后半秒锁定有独立机械卡扣，与开枪分离")
	await create_timer(0.20).timeout
	var boot := current_scene
	current_scene = null
	boot.queue_free()
	await create_timer(0.15).timeout
	SESSION.reset_for_tests()
	print("CHRONO_MENU_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png(OUT + name)
