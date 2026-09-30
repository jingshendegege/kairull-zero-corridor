extends RefCounted
## 有限时停的独立实时时钟：不改 Engine.time_scale，不把主角和菜单一起冻住。

const MAX_DURATION := 2.0
const RECHARGE_TIME := 5.0
const RECHARGE_DELAY := 0.65
const EMPTY_LOCKOUT := 1.2
const MIN_ACTIVATION := 0.18
## VibeHub 创意工坊（ModBridge 写入）：时停时长 / 充能时间倍率，默认 1。
static var duration_scale := 1.0
static var recharge_scale := 1.0

var energy := MAX_DURATION * duration_scale
var active := false
var lockout := 0.0
var recovery_delay := 0.0
var require_release := false

func advance(dt: float, held: bool, permitted := true) -> void:
	var step := maxf(0.0, dt)
	lockout = maxf(0.0, lockout - step)
	if not held:
		require_release = false
	if not permitted:
		active = false
		return
	if active and not held:
		active = false
		recovery_delay = RECHARGE_DELAY
	if not active and held and not require_release and lockout <= 0.0 and energy >= MIN_ACTIVATION:
		active = true
	if active:
		energy = maxf(0.0, energy - step)
		recovery_delay = RECHARGE_DELAY
		if energy <= 0.00001:
			active = false
			lockout = EMPTY_LOCKOUT
			require_release = true  # 耗尽后必须松开，不能按住自动一闪一闪续停。
	else:
		var available := maxf(0.0, step - recovery_delay)
		recovery_delay = maxf(0.0, recovery_delay - step)
		energy = minf(max_duration(), energy + available * max_duration() / (RECHARGE_TIME * recharge_scale))

func cancel() -> void:
	active = false
	require_release = true

func reset() -> void:
	energy = max_duration()
	active = false
	lockout = 0.0
	recovery_delay = 0.0
	require_release = false

func ratio() -> float:
	return clampf(energy / max_duration(), 0.0, 1.0)


static func max_duration() -> float:
	return MAX_DURATION * duration_scale
