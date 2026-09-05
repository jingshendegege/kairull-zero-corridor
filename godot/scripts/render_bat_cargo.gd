extends SceneTree
## 真窗口验收：同一正式地图中用真实左键动画击飞货箱，再捕捉彩色命中。
var errors := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("货箱视觉验收必须使用真窗口")
		quit(1)
		return
	var boot = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	var game = boot.get_node("Game")
	game.set_physics_process(false)
	game.set_process(false)
	game.hud.visible = false
	var p: KairullPlayer = game.player
	p.auto_input = false
	p.hp = 999
	# 扩展后实体按行生成，不能再把第一个对象当成检疫厅示范货箱。
	var cargo: PropBatCargo = null
	for prop: Node2D in game.props:
		if prop is PropBatCargo and is_equal_approx(prop.spawn_position.x, 28 * 32 + 16):
			cargo = prop
			break
	if cargo == null:
		push_error("缺少检疫厅 c28 示范货箱")
		boot.free()
		quit(1)
		return
	p.position = cargo.position - Vector2(64, 0)
	p.vy = 0
	p.on_ground = true
	p.face = 1
	p.set_state("gun_idle")
	p.keys.clear()
	p._prev_keys.clear()
	p._sync_sprite()
	var target: Node2D = null
	for enemy: Node2D in game.minions:
		if enemy is GruntGunner and enemy.position.x > cargo.position.x \
				and absf(enemy.position.y - cargo.position.y) < 4.0:
			if target == null or enemy.position.x < target.position.x:
				target = enemy
	# 暂停 AI 仅为可重复拍摄；真实移动/击飞/伤害/特效链完整保留。
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	cargo.highlighted = true
	cargo.step(0)
	await _shot("shot_combat_slice_1_ready")
	var launch_seen := false
	var impact_seen := false
	for i in 65:
		p.keys = {KEY_D: true, MOUSE_BUTTON_LEFT: true} if i == 0 else {KEY_D: true}
		p.step(1.0 / 60.0)
		for prop: Node2D in game.props:
			prop.step(1.0 / 60.0)
			if prop is PropBatCargo:
				prop.advance(1.0 / 60.0, game.level, game._enemies(), game.doors)
		game._update_enemy_knockbacks(1.0 / 60.0)
		if cargo.flying and not launch_seen and cargo.position.x > cargo.spawn_position.x + 75:
			launch_seen = true
			await _shot("shot_combat_slice_2_launch")
		if cargo.dead and not impact_seen:
			impact_seen = true
			await _shot("shot_combat_slice_3_impact")
		await process_frame
	if not launch_seen or not impact_seen or target == null or not target.dead:
		errors += 1
		push_error("真实挥棒未完成发射→枪手命中链")
	for audio: AudioStreamPlayer in game._sfx_pool:
		audio.stop()
		audio.stream = null
	game._sfx.clear()
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	game.fx_layer.clear_explosions()
	boot.free()
	await process_frame
	print("CARGO_WINDOW_RESULT: ", "PASS" if errors == 0 else "FAIL")
	quit(0 if errors == 0 else 1)


func _shot(stem: String) -> void:
	# 等待真实窗口完成绘制，输出当前帧而不是 headless 代画。
	await RenderingServer.frame_post_draw
	var path := "user://%s.png" % stem
	var err := get_root().get_texture().get_image().save_png(path)
	if err != OK:
		errors += 1
	print(ProjectSettings.globalize_path(path), " err=", err)
