extends SceneTree
## 音效用途、变体不重复、连杀、混音预算、限幅总线和场景生命周期；实际音色需另行试听。

const ROUTER := preload("res://scripts/action_sound_router.gd")
var _pass := 0
var _fail := 0


func _init() -> void:
	call_deferred("_run")


func ok(value: bool, label: String, detail := "") -> void:
	if value:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _run() -> void:
	var original_bus_count := AudioServer.bus_count
	var router := ROUTER.new()
	get_root().add_child(router)
	router.clock_override = 10.0
	router.set_random_seed(50905)
	ok(router.debug_stats()["voices"] == 8 and router.debug_stats()["streams"] == 72 \
			and router.debug_stats()["events"] == 18, "启动一次性建立8声部并加载18类72条流")
	var bus := AudioServer.get_bus_index(ROUTER.BUS_NAME)
	ok(bus >= 0 and AudioServer.get_bus_effect_count(bus) == 1, "独立动作音效总线有唯一限幅器")
	var limiter := AudioServer.get_bus_effect(bus, 0)
	ok(absf(float(limiter.get("ceiling_db")) + 1.5) < 0.001, "混合后的硬限幅上限为-1.5dB")
	var all_paths := {}
	for event: String in router.event_names():
		var previous := -1
		var unique := {}
		var never_repeated := true
		var valid_paths := true
		for index in 20:
			router.clock_override += 3.0
			var result: Dictionary = router.play_event(event)
			var variant := int(result.get("variant", -1))
			never_repeated = never_repeated and result.get("played", false) and variant != previous
			previous = variant
			unique[variant] = true
			var path := str(result.get("path", ""))
			valid_paths = valid_paths and path.contains("/action_v1/" + event + "_")
			all_paths[path] = true
		ok(never_repeated and unique.size() == 4 and valid_paths,
				"%s 20次含跨洗牌袋均不连用同一变体" % event)
	ok(all_paths.size() == 72, "每个作用使用自己的音频，不跨用途借用slime/wall/ghit")
	ok(router.debug_stats()["streams"] == 72, "反复播放不新建或重复加载音频流")
	for stream: AudioStream in router._streams["tv_fault"]:
		ok(stream.get_length() >= 0.28 and stream.get_length() <= 0.36,
				"电视故障变体保持0.28至0.36秒短提示")
	ok(router._catalog["tv_fault"]["gain_db"] == -14.0 \
			and router._catalog["tv_fault"]["voice_cap"] == 1,
			"故障音独立低增益且同类最多一声部，不堆叠噪声")
	ok(not router.play_event("not_an_event").get("played", true), "未知音效安全拒绝")
	router.reset_sequence()
	router.clock_override = 1000
	var first: Dictionary = router.play_event("enemy_kill")
	router.clock_override += 0.01
	var merged: Dictionary = router.play_event("enemy_kill")
	ok(first["played"] and not merged["played"] and merged["reason"] == "coalesced" \
			and merged["kill_streak"] == 2, "28ms内多杀合并确认但仍正确计算连杀数")
	router.clock_override += 0.16
	var chain: Dictionary = router.play_event("enemy_kill")
	ok(chain["played"] and chain["pitch"] > first["pitch"] and chain["pitch"] <= 1.0961 \
			and chain["gain_db"] < first["gain_db"], "连杀轻微升调但同时压低重叠音量，不越杀越吵")
	router.clock_override += 3.0
	var fresh: Dictionary = router.play_event("enemy_kill")
	ok(fresh["kill_streak"] == 1 and is_equal_approx(fresh["pitch"], 1.0), "连杀窗口过期恢复正常音高")
	router.reset_sequence()
	router.clock_override = 2000
	var capped := true
	for index in 40:
		router.clock_override += 0.001
		router.play_event("bat_swing")
		capped = capped and router._active_count("bat_swing") <= 2
	ok(capped, "连续挥棒最多两声部，不无限堆叠")
	var stress_events := ["body_hit", "cargo_impact", "enemy_shot", "metal_impact", "glass_break", "explosion"]
	for index in 80:
		router.play_event(stress_events[index % stress_events.size()])
		capped = capped and router.debug_stats()["active"] <= 8
	ok(capped and router.get_child_count() == 8, "密集混音始终只有8个播放器和最多8活声部")
	var extreme: Dictionary = router.play_event("player_death", 8.0, 90.0)
	ok(extreme["played"] and is_equal_approx(extreme["pitch"], 1.45) and is_equal_approx(extreme["gain_db"], -2.0),
			"异常调用音高/增益均钳制且高优先级死亡可抢占")
	router.play_event("rewind")
	router.play_event("bat_swing")
	ok(router._active_count("player_death") == 1 and router._active_count("rewind") == 1,
			"低优先级挥棒不会截断死亡或倒带")
	router.stop_all()
	ok(router.debug_stats()["active"] == 0, "stop_all可在进入回溯前清掉现时战斗声")
	router.reset_sequence()
	ok(router.debug_stats()["kill_streak"] == 0 and router.last_event.is_empty(), "新一轮清除连杀/洗牌状态")
	var sibling := ROUTER.new()
	get_root().add_child(sibling)
	ok(AudioServer.bus_count == original_bus_count + 1 and sibling.debug_stats()["bus_users"] == 2,
			"两场景短暂重叠复用同一bus，不增殖限幅器")
	sibling.free()
	ok(AudioServer.bus_count == original_bus_count + 1, "旧场景退出不移除另一场景仍使用的bus")
	router.free()
	ok(AudioServer.bus_count == original_bus_count, "最后一个路由退出清理自己创建的bus")
	for _index in 3:
		var next := ROUTER.new()
		get_root().add_child(next)
		next.free()
	ok(AudioServer.bus_count == original_bus_count, "连续重试三次不留下额外音频总线")
	limiter = null
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
