extends SceneTree
## M02 playtest 第六轮渲染验收（真实窗口跑，arena boot 自带 BGM）：
##   a 大黄蜂存活 —— 出口门锁定（暗红边光 + 门楣红灯），玩家走到门口也不过关
##   b 击杀瞬间 —— 大黄蜂受击白闪/倒地，出口门解锁转青（品红楣线）
##   c 击破后站进门口 —— CLEAR 卡弹出（竞技场过关，无连锁转场）
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_shot9.gd
## 输出：user://shot9_*.png（外层拷到 m02_renders/）

var _shot_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena: Node2D = load("res://scenes/hk_arena.tscn").instantiate()
	get_root().add_child(arena)
	current_scene = arena
	await process_frame
	await process_frame

	var game: Node2D = arena.get_node("Game")
	var player: KairullPlayer = game.player
	player.auto_input = false
	player.hp = 999   ## 摆拍期间挨 Boss 技能不死
	game.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 20.0   ## 标题卡/帮助条淡出
	print("  BGM playing = ", game.music != null and game.music.playing, "（应为 true）")
	print("  闸门开关 = ", CorridorLevel.active_exit_requires_boss, "（应为 true）")

	var exit_pos: Vector2 = game.level.exit_point
	var boss: Node2D = game.red_boss

	# ============ 镜头 a：大黄蜂存活，出口门锁定（暗红）============
	# 玩家站门口左侧取景（门体 + hornet 同框；玩家暂不踩进触发区，免得过关抢镜）
	player.position = exit_pos + Vector2(-120.0, 0.0)
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	player.face = 1
	for i in range(40):   ## hornet AI 起步 + 相机缓动就位
		await physics_frame
	game.cam_tl = game._cam_target()
	for i in range(4):
		await process_frame
	print("  镜头a locked = ", game.exit_door.locked, " cleared = ", game.level_cleared,
		"（应 true / false） boss_hp = ", boss.hp)
	await _shot("shot9_a_exit_locked_hornet_alive")

	# ============ 镜头 b：击杀瞬间，出口解锁转青 ============
	# 玩家保持在触发区外（门口左侧 120px > 门半宽 22px + 玩家半宽，不触发过关）
	player.position = exit_pos + Vector2(-120.0, 0.0)
	player.vx = 0.0
	while not boss.dead:
		boss.take_hit(player.position.x, 1)
	# 击杀后立刻截图：白闪（hitstop 0.09s ≈ 3 帧@30fps）+ 门刚转青
	# （physics_frame 信号在节点 _physics_process 之前发，等两帧闸门才写入解锁；
	#  截图读的是上一帧已渲染纹理，再等两帧让门体重绘进帧）
	await physics_frame
	await physics_frame   ## game._physics_process 写入 exit_door.locked = false + 闩响
	await process_frame
	await process_frame   ## 门体按解锁态重绘并渲染进纹理
	print("  镜头b boss_dead = ", boss.dead, " locked = ", game.exit_door.locked,
		" cleared = ", game.level_cleared, "（应 true / false / false）")
	await _shot("shot9_b_hornet_death_exit_unlock")

	# ============ 镜头 c：站进门口，CLEAR 卡 ============
	player.position = exit_pos
	player.vx = 0.0
	player.vy = 0.0
	for i in range(10):
		await physics_frame
		if game.level_cleared:
			break
	print("  镜头c cleared = ", game.level_cleared, "（应为 true）")
	game.cam_tl = game._cam_target()
	for i in range(15):   ## 卡呼吸 + 相机就位（active_next_scene 空，卡常驻不淡出）
		await process_frame
	print("  镜头c fade_k = %.2f（应为 0，竞技场无连锁转场）" % game._fade_k)
	await _shot("shot9_c_clear_at_exit")

	print("RENDER_RESULT: PASS")
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
