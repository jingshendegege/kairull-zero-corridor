extends SceneTree
## 用既有正式关卡做0.10/0.70/1.80秒真窗口验收，不新画场景、不触发死亡花屏。
const SESSION := preload("res://scripts/run_session.gd")
const VICTORY := preload("res://scripts/victory_transition.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/single-crt-checkpoint-20260906"
var failed := false
var checks := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	failed = failed or not value
	print("PASS " if value else "FAIL ", label)


func shot(stem: String) -> Image:
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(1360, 765), stem + "为1360×765实际窗口")
	check(image.save_png(OUT.path_join(stem + ".png")) == OK, stem + "截图成功")
	return image


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("通关效果验收必须真窗口")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = Vector2i(1360, 765)
	DirAccess.make_dir_recursive_absolute(OUT)
	SESSION.begin_run("easy")
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.keys.clear()
	game.action_audio_enabled = false
	game._sfx.clear()
	if game.action_audio != null:
		game.action_audio.stop_all()
	var overlay: VICTORY = game.victory_transition
	check(overlay != null and overlay.get_parent() == game, "使用宿主正式挂载的唯一VictoryTransition")
	if overlay == null:
		boot.free()
		quit(1)
		return
	overlay.set_process(false)
	overlay.reset()
	# 只为视觉取景建立“已清场的出口”状态；不把这个摆位当作真实战斗通关测试。
	for enemy: Node2D in game.minions:
		enemy.dead = true
		enemy.visible = false
	game.player.position = game.level.exit_point - Vector2(16, 0)
	game.player.vx = 0.0
	game.player.vy = 0.0
	game.player.on_ground = true
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	game._sync_temporal_projection()
	for _i in 20:
		await process_frame
	var music_id: int = game.music.get_instance_id()
	var camera_before: Transform2D = game.cam.global_transform
	game.level_cleared = true
	game._begin_victory()
	check(not game.hud.visible, "宿主在通关同帧隐藏旧HUD/CLEAR，半暗阶段不叠两套字")
	overlay.advance(.10)
	check(overlay.visible and overlay.fade_progress > 0 and overlay.fade_progress < .1,
		"通关0.10秒背景仅轻微变暗")
	await shot("通关-01-白字缓显-0.10秒")
	overlay.advance(.60)
	check(is_equal_approx(overlay.fade_progress, .5) and overlay.text_opacity == 1,
		"通关0.70秒白字清晰、背景半暗")
	await shot("通关-02-背景渐黑-0.70秒")
	overlay.advance(1.10)
	check(overlay.fade_progress == 1 and overlay.is_ready() and overlay.prompt_opacity == 1,
		"通关1.80秒完全黑底并显示操作小字")
	var final_image := await shot("通关-03-黑底白字与继续提示-1.80秒")
	var black := true
	for point in [Vector2i(25, 25), Vector2i(1100, 120), Vector2i(120, 700)]:
		var pixel := final_image.get_pixelv(point)
		black = black and pixel.r < .01 and pixel.g < .01 and pixel.b < .01
	check(black, "最终画面非文字区域为真黑幕")
	var white_pixels := 0
	for y in range(410, 470, 2):
		for x in range(400, 970, 2):
			var pixel := final_image.get_pixel(x, y)
			white_pixels += int(pixel.r > .8 and pixel.g > .8 and pixel.b > .8)
	check(white_pixels > 80, "最终GPU画面存在居中偏下白字，而非黑屏占位")
	check(game.music.get_instance_id() == music_id and game.music.playing,
		"三阶段保持同一个真实BGM播放器继续播放")
	check(game.cam.global_transform == camera_before and not paused,
		"未移动相机或暂停场景树")
	await create_timer(.20).timeout
	boot.free()
	await create_timer(.20).timeout
	SESSION.reset_for_tests()
	print("VICTORY_RENDER_RESULT: ", "FAIL" if failed else "PASS", " checks=", checks)
	quit(int(failed))
