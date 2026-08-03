class_name VsHazard
extends Area2D
## 場地機關：懸崖/傳送矩陣/陷阱/彈簧/補包/buff包共用同一個類別，用
## hazard_type 決定行為、各 @export_group 提供該類型專屬參數——這幾種本質上
##都是「矩形判定區 + 進入時觸發效果」，跟 VsHitbox 用一堆 @export_group
## 覆蓋不同攻擊模式的既有慣例一致，不用拆成 6 個獨立類別。
##
## 是場地場景（VsArena 底下）的固定節點，不是動態生成/銷毀的——跟
## VsPlayer.hitboxes 用 _ready() 收集所有 hitbox 子節點同一個模式，
## vs_world._spawn_arena() 掛完場地後用 find_children() 收集所有 VsHazard。
##
## ⚠ extends Area2D 純粹是為了掛一顆 CollisionShape2D 當「判定區大小」的
## 視覺/編輯器representation（Godot 的碰撞形狀可以直接在 2D 視窗拖曳調整，
## 也會出現在「顯示碰撞形狀」除錯畫面裡）——跟 VsHitbox/VsHurtbox 同一個
## 既有慣例，**不代表判定走 Area2D 訊號**（rollback 中間幀不會觸發，見
## CLAUDE.md 確定性規則），`_ready()` 把 monitoring/monitorable 都關掉，確保
## 不會意外觸發任何訊號/物理運算，純粹當形狀資料容器。真正的判定由
## vs_world._check_arena_hazards() 每幀手動讀子節點 CollisionShape2D 的
## RectangleShape2D 尺寸做幾何判定，錨點是這個節點自己的 position（vs_world
## 直屬場地子樹下的 position 才等同世界座標）。
##
## 平台（單向下拉）不算在這個類別裡——那是碰撞層級的機制，不是觸發區域，
## 靠 Godot 原生 CollisionShape2D.one_way_collision + VsPlayer 的下拉輸入
## 攔截處理，見 VsPlayer.gd/VsPlayerState.gd 的平台相關函式。

func _ready() -> void:
	monitoring   = false
	monitorable  = false

enum HazardType {
	CLIFF,          ## 懸崖：必定死亡，忽略無敵
	TELEPORT_POOL,  ## 傳送矩陣：必定扣血，傳送到指定 Marker2D
	TRAP,           ## 地圖陷阱：扣血/擊退硬直/擊飛（可複選），尊重無敵
	SPRING,         ## 彈簧：向上彈射進入跳躍狀態，尊重無敵
	HEAL_PICKUP,    ## 補包：恢復比例血量，一次性（每回合重置）
	BUFF_PICKUP,    ## buff包：隨機屬性增減，一次性（每回合重置）
}

@export var hazard_type: HazardType = HazardType.TRAP
## 判定矩形大小不是這裡的 @export 數字——直接在編輯器裡拖曳子節點
## CollisionShape2D 的形狀控制點調整，vs_world._sim_rect_hazard() 讀那顆
## 形狀的實際大小（跟 VsHitbox 用同一顆子節點決定判定框大小的慣例一致）。

@export_group("懸崖 (CLIFF)")
## 比照 VsPlayer.vfx_shake()／VsCamera.shake()：intensity 是像素級隨機偏移
## 幅度、duration 是秒數。現有最大值是 Art_Clotty_2 龍墜地的 25.0——這裡預設
## 給更大的 40.0＋更長的 0.3s，讓「掉下懸崖」明顯比任何招式都誇張。純視覺，
## 走 vs_world._trigger_hazard() → player.vfx_shake()，跟其他 vfx_* 一樣受
## _vfx_blocked()（rollback 防重複）與 Game.config_enable_screen_shake 保護。
@export var cliff_shake_intensity: float = 40.0
@export var cliff_shake_duration:  float = 0.3

@export_group("陷阱 (TRAP)")
@export var trap_damage: float = 0.0
@export var trap_knockback: Vector2 = Vector2.ZERO
@export var trap_causes_knockdown: bool = false
@export var trap_hitstun: float = 0.3

@export_group("彈簧 (SPRING)")
@export var spring_force: float = -600.0   ## VsPlayer.jump_force 預設 -420，這裡要更強才有「更高跳躍」的感覺

@export_group("傳送矩陣 (TELEPORT_POOL)")
@export var teleport_damage: float = 10.0
@export var teleport_target_path: NodePath   ## 指向同場景裡的 Marker2D（傳送目的地），關卡設計者自己放
## true＝傳送後擊飛（進 VsLaunched，弧線飛行、可被追打）；false＝傳送後直接
## 下落（一般重力墜落，不強制任何狀態，落地就正常站穩，不經過 VsHurt 硬直）。
@export var teleport_launches: bool = false
## 只在 teleport_launches=true 時使用。y 必須 < 0 才會真的觸發 VsLaunched——
## 見 VsPlayer._apply_pending_hit() 的 causes_knockdown + kb.y<0 分流條件。
@export var teleport_knockback: Vector2 = Vector2(0, -200)

@export_group("補包 (HEAL_PICKUP)")
@export var heal_percent: float = 0.1   ## 佔 max_hp 的比例

var consumed: bool = false           ## 補包/buff包一次性用，其他類型不管這個欄位（外部 vs_world 直接讀寫，不加底線）
var _p1_overlapping: bool = false    ## 陷阱/彈簧/懸崖/傳送矩陣的邊緣觸發：1v1 只有兩個玩家，各自一個 bool 就夠——只透過下面 get/set_overlapping() 存取，外部不直接碰
var _p2_overlapping: bool = false
## 血影（Asatsubaki 專屬）的懸崖邊緣觸發——跟玩家本體的重疊旗標是分開的
## 獨立追蹤欄位，不能共用 _p1_overlapping/_p2_overlapping（同一個 hazard 底下
## 玩家本體跟自己的血影可能同時分別重疊/不重疊，混用同一個欄位會互相蓋掉）。
var _p1_shadow_overlapping: bool = false
var _p2_shadow_overlapping: bool = false

## 讀/寫某一位玩家的重疊旗標——vs_world._check_arena_hazards() 用 player_id
## 決定要動哪一個，兩個玩家各自獨立觸發，不會互相影響
func get_overlapping(player_id: int) -> bool:
	return _p1_overlapping if player_id == 1 else _p2_overlapping

func set_overlapping(player_id: int, value: bool) -> void:
	if player_id == 1: _p1_overlapping = value
	else:               _p2_overlapping = value

## 血影版本——player_id 是血影 owner_player 的 player_id，不是血影自己的 id
## （血影沒有 player_id 概念）。
func get_shadow_overlapping(player_id: int) -> bool:
	return _p1_shadow_overlapping if player_id == 1 else _p2_shadow_overlapping

func set_shadow_overlapping(player_id: int, value: bool) -> void:
	if player_id == 1: _p1_shadow_overlapping = value
	else:               _p2_shadow_overlapping = value

func save_state() -> Dictionary:
	return {
		"consumed": consumed,
		"p1_ov": _p1_overlapping, "p2_ov": _p2_overlapping,
		"p1_sov": _p1_shadow_overlapping, "p2_sov": _p2_shadow_overlapping,
	}

func restore_state(d: Dictionary) -> void:
	consumed         = d["consumed"]
	_p1_overlapping  = d["p1_ov"]
	_p2_overlapping  = d["p2_ov"]
	_p1_shadow_overlapping = d.get("p1_sov", false)
	_p2_shadow_overlapping = d.get("p2_sov", false)

## VsRoundManager 每回合重置時呼叫（透過 vs_world._on_round_started()，見該處
## 說明）——補包/buff包每回合重新可用，不是永久消耗也不是整場累積。
func reset_for_round() -> void:
	consumed = false
