extends RefCounted
## 尸体的短离地轮廓：只控制显示抬升，不重新结算伤害或更改地图/水平击退。
## 用秒而非动画帧计时，低帧率也只有一次主落地事件；时停由宿主暂停advance。

const LIFT_HEIGHTS := [26.0, 32.0, 38.0]
const RISE_TIME := 0.12
const HANG_TIME := 0.065
const FALL_TIME := 0.18
const LAND_TIME := RISE_TIME + HANG_TIME + FALL_TIME
const BOUNCE_TIME := 0.14
const DURATION := LAND_TIME + BOUNCE_TIME

var elapsed := 0.0
var height := 26.0
var active := true
var landed := false


func setup(stage: int, headroom := INF) -> void:
	height = minf(LIFT_HEIGHTS[clampi(stage, 0, 2)], maxf(0.0, headroom))
	elapsed = 0.0
	active = true
	landed = false


func advance(dt: float) -> bool:
	if not active:
		return false
	elapsed = minf(DURATION, elapsed + maxf(0.0, dt))
	var first_contact := not landed and elapsed >= LAND_TIME
	landed = landed or first_contact
	active = elapsed < DURATION
	return first_contact


func lift() -> float:
	if elapsed < RISE_TIME:
		return height * (1.0 - pow(1.0 - elapsed / RISE_TIME, 3.0))
	if elapsed < RISE_TIME + HANG_TIME:
		return height  # 顶点只停65ms；不延迟击杀、不冻结主角或全场。
	if elapsed < LAND_TIME:
		var fall := (elapsed - RISE_TIME - HANG_TIME) / FALL_TIME
		return height * (1.0 - fall * fall)
	var bounce := clampf((elapsed - LAND_TIME) / BOUNCE_TIME, 0.0, 1.0)
	return minf(5.0, height * 0.18) * 4.0 * bounce * (1.0 - bounce)
