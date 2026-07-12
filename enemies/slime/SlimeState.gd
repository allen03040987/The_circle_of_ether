class_name SlimeState
extends EnemyState
## Slime 專屬狀態基底——跟 enemies/boss/BossState.gd 同一個模式

var slime: Slime

func _ready() -> void:
	super._ready()
	slime = owner as Slime

## 死亡永遠最優先——不管現在在哪個狀態，血量歸零就是要轉進 Dying（Dying 自己不用呼叫這個）
func check_death() -> bool:
	if slime.stats.health <= 0:
		state_machine.transition_to("Dying")
		return true
	return false

## 受傷打斷判定：其次優先，不分現在在哪個狀態都要檢查，回傳目標狀態名稱、空字串代表不用中斷。
## exempt_light：目前狀態是不是「攻擊/蓄力中」，這類狀態要無視輕擊(LIGHT)打斷（沿用原本 PREPARE/ATTACK 的例外規則）
func check_damage_interrupt(exempt_light: bool = false) -> String:
	if slime.pending_damage == null: return ""
	var p_type = slime.pending_damage["type"]
	var p_kb = slime.pending_damage["knockback_force"]

	if p_type == Damage.Type.NO_STUN:
		slime.pending_damage = null
		return ""

	if exempt_light and p_type == Damage.Type.LIGHT:
		slime.pending_damage = null
		return ""

	if p_type == Damage.Type.HEAVY or p_kb.y < 0:
		return "launched"
	return "hurt"
