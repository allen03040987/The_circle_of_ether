class_name VsBloodShadow
extends CharacterBody2D
## 血影（Asatsubaki 專屬，見 CLAUDE.md「VsMods Asatsubaki 血影機制」）——
## 確定性物件，比照 VsProjectile 的座標慣例：必須以 vs_world 的直屬子節點
## 形式存在（position 才等同世界座標）。跟彈道不同的地方：只有 0/1 顆
## （vs_world.p1_shadow/p2_shadow，不是陣列），移動由玩家操控（見
## VsPlayer._apply_possession_input()）而不是無狀態直線位移，而且**沒有
## hurtbox**——不掛任何會被 _check_manual_hits() 掃到的節點，天然滿足
## 「血影不會受到任何攻擊判定」，不需要額外的無敵判斷。
##
## **會被牆壁/地板擋住**（使用者明確要求「和角色一樣」，不是幽靈）：
## extends CharacterBody2D，跟 VsPlayer._move_deterministic() 同一套確定性
## 碰撞寫法——move_and_collide()（無狀態，結果只取決於當前 position/velocity）
## ＋碰到牆用法線判斷該歸零哪一軸再補推剩餘位移，嚴禁 move_and_slide()（見
## CLAUDE.md 確定性規則表，內部隱藏的「上一幀是否貼地」記憶在 rollback 還原
## position 後對不上，會造成永久分歧）。collision_layer=0（不需要被任何人
## 偵測到，機關/命中判定都是手動 Rect2，不靠 Area2D/Body 訊號）、
## collision_mask=4224（128 地板層｜4096 平台層，跟 VsPlayer.GROUND_LAYER_BIT/
## PLATFORM_LAYER_BIT 同一組值，直接寫在 .tscn 根節點屬性，不用另外在腳本
## 設定）。不做階梯輔助——沒人要求，撞到台階當一般牆壁擋住即可。
##
## **吃重力＋可以跳躍**（2026-08-03 從「無重力四方向自由飛行」改版，使用者
## 實測飛行手感後要求改回一般平台動作邏輯）：垂直方向由 velocity.y 累積
## SHADOW_GRAVITY（600，獨立常數，比本體 980 輕——使用者要求飄得比本體慢）
## ／落地時按跳躍鍵可跳，跳躍力道讀 owner_player.effective_jump_force()
## （跟本體同一份數值，角色調跳躍高度血影自動跟著變）；水平方向用血影自己的
## SHADOW_MOVE_SPEED（比本體快，使用者先前要求調快過）。grounded 用跟
## VsPlayer 同款的 test_move() 純位置查詢（無隱藏狀態，隨快照保存），不是
## CharacterBody2D 內建的 is_on_floor()（那個是 move_and_slide() 專屬，這裡
## 完全不呼叫）。facing_dir 依水平輸入翻轉 sprite.flip_h（純視覺，沒有
## hitbox 要跟著鏡像，不像 VsPlayer 要整個 graphics 子樹翻轉）。
##
## ⚠ 動畫要自己加：在編輯器對 VsBloodShadow.tscn 新增一顆 AnimationPlayer
## 子節點（名稱固定 "AnimationPlayer"）＋一個 AnimationLibrary，裡面放兩支
## 固定名稱的動畫——"summon"（召喚瞬間播一次）跟 "idle"（待機循環）；沒有
## "summon" 就直接播 "idle"，兩支都沒有就完全沒有動畫（跟目前一樣，純視覺
## 佔位）。名稱是寫死的約定，這支腳本不用知道實際動畫內容長什麼樣。

const SHADOW_MOVE_SPEED: float = 350.0
const SHADOW_GRAVITY:    float = 850.0   # 獨立於 owner_player.gravity（本體 980）——使用者要求血影飄得比本體輕

## 附身期間的紅色殘影拖尾——讓玩家一眼看出現在操控的是血影，跟 VsDodge 的
## 衝刺殘影同一套（CombatManager.spawn_ghost() 複製 Sprite2D 外觀＋Tween 淡出，
## 純視覺、真實時間淡出不影響確定性，跟 VsPlayer.vfx_ghost() 同一個既有慣例）。
const GHOST_INTERVAL: float = 0.05
const GHOST_COLOR := Color(1.0, 0.15, 0.15, 0.5)
const GHOST_Z_INDEX_OFFSET: int = -1     # 疊在血影本體「後面」（血影 z_index 預設 0）
const GHOST_RISE_DISTANCE: float = 24.0  # 淡出的同時往上飄的距離（px），不是原地消失

@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var sprite:      Sprite2D        = $Sprite2D

var owner_player: VsPlayer = null   # 不進快照，還原時由 vs_world 重新指派（同 VsProjectile 慣例）
var _age:         float = 0.0       # 存在秒數，純累加，用來判斷 summon 播完了沒
var _idle_started: bool = false     # 是否已經切到 idle（summon 播完，或本來就沒有 summon）
var grounded:     bool  = false     # 跟 VsPlayer.grounded 同款：純位置查詢，隨快照保存
var facing_dir:   float = 1.0       # 朝向（1=右/-1=左），只影響 sprite.flip_h（純視覺）
var _ghost_timer: float = 0.0       # 殘影間隔倒數，跟 VsDodge._ghost_timer 同款，隨快照保存
var is_resimulating: bool = false   # 由 vs_world._simulate_frame() 每幀同步，vfx_ghost() 靠這個擋 rollback 重複觸發，不進快照（執行期中繼資訊）

func _ready() -> void:
	if not anim_player:
		return
	# MANUAL 模式在運行時才切、Call Method 用 IMMEDIATE——跟 VsPlayer._ready()/
	# VsProjectile._ready() 同一套確定性理由，見 CLAUDE.md 確定性規則表。
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_player.callback_mode_method  = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	if anim_player.has_animation("summon"):
		anim_player.play("summon")
	elif anim_player.has_animation("idle"):
		anim_player.play("idle")
		_idle_started = true

## 每幀由 VsPlayer._apply_possession_input() 呼叫。move_dir 是水平輸入軸
## （-1/0/1），jump_pressed 是這一幀跳躍鍵是否剛按下（edge-triggered，跟
## VsJump 的觸發條件同款）。重力用血影自己的 SHADOW_GRAVITY，跳躍力道讀
## owner_player.effective_jump_force()；跟 VsPlayer._move_deterministic()
## 同一套 move_and_collide() 確定性寫法——碰到東西時依法線判斷該歸零哪一軸、
## 剩餘位移再補推一次（貼著牆/地板滑動，不會卡死）。動畫推進交給
## advance_visual()（見下）。
func move(delta: float, move_dir: float, jump_pressed: bool) -> void:
	var owner := owner_player
	var jump_force: float = owner.effective_jump_force() if is_instance_valid(owner) else -420.0

	if grounded and jump_pressed:
		velocity.y = jump_force
	elif not grounded:
		velocity.y += SHADOW_GRAVITY * delta
	velocity.x = move_dir * SHADOW_MOVE_SPEED

	if move_dir != 0.0:
		facing_dir = signf(move_dir)
	sprite.flip_h = facing_dir < 0.0

	var motion := velocity * delta
	var col := move_and_collide(motion)
	if col:
		var n := col.get_normal()
		var rem := col.get_remainder()
		if absf(n.y) > 0.7:
			velocity.y = 0.0
			rem.y = 0.0
		else:
			velocity.x = 0.0
			rem.x = 0.0
		if rem != Vector2.ZERO:
			move_and_collide(rem)
	# 消除碰撞求解的浮點雜訊，比照 VsPlayer._move_deterministic() 對齊
	# checksum 精度（0.01px），真正的位置分叉才會被 desync 偵測抓到。
	position = position.snapped(Vector2(0.01, 0.01))
	grounded = test_move(global_transform, Vector2(0.0, 0.1))

## 動畫推進——每個模擬幀都要跑（不管血影當下有沒有被操控：召喚後、玩家還沒
## 按下第二次技能鍵轉移操控權之前，血影已經存在但 move() 不會被呼叫，這段期間
## summon→idle 的自動切換還是要照常進行），由 vs_world._update_shadows()
## 統一呼叫，跟 _update_projectiles() 同一個呼叫層級。附身期間額外每
## GHOST_INTERVAL 秒噴一次紅色殘影，沒被操控（剛召喚、還沒轉移操控權）不噴。
func advance_visual(delta: float) -> void:
	_age += delta
	if is_instance_valid(owner_player) and owner_player.is_possessing:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			_vfx_ghost()
	if not anim_player:
		return
	anim_player.advance(delta)
	if not _idle_started and anim_player.has_animation("summon"):
		var summon_len := anim_player.get_animation("summon").length
		if _age >= summon_len and anim_player.has_animation("idle"):
			anim_player.play("idle")
			_idle_started = true

## 殘影本體——跟 VsPlayer.vfx_ghost() 同一套 CombatManager.spawn_ghost()，
## 只是顏色固定紅色、來源永遠是血影自己的 sprite，另外多帶 z_index_offset
## （疊在血影本體後面，不是蓋在上面）跟 rise_distance（淡出同時往上飄，不是
## 原地消失）——這兩個參數 CombatManager.spawn_ghost() 預設 0，既有呼叫端
## （VsDodge 衝刺殘影）完全不受影響。is_resimulating 擋掉 rollback 重模擬期間
## 的重複觸發（跟 VsPlayer._vfx_blocked() 同一個理由，血影沒有動畫 resync 的
## Call Method 軌道問題，不需要額外的 _resyncing_anim）。
func _vfx_ghost() -> void:
	if is_resimulating:
		return
	CombatManager.spawn_ghost(sprite, sprite.global_position, sprite.scale, GHOST_COLOR, GHOST_Z_INDEX_OFFSET, GHOST_RISE_DISTANCE)

func save_state() -> Dictionary:
	return {"pos": position, "vel": velocity, "grounded": grounded, "facing": facing_dir, "age": _age, "idle": _idle_started, "ghost_t": _ghost_timer}

func restore_state(d: Dictionary) -> void:
	position     = d["pos"]
	velocity     = d.get("vel", Vector2.ZERO)
	grounded     = d.get("grounded", false)
	facing_dir   = d.get("facing", 1.0)
	sprite.flip_h = facing_dir < 0.0
	_age         = d.get("age", 0.0)
	_idle_started = d.get("idle", false)
	_ghost_timer = d.get("ghost_t", 0.0)
	if not anim_player:
		return
	if _idle_started and anim_player.has_animation("idle"):
		anim_player.play("idle")   # 循環動畫，直接從頭接上即可，不用精確對齊時間點
	elif anim_player.has_animation("summon"):
		anim_player.play("summon")
		anim_player.seek(_age, true)
