extends SceneTree
## 有限时停纯算法合同：2 秒容量、5 秒补充、耗尽锁定和松键门槛。

const CHRONO := preload("res://scripts/chrono_charge.gd")

var _pass := 0
var _fail := 0


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func near(actual: float, expected: float, epsilon := 0.0001) -> bool:
	return absf(actual - expected) <= epsilon


func _run() -> void:
	print("== 两秒容量与主动释放 ==")
	var charge := CHRONO.new()
	ok(near(charge.energy, 2.0) and near(charge.ratio(), 1.0) and not charge.active,
			"初始能量为完整 2 秒")
	charge.advance(0.75, true)
	ok(charge.active and near(charge.energy, 1.25),
			"按住立即进入时停并按实时时长消耗", "energy=%.3f" % charge.energy)
	charge.advance(0.01, false)
	ok(not charge.active and near(charge.recovery_delay, CHRONO.RECHARGE_DELAY - 0.01),
			"松开立即结束并进入补充延迟", "delay=%.3f" % charge.recovery_delay)
	charge.advance(0.01, true)
	ok(charge.active, "未耗尽时允许再次按住激活")

	print("== 耗尽锁定与必须松开 ==")
	charge.reset()
	charge.advance(CHRONO.MAX_DURATION, true)
	ok(near(charge.energy, 0.0) and not charge.active
			and near(charge.lockout, CHRONO.EMPTY_LOCKOUT) and charge.require_release,
			"完整 2 秒耗尽后进入 1.2 秒锁定并要求松键",
			"energy=%.3f lockout=%.3f" % [charge.energy, charge.lockout])
	charge.advance(CHRONO.EMPTY_LOCKOUT + 0.4, true)
	ok(not charge.active and charge.require_release and charge.lockout <= 0.0001,
			"持续按住即使锁定结束也不会自动重启")
	charge.advance(0.0, false)
	ok(not charge.require_release, "松开后解除耗尽门槛")
	charge.advance(0.0, true)
	ok(charge.active, "已有最低能量时重新按下可以激活")

	print("== 五秒补充与许可门控 ==")
	charge.reset()
	charge.advance(CHRONO.MAX_DURATION, true)
	charge.advance(0.0, false)
	charge.advance(CHRONO.RECHARGE_DELAY, false)
	ok(near(charge.energy, 0.0), "0.65 秒恢复延迟内不补充能量")
	charge.advance(CHRONO.RECHARGE_TIME * 0.5, false)
	ok(near(charge.energy, 1.0), "空槽经过 2.5 秒补到一半", "energy=%.3f" % charge.energy)
	charge.advance(CHRONO.RECHARGE_TIME * 0.5, false)
	ok(near(charge.energy, CHRONO.MAX_DURATION) and near(charge.ratio(), 1.0),
			"延迟结束后完整补充固定为 5 秒")
	charge.advance(0.2, true, true)
	charge.advance(0.2, true, false)
	ok(not charge.active and near(charge.energy, 1.8),
			"宿主禁止时会释放时停且不继续消耗")

	print("== cancel / reset 边界 ==")
	charge.reset()
	charge.advance(0.25, true)
	charge.cancel()
	ok(not charge.active and charge.require_release, "cancel 强制停止并要求重新松键")
	charge.advance(0.0, true)
	ok(not charge.active, "cancel 后持续按住不能重启")
	charge.advance(0.0, false)
	charge.advance(0.0, true)
	ok(charge.active, "cancel 后松开再按可恢复")
	charge.reset()
	ok(near(charge.energy, 2.0) and not charge.active and not charge.require_release
			and near(charge.lockout, 0.0), "reset 恢复完整干净状态")

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)

