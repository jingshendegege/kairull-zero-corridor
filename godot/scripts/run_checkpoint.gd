extends RefCounted
## 中段快照只保留已完成进度，不持有Node/材质/音频；失败仍真正重建场景。

static func signature() -> String:
	return (CorridorLevel.active_map + JSON.stringify(CorridorLevel.active_stairs)
		+ JSON.stringify(CorridorLevel.active_rooms) + JSON.stringify(CorridorLevel.active_checkpoints)
		+ JSON.stringify(CorridorLevel.active_tactical_objects)).sha256_text()

static func enemy_key(enemy: Node2D) -> Vector2i:
	return enemy.get_meta("spawn_cell", Vector2i(-1, -1))

static func hazard_key(hazard: Node2D) -> String:
	return "%s:%d:%d" % [hazard.hazard_type, roundi(hazard.position.x), roundi(hazard.position.y)]

static func capture(host: Node2D, config: Dictionary, at: Vector2) -> Dictionary:
	var defeated: Array[Vector2i] = []
	for enemy: Node2D in host.minions:
		if is_instance_valid(enemy) and enemy.dead:
			defeated.append(enemy_key(enemy))
	var spent_props: Array[String] = []
	for prop: Node2D in host.props:
		if is_instance_valid(prop) and (prop.dead or (prop is PropBatCargo and prop.flying)):
			# 已投出的货箱视为已消耗，不能借存档复制仍在飞行的投掷物。
			spent_props.append(String(prop.get_meta("checkpoint_key", "")))
	var hazards: Dictionary = {}
	for hazard: Node2D in host.tactical_hazards:
		if hazard.dead or hazard.cleared_disabled:
			hazards[hazard_key(hazard)] = {"dead": hazard.dead, "disabled": hazard.cleared_disabled}
	var pickups: Array[Vector2] = []
	if host.smoke_tactics != null:
		for pickup: Dictionary in host.smoke_tactics.pickups:
			pickups.append(pickup.position)
	return {"schema": 1, "signature": signature(), "id": String(config.id), "spawn": at,
		"room_index": int(config.room_index), "name": String(host.level.rooms[int(config.room_index)].name),
		"defeated": defeated, "spent_props": spent_props, "hazards": hazards,
		"smoke_pickups": pickups, "carried_smoke": host.player.carried_smoke,
		"visited_rooms": host._visited_rooms.duplicate(true), "frontier": host._campaign_frontier,
		"elapsed": host._run_elapsed}

static func restore(host: Node2D, state: Dictionary) -> bool:
	if state.is_empty() or int(state.get("schema", -1)) != 1 or state.get("signature", "") != signature():
		return false
	var matching := false
	for config: Dictionary in CorridorLevel.active_checkpoints:
		matching = matching or String(config.id) == state.get("id", "")
	if not matching:
		return false # 地图热改/跨关后拒绝旧快照，不能把角色放进已改变的墙体。
	for enemy: Node2D in host.minions:
		if state.defeated.has(enemy_key(enemy)):
			enemy.dead = true
			enemy.visible = false
			enemy.set_meta("checkpoint_cleared", true)
			enemy.set_process(false)
			enemy.set_physics_process(false)
	for prop: Node2D in host.props:
		if state.spent_props.has(String(prop.get_meta("checkpoint_key", ""))):
			prop.dead = true
			prop.visible = false
			prop.set_meta("checkpoint_spent", true)
			prop.set_process(false)
			prop.set_physics_process(false)
	for hazard: Node2D in host.tactical_hazards:
		var key := hazard_key(hazard)
		if not state.hazards.has(key):
			continue
		var status: Dictionary = state.hazards[key]
		if bool(status.dead):
			hazard.dead = true
			hazard.armed = false
			hazard._change_state("dead")
		else:
			hazard.deactivate_cleared()
		# 复原器械不走take_hit，不能再触发爆音/击杀/彩血。
		hazard.queue_redraw()
	if host.smoke_tactics != null:
		for index in range(host.smoke_tactics.pickups.size() - 1, -1, -1):
			var pickup: Dictionary = host.smoke_tactics.pickups[index]
			if not state.smoke_pickups.has(pickup.position):
				pickup.node.free()
				host.smoke_tactics.pickups.remove_at(index)
	host._visited_rooms = state.visited_rooms.duplicate(true)
	host._campaign_frontier = int(state.frontier)
	host._run_elapsed = float(state.elapsed)
	host._checkpoint_index = int(state.room_index)
	host._checkpoint_name = String(state.name)
	host.player.spawn = state.spawn
	host.player.reset_to_spawn()
	host.player.on_ground = true
	host.player.invuln_t = 0.8 # 安全落脚点重建保护，不重放失败时的伤害/预瞄准。
	host.player.set_carried_smoke(bool(state.carried_smoke))
	host.time_charge.reset()
	host.current_room = -1
	host._update_room_state()
	host._cam_room_boost = 0.0
	host.cam_tl = host._cam_target()
	host.cam.position = (host.cam_tl + Vector2(host.VW, host.VH) * .5).round()
	host.cam.force_update_scroll()
	if host._checkpoint_beacons.has(host._checkpoint_index):
		host._checkpoint_beacons[host._checkpoint_index].set_status(true, true)
	return true
