extends SceneTree
## M04真实场景局部烟幕验收：只摆相机/主角，烟雾仍由拾取→投掷→生产状态机生成。
## 不改地形/敌人美术/命中规则；必须普通窗口，headless直接拒绝。

const SESSION := preload("res://scripts/run_session.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/chrono-freight-20260905"
var _game: Node2D
var _boot: Node2D
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	_failed = _failed or not value


func _place(column: float) -> void:
	var actor: KairullPlayer = _game.player
	actor.position = Vector2(column * 32.0 + 16.0, 27 * 32.0 - 0.1)
	actor.set_state("gun_idle")
	actor.on_ground = true
	actor.vx = 0
	actor.vy = 0
	actor.hp = 5
	actor.keys.clear()
	actor._sync_sprite()
	_game._update_room_state()
	_game.cam_tl = _game._cam_target().round()
	_game.cam.position = _game.cam_tl + Vector2(680, 382.5)
	_game.cam.reset_smoothing()
	_game._step_tactics(0.001)
	for _i in 8:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture.get_size() == Vector2i(1360, 765), name + " 真窗口尺寸")
	_check(picture.save_png(OUT.path_join(name + ".png")) == OK, name + " 保存")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("烟幕剪影美术验收必须使用真窗口")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = Vector2i(1360, 765)
	root.title = "M04 烟幕剪影 - 真窗口验收"
	DirAccess.make_dir_recursive_absolute(OUT)
	SESSION.begin_run("hard")
	_boot = load("res://scenes/m04_chrono_freight.tscn").instantiate()
	root.add_child(_boot)
	current_scene = _boot
	_game = _boot.get_node("Game")
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.player.auto_input = false
	_game.action_audio_enabled = false
	_game._sfx.clear()
	_game.hud.visible = false
	if _game.action_audio != null:
		_game.action_audio.stop_all()
	await _place(405)
	_game.smoke_tactics.try_pickup(_game.player)
	_check(_game.player.carried_smoke, "拾取真实地图第六处烟雾补给")
	await _place(433)
	await _shot("烟雾-剪影-01-释放前")
	_game.player.aim_override = Vector2(440 * 32 + 16, 27 * 32 - 0.1) # 留出可辨识的预览弧线，仍在真实投距内。
	_game.player.keys = {KEY_R: true}
	_game.player._prev_keys.clear()
	_game.player.step(1.0 / 60.0)
	_game._step_tactics(0.0)
	_check(_game.smoke_tactics._preview_visible and _game.smoke_tactics.grenades.is_empty(),
			"真实按住R只有轨迹，不立即投掷")
	await _shot("烟雾-剪影-01b-按住R瞄准")
	_game.player.keys[MOUSE_BUTTON_LEFT] = true
	_game.player.step(1.0 / 60.0)
	_check(_game.smoke_tactics.grenades.size() == 1 and not _game.player.batting(),
			"真实左键确认投出一颗，不同时挥棒")
	_game.player.keys.clear()
	for _i in 65:
		_game._step_tactics(1.0 / 60.0)
	_check(_game.smoke_tactics.clouds.size() == 1 and _game.player.smoke_cover_active(),
			"生产抛物线落地成烟且主角实际进入保护区")
	var hero_tint: Color = _game.player._sprite.self_modulate
	_check(hero_tint.r < 0.1 and is_equal_approx(hero_tint.a, 1.0), "主角使用不透明深色剪影")
	var covered_enemies := 0
	for enemy: Node2D in _game.minions:
		if _game.smoke_tactics.contains_actor(enemy):
			covered_enemies += 1
			_check(enemy._sprite.self_modulate.r < 0.1 and is_equal_approx(enemy._sprite.self_modulate.a, 1.0),
					"同一烟区内敌人也显示不透明深色剪影")
	_check(covered_enemies > 0, "画面同时包含主角和至少一名烟中敌人")
	await _shot("烟雾-剪影-02-主角与敌人")
	_game.player.keys = {MOUSE_BUTTON_RIGHT: true}
	_game._advance_time_charge(1.0 / 60.0)
	for _i in 10:
		await process_frame
	_check(_game.player.time_focus_active() and _game.player._sprite.material != null,
			"烟内剪影不覆盖时停高亮材质")
	await _shot("烟雾-剪影-03-时停高亮仍保留")
	_game.player.keys.clear()
	_game._advance_time_charge(0.0)
	_game.smoke_tactics.clear_effects()
	_game._refresh_smoke_cover()
	for _i in 10:
		await process_frame
	_check(_game.player._sprite.self_modulate == Color.WHITE, "离烟恢复原本主角颜色")
	await _shot("烟雾-剪影-04-消散恢复")
	_boot.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	SESSION.reset_for_tests()
	print("SMOKE_SILHOUETTE_VISUAL_RESULT: ", "FAIL" if _failed else "PASS")
	quit(int(_failed))
