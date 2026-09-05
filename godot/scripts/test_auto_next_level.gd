extends SceneTree
## 清敌为测试夹具；出口判定、白字渐黑、暂停与实际change_scene接续全部走生产入口。
const SESSION := preload("res://scripts/run_session.gd")
var game: Node2D
var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ",label)

func prepare() -> void:
	game = current_scene.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.set_physics_process(false)
	game._sfx.clear()
	game.action_audio_enabled = false
	game.action_audio.stop_all()
	game.victory_transition.set_process(false)

func _run() -> void:
	SESSION.begin_run("zero")
	var boot: Node2D = load(SESSION.LEVEL_SCENES[0]).instantiate()
	root.add_child(boot)
	current_scene = boot
	prepare()
	await create_timer(.15).timeout
	game.music.play(7.0)
	await create_timer(.15).timeout
	var music_id: int = game.music.get_instance_id()
	check(SESSION.next_scene_after("res://scenes/old_prototype.tscn").is_empty(),"旧试作不被强行接入三关流程")
	for index in 3:
		var source: String = SESSION.LEVEL_SCENES[index]
		check(CorridorLevel.active_restart_scene == source,"实际处于第%d关"%(index+1))
		check(game.player.hp == 1 and SESSION.difficulty == "zero", "跨关保留武士零1血难度")
		var expected_music := "res://assets/bgm/m04_chrono_freight_0906.mp3" if index == 1 else "res://assets/bgm/m02_oldtown.mp3"
		check(game.music.stream.resource_path == expected_music and game.music.get_meta("track_path") == expected_music,
				"三关音乐依次为第一关原曲/9月6日/第一关原曲")
		check(game._checkpoint_index == -1 and SESSION.checkpoint.is_empty(),"新关检查点未激活，不继承旧关存档")
		var count := 0
		for enemy: Node2D in game.minions:
			count += int(not enemy.dead)
		check(count == [20,38,52][index],"新关完整生成自己的敌人")
		# 激活当前关中段点，验证自动换关只清这份旧存档。
		var config: Dictionary = CorridorLevel.active_checkpoints[0]
		for enemy: Node2D in game.minions:
			var cell: Vector2i = enemy.get_meta("spawn_cell")
			if config.required_clear_rooms.has(game.level.room_at(cell.x*32+16,cell.y*32+16)):
				enemy.dead = true
		game.player.position = game._checkpoint_beacons[int(config.room_index)].position
		game.player.on_ground = true
		game._update_room_state()
		game._update_campaign_progress(0.0)
		check(not SESSION.checkpoint.is_empty(),"本关检查点经真实接口激活")
		for enemy: Node2D in game.minions:
			enemy.dead = true
		game.player.position = game.level.exit_point
		game.player.on_ground = true
		game._physics_process(0.0)
		check(game.level_cleared and game._victory_started,"真实出口开启白字渐黑")
		var old_id: int = current_scene.get_instance_id()
		game.victory_transition.advance(1.4)
		game._process(0.0)
		check(game.victory_transition.fade_progress == 1.0 and not game._transitioning,"渐黑完成时仍留出白字停顿")
		game.victory_transition.advance(.7)
		if index < 2:
			check(game.victory_transition.prompt_text().contains("下一关"),"前两关提示自动接续而非Enter重玩")
			await snapshot("%d-通关黑底白字.png"%(index+1))
			var enter := InputEventKey.new()
			enter.keycode = KEY_ENTER
			enter.pressed = true
			game._unhandled_input(enter)
			check(not game._transitioning,"Enter不抢跑重开当前关")
			game.pause_controller.pause_game()
			await create_timer(.15,true).timeout
			game._process(2.0)
			check(current_scene.get_instance_id()==old_id and not game._transitioning,"通关中Esc暂停不会跨关")
			game.pause_controller.resume_game()
			game._process(0.0)
			check(not game._transitioning,"继续后不补算暂停时长")
			if DisplayServer.get_name() != "headless":
				# 真窗口由实际_process/墙钟完成剩余过渡，不手动调用切关函数。
				game.victory_transition._last_usec = Time.get_ticks_usec()
				game.victory_transition.set_process(true)
				game.set_process(true)
				var deadline := Time.get_ticks_usec()+3000000
				while current_scene.get_instance_id()==old_id and Time.get_ticks_usec()<deadline:
					await process_frame
				check(current_scene.get_instance_id()!=old_id,"真窗口生产时钟自动完成接关")
			else:
				game.victory_transition.advance(.11)
				game._process(0.0)
				check(game._transitioning,"2.2秒后自动请求下一关，无需按键")
				game._process(0.0)
			for frame in 4:
				await process_frame
			prepare()
			await snapshot("%d-自动进入下一关.png"%(index+1))
			check(current_scene.get_instance_id()!=old_id and SESSION.start_level==index+1 \
					and SESSION.attempt==1,"下一关只切一次并更新菜单选择与本关轮次")
			check(game.player.position.distance_to(game.level.spawn)<1.0 \
					and not game.level_cleared and game.enemy_bullets.is_empty(),"新关从入口开始且无旧胜利/弹道状态")
			check(game.music.get_instance_id()==music_id \
					and game.music.playing and game.music.get_playback_position()<2.0,
					"跨关异曲使用唯一播放器，新曲从头开始，不叠播旧曲")
			var players := 0
			for child: Node in root.get_children():
				if child is AudioStreamPlayer and String(child.name).begins_with("ContinuousLevelMusic"):
					players += 1
			check(players == 1,"跨关后根节点只有一个BGM声部")
		else:
			game.victory_transition.advance(10.0)
			game._process(0.0)
			check(not game._transitioning and game.victory_next_scene().is_empty(),"第三关不跳回第一关或旧试作")
			check(game.victory_transition.prompt_text().contains("重新挑战") \
					and game._can_restart_campaign(),"最终关保留重玩和暂停菜单")
	current_scene.free()
	current_scene = null
	SESSION.reset_for_tests()
	await create_timer(.2,true).timeout
	print("AUTO_NEXT_LEVEL_RESULT: %d PASS / %d FAIL"%[passed,failed])
	quit(int(failed>0))

func snapshot(filename: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/auto-next-level-20260906/"
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output+filename)
