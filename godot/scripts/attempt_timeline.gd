extends RefCounted
## 录像式短倒带：只记录对象姿态/弹道，不回读全屏图片，也不在倒带中重新触发伤害。
## 以 12Hz 保留最近约 3 秒；只回看死亡前 1.2 秒，随后由宿主花屏并重载整场。

const MAX_SNAPSHOTS := 36
const INITIAL_INTERVAL := 1.0 / 12.0
const REWIND_LOOKBACK := 1.2
var frames: Array[Dictionary] = []
var elapsed := 0.0
var interval := INITIAL_INTERVAL
var accumulator := 0.0

func record(host: Node2D, dt: float, force := false) -> void:
	elapsed += maxf(0.0, dt)
	accumulator += maxf(0.0, dt)
	if not force and not frames.is_empty() and accumulator < interval:
		return
	accumulator = 0.0
	frames.append(_capture(host))
	# 固定频率滑动窗口：不抽稀、不保留整关原点，避免长局录像逐渐失去动作细节。
	if frames.size() > MAX_SNAPSHOTS:
		frames.pop_front()

func _capture(host: Node2D) -> Dictionary:
	var actors: Array[Dictionary] = []
	for enemy: Node2D in host.minions:
		if not is_instance_valid(enemy):
			actors.append({})
			continue
		actors.append({"position": enemy.position, "state": enemy.state,
			"frame": enemy.frame, "face": enemy.face, "dead": enemy.dead,
			"anim_clock": enemy.get("_anim_clock"),
			"corpse_lift": enemy.get("corpse_lift") if enemy.has_method("set_corpse_lift") else 0.0,
			"corpse_ground_y": enemy.get("corpse_ground_y") if enemy.has_method("set_corpse_ground") else 0.0,
			"corpse_ground_valid": enemy.get("corpse_ground_valid") if enemy.has_method("set_corpse_ground") else false,
			"corpse_ground_projected": enemy.get("corpse_ground_projected") if enemy.has_method("set_corpse_ground") else false})
	var cargo: Array[Dictionary] = []
	for prop: Node2D in host.props:
		if not is_instance_valid(prop):
			cargo.append({})
			continue
		cargo.append({"position": prop.position, "rotation": prop.rotation,
			"dead": prop.dead, "flying": prop.get("flying") if prop is PropBatCargo else false})
	var paint: SlimePaintLayer = host.paint_layer
	return {"time": elapsed, "player": host.player.capture_timeline_pose(),
		"camera": host.cam.position, "camera_tl": host.cam_tl, "enemies": actors, "props": cargo,
		"bullets": host.enemy_bullets.duplicate(true), "splats": paint.splats.size(),
		"flecks": paint.flecks.size(), "blood_serial": paint.blood_wall_manager._serial}

func apply_rewind(host: Node2D, progress: float) -> void:
	if frames.is_empty():
		return
	# 先读清死亡附近动作，再回到最近 1.2 秒边界；整关重置由宿主换场负责。
	var p := clampf(progress, 0.0, 1.0)
	var latest_time := float(frames[-1]["time"])
	var rewind_start_time := maxf(float(frames[0]["time"]), latest_time - REWIND_LOOKBACK)
	var target_time := lerpf(latest_time, rewind_start_time, pow(p, 2.0))
	var first: Dictionary
	var second: Dictionary
	if target_time <= float(frames[0]["time"]):
		first = frames[0]
		second = first
	elif target_time >= latest_time:
		# force 可能在同一时刻补录死亡姿态，0% 必须严格取最后一帧而非同时间旧帧。
		first = frames[-1]
		second = first
	else:
		var low := 0
		var high := frames.size() - 1
		while high - low > 1:
			var middle := (low + high) / 2
			if float(frames[middle]["time"]) <= target_time:
				low = middle
			else:
				high = middle
		first = frames[low]
		second = frames[high]
	var blend := clampf((target_time - float(first["time"])) /
			maxf(0.00001, float(second["time"]) - float(first["time"])), 0.0, 1.0)
	# 连续坐标插值，离散动画/生死姿态取最近采样；末端不能错留在倒数第二帧。
	var nearest: Dictionary = second if blend >= 0.5 else first
	var pose: Dictionary = nearest["player"].duplicate(true)
	pose["position"] = Vector2(first["player"]["position"]).lerp(second["player"]["position"], blend).round()
	# 主角根位置与投地阴影必须在同一时间轴上插值，不能使用死亡末帧的地面缓存。
	if bool(first["player"].get("ground_valid", false)) and bool(second["player"].get("ground_valid", false)):
		pose["ground_y"] = lerpf(float(first["player"].get("ground_y", 0.0)),
				float(second["player"].get("ground_y", 0.0)), blend)
	host.player.apply_timeline_pose(pose)
	host.cam.position = Vector2(first["camera"]).lerp(second["camera"], blend).round()
	host.cam_tl = Vector2(first["camera_tl"]).lerp(second["camera_tl"], blend).round()
	host.cam.offset = Vector2.ZERO
	for index in mini(host.minions.size(), first["enemies"].size()):
		var enemy: Node2D = host.minions[index]
		var state: Dictionary = first["enemies"][index]
		var next: Dictionary = second["enemies"][index]
		if not is_instance_valid(enemy) or state.is_empty() or next.is_empty():
			continue
		enemy.position = Vector2(state["position"]).lerp(next["position"], blend).round()
		# 尸体高度是独立的连续视觉曲线，不能只回读离散的死亡动画帧。
		var corpse_lift := lerpf(float(state.get("corpse_lift", 0.0)),
				float(next.get("corpse_lift", 0.0)), blend)
		var corpse_ground_y := float(nearest["enemies"][index].get("corpse_ground_y", 0.0))
		if bool(state.get("corpse_ground_valid", false)) and bool(next.get("corpse_ground_valid", false)):
			corpse_ground_y = lerpf(float(state.get("corpse_ground_y", 0.0)),
					float(next.get("corpse_ground_y", 0.0)), blend)
		state = nearest["enemies"][index]
		enemy.state = state["state"]
		enemy.frame = state["frame"]
		enemy.face = state["face"]
		enemy.dead = state["dead"]
		if state["anim_clock"] != null:
			enemy.set("_anim_clock", state["anim_clock"])
		if enemy.has_method("set_corpse_lift"):
			# 回放只还原姿态，不推进物理/落地事件；回到生前必须清掉抬升。
			enemy.set("corpse_lift", maxf(0.0, corpse_lift) if enemy.dead else 0.0)
		if enemy.has_method("set_corpse_ground"):
			# 只还原阴影姿态，不重跑物理或落尘事件；旧录像/生前不遗留死亡投影。
			var projected: bool = enemy.dead and bool(state.get("corpse_ground_projected", false))
			enemy.set("corpse_ground_y", corpse_ground_y)
			enemy.set("corpse_ground_valid", projected and bool(state.get("corpse_ground_valid", false)))
			enemy.set("corpse_ground_projected", projected)
			if projected:
				enemy.set("corpse_lift", 0.0)
		enemy._sync_sprite()
	for index in mini(host.props.size(), first["props"].size()):
		var prop: Node2D = host.props[index]
		var state: Dictionary = first["props"][index]
		var next: Dictionary = second["props"][index]
		if not is_instance_valid(prop) or state.is_empty() or next.is_empty():
			continue
		prop.position = Vector2(state["position"]).lerp(next["position"], blend).round()
		prop.rotation = lerpf(state["rotation"], next["rotation"], blend)
		state = nearest["props"][index]
		prop.dead = state["dead"]
		if prop is PropBatCargo:
			prop.flying = state["flying"]
			prop._shards.clear()
			prop._trail.clear()
			prop._hint.visible = false
		prop.queue_redraw()
	host.enemy_bullets = nearest["bullets"].duplicate(true)
	var paint: SlimePaintLayer = host.paint_layer
	paint.splats.resize(mini(paint.splats.size(), int(nearest["splats"])))
	paint.flecks.resize(mini(paint.flecks.size(), int(nearest["flecks"])))
	for slot: Dictionary in paint.blood_wall_manager._slots:
		(slot["sprite"] as Sprite2D).visible = int(slot["serial"]) > 0 \
				and int(slot["serial"]) <= int(nearest["blood_serial"])
	paint.queue_redraw()
	host.fx_layer.queue_redraw()

func clear() -> void:
	frames.clear()
	elapsed = 0.0
	interval = INITIAL_INTERVAL
	accumulator = 0.0
