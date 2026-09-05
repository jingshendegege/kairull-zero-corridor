extends SceneTree
## 正式接入合同：非致命命中=弱液丝；死亡=完整液幕；两者都有材质音效与起点墙漆。

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("== Slime hit / death production routing ==")
	var game_scene := load("res://scenes/game.tscn") as PackedScene
	var hit_game = game_scene.instantiate()
	get_root().add_child(hit_game)
	await process_frame
	if not hit_game.fx_layer.has_method("spawn_slime_hit"):
		ok(false, "特效层提供弱化受击液丝接口")
		_free_game(hit_game)
		await process_frame
		_finish()
		return
	ok(hit_game._sfx.has("slime_hit") and hit_game._sfx["slime_hit"] != null,
			"湿润受击音效已加载")
	ok(hit_game._sfx.has("slime_death") and hit_game._sfx["slime_death"] != null,
			"液体爆裂死亡音效已加载")
	if not hit_game.has_method("sfx_gain_db"):
		ok(false, "材质音叠加枪声时有独立衰减，避免总线削波")
		_free_game(hit_game)
		await process_frame
		_finish()
		return
	ok(hit_game.sfx_gain_db("slime_hit") <= -4.0 and
			hit_game.sfx_gain_db("slime_death") <= -2.0,
			"湿拍与爆裂音以较低增益叠放在枪声下方")
	ok(hit_game._sfx_pool.size() >= 10, "枪声、命中声和液体材质声有足够并发声道",
			str(hit_game._sfx_pool.size()))
	# 测试只验路由，禁掉实际播放，避免进程退出时音频仍被解码。
	hit_game._sfx.clear()
	hit_game.set_physics_process(false)
	hit_game.player.auto_input = false
	var hit_enemy: KairullBoss = hit_game.minions[0]
	hit_enemy.hp = 2
	var hit_point := hit_enemy.body_rect().get_center()
	var force := Vector2(900.0, -220.0)
	hit_game.bullets.append({"x": hit_point.x, "y": hit_point.y,
			"vx": force.x, "vy": force.y, "life": 1.0})
	hit_game._physics_process(0.0)
	var weak_effects: Array = []
	for child in hit_game.fx_layer.get_children():
		if child is SlimeRibbonBurst and child.active and child.weak_mode:
			weak_effects.append(child)
	ok(not hit_enemy.dead and hit_enemy.hp == 1, "非致命命中保留敌人", str(hit_enemy.hp))
	ok(weak_effects.size() == 1, "非致命命中只生成一次弱化液丝", str(weak_effects.size()))
	var hit_trauma: float = hit_game.camera_trauma   ## 震屏值要在衰减前读取
	ok(hit_trauma > 0.0 and hit_trauma < 0.3, "受击震屏较弱", str(hit_trauma))
	# 微粒喷溅在液幕前缘到位时（0.12s）才释放并同步算出落点，等它触发
	for i in 300:
		await process_frame
		if hit_game.paint_layer.fleck_count() > 0:
			break
	ok(hit_game.paint_layer.splat_count() + hit_game.paint_layer.fleck_count() >= 3,
			"受击留下微粒碎渍", "splats=%d flecks=%d" % [
			hit_game.paint_layer.splat_count(), hit_game.paint_layer.fleck_count()])
	_free_game(hit_game)
	await process_frame

	var death_game = game_scene.instantiate()
	get_root().add_child(death_game)
	await process_frame
	death_game._sfx.clear()
	death_game.set_physics_process(false)
	death_game.player.auto_input = false
	var death_enemy: KairullBoss = death_game.minions[0]
	death_enemy.hp = 1
	var death_point := death_enemy.body_rect().get_center()
	# 同一帧两颗致命子弹也只能触发一次死亡液幕。
	for i in 2:
		death_game.bullets.append({"x": death_point.x, "y": death_point.y,
				"vx": force.x, "vy": force.y, "life": 1.0})
	death_game._physics_process(0.0)
	var full_effects: Array = []
	for child in death_game.fx_layer.get_children():
		if child is SlimeRibbonBurst and child.active and not child.weak_mode:
			full_effects.append(child)
	ok(death_enemy.dead, "致命命中杀死敌人")
	ok(full_effects.size() == 1, "死亡只播放一次完整液幕", str(full_effects.size()))
	var death_trauma: float = death_game.camera_trauma   ## 同样在衰减前读取
	# 死亡版微粒喷溅 0.15s 释放，等落点生成
	for i in 300:
		await process_frame
		if death_game.paint_layer.fleck_count() > 0:
			break
	ok(death_game.paint_layer.splat_count() + death_game.paint_layer.fleck_count() >= 6,
			"死亡爆点留下完整微粒喷溅", "splats=%d flecks=%d" % [
			death_game.paint_layer.splat_count(), death_game.paint_layer.fleck_count()])
	ok(death_trauma > hit_trauma, "死亡震屏强于普通受击",
			"hit=%.3f death=%.3f" % [hit_trauma, death_trauma])
	_free_game(death_game)
	await process_frame
	_finish()


func _free_game(game) -> void:
	for audio in game._sfx_pool:
		audio.stop()
		audio.stream = null
	game._sfx.clear()
	game.queue_free()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
