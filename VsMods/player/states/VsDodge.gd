class_name VsDodge
extends VsPlayerState
## 衝刺狀態
## 消耗 30 點衝刺能量，往前位移，期間不受重力影響。
## ⚠ 2026-07-27 使用者要求拿掉：衝刺不再有任何無敵時間，受擊時也不再有
## 「完美閃避」機制（原本受擊會延伸無敵＋結束後給 2 秒強霸體），純粹只是
## 位移＋殘影，被打到就正常進硬直，跟一般移動沒有防禦性質上的差異。

const DODGE_DURATION: float = 0.35
const GHOST_INTERVAL: float = 0.05  # 殘影間隔（秒），比照主遊戲 Slide.gd

const SLIDING_SFX_2 := preload("res://sound/SFX/sprint.wav")
const SLIDING_SFX_3 := preload("res://sound/SFX/attack/wind_2.wav")

var dodge_dir:    int   = 1
var elapsed:      float = 0.0
var _ghost_timer: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed        = 0.0
	_ghost_timer   = 0.0
	var vs         := player as VsPlayer
	# 以 last_input 決定方向；無移動輸入則沿目前面向
	var lm := vs.last_input.move_dir if vs.last_input else 0.0
	dodge_dir = int(sign(lm)) if lm != 0.0 else vs.facing_dir
	# 動畫朝向要跟移動方向一致：沒這行的話，若衝刺前面向跟 dodge_dir 不同
	# （例如剛轉身瞬間衝刺），畫面會出現「朝左的滑動動畫、卻往右衝」
	vs.facing_dir = dodge_dir
	vs.anim_player.play("sliding")
	vs.vfx_sfx(SLIDING_SFX_2, -12.0)
	vs.vfx_sfx(SLIDING_SFX_3, -8.0)

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed             += delta
	player.velocity.x    = dodge_dir * (player as VsPlayer).dodge_speed
	player.velocity.y    = 0.0   # 衝刺期間不受重力影響

	_ghost_timer += delta
	if _ghost_timer >= GHOST_INTERVAL:
		_ghost_timer -= GHOST_INTERVAL
		(player as VsPlayer).vfx_ghost()

	if elapsed >= DODGE_DURATION:
		player.velocity.x = 0.0   # 衝刺結束直接停下，不滑行
		return _recovery_transition(input)   # 支援跑步預輸入
	return &""

func save_state() -> Dictionary:
	return {
		"dir":     dodge_dir,
		"elapsed": elapsed,
		"gt":      _ghost_timer,
	}

func restore_state(d: Dictionary) -> void:
	dodge_dir     = d.get("dir",     1)
	elapsed       = d.get("elapsed", 0.0)
	_ghost_timer  = d.get("gt",      0.0)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("sliding")
	vs.anim_player.seek(elapsed, true)
