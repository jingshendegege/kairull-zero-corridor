extends SceneTree
## 敌人非攻击动作与彩色喷液的真窗口抽检；不修改生产动画或特效配置。
## 输出 user://enemy_presentation/：同基线接触表与 .04/.15/.30/.50 秒实景喷液。

const OUT := "user://enemy_presentation"
var _failed := false
var _shot_count := 0
var _font: SystemFont


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("敌人与喷液视觉验收必须使用真窗口")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	_font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	await _contact_sheet("idle", "01_idle_3fps_pingpong", 1.0 / 3.0)
	await _contact_sheet("run", "02_run_8fps", 1.0 / 8.0)
	await _contact_sheet("mixed", "03_alert_and_death", 0.0)
	await _contact_sheet("death_hitstop", "04_death_during_knockback", 0.0)
	await _blood_timeline()
	await process_frame
	_failed = _failed or _shot_count != 8
	print("RENDER_RESULT: ", "FAIL" if _failed else "PASS")
	print("PREVIEW_DIR: ", ProjectSettings.globalize_path(OUT))
	quit(1 if _failed else 0)


func _label(parent: Node, value: String, at: Vector2, size := 17) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.modulate = Color("#c4d7d9")
	parent.add_child(label)


func _contact_sheet(action: String, file_name: String, interval: float) -> void:
	var stage := Node2D.new()
	get_root().add_child(stage)
	var background := ColorRect.new()
	background.color = Color("#263b48")
	background.size = Vector2(1360, 765)
	stage.add_child(background)
	_label(stage, "敌人动作真窗抽检 · " + action, Vector2(32, 30), 26)
	_label(stage, "横向各格为连续时间采样；细线为世界脚底，使用生产图集与实际游戏缩放。", Vector2(33, 69), 15)
	for row in 2:
		var floor_y := 295.0 + row * 250.0
		var baseline := ColorRect.new()
		baseline.position = Vector2(30, floor_y)
		baseline.size = Vector2(1300, 1)
		baseline.color = Color("#9bd0cf")
		stage.add_child(baseline)
		_label(stage, "枪手" if row == 0 else "货运巡检员", Vector2(33, floor_y - 150), 18)
		var min_bottom := INF
		var max_bottom := -INF
		for column in 8:
			var enemy: Node2D = GruntGunner.new() if row == 0 else FreightInspector.new()
			enemy.position = Vector2(98 + 165 * column, floor_y)
			stage.add_child(enemy)
			var sample_state := action
			var tick := 0
			if action == "mixed":
				sample_state = "alert" if column < 4 else "dead"
				tick = [0, 6, 12, 17, 0, 18, 36, 53][column]
			elif action == "death_hitstop":
				sample_state = "dead"
			enemy._set_state(sample_state)
			enemy._anim_clock = column * interval
			enemy.frame = tick
			enemy.face = 1
			enemy.dead = sample_state == "dead"
			if action == "death_hitstop":
				# 用真正 step 推进击退锁定期间的倒地，避免直接塞帧号掩盖尸体动画冻结。
				tick = [0, 6, 12, 18, 27, 36, 45, 54][column]
				enemy.hitstop = 0.25
				for _step in tick:
					enemy.step(1.0 / 60.0)
			enemy._sync_sprite()
			var sprite: Sprite2D = enemy._sprite
			var image := sprite.texture.get_image().get_region(Rect2i(sprite.region_rect))
			var used := image.get_used_rect()
			var bottom := sprite.position.y + (used.end.y - sprite.region_rect.size.y * 0.5) * sprite.scale.y
			min_bottom = minf(min_bottom, bottom)
			max_bottom = maxf(max_bottom, bottom)
			var caption := "%.2fs" % (column * interval) if action not in ["mixed", "death_hitstop"] else "%s t%d" % [sample_state, tick]
			_label(stage, caption, Vector2(54 + 165 * column, floor_y + 24), 13)
			_label(stage, "脚底 %+.2fpx" % bottom, Vector2(50 + 165 * column, floor_y + 46), 12)
		print("BASELINE ", "gunner" if row == 0 else "freight", " ", action,
				" min=", min_bottom, " max=", max_bottom, " delta=", max_bottom - min_bottom)
	await _shot(file_name)
	stage.free()
	await process_frame


func _blood_timeline() -> void:
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	if game.player == null or game.fx_layer == null:
		_failed = true
		boot.free()
		return
	# 固定实景镜头并手动按小步推进，截图等待不增加模拟时间。
	game.set_process(false)
	game.set_physics_process(false)
	game.hud.visible = false
	game.player.auto_input = false
	game.fx_layer.process_mode = Node.PROCESS_MODE_DISABLED
	game.paint_layer.set_process(false)
	var target: Node2D
	for enemy: Node2D in game.minions:
		if target == null and enemy is FreightInspector:
			target = enemy
		else:
			enemy.visible = false
	for prop: Node2D in game.props:
		prop.visible = false
	target.position = Vector2(30 * 32 + 16, 28 * 32 - 0.1)
	target.player = null
	target.face = -1
	game.player.position = target.position - Vector2(105, 0)
	game.player.face = 1
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	seed(37041)
	var origin: Vector2 = target.body_rect().get_center()
	var direction := Vector2(1, -0.18).normalized()
	target.take_hit(game.player.position.x, 1)
	var burst: SlimeRibbonBurst = game.fx_layer.spawn_bat_hit(origin, direction, 1.35, true, target)
	game._start_enemy_knockback(target, direction, 0, true, 0.0)
	var elapsed := 0.0
	var simulated_enemy_ticks := 0
	for time: float in [0.04, 0.15, 0.30, 0.50]:
		while elapsed < time - 0.000001:
			var dt := minf(1.0 / 240.0, time - elapsed)
			# 敌人逻辑 tick 按60fps单独推进，喷液按240Hz积分，免得抽检本身加速倒地。
			elapsed += dt
			while simulated_enemy_ticks < floori(elapsed * 60.0 + 0.000001):
				target.step(1.0 / 60.0)
				simulated_enemy_ticks += 1
			game._update_enemy_knockbacks(dt)
			for effect: Node in game.fx_layer.get_children():
				if effect is SlimeRibbonBurst or effect is WoundBloodSpray:
					effect._process(dt)
		print("BLOOD t=", elapsed, " stats=", burst.debug_stats(), " color=", burst.current_color,
				" decals=", game.paint_layer.blood_wall_manager.debug_stats()["active"],
				" enemy_frame=", target.frame, " hitstop=", target.hitstop)
		await _shot("blood_%03dms" % roundi(time * 1000.0))
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
	boot.free()
	await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var path := ProjectSettings.globalize_path(OUT.path_join(name + ".png"))
	var error := get_root().get_texture().get_image().save_png(path)
	_failed = _failed or error != OK
	_shot_count += 1
	print("SHOT ", path, " err=", error)
