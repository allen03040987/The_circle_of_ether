class_name VsPlayer
extends CharacterBody2D

# ── 體質效果枚舉 ──────────────────────────────────────────────────────────────
enum ArmorTier {
	NONE,        # 正常
	HYPER,       # 霸體：免疫非破霸攻擊的擊退/硬直
	STRONG_HYPER # 強霸體：免疫非強破霸攻擊的擊退/硬直，並獲得 50% 減傷
}

## 這次命中的結果分類——供 vs_world 在命中判定後決定要給哪種打擊回饋
## （無敵目標不給音效/火花；防禦成功目標的火花換成格擋專用款）。純粹是
## 同一幀內「_on_hurtbox_hurt() 設定 → vs_world 立刻讀取」的執行期通訊，
## 不影響後續模擬，不進快照（跟 is_resimulating 同一類，不是模擬狀態）。
enum HitOutcome { NORMAL, GUARDED, INVINCIBLE }

# ── 設定 ─────────────────────────────────────────────────────────────────────
@export var player_id:       int   = 1
@export var max_hp:          float = 1000.0
# 武藝能量：脫戰後每秒恢復，上限 50
@export var max_arts_energy: float = 50.0
@export var arts_regen_rate: float = 10.0   # 每秒回復量（apply_arts_bonus 會疊加）
# 衝刺能量：永遠自動恢復，上限 100
@export var max_dash_energy: float = 100.0
@export var dash_regen_rate: float = 10.0   # 每秒回復量（永遠生效）

# ── 基礎移動數值（原本是 VsPlayerState.gd 的共用 const，改成這裡的 @export
# 讓角色專屬的 derived 場景能覆寫成不同手感；VsPlayerState 的共用輔助方法與
# 各狀態腳本改讀 (player as VsPlayer).xxx，不再用裸露的常數名稱）──────────────
@export_group("基礎移動數值")
@export var gravity:     float = 980.0   # px/s²
@export var move_speed:  float = 150.0   # px/s（地面）
@export var air_speed:   float = 130.0   # px/s（空中）
@export var friction:    float = 900.0   # px/s²（地面減速）
@export var jump_force:  float = -420.0  # px/s（負號朝上）
@export var dodge_speed: float = 300.0   # px/s（衝刺）

# ── VFX 字典庫（比照主遊戲 Player.gd 的 vfx_common/vfx_weapon/vfx_system）─────
# 用途：登記「名稱 → 特效場景」，動畫 Call Method 軌道或程式碼直接用字串名稱
# 呼叫 spawn_anim_vfx(name, ...)，不用像 vfx_spark_self 那樣被固定在單一枚舉
# 上——任何自訂特效場景都能掛，例如武藝/技能的專屬視覺。在 Inspector 展開
# 字典逐一新增 key（特效名）/value（PackedScene）即可，跟主遊戲用法一致。
@export_group("VFX 字典庫")
@export var vfx_common: Dictionary = {}   ## 通用特效（環境/煙塵等，跨角色共用）
@export var vfx_weapon: Dictionary = {}   ## 武器/角色專屬特效
@export var vfx_system: Dictionary = {}   ## 系統反饋（蓄力/受擊閃光等）

# ── 角色預設火花（比照主遊戲 Weapon.get_weapon_default_spark()）──────────────
# 每顆 VsHitbox 預設 use_character_default_spark=true，會完全套用這裡的值，
# 不用每招自己填一遍；想要某招火花不一樣才去該 hitbox 節點關掉開關、自己填。
@export_group("角色預設火花")
@export var default_spark_type: Hitbox.SparkType = Hitbox.SparkType.SLASH
@export var default_spark_scale: float = 0.3
@export var default_spark_color: Color = Color.WHITE
@export var default_aura_color: Color = Color(1.0, 1.0, 1.0, 0.5)
@export var default_spark_raw_intensity: float = 1.0
@export var default_spark_random_angle: float = 20.0
@export var default_spark_base_offset: Vector2 = Vector2.ZERO
@export var default_spark_random_offset: Vector2 = Vector2.ZERO
@export var default_attach_spark_to_victim: bool = true
@export var default_custom_spark_scene: PackedScene

# ── 武藝槽（由 vs_world 從 VsGameManager 注入）──────────────────────────────
var art_slots: Array[String] = ["", "", ""]
## 對應 art_slots 動態載入的武藝狀態節點（空字串槽位對應 null）。由 _load_arts()
## 在 vs_world 注入 art_slots 之後呼叫填入——場景初始化時 art_slots 還是空的，
## 沒辦法在 _ready() 就知道要掛哪個武藝腳本，跟地面/空中攻擊是場景固定子節點
## 不同，這裡必須是動態的。
var loaded_arts: Array[VsMartialArt] = [null, null, null]

## 依 art_slots 動態載入 3 個武藝腳本，掛成 VsStateMachine 的子節點並註冊進
## 狀態機（名稱固定 VsArt1~3，對應槽位 1~3，不是武藝的實際身分——同一個槽位
## 名稱在不同玩家/不同場次可能對應到不同武藝，靠 VsArtRegistry 查表決定實際
## 要 instantiate 哪個腳本）。由 vs_world._spawn_players() 在設定完 art_slots
## 後呼叫，此時 state_machine.init() 早已跑過，用 register_state() 補登記。
func _load_arts() -> void:
	for i in art_slots.size():
		var art_name := art_slots[i]
		if art_name == "":
			continue
		var script := VsArtRegistry.get_art_script(art_name)
		if script == null:
			continue   # 選了但還沒對應腳本的武藝（例如 Art_Clotty_2~6）先跳過
		var node := script.new() as VsMartialArt
		node.name = "VsArt%d" % (i + 1)
		node.art_id = art_name
		state_machine.add_child(node)
		state_machine.register_state(node, self)
		loaded_arts[i] = node

## slot：1/2/3。回傳該槽位動態載入的武藝狀態，沒裝或還沒對應腳本回傳 null。
func get_art_in_slot(slot: int) -> VsMartialArt:
	if slot < 1 or slot > loaded_arts.size():
		return null
	return loaded_arts[slot - 1]

# ── 數值 ─────────────────────────────────────────────────────────────────────
var hp:          float
var arts_energy: float
var dash_energy: float
var facing_dir:  int = 1    # 1 = 右, -1 = 左
## 確定性地面旗標：由 _move_deterministic 移動後以 test_move()（無狀態位置查詢）
## 更新，隨快照保存還原。所有模擬邏輯一律讀 grounded（VsPlayerState._grounded()），
## 嚴禁 is_on_floor()——它依賴 move_and_slide 的內部記憶，rollback 下不可靠。
var grounded:    bool = true
## 連段窗口旗標：由攻擊動畫的 `.:can_combo` 軌道開關（主遊戲同款做法），
## 程式碼不要直接排程它——時間點去動畫軌道上調。VsAttack 的 enter/exit 會歸零。
var can_combo:   bool = false
## 這次跳躍是否已經用掉空中普攻的施放機會（比照主遊戲 Katana.gd 的
## air_attack_locked）——每次跳躍只能觸發一輪空中普攻連段。VsAirAttack.enter()
## 開始新一輪時設 true；落地（grounded 變 true）時在 _move_deterministic() 歸零。
var air_attack_used: bool = false

# ── 戰鬥 ─────────────────────────────────────────────────────────────────────
var invincible_time_left:  float      = 0.0   # 剩餘無敵秒數（以 delta 遞減）
var post_dash_armor_left:  float      = 0.0   # 衝刺後強霸體倒計（秒）
var pending_hit:           Dictionary = {}    # 本幀設定，下幀處理（空 = 無）
var queued_hitstun:        float      = 0.4   # VsHurt.enter() 讀取的硬直時長
var queued_knockdown:      bool       = false # 落地屬性（y=0）：VsHurt 硬直完進倒地
var last_input:            InputState         # 當幀輸入備份（供 enter() 讀取方向）
var last_hit_outcome:      HitOutcome = HitOutcome.NORMAL   # 見 HitOutcome 註解

## 受身（全角色通用）：受擊硬直（VsHurt）或擊飛（VsLaunched）期間——這兩個
## 狀態本來就「無法操作」——按下技能鍵立刻獲得 UKEMI_DURATION 秒強霸體，藉此
## 打斷正在進行中的連段/juggle（強霸體讓後續非強破霸的攻擊只扣血不再重新
## 進硬直，VsHurt 自己的 elapsed 倒數不會被打斷重置，juggle 到此為止）。不
## 取消當下狀態本身——角色仍照原本的硬直/落地時間軸走，只是變得打不動。
## 每回合限用 UKEMI_MAX_USES 次（VsRoundManager._reset_round() 重置）。
const UKEMI_DURATION:  float = 2.0
const UKEMI_MAX_USES:  int   = 2
var ukemi_uses_left: int = UKEMI_MAX_USES

## 由 VsHurt/VsLaunched 的 physics_update() 在 input.skill 時呼叫。
## 次數用完回傳 false（呼叫端不用另外檢查次數，這裡就是唯一入口）。
func try_ukemi() -> bool:
	if ukemi_uses_left <= 0:
		return false
	ukemi_uses_left -= 1
	post_dash_armor_left = maxf(post_dash_armor_left, UKEMI_DURATION)
	# 觸發回饋：黃色十字特效（Cross slash sparks，套用跟強霸體描邊同一個金色
	# HDR 值 OUTLINE_COLOR_STRONG_HYPER，視覺語彙一致）+ beam_2 音效。兩個
	# 呼叫內建各自的 _vfx_blocked() 防呆，rollback 重模擬不會重複觸發，
	# try_ukemi() 不用另外處理
	spawn_anim_vfx("Cross slash sparks", 0.0, -30.0, Vector2(1.0, 1.0), 0.0, OUTLINE_COLOR_STRONG_HYPER)
	vfx_action_sfx("beam_2")
	return true

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var state_machine: VsStateMachine  = $VsStateMachine
@onready var anim_player:  AnimationPlayer = $AnimationPlayer
@onready var graphics:     Node2D          = $Graphics
@onready var hurtbox:      VsHurtbox       = $Graphics/VsHurtbox
## 技能專屬 hitbox（單發，不像普攻有一組陣列）——規則要求技能要能強破霸，
## break_level 直接設在這顆節點上（編輯器可調，但技能存在的意義就是要能破
## 強霸體，別把它調回 NONE）。同時也會被下面的 hitboxes 通用收集掃到。
@onready var skill_hitbox: VsHitbox = $Graphics/HitboxSkill
## Graphics 下所有 VsHitbox（每招一顆：HitboxA1~A5...，大小/位置/傷害數值都在
## 編輯器節點上調），開關由各攻擊動畫的 monitoring 軌道驅動，_ready() 收集
var hitboxes: Array[VsHitbox] = []
## 對手參照（由 vs_world._spawn_players 注入）——輔助鎖敵用
var opponent: VsPlayer = null

## 是否正在 rollback 重模擬中（由 vs_world._simulate_frame 每幀同步，不進快照——
## 這是「這次呼叫是不是重跑」的執行期中繼資訊，不是模擬狀態本身）。
## 所有 vfx_* 特效輔助函式都靠這個旗標擋掉重模擬期間的重複觸發：同一次命中、
## 同一幀衝刺可能因為多次 rollback 被重新跑過好幾遍，不擋的話火花/震動/殘影
## 會噴好幾份。純視覺、不影響模擬結果，兩端各自獨立判斷即可，不用同步。
var is_resimulating: bool = false

## 轉向指定世界 x 座標（模擬資料 position，rollback 安全）。x 等於自己時不變。
func face_towards_x(x: float) -> void:
	if x > position.x:
		facing_dir = 1
	elif x < position.x:
		facing_dir = -1

## 待機時持續鎖定面向對手（輔助鎖敵）。由 VsIdle 在靜止（無移動輸入）時每幀呼叫。
func face_opponent() -> void:
	if opponent:
		face_towards_x(opponent.position.x)

## 動畫呼叫方法軌道專用（主遊戲 Player.strike_impulse 同款設計）：攻擊動畫的
## 前衝/突刺幀直接注入水平速度，取代殘留動量——前衝力道由動畫軌道時間點與
## strength 參數決定，不用程式碼排程（跟 can_combo/hitbox 軌道同一套原則）。
## 只在攻擊狀態生效：若這幀之間已被打斷轉去別的狀態，該狀態 enter() 早已把
## anim_player 換成別的動畫，這條 call method 軌道理論上不會再被觸發，這裡多一層防呆。
##
## ⚠ rollback 確定性關鍵：_resyncing_anim 為 true 時直接跳過，不套用衝力。
## 原因：can_combo/hitbox monitoring 是「值」軌道，seek() 重複套用同一個值是
## 無害的（冪等）；但這是「呼叫方法」軌道，每次觸發都會真的改一次 velocity，
## 不是冪等的。sync_anim_to_state()（每次 rollback 還原快照、以及重模擬結束
## 都會呼叫）內部用 seek(elapsed, true) 把動畫時間跳到還原後的位置——Godot 的
## seek 是否會回放沿途經過的 call method key，行為不夠明確保證不會，一旦真的
## 回放了，這裡就會拿「已經是重模擬後正確結果」的 velocity 再蓋一次錯的衝力，
## 而且每次 rollback 都疊加一次，形同持續累積誤差 → desync（實測抓到過：連續
## 幾次 rollback 後 P2 在 vsattack 狀態 position/dash_energy 兩端對不上）。
## 這裡直接擋掉「因為 seek 而觸發」的呼叫，只允許「真的走過這一幀模擬」時
## （_do_rollback 重模擬迴圈裡的 advance()，或正常單幀模擬）才生效。
var _resyncing_anim: bool = false

## 「這幀之間已被打斷轉去別的狀態」防呆用的白名單——只有這些會播放 strike_impulse
## 動畫軌道的攻擊性狀態才允許生效。加新的攻擊/招式狀態、且它的動畫也想用
## strike_impulse 前衝軌道時，記得把該狀態類別加進這裡，不然呼叫全部是空跑
## （曾經只認 VsAttack，導致 VsAirAttack/VsSkill/武藝的 strike_impulse key 全部
## 沒作用，這裡才擴大範圍修正）。
func strike_impulse(strength: float) -> void:
	if _resyncing_anim: return
	var cur := state_machine.current_state
	var allowed := cur is VsAttack or cur is VsAirAttack or cur is VsSkill or cur is VsMartialArt
	if not allowed: return
	velocity.x = facing_dir * strength

## 動畫呼叫方法軌道專用：脫手發射彈道（比照主遊戲武藝的「劍氣」設計，簡化版，
## 見 Art_Clotty_5）。只在武藝狀態生效；跟 strike_impulse 同一套 rollback 防呆
## 原則——只擋 `_resyncing_anim`（純視覺 seek resync 誤觸發），不擋
## `is_resimulating`：這裡是「生成彈道」這個模擬狀態的一部分，rollback 重模擬
## 同一幀時必須照樣真的生成一顆新的彈道節點，兩端結果才會一致，跟 vfx_* 系列
## （純視覺、必須被 is_resimulating 擋掉重複觸發）性質不同，別搞混。
## damage_override > 0 時覆寫這顆彈道的傷害（例如 Art_Clotty_1 反擊劍氣的
## 700 傷害，跟 Art_Clotty_5 一般劍氣的預設值不同）；<=0（預設）就用
## VsProjectile.tscn 節點上的預設值，不用每個呼叫端都指定。
func fire_sword_wave(damage_override: float = -1.0) -> void:
	if _resyncing_anim: return
	if not (state_machine.current_state is VsMartialArt): return
	var vw := get_parent()
	if vw and vw.has_method("spawn_projectile"):
		var proj: VsProjectile = vw.spawn_projectile(self, facing_dir)
		if damage_override > 0.0:
			proj.hitbox.damage = damage_override

# 脫戰計時器：用 float + 模擬 delta，不用 Timer 節點（Timer 用真實時間，rollback 下會飄）
const OUT_OF_COMBAT_DELAY := 2.0
var out_of_combat_left: float = 0.0

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	hp          = max_hp
	arts_energy = max_arts_energy
	dash_energy = max_dash_energy
	_base_arts_regen_rate = arts_regen_rate   # apply_arts_bonus() 的疊加基準，見該函式註解
	# MANUAL 模式在運行時才切（rollback 需要：動畫由 apply_input 以模擬 delta 推進）。
	# 不寫死在 tscn——編輯器預覽在 MANUAL 模式下不會推進，動畫面板會壞掉不能播
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Call Method 軌道（strike_impulse）預設是「延遲執行」——真正呼叫的時機是
	# call_deferred() 排到這一幀稍後，不是 advance()/seek() 呼叫的當下。這會讓
	# _resyncing_anim 防呆完全失效（guard 早就重置回 false 了才真的觸發），
	# 而且 rollback 重模擬同一真實影格內會連續呼叫多次 advance()，若都被排到
	# 延遲佇列，執行次數/順序不保證對應到各自的模擬幀，直接破壞確定性
	# （實測：velocity 出現 -554.17 這種只有 strike_impulse 直接寫入才會有的
	# 異常值，重複觸發到離譜的程度）。改成立即模式，呼叫嚴格同步在 advance()/
	# seek() 呼叫當下發生，_resyncing_anim 才真的擋得住 resync 觸發的呼叫。
	anim_player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	for c in graphics.get_children():
		if c is VsHitbox:
			c.owner_player = self   # 受擊方向計算用（模擬資料，不依賴 scene tree transform）
			hitboxes.append(c)
	state_machine.init(self, &"vsidle")
	hurtbox.hurt.connect(_on_hurtbox_hurt)

# ── 主更新（由 vs_world 每幀呼叫）────────────────────────────────────────────
func apply_input(delta: float, input: InputState) -> void:
	last_input = input
	_update_energy_regen(delta)
	_tick_invincibility(delta)
	_apply_pending_hit()
	# 動畫用模擬 delta 手動推進（AnimationPlayer 是 MANUAL 模式）——
	# 攻擊動畫的 can_combo / hitbox monitoring 軌道值因此是模擬時間的純函數，
	# rollback 重模擬每幀都會重跑軌道，兩端保證一致。放在狀態更新之前，
	# 讓「動畫時間」與各狀態的 elapsed 對齊（enter 播動畫的下一幀兩者同為 1 delta）
	anim_player.advance(delta)
	state_machine.physics_update(delta, input)
	_move_deterministic(delta)
	graphics.scale.x = facing_dir

## 移動嚴禁用 move_and_slide()：它內部有「上一幀是否在地面」的隱藏記憶
## （地面吸附機制），rollback 還原 position 後該記憶仍是回滾前的舊值，
## 重模擬的移動結果會與直跑不同（實測：一邊多施一次重力 → y 永久分歧）。
## move_and_collide() 與 test_move() 都是無狀態查詢，結果只取決於當前
## position/velocity，且 motion 向量顯式傳入，不依賴引擎真實 delta。
func _move_deterministic(sim_delta: float) -> void:
	var col := move_and_collide(velocity * sim_delta)
	if col:
		var n := col.get_normal()
		if absf(n.y) > 0.7:
			# 地板 / 天花板：垂直速度歸零，剩餘位移只保留水平分量
			velocity.y = 0.0
			var rem := col.get_remainder()
			rem.y = 0.0
			if rem != Vector2.ZERO:
				move_and_collide(rem)
		else:
			# 牆壁：水平速度歸零，剩餘位移只保留垂直分量
			velocity.x = 0.0
			var rem := col.get_remainder()
			rem.x = 0.0
			if rem != Vector2.ZERO:
				move_and_collide(rem)
	# 消除碰撞求解的浮點雜訊：position 精度對齊 checksum（0.01px）
	# 這樣任何真實的位置分叉都至少差 0.01px，保證被 checksum 抓到
	position = position.snapped(Vector2(0.01, 0.01))
	# 地面旗標唯一更新點：純位置查詢（往下 0.1px 是否碰撞），無隱藏狀態，
	# 隨快照保存 → rollback 重模擬讀到正確值
	grounded = test_move(global_transform, Vector2(0.0, 0.1))
	if grounded:
		air_attack_used = false

# ── 能量 ─────────────────────────────────────────────────────────────────────
## 消耗衝刺能量（30點/次）；失敗回傳 false
func use_dash_energy(amount: float) -> bool:
	if dash_energy < amount:
		return false
	dash_energy -= amount
	return true

## 消耗武藝能量；失敗回傳 false，成功同時重置脫戰計時
func use_arts_energy(amount: float) -> bool:
	if arts_energy < amount:
		return false
	arts_energy -= amount
	out_of_combat_left = OUT_OF_COMBAT_DELAY
	return true

func mark_in_combat() -> void:
	out_of_combat_left = OUT_OF_COMBAT_DELAY

func _update_energy_regen(delta: float) -> void:
	# 衝刺能量：永遠恢復
	dash_energy = minf(dash_energy + dash_regen_rate * delta, max_dash_energy)
	# 武藝能量：脫戰後恢復
	if out_of_combat_left > 0.0:
		out_of_combat_left = maxf(out_of_combat_left - delta, 0.0)
	else:
		arts_energy = minf(arts_energy + arts_regen_rate * delta, max_arts_energy)
	# 衝刺後強霸體倒計
	if post_dash_armor_left > 0.0:
		post_dash_armor_left = maxf(post_dash_armor_left - delta, 0.0)

# ── 體質效果 ──────────────────────────────────────────────────────────────────
## 根據當前狀態與計時器計算實際 ArmorTier（衍生值，不儲存）
func get_armor_tier() -> ArmorTier:
	var cur := state_machine.current_state
	if cur is VsGuard:
		# 後搖（defense_2）期間沒有霸體，見 VsGuard.is_blocking() 註解
		return ArmorTier.STRONG_HYPER if (cur as VsGuard).is_blocking() else ArmorTier.NONE
	# 規則：武藝施放全程要有霸體或以上——多數武藝維持 HYPER（免疫非破霸攻擊）
	# 即符合下限，個別招式想要強霸體就設 armor_tier_override_strong
	if cur is VsMartialArt:
		return ArmorTier.STRONG_HYPER if (cur as VsMartialArt).armor_tier_override_strong else ArmorTier.HYPER
	if post_dash_armor_left > 0.0:
		return ArmorTier.STRONG_HYPER
	return ArmorTier.NONE

# ── 無敵 ─────────────────────────────────────────────────────────────────────
func _tick_invincibility(delta: float) -> void:
	if invincible_time_left > 0.0:
		invincible_time_left = maxf(invincible_time_left - delta, 0.0)

func is_invincible() -> bool:
	return invincible_time_left > 0.0

# ── 受傷信號（Area 重疊時由 VsHurtbox 觸發）─────────────────────────────────
func _on_hurtbox_hurt(hitbox: VsHitbox) -> void:
	var cur := state_machine.current_state
	last_hit_outcome = HitOutcome.NORMAL   # 預設；下面各分支視情況覆寫

	# 完美閃避：判定窗（VsDodge 前 PERFECT_WINDOW 秒，同時 invincible_time_left > 0）
	if cur is VsDodge and invincible_time_left > 0.0:
		(cur as VsDodge).trigger_perfect_dodge()
		last_hit_outcome = HitOutcome.INVINCIBLE
		return

	if is_invincible():
		last_hit_outcome = HitOutcome.INVINCIBLE
		return

	# 反擊型武藝（例如逆鱗返 Art_Clotty_1）：格擋窗口內、且攻擊破霸等級夠低
	# 就完全格擋+觸發反擊，這下攻擊直接被吃掉，不進入後續傷害/硬直流程。
	# duck-typed 呼叫（比照專案既有的 has_method 慣例）——之後任何武藝想做
	# 類似的「條件性完全格擋」都可以照這個介面接，不用改這裡。
	if cur and cur.has_method("try_parry") and cur.try_parry(hitbox):
		return

	# 被打時立刻轉向攻擊者（輔助鎖敵）——不管接下來走哪個分支（硬直/防禦/擊飛）
	if hitbox.owner_player:
		face_towards_x(hitbox.owner_player.position.x)

	# 擊退方向：用「攻擊者當下面向」而非兩者相對座標——主遊戲 Hitbox.gd 同款做法。
	# 出招時 hitbox 本就往攻擊者面向那側長出去，打中人時攻擊者幾乎必然面向被打者，
	# 用相對座標算會依兩人誰在左右而正負顛倒（同樣正值擊退卻一下前一下後的 bug 根源）。
	# 例外：彈道判定框（VsProjectile.hitbox）有 direction_override，優先採用——
	# 彈道命中當下，施放者早就可能轉身/移動走了，讀 owner_player.facing_dir
	# 會讓擊退方向跟著施放者事後的動作亂變，見 VsHitbox.direction_override 註解。
	var dir_x: int = hitbox.direction_override if hitbox.direction_override != 0 \
		else (hitbox.owner_player.facing_dir if hitbox.owner_player else -facing_dir)

	# 多段連擊方向鎖定：第一下命中（hits_dealt 剛被 register_hit() 設成 1）
	# 時把這次算出來的方向存進 direction_override，後續每一下（上面那行的
	# 判斷式會優先採用 direction_override）直接沿用同一個值，不再重新讀
	# owner_player 當下面向。見 VsHitbox.direction_override 欄位註解：sticky
	# 連擊時間跨度可能很長，攻擊者早就可能已經打完整招、回到自由操作，後續
	# 每一下若還即時讀當下面向會整個亂跳（2026-07-19 實測抓到：HitboxArt2Air
	# 落地後角色在 VsRun 自由移動，owner.facing 隨移動方向不斷改變，殘留命中
	# 的擊退方向跟著亂跳）。不管是不是 guard 擋下的第一下都照樣鎖定，純粹
	# 記錄用不影響本次判定流程。
	if hitbox.combo_hits > 1 and hitbox.hits_dealt == 1:
		hitbox.direction_override = dir_x

	# 防禦：只有還在按住階段（有霸體）才交給 VsGuard 處理格擋減傷/破防；
	# 後搖（defense_2）期間 is_blocking()==false，直接落到下面一般體質流程，
	# 這時 get_armor_tier() 也會回傳 NONE，等同正常受傷
	if cur is VsGuard and (cur as VsGuard).is_blocking():
		# 只有真的擋下來（非強破霸）才算 GUARDED 回饋；強破霸直接破防，走完整
		# 傷害/擊退/硬直，視覺上跟一般受擊沒兩樣，維持 NORMAL 預設值
		if hitbox.break_level != VsHitbox.BreakLevel.STRONG_ARMOR_BREAK:
			last_hit_outcome = HitOutcome.GUARDED
		(cur as VsGuard).on_guard_hit(hitbox)
		return

	# 體質效果判定
	var at := get_armor_tier()
	var bl := hitbox.break_level

	var allows_hitstun: bool
	var dmg_mult: float
	match at:
		ArmorTier.STRONG_HYPER:
			allows_hitstun = (bl == VsHitbox.BreakLevel.STRONG_ARMOR_BREAK)
			dmg_mult = 1.0 if bl == VsHitbox.BreakLevel.STRONG_ARMOR_BREAK else 0.5
		ArmorTier.HYPER:
			allows_hitstun = (bl >= VsHitbox.BreakLevel.ARMOR_BREAK)
			dmg_mult = 1.0
		_:  # NONE
			allows_hitstun = true
			dmg_mult = 1.0

	if not allows_hitstun:
		# 霸體吸收擊退/硬直；仍承受傷害（可能有 50% 減傷）
		hp = maxf(hp - hitbox.damage * dmg_mult, 0.0)
		mark_in_combat()
		return

	# 一般受傷：排隊（下幀 _apply_pending_hit 處理）
	pending_hit = {
		"damage":           hitbox.damage * dmg_mult,
		"hitstun_time":     hitbox.hitstun_time,
		"knockback":        Vector2(hitbox.knockback.x * dir_x, hitbox.knockback.y),
		"causes_knockdown": hitbox.causes_knockdown,
	}

func _apply_pending_hit() -> void:
	if pending_hit.is_empty(): return
	var hit  := pending_hit
	pending_hit = {}

	hp            = maxf(hp - hit["damage"], 0.0)
	velocity      = hit["knockback"]
	queued_hitstun = hit["hitstun_time"]
	mark_in_combat()

	# 落地規則分流：
	#   落地屬性 + y<0 擊退 → 擊飛（忽略硬直，落地那一刻直接進倒地）
	#   落地屬性 + y=0 擊退 → 正常硬直，硬直結束後進倒地（queued_knockdown）
	#   無落地屬性          → 正常硬直
	var cur := state_machine.current_state
	var kb: Vector2 = hit["knockback"]
	if hit["causes_knockdown"] and kb.y < 0.0:
		if cur is VsLaunched:
			cur.enter(&"vslaunched")   # 空中再次被擊飛（juggle）：重入刷新
		else:
			state_machine.transition_to(&"vslaunched")
	elif cur is VsKnockdown or cur is VsLaunched:
		pass  # 倒地（OTG）/擊飛中被普通攻擊打到：只吃傷害與擊退速度，不改變狀態
	else:
		queued_knockdown = hit["causes_knockdown"]
		if cur is VsHurt:
			cur.enter(&"vshurt")
		else:
			state_machine.transition_to(&"vshurt")

# ── 受傷（直接扣血，不帶硬直，外部工具用）───────────────────────────────────
func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)

# ── Rollback：快照 / 還原 / 動畫同步 ─────────────────────────────────────────
func save_state() -> Dictionary:
	var cur := state_machine.current_state
	return {
		"pos":    position,
		"vel":    velocity,
		"hp":     hp,
		"arts_e": arts_energy,
		"dash_e": dash_energy,
		"facing": facing_dir,
		"gnd":    grounded,
		"cc":     can_combo,
		"aau":    air_attack_used,
		"inv":    invincible_time_left,
		"pda":    post_dash_armor_left,
		"ukemi":  ukemi_uses_left,
		"phit":   pending_hit.duplicate(true),
		"qhit":   queued_hitstun,
		"qkd":    queued_knockdown,
		"ctimer": out_of_combat_left,
		# 每顆判定框的 [monitoring, has_hit, hits_dealt, hit_cooldown_left, is_locked]：
		# monitoring 平時由動畫軌道驅動，has_hit（=連擊全部打完）防 rollback
		# 重模擬時同一攻擊窗重複命中；hits_dealt/hit_cooldown_left/is_locked
		# 是連擊系統（含 sticky 鎖定）的進度，一併存進快照才能正確還原連擊節奏
		"hbs":    hitboxes.map(func(h: VsHitbox) -> Array:
			return [h.monitoring, h.has_hit, h.hits_dealt, h.hit_cooldown_left, h.is_locked]),
		"sname":  state_machine.current_state_name,
		"sdata":  cur.save_state() if cur else {},
	}

func restore_state(s: Dictionary) -> void:
	position             = s["pos"]
	velocity             = s["vel"]
	hp                   = s["hp"]
	arts_energy          = s["arts_e"]
	dash_energy          = s["dash_e"]
	facing_dir           = s["facing"]
	grounded             = s["gnd"]
	can_combo            = s["cc"]
	air_attack_used      = s["aau"]
	invincible_time_left = s["inv"]
	post_dash_armor_left = s["pda"]
	ukemi_uses_left      = s.get("ukemi", UKEMI_MAX_USES)
	pending_hit          = s["phit"].duplicate(true)
	queued_hitstun       = s["qhit"]
	queued_knockdown     = s["qkd"]
	out_of_combat_left   = s["ctimer"]
	graphics.scale.x     = facing_dir
	var hbs: Array = s["hbs"]
	for i in hitboxes.size():
		hitboxes[i].monitoring        = hbs[i][0]
		hitboxes[i].has_hit           = hbs[i][1]
		hitboxes[i].hits_dealt        = hbs[i][2]
		hitboxes[i].hit_cooldown_left = hbs[i][3]
		hitboxes[i].is_locked         = hbs[i][4]
		hitboxes[i].hit_targets.clear()
	state_machine.set_state_quiet(s["sname"])
	if state_machine.current_state:
		state_machine.current_state.restore_state(s["sdata"])
	# 動畫時間必須立刻對齊還原後的狀態：軌道值由 advance() 依動畫時間驅動，
	# 時間不對的話重模擬會漏觸發/多觸發 can_combo、hitbox monitoring 的 key
	sync_anim_to_state()

func sync_anim_to_state() -> void:
	if state_machine.current_state:
		# 期間發生的動畫 seek 純粹是視覺重新對齊，不代表真的走過那段模擬時間——
		# 見 strike_impulse() 的說明，擋掉 seek 觸發的方法呼叫副作用
		_resyncing_anim = true
		state_machine.current_state.sync_anim()
		_resyncing_anim = false

# ── 武藝加成（vs_world 注入 art_slots 後呼叫；reload_arts() 換裝後也會重呼叫，
# 見下方）────────────────────────────────────────────────────────────────────
var _base_arts_regen_rate: float = 0.0   # _ready() 捕捉的 @export 原始值，見下

## 從 _base_arts_regen_rate 重新算，不是疊加——換裝武藝（reload_arts()）可能
## 讓空槽數量變動，這裡要能重複呼叫且每次都是「乾淨地」依當下空槽數重算，
## 不能像原本那樣 `+=`（重呼叫會疊加出雪球式暴增的回復速率）。
func apply_arts_bonus() -> void:
	var empty := art_slots.count("")
	arts_regen_rate = _base_arts_regen_rate + empty * VsGameManager.EMPTY_SLOT_REGEN_BONUS

## 回合間重選武藝用：卸下舊的動態武藝狀態節點，依 new_slots 重新載入。
## 只能在玩家不處於任何武藝狀態時呼叫（VsRoundManager 在 _reset_round() 裡
## transition_to(&"vsidle") 之後才呼叫，此時 current_state 保證不是任何
## VsMartialArt 節點，可以安全移除舊節點不會留下懸空的 current_state 參照）。
func reload_arts(new_slots: Array) -> void:
	for i in loaded_arts.size():
		var old: VsMartialArt = loaded_arts[i]
		if is_instance_valid(old):
			state_machine.states.erase(StringName(old.name.to_lower()))
			# ⚠ 必須先 remove_child() 再 queue_free()，不能只呼叫 queue_free()：
			# queue_free() 只是排到這一幀結束才真正移除，這一幀稍後 _load_arts()
			# 馬上又會 add_child() 一個同名的新節點（例如同樣叫 "VsArt1"）——
			# 舊節點這時還「活」在場景樹裡（只是排隊等刪），Godot 偵測到同名
			# 衝突會自動幫新節點改名（例如變成 "VsArt1@2"），register_state()
			# 就會用錯誤的 key 登記進 states 字典，之後 transition_to("vsart1")
			# 就會找不到狀態（實測：VsStateMachine: 找不到狀態 'vsart1'）。
			# remove_child() 立刻把舊節點從樹上摘掉、釋放名稱，新節點才能順利
			# 沿用同一個名字；queue_free() 仍然安全處理之後的記憶體釋放。
			state_machine.remove_child(old)
			old.queue_free()
		loaded_arts[i] = null
	# .assign() 而非直接指派——new_slots 常常是外部傳來的純 Array（例如
	# VsRoundManager.p1_new_arts），直接指派給 Array[String] 型別的 art_slots
	# 會因為型別不符出錯，跟 vs_world._spawn_players() 用 art_slots.assign(...)
	# 而非 = 的理由一樣
	art_slots.assign(new_slots)
	_load_arts()
	apply_arts_bonus()

# ==========================================
# 🎇 打擊回饋 VFX
# ==========================================
## CombatManager（autoload）是共用的特效庫，`vfx_spark`/`vfx_shake`/`vfx_ghost`/
## `vfx_dodge_spark` 是每個角色呼叫它的統一入口。`spawn_anim_vfx` 則是完整移植
## 主遊戲 Player.gd 的「字典庫」系統（見下方，vfx_common/vfx_weapon/vfx_system 三
## 個 @export Dictionary），用來掛任意自訂特效場景（不限於固定的 SparkType 打擊
## 火花）——這兩套系統並存，各司其職：固定打擊回饋用 vfx_*，招式專屬/自訂特效
## 用 spawn_anim_vfx。都不需要另外蓋一個「特效字典場景」，CombatManager／
## Dictionary 本身就是。
##
## **火花只綁在命中判定上，動畫軌道用不到**：`vfx_spark` 一定要有實際命中的
## `VsHitbox`（讀它的 use_character_default_spark/角色預設 fallback），只會由
## `vs_world._manual_check()` 在真正判定命中時呼叫，不提供動畫 Call Method 軌道
## 版本——招式自己的動畫不該無條件噴火花，那是命中那一刻、命中對象身上才有的
## 反應。`vfx_shake`/`vfx_ghost`/`vfx_dodge_spark`/`spawn_anim_vfx` 則兩種來源
## 都能呼叫：(1) 程式碼直接呼叫（hit 判定、dash 計時器這種要等執行期才知道該不
## 該觸發的場合）；(2) 當動畫 Call Method 軌道用（NodePath 打 `.`、方法名填函式
## 名，比照 strike_impulse 的用法，適合「這一幀就是要有這個特效」的固定時間點，
## 例如出招瞬間的塵土、蓄力閃光——這些不是「命中回饋」，是招式本身自帶的效果，
## 所以可以綁動畫時間點）。
## 兩種來源共用同一套 rollback 防呆：
##   - is_resimulating：擋掉 rollback 重模擬期間的重複觸發
##   - _resyncing_anim：擋掉 sync_anim_to_state() 的 seek() 可能回放 Call Method key
## 兩者缺一不可（原因見 _ready() 設定 callback_mode_method 那段說明），任何新的
## Call Method 軌道都要走這裡而不是直接呼叫 CombatManager，否則會漏掉這層防呆。
func _vfx_blocked() -> bool:
	return is_resimulating or _resyncing_anim

## 角色 Sprite2D 的實際世界座標——VsPlayer 根節點對齊腳底，特效要對齊「看起來的
## 身體位置」得讀這個，不能直接用 global_position（那是腳底，殘影/火花會貼地）
func vfx_anchor_position() -> Vector2:
	var sprite := graphics.get_node_or_null("Sprite2D") as Sprite2D
	return sprite.global_position if is_instance_valid(sprite) else global_position

## 打擊火花——由 vs_world._manual_check 命中確認後呼叫。完整比照主遊戲
## Hitbox._execute_hit() 的解析流程：先決定這顆 hitbox 是用角色預設還是自己的
## 火花設定（VsHitbox.use_character_default_spark），再算隨機角度/偏移，最後
## 呼叫 CombatManager.spawn_spark。純視覺，兩端各自 randf_range 不用同步。
func vfx_spark(hb: VsHitbox, base_pos: Vector2, victim: Node) -> void:
	if _vfx_blocked(): return
	var type: Hitbox.SparkType
	var scale: float
	var color: Color
	var aura: Color
	var intensity: float
	var rand_angle: float
	var base_offset: Vector2
	var rand_offset: Vector2
	var attach: bool
	var custom_scene: PackedScene
	if hb.use_character_default_spark:
		type          = default_spark_type
		scale         = default_spark_scale
		color         = default_spark_color
		aura          = default_aura_color
		intensity     = default_spark_raw_intensity
		rand_angle    = default_spark_random_angle
		base_offset   = default_spark_base_offset
		rand_offset   = default_spark_random_offset
		attach        = default_attach_spark_to_victim
		custom_scene  = default_custom_spark_scene
	else:
		type          = hb.spark_type
		scale         = hb.spark_scale
		color         = hb.spark_color
		aura          = hb.aura_color
		intensity     = hb.spark_raw_intensity
		rand_angle    = hb.spark_random_angle
		base_offset   = hb.spark_base_offset
		rand_offset   = hb.spark_random_offset
		attach        = hb.attach_spark_to_victim
		custom_scene  = hb.custom_spark_scene

	var pos := base_pos + Vector2(base_offset.x * facing_dir, base_offset.y)
	pos.x += randf_range(-rand_offset.x, rand_offset.x)
	pos.y += randf_range(-rand_offset.y, rand_offset.y)
	var angle := randf_range(-rand_angle, rand_angle)
	var target: Node = victim if attach else null
	CombatManager.spawn_spark(type, pos, facing_dir, target, angle, scale, color, custom_scene, aura, intensity)

## 螢幕震動——強度 <= 0 視為不震動。可直接當動畫 Call Method 軌道呼叫。
## ⚠ 走 VsCamera.shake()，不是主遊戲的 CombatManager.apply_camera_shake()：
## VsCamera._physics_process() 每幀都會用自己的 shake_timer/shake_intensity
## 決定 offset（沒在震動就強制歸零），如果改呼叫 CombatManager 那邊用 Tween
## 動 camera.offset，兩邊每幀互搶同一個屬性，Tween 的效果會被 VsCamera 自己的
## 「沒在搖就歸零」蓋掉，震動等於沒作用（實測發現的坑，VsCamera 早就有自己
## 一套完整的震動系統，直接用它就好，不要重複做兩套）。
func vfx_shake(intensity: float, duration: float = 0.06) -> void:
	if _vfx_blocked() or intensity <= 0.0: return
	if not Game.config_enable_screen_shake: return
	var cam := get_viewport().get_camera_2d() as VsCamera
	if is_instance_valid(cam):
		cam.shake(intensity, duration)

## 殘影——沿用主遊戲 add_ghost 的預設半透明白色。可當動畫 Call Method 軌道呼叫，
## 也可由 VsDodge 每 0.05s 呼叫一次（衝刺拖尾）
func vfx_ghost(color: Color = Color(1.0, 1.0, 1.0, 0.4)) -> void:
	if _vfx_blocked(): return
	var sprite := graphics.get_node_or_null("Sprite2D") as Sprite2D
	if is_instance_valid(sprite):
		CombatManager.spawn_ghost(sprite, sprite.global_position, graphics.scale, color)

## 完美閃避專屬火花——由 VsDodge.trigger_perfect_dodge() 呼叫
func vfx_dodge_spark() -> void:
	if _vfx_blocked(): return
	CombatManager.spawn_dodge_spark(vfx_anchor_position())

## 格擋成功火花——比照主遊戲 player/state/Guard.gd::try_block() 的火花參數
## （BLUNT 鈍擊型、貼在防禦方身上、朝防禦方面向），跟一般命中火花 vfx_spark
## （貼在受害者身上但套用「攻擊方」的火花預設/角色設定）是不同的視覺語彙：
## 全角色共用同一款固定外觀，不走 use_character_default_spark 那套 fallback。
## 由 vs_world 在判定命中結果是 VsPlayer.HitOutcome.GUARDED 時對防禦方呼叫。
func vfx_block_spark() -> void:
	if _vfx_blocked(): return
	var pos := vfx_anchor_position() + Vector2(20.0 * facing_dir, -30.0)
	CombatManager.spawn_spark(Hitbox.SparkType.BLUNT, pos, facing_dir)

## 特寫運鏡——鏡頭短暫拉近盯著自己再自動恢復一般立回模式。可直接當動畫 Call
## Method 軌道呼叫（NodePath 打 `.`，方法名 vfx_closeup）。
## depth = 拉近倍率（VsCamera.cinematic_zoom() 規定 > 1.0 才會真的觸發特寫，
## 數值越大鏡頭拉得越近；平常立回縮放範圍是 min_zoom~max_zoom= 0.6~1.2，
## depth 建議抓 1.5~2.5 左右試手感）；duration = 維持特寫的秒數，時間到
## VsCamera 自己倒數退出，不用另外呼叫「結束特寫」。
## 走 VsCamera 自己的 cinematic_zoom（不是主遊戲 CombatManager.apply_camera_closeup）：
## VsCamera 平常持續動態運算縮放（依兩位玩家距離即時調整），主遊戲那套「直接
## tween camera.zoom、時間到還原成固定 base_zoom」的做法會跟這個動態運算打架
## ——VsCamera 已經有專門的 is_in_cinematic 分支處理特寫期間暫停動態運算，
## 直接用它才不會互相搶 zoom 屬性。
func vfx_closeup(depth: float, duration: float) -> void:
	if _vfx_blocked(): return
	var cam := get_viewport().get_camera_2d() as VsCamera
	if is_instance_valid(cam):
		cam.cinematic_zoom(self, depth, duration)

## 生成字典庫裡登記的自訂特效（比照主遊戲 Player.spawn_anim_vfx，完整移植）。
## 依序查 vfx_common → vfx_weapon → vfx_system，找不到就不生成。
## detach=true：掛在 vs_world 底下（世界座標獨立存在，角色死亡/換狀態不會帶走）；
## detach=false：掛在角色自己身上（跟著移動，例如貼身持續特效）。
## 位置基準跟主遊戲一樣是角色的 global_position（腳底）＋呼叫端自己指定的
## offset_x/offset_y——不是 vfx_anchor_position()，因為主遊戲每個特效呼叫本來
## 就是靠 offset 手動校正位置（例如 "heal_flash" 用 offset_y=-30 對準胸口），
## 換成自動抓 Sprite2D 位置反而會跟既有的 offset 數值對不上。
func spawn_anim_vfx(
	vfx_name: String, offset_x: float = 0.0, offset_y: float = 0.0,
	custom_scale: Vector2 = Vector2(1.0, 1.0), rotation_deg: float = 0.0,
	custom_color: Color = Color.WHITE, aura_color: Color = Color.WHITE,
	detach: bool = true, custom_z_index: int = 1, raw_intensity: float = 1.0
) -> void:
	if _vfx_blocked(): return
	var vfx_scene: PackedScene = null
	if vfx_common.has(vfx_name): vfx_scene = vfx_common[vfx_name]
	elif vfx_weapon.has(vfx_name): vfx_scene = vfx_weapon[vfx_name]
	elif vfx_system.has(vfx_name): vfx_scene = vfx_system[vfx_name]
	if vfx_scene == null: return

	var vfx := vfx_scene.instantiate()
	if detach:
		get_parent().add_child(vfx)
		vfx.global_position = global_position + Vector2(offset_x * facing_dir, offset_y)
		vfx.z_index = z_index + custom_z_index
	else:
		add_child(vfx)
		vfx.position = Vector2(offset_x * facing_dir, offset_y)
		vfx.z_index = custom_z_index

	vfx.scale = Vector2(facing_dir * custom_scale.x, custom_scale.y)
	vfx.rotation_degrees = rotation_deg * facing_dir
	var hdr_color := Color(custom_color.r * raw_intensity, custom_color.g * raw_intensity, custom_color.b * raw_intensity, custom_color.a)
	CombatManager._apply_vfx_colors(vfx, hdr_color, aura_color)

## 音效——跟 vfx_shake/vfx_ghost 同一套 rollback 防呆（_vfx_blocked()）：
## rollback 重模擬同一真實影格可能重跑好幾次，音效是一次性副作用，沒防呆
## 會重複播放。三個包裝函式對應主遊戲 AudioManager 的三種呼叫方式：
##   - vfx_sfx：直接給 AudioStream（play_sfx 的包裝，低階用法）
##   - vfx_action_sfx：用字串 key 查 action_sfx_bank（play_action_sfx 的包裝，
##     動作/演出類音效，例如格擋、防禦成功、彈反成功）
##   - vfx_hit_sfx：命中專用，讀 VsHitbox.hit_sfx_type 查 hit_sfx_bank
##     （play_hit_sfx 的包裝，比照主遊戲 classes/Hitbox.gd::_execute_hit()）
## 三者都可直接當動畫 Call Method 軌道呼叫（NodePath 打 `.`）。
func vfx_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if _vfx_blocked() or stream == null: return
	AudioManager.play_sfx(stream, volume_db, pitch_scale)

func vfx_action_sfx(key: String, volume_db: float = -8.0) -> void:
	if _vfx_blocked() or key == "": return
	AudioManager.play_action_sfx(key, volume_db)

## 打擊命中音效——由 vs_world._manual_check()/_manual_check_projectile() 命中
## 確認後呼叫，跟 vfx_spark/vfx_shake 同一個呼叫點：不管防禦/霸體/無敵吸收
## 與否都照樣給回饋（「打中了」跟「打中造成多少效果」是兩件事，比照主遊戲
## Hitbox._execute_hit() 的做法，這裡不加條件判斷）。
func vfx_hit_sfx(hb: VsHitbox) -> void:
	if _vfx_blocked() or hb.hit_sfx_type == "": return
	AudioManager.play_hit_sfx(hb.hit_sfx_type, -2.0)

# ==========================================
# 🎨 狀態輪廓描邊（主遊戲 StatusOutline 同款）：藍=霸體、黃=強霸體、紅=無敵
# 優先權：無敵 > 強霸體 > 霸體。純視覺——每個渲染幀從「當下模擬狀態」衍生，
# 不參與模擬、不進快照，rollback 無關（tween 用真實時間也沒關係）。
# ==========================================
const OUTLINE_SHADER = preload("res://classes/StatusOutline.gdshader")
const OUTLINE_COLOR_HYPER        := Color(0.5, 0.8, 1.4, 0.7)  ## 藍（低調）
const OUTLINE_COLOR_STRONG_HYPER := Color(1.4, 1.1, 0.0, 1.0)  ## 黃（HDR 飽和）
const OUTLINE_COLOR_INVINCIBLE   := Color(1.0, 0.15, 0.15, 1.0) ## 紅
const OUTLINE_FADE_DURATION: float = 0.15

var _outline_mat:      ShaderMaterial = null
var _outline_original: Material       = null
var _outline_tween:    Tween          = null
var _outline_state:    String         = ""  ## "" / "invincible" / "strong_hyper" / "hyper"

func _process(_delta: float) -> void:
	_update_status_outline()

func _update_status_outline() -> void:
	var desired := ""
	# 跟主遊戲共用同一個純視覺開關（設定選單的「狀態輪廓」）
	if Game.config_enable_status_outline:
		if is_invincible():
			desired = "invincible"
		else:
			match get_armor_tier():
				ArmorTier.STRONG_HYPER: desired = "strong_hyper"
				ArmorTier.HYPER:        desired = "hyper"

	if desired != _outline_state:
		_outline_state = desired
		match desired:
			"invincible":   _apply_outline_color(OUTLINE_COLOR_INVINCIBLE)
			"strong_hyper": _apply_outline_color(OUTLINE_COLOR_STRONG_HYPER)
			"hyper":        _apply_outline_color(OUTLINE_COLOR_HYPER)
			_:              _clear_outline()

	# spritesheet 每幀重算「目前這一格」的 UV 範圍，避免描邊採樣到隔壁格（主遊戲同款處理）
	if is_instance_valid(_outline_mat) and _outline_state != "":
		_sync_outline_frame_bounds()

func _apply_outline_color(color: Color) -> void:
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("line_color", color)
	_outline_mat.set_shader_parameter("outline_alpha", 0.0)
	var sprite := graphics.get_node_or_null("Sprite2D")
	if is_instance_valid(sprite):
		if sprite.material != _outline_mat:
			_outline_original = sprite.material
			sprite.material = _outline_mat
	if is_instance_valid(_outline_tween) and _outline_tween.is_valid(): _outline_tween.kill()
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_alpha", 1.0, OUTLINE_FADE_DURATION)

func _clear_outline() -> void:
	if not is_instance_valid(_outline_mat): return
	if is_instance_valid(_outline_tween) and _outline_tween.is_valid(): _outline_tween.kill()
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_alpha", 0.0, OUTLINE_FADE_DURATION)
	_outline_tween.tween_callback(_restore_outline_material)

func _restore_outline_material() -> void:
	var sprite := graphics.get_node_or_null("Sprite2D")
	if is_instance_valid(sprite) and sprite.material == _outline_mat:
		sprite.material = _outline_original
	_outline_original = null

func _sync_outline_frame_bounds() -> void:
	var sprite := graphics.get_node_or_null("Sprite2D") as Sprite2D
	if not is_instance_valid(sprite): return
	var h := maxi(sprite.hframes, 1)
	var v := maxi(sprite.vframes, 1)
	if h <= 1 and v <= 1:
		_outline_mat.set_shader_parameter("frame_uv_min", Vector2.ZERO)
		_outline_mat.set_shader_parameter("frame_uv_max", Vector2.ONE)
		return
	var col := sprite.frame % h
	var row := int(sprite.frame / float(h))
	var uv_min := Vector2(float(col) / h, float(row) / v)
	var uv_max := uv_min + Vector2(1.0 / h, 1.0 / v)
	_outline_mat.set_shader_parameter("frame_uv_min", uv_min)
	_outline_mat.set_shader_parameter("frame_uv_max", uv_max)
