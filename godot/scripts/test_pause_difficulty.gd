extends SceneTree
const SESSION := preload("res://scripts/run_session.gd")
var passed := 0
var failed := 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ",label)
func run() -> void:
	check(SESSION.difficulty=="zero","新进程默认武士零")
	SESSION.begin_run("zero")
	var boot: Node2D = load("res://scenes/m04_chrono_freight.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.auto_input=false
	game._sfx.clear()
	game.action_audio_enabled=false
	game.action_audio.stop_all()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	check(is_equal_approx(game.music.volume_db,-5.5),"第二关音乐补偿10.5dB")
	var scene_id := boot.get_instance_id()
	var point: Vector2 = game.player.position
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	for enemy: Node2D in game.minions:
		var cell: Vector2i=enemy.get_meta("spawn_cell")
		if config.required_clear_rooms.has(game.level.room_at(cell.x*32+16,cell.y*32+16)):
			enemy.dead=true
	game.player.position=game._checkpoint_beacons[int(config.room_index)].position
	game.player.on_ground=true
	game._update_campaign_progress(0)
	var saved: Dictionary=SESSION.checkpoint.duplicate(true)
	game.player.position=point
	game.pause_controller.pause_game()
	var ui: CanvasLayer=game.pause_controller.ui
	ui.selected_index=3
	ui._activate()
	check(ui.confirmation_action=="difficulty","暂停第四项打开难度选择")
	for mode in ["easy","hard","zero"]:
		var index:=SESSION.DIFFICULTIES.find(mode)
		for down in [true,false]:
			var event:=InputEventMouseButton.new()
			event.button_index=MOUSE_BUTTON_LEFT
			event.pressed=down
			event.position=ui.difficulty_button_rect(index).get_center()
			game.pause_controller._input(event)
		check(SESSION.difficulty==mode and game.player.max_hp==SESSION.health_for_difficulty(mode),"鼠标卡片实际切换"+mode)
		check(game.player.hp==1 and not game.player.dead,"切换不刷血/复活")
		check(paused and game.pause_controller.active and boot.get_instance_id()==scene_id and game.player.position==point,"切难度不解除暂停或重开")
		check(SESSION.checkpoint_for(CorridorLevel.active_restart_scene).get("id")==saved.get("id"),"切难度保留检查点")
	game.pause_controller.change_difficulty("easy")
	game.player.hp=4
	game.pause_controller.change_difficulty("hard")
	check(game.player.hp==3,"更难档当前生命限制到新上限")
	game.pause_controller.change_difficulty("easy")
	check(game.player.hp==3,"切回简单不补血")
	game.player.dead=true
	game.player.hp=0
	game.pause_controller.change_difficulty("zero")
	check(game.player.dead and game.player.hp==0,"死亡后改难度不绕过死亡流程")
	game.player.dead=false
	game.player.hp=1
	if DisplayServer.get_name()!="headless":
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var output:="C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/pause-difficulty-20260906/"
		DirAccess.make_dir_recursive_absolute(output)
		root.get_texture().get_image().save_png(output+"暂停切换难度.png")
	game.pause_controller.resume_game()
	check(not paused and game.player.position==point,"Esc同款继续仍原位")
	game.action_audio.stop_all()
	await create_timer(.15,true).timeout
	boot.free()
	SESSION.reset_for_tests()
	await create_timer(.2,true).timeout
	print("PAUSE_DIFFICULTY_RESULT: %d PASS / %d FAIL"%[passed,failed])
	quit(int(failed>0))
