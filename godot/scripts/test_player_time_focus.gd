extends SceneTree
## 时停主角：55%逻辑速度、真实秒CD、轻青材质与短虚影；不改变普通动作参数。

const DT := 1.0 / 60.0
var _pass := 0
var _fail := 0
var _db: AtlasDB
var _level: CorridorLevel


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _run() -> void:
	_db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json"])
	var rows := PackedStringArray()
	for y in 18:
		rows.append("#".repeat(48) if y == 14 else ".".repeat(48))
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_stairs = []
	_level = CorridorLevel.new()
	_level.build(false)
	_test_simulation_speed()
	_test_burst_cooldowns()
	_test_visual_history()
	_test_death_and_reset()
	_level.free()
	_db = null
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _player() -> KairullPlayer:
	var player := KairullPlayer.new()
	player.auto_input = false
	player.level = _level
	player.db = _db
	player.spawn = Vector2(500, 447.9)
	get_root().add_child(player)
	player.on_ground = true
	player.keys.clear()
	player._sync_sprite()
	return player


func _test_simulation_speed() -> void:
	var normal := _player()
	var focused := _player()
	focused.set_time_focus(true)
	for player in [normal, focused]:
		player.keys = {KEY_D: true}
		for _i in 24:
			player.step(DT)
	ok(absf((focused.position.x - 500) / (normal.position.x - 500) - 0.55) < 0.0001,
			"持续奔跑距离严格为正常55%")
	ok(absf(focused.t / normal.t - 0.55) < 0.0001, "人物动画时钟同步降到55%")
	ok(focused.on_ground and focused.position.y == normal.position.y, "减速仍稳定落脚不改变身体高度")
	for player in [normal, focused]:
		player.reset_to_spawn()
		player.on_ground = true
		player._prev_keys.clear()
	focused.set_time_focus(true)
	for player in [normal, focused]:
		player.keys = {MOUSE_BUTTON_LEFT: true}
		for _i in 12:
			player.step(DT)
	ok(normal.batting() and focused.batting() and focused.frame < normal.frame \
			and focused._bat_progress() < normal._bat_progress(), "挥棒动作与命中窗口一起放慢而非仅降低位移")
	ok(normal._sprite.scale == focused._sprite.scale and normal.w == focused.w and normal.h == focused.h,
			"减速/高亮不修改图集缩放或碰撞尺寸")
	for player in [normal, focused]:
		player.free()


func _test_burst_cooldowns() -> void:
	var player := _player()
	player.set_time_focus(true)
	player.dash_cooldown_t = 1.5
	player.roll_cooldown_t = 0.26
	for _i in 30:
		player.step(DT)
	ok(absf(player.dash_cooldown_t - 1.0) < 0.001 and player.roll_cooldown_t == 0.0,
			"真实半秒扣半秒冲刺CD；翻滚CD也按真实时钟")
	player.reset_to_spawn()
	player.on_ground = true
	player._prev_keys.clear()
	player.set_time_focus(true)
	player.keys = {KEY_SHIFT: true}
	player.step(DT)
	for _i in 6:
		player.keys.clear()
		player.step(DT)
	ok(player.dashing(), "时停中冲刺经过原0.11秒后仍在动作中")
	for _i in 7:
		player.step(DT)
	ok(not player.dashing() and absf(player.position.x - 500 - KairullPlayer.DASH_DISTANCE) < 0.1,
			"减速冲刺约0.20秒完成，5.5格距离不变")
	ok(player.dash_cooldown_t > 1.25 and player.dash_cooldown_t < 1.30,
			"动作变慢不把1.5秒CD一起拉长")
	player.reset_to_spawn()
	player.on_ground = true
	player._prev_keys.clear()
	player.set_time_focus(true)
	player.keys = {KEY_CTRL: true}
	for _i in 37:
		player.step(DT)
	ok(not player.rolling() and absf(player.position.x - 500 - KairullPlayer.ROLL_DISTANCE) < 0.1,
			"翻滚放慢到约0.61秒，仍保持6格距离")
	player.free()


func _test_visual_history() -> void:
	var player := _player()
	var normal_pose := player.capture_timeline_pose()
	player.z_index = 50
	player.set_time_focus(true)
	var focus_material := player._sprite.material as ShaderMaterial
	ok(focus_material != null and focus_material != player._dash_material \
			and is_equal_approx(focus_material.get_shader_parameter("tint_mix"), 0.23),
			"轻青高亮使用独立低混合度材质，保留原人物颜色")
	player.keys = {KEY_D: true}
	for _i in 18:
		player.step(DT)
	ok(player.dash_afterimage_count() >= 3 and player.dash_afterimage_count() <= 4,
			"移动中75ms一张短虚影，常驻仅约3张", str(player.dash_afterimage_count()))
	ok(player._dash_trail_root.z_index == 50 and not player._dash_trail_root.z_as_relative \
			and player._outline.z_index == 0, "top_level虚影跟随主角抬至z50，描边相对层不变")
	var source_clip := player._sprite.texture
	var source_scale := player._sprite.scale
	var ghosts_valid := true
	for data in player._dash_ghosts:
		ghosts_valid = ghosts_valid and data["sprite"].texture == source_clip \
				and data["sprite"].scale == source_scale and data["lifetime"] == 0.24 \
				and data["base_alpha"] == 0.24
	ok(ghosts_valid, "时停虚影复用同图集和尺寸，只降低不透明度/缩短寿命")
	var focus_pose := player.capture_timeline_pose()
	player.set_time_focus(false)
	player.z_index = 0
	player.keys.clear()
	for _i in 16:
		player.step(DT)
	ok(player._sprite.material == null and player.dash_afterimage_count() == 0 \
			and player._dash_trail_root.z_index == 0, "退出后本体恢复、旧虚影自然消散且z回归")
	player.apply_timeline_pose(focus_pose)
	ok(player._sprite.material == focus_material \
			and focus_material.get_shader_parameter("tint_color") == KairullPlayer.TIME_FOCUS_TINT,
			"恢复时停历史帧仍有原轻青高亮，无共享材质串色")
	player.apply_timeline_pose(normal_pose)
	ok(player._sprite.material == null and not player.time_focus_active(),
			"普通历史帧恢复原材质，回放不重新开启减速")
	player.reset_to_spawn()
	player.set_time_focus(true)
	for _i in 30:
		player.step(DT)
	ok(player.dash_afterimage_count() == 0, "站立时不重复叠亮同一轮廓")
	player.free()


func _test_death_and_reset() -> void:
	var player := _player()
	var normal := _player()
	player.set_time_focus(true)
	player.force_death(0)
	normal.force_death(0)
	for _i in 18:
		player.step(DT)
		normal.step(DT)
	ok(not player.time_focus_active() and player.position.is_equal_approx(normal.position) \
			and player.position.x > 650.0,
			"死亡退出55%减速，与正常死亡逐帧同款惯性，小抛物线按真实秒推进")
	for _i in 28:
		player.step(DT)
	ok(player.death_animation_finished() and player.frame == 14 and player._sprite.material == null,
			"死亡仍在.75秒完成15帧倒地，无高亮污染")
	player.set_time_focus(true)
	ok(not player.time_focus_active(), "尸体不会被后续时停状态重新减速")
	player.reset_to_spawn()
	ok(not player.time_focus_active() and player._sprite.material == null,
			"新一轮重置彻底关闭时停表现")
	ok(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED \
			and KairullPlayer.DASH_COOLDOWN == 1.5, "枪械/旧滑铲仍关闭，冲刺CD基础常量不变")
	player.free()
	normal.free()
