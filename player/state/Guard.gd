extends State
class_name GuardState
## 格擋狀態 (Guard State)
## 與 Slide 同性質的「反射型」狀態：可從玩家自身任何招式強制打斷進場（格擋與 Slide 除外），
## 施放後的 GUARD_WINDOW 秒內，命中的攻擊會被格擋。
##
## 🌟 刻意不使用 invincible_timer / grant_invincibility 這種全域無敵旗標：
## 判定完全交給 Player._on_hurtbox_hurt() 在命中當下呼叫 try_block(hitbox) 現場裁決，
## 跟「彈反型招式」(Art_Katana_1) 走同一套攔截模式。這樣才能依據「敵人這個 hitbox」本身的
## 屬性做例外判斷（例如黃圈技的 requires_countermeasure 不能被格擋），而不是無腦擋掉全部傷害。

const GUARD_WINDOW: float = 0.3
const GUARD_HURTBOX_SIZE := Vector2(150.0, 150.0) ## 格擋判定期間暫時放大成正方形，比較容易撈到攻擊

const GUARD_POISE_CHIP: float = 8.0 ## 格擋成功給攻擊者的基礎少許削韌
const FALLBACK_PUSHBACK: float = 250.0

## 依攻擊的 Attack Type 給自己不同強度的格擋擊退，比固定值更符合打擊感
const PUSHBACK_BY_TYPE := {
	Damage.Type.LIGHT: 250.0,
	Damage.Type.HEAVY: 500.0,
	Damage.Type.THROW: 300.0, # 目前遊戲裡還沒有任何攻擊真的用到 THROW，先抓一個介於 LIGHT/HEAVY 之間的暫定值
	Damage.Type.NO_STUN: 100.0,
}

const GUARD_BREAK_BURST_SCENE = preload("res://Explod/tscn/GuardBreakBurst.tscn")
const BLOCK_BURST_COLOR := Color(0.06, 0.2, 0.12, 1.0) ## 墨綠黑色
## 碎片範圍比敵人被彈刀時的原版（300~700 / 3~6）縮小很多，格擋成功的回饋不需要噴那麼遠、那麼大
const BLOCK_BURST_VELOCITY := Vector2(100.0, 220.0)
const BLOCK_BURST_SCALE := Vector2(1.2, 2.2)

## 連續格擋之間的最短間隔：即使格擋成功、也不能立刻被下一次輸入無縫打斷後搖，
## 避免玩家連按導致同一瞬間疊了兩次格擋（視覺上根本看不出來發生過兩次）。
## 這段鎖定期間改用無敵頂著，確保「銜接下一輪判定窗」的體驗不會因為這道鎖定而漏接傷害
const CHAIN_LOCK_DURATION: float = 0.2

var elapsed: float = 0.0

## 供未來「格擋風格」擴充使用；同時也是「連續格擋」的開關——
## 只有這次格擋真的擋到東西了，下一次格擋輸入才有資格打斷這次的後搖、無縫接上一輪新的判定窗
var has_blocked: bool = false
var _chain_lock_time_left: float = 0.0

var _hurtbox_shape_node: CollisionShape2D = null
var _original_hurtbox_shape: Shape2D = null
var _guard_hurtbox_shape: RectangleShape2D = null
var _hurtbox_expanded: bool = false

func enter() -> void:
	_reset()

	if player.scabbard:
		player.scabbard.fade_in()

func physics_update(delta: float) -> void:
	elapsed += delta
	if _chain_lock_time_left > 0:
		_chain_lock_time_left -= delta

	player.velocity.x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	if not player.is_on_floor():
		player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()

	# 判定窗過了就把 Hurtbox 縮回原本大小，放大只在真正的判定期間生效
	if _hurtbox_expanded and elapsed > GUARD_WINDOW:
		_restore_hurtbox()

	# 閃避的權限永遠最高，格擋也能被閃避打斷
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		state_machine.transition_to("Slide")
		return

	# 武藝的權限僅次於閃避，一樣能打斷格擋——直接轉去 WeaponAttack，讓它 enter() 自己派發武藝
	if player.is_martial_requested and is_instance_valid(player.current_weapon) and player.current_weapon.has_method("execute_martial_art"):
		state_machine.transition_to("WeaponAttack")
		return

	# 🌟 連續格擋：格擋成功過，下一次格擋輸入可以直接打斷這次格擋的後搖、無縫銜接下一輪判定窗，
	# 方便應對敵人的連段攻擊。沒擋到任何東西的話，後搖就不能被同一招自己打斷（防止純粹的無成本格擋螺旋）
	# 🔒 但即使格擋成功了，也要先過 CHAIN_LOCK_DURATION 這段最短間隔，避免連按導致同一瞬間疊出兩次格擋
	if has_blocked and _chain_lock_time_left <= 0.0 and player.guard_request_timer.time_left > 0:
		_reset()
		return

	if not player.animation_player.is_playing():
		if player.is_on_floor():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Fall")

func exit() -> void:
	_restore_hurtbox()

## 重新開始這次格擋的判定窗（enter() 首次進場、或 has_blocked 之後自我打斷後搖時都會呼叫）。
## 同狀態自我打斷沒辦法走 state_machine.transition_to()（會被防遞迴鎖擋掉），所以自己手動重播動畫、重置計時
func _reset() -> void:
	elapsed = 0.0
	has_blocked = false
	_chain_lock_time_left = 0.0
	player.guard_request_timer.stop()

	player.animation_player.stop()
	player.play_safe_anim("guard")

	_expand_hurtbox()

## 由 Player._on_hurtbox_hurt() 呼叫：判定這一下攻擊是否在格擋判定窗內被擋下。
## 回傳 true 代表格擋成功（呼叫端會接著呼叫 hitbox.suppress_feedback() 並攔下傷害）
func try_block(hitbox: Hitbox) -> bool:
	if elapsed > GUARD_WINDOW: return false
	# 黃圈技只有專屬對策技能破，通用防禦手段（格擋、彈反型招式）一律無效
	if ("requires_countermeasure" in hitbox) and hitbox.requires_countermeasure: return false

	has_blocked = true
	# TODO: 未來依裝備的「格擋風格」在這裡分流觸發對應效果

	# 🔒 進入連續格擋的最短鎖定期：這段期間無敵頂著，確保鎖定不會反而漏接下一下傷害
	_chain_lock_time_left = CHAIN_LOCK_DURATION
	player.grant_invincibility(CHAIN_LOCK_DURATION)

	# 1. 轉向攻擊者當下所在方向
	var attacker_pos = hitbox.global_position
	if is_instance_valid(hitbox.owner):
		attacker_pos = hitbox.owner.global_position
	var dir_x = sign(attacker_pos.x - player.global_position.x)
	if dir_x == 0: dir_x = player.direction
	player.direction = player.Direction.RIGHT if dir_x > 0 else player.Direction.LEFT

	# 2. 依攻擊的 Attack Type 給自己不同強度的擊退，往攻擊者的反方向推開
	var attack_type = hitbox.attack_type if "attack_type" in hitbox else Damage.Type.LIGHT
	var pushback: float = PUSHBACK_BY_TYPE.get(attack_type, FALLBACK_PUSHBACK)
	player.external_force.x = -dir_x * pushback

	# 3. 給攻擊者一點基礎削韌
	if is_instance_valid(hitbox.owner) and "stats" in hitbox.owner:
		var attacker_stats = hitbox.owner.stats
		if is_instance_valid(attacker_stats) and "poise" in attacker_stats:
			attacker_stats.poise -= GUARD_POISE_CHIP
			# 🔧 這條削韌沒有經過 take_damage()/_on_hurtbox_hurt()，韌性歸零不會自動觸發癱瘓轉換，
			# 有實作 check_poise_break() 的敵人（目前是 BossNaihe）要自己補這一下檢查
			if hitbox.owner.has_method("check_poise_break"):
				hitbox.owner.check_poise_break()

	# 4. 特效：墨綠黑矩形碎片 + 鈍擊火花 + 震動 + 音效
	if GUARD_BREAK_BURST_SCENE:
		var burst = GUARD_BREAK_BURST_SCENE.instantiate()
		var burst_particles = burst.get_node_or_null("CPUParticles2D")
		if burst_particles:
			burst_particles.color = BLOCK_BURST_COLOR
			burst_particles.initial_velocity_min = BLOCK_BURST_VELOCITY.x
			burst_particles.initial_velocity_max = BLOCK_BURST_VELOCITY.y
			burst_particles.scale_amount_min = BLOCK_BURST_SCALE.x
			burst_particles.scale_amount_max = BLOCK_BURST_SCALE.y
		get_tree().current_scene.add_child(burst)
		burst.global_position = player.global_position + Vector2(10 * player.direction, -10)

	if CombatManager.has_method("spawn_spark"):
		CombatManager.spawn_spark(Hitbox.SparkType.BLUNT, player.global_position + Vector2(20 * player.direction, -30), player.direction)
	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(6.0, 0.08)

	
	AudioManager.play_action_sfx("hit_2", 0.0)
	AudioManager.play_action_sfx("hit_8", -10.0)

	return true

## 格擋判定期間把 Hurtbox 暫時放大成正方形，過了判定窗或離開狀態就要記得縮回去
func _expand_hurtbox() -> void:
	var shape_node = _get_hurtbox_shape_node()
	if shape_node == null: return

	if _original_hurtbox_shape == null:
		_original_hurtbox_shape = shape_node.shape
	if _guard_hurtbox_shape == null:
		_guard_hurtbox_shape = RectangleShape2D.new()
		_guard_hurtbox_shape.size = GUARD_HURTBOX_SIZE

	shape_node.shape = _guard_hurtbox_shape
	_hurtbox_expanded = true

func _restore_hurtbox() -> void:
	if not _hurtbox_expanded: return
	var shape_node = _get_hurtbox_shape_node()
	if shape_node and _original_hurtbox_shape:
		shape_node.shape = _original_hurtbox_shape
	_hurtbox_expanded = false

func _get_hurtbox_shape_node() -> CollisionShape2D:
	if _hurtbox_shape_node == null:
		_hurtbox_shape_node = player.get_node_or_null("Graphics/Hurtbox/CollisionShape2D")
	return _hurtbox_shape_node
