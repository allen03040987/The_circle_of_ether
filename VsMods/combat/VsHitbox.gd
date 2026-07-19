class_name VsHitbox
extends Area2D
## VS 模式攻擊判定框（格鬥遊戲用）

enum BreakLevel {
	NONE,              # 無破甲
	ARMOR_BREAK,       # 破霸：可對霸體造成擊退/硬直
	STRONG_ARMOR_BREAK # 強破霸：可對強霸體造成擊退/硬直，並無視 50% 減傷
}

@export var damage: float = 100.0
@export var hitstun_time: float = 0.4       # 受擊硬直時長（秒）
@export var knockback: Vector2 = Vector2(200.0, -80.0)
@export var causes_knockdown: bool = false  # true = 觸發倒地狀態
@export var break_level: BreakLevel = BreakLevel.NONE
@export var guard_damage: float = 0.0      # 留用欄位（目前由體質效果系統統一計算）

@export_group("連擊")
@export var combo_hits: int = 1         ## 這顆判定框最多可以命中幾次（預設 1 = 一般單發，維持舊行為）
@export var combo_interval: float = 0.0 ## 每次命中之間的最短間隔秒數（第一下不受此限制，一碰到就算）
## 比照主遊戲 Hitbox.sticky_multi_hit：true = 第一下命中後鎖定該目標，後續
## 連擊不再檢查幾何是否還重疊，冷卻時間一到就自動觸發傷害，直到連擊數用完。
## 這是取代先前 `detached` 設計的做法——原本 `detached` 只處理「狀態結束後
## 判定框是否還存活」，但沒解決真正的問題：像升龍這類攻擊者自己會被彈飛的
## 連段，中間幾下攻擊者早就跟目標分開了，若還要求幾何重疊，後續傷害幾乎打
## 不到。`sticky` 直接讓已鎖定的連擊不再依賴幾何重疊，天然也就不受施放狀態
## 存活時間限制（見下面 close_on_state_exit()），不需要另一個獨立開關。
@export var sticky: bool = false

@export_group("打擊回饋")
## 命中音效 key，查主遊戲 AudioManager.hit_sfx_bank（"hit"/"hit_2".."hit_7"）。
## 空字串 = 不播放。比照主遊戲 classes/Hitbox.gd 的 hit_sfx_type 欄位同款用法。
@export var hit_sfx_type: String = ""
@export var shake_intensity: float = 0.0   # 0 = 不震動（沒有角色預設層，跟主遊戲一樣每招自己填）

@export_subgroup("火花")
## true（預設）＝完全套用角色的預設火花（VsPlayer.default_spark_*，比照主遊戲
## Weapon.get_weapon_default_spark()），下面這顆 hitbox 自己的欄位全部忽略——
## 大多數招式不用管火花，維持 true 即可。想讓「這一招」火花長得不一樣，關掉這個
## 開關、把下面欄位填成這招要的樣子。VsMods 是節點驅動（不是主遊戲那種資料表），
## 所以簡化成「整組套用角色預設」或「整組用這招自己的」二選一，不像主遊戲能單一
## 欄位分開 fallback（例如只覆蓋顏色、其他繼續繼承）——多數情況這樣已經夠用。
@export var use_character_default_spark: bool = true
@export var spark_type: Hitbox.SparkType = Hitbox.SparkType.SLASH
@export var spark_scale: float = 0.3
@export var spark_color: Color = Color.WHITE
@export var aura_color: Color = Color(1.0, 1.0, 1.0, 0.5)
@export var spark_raw_intensity: float = 1.0
@export var spark_random_angle: float = 20.0
@export var spark_base_offset: Vector2 = Vector2.ZERO
@export var spark_random_offset: Vector2 = Vector2.ZERO
@export var attach_spark_to_victim: bool = true
@export var custom_spark_scene: PackedScene

## 保留欄位：1v1 只有一顆對手 hurtbox，連擊判定不靠它當門檻（見 hits_dealt），
## 目前只作為除錯/未來多目標情境的紀錄用途。
var hit_targets: Dictionary = {}
## rollback 安全旗標：= hits_dealt >= combo_hits（連擊全部用完），由
## register_hit() 統一維護，不要在別處直接寫入（會跟 hits_dealt 對不上）
var has_hit: bool = false
## 目前已命中次數（連擊用；一般單發攻擊 combo_hits=1，命中一次就等於 has_hit）
var hits_dealt: int = 0
## 連擊間隔倒數：>0 時無法再次命中，由 tick_cooldown() 每幀遞減
var hit_cooldown_left: float = 0.0
## sticky 專用：是否已經鎖定目標（1v1 只有一個對手，不用存目標引用本身——
## 「鎖定」等於「只認那唯一的對手」，鎖定後 vs_world._manual_check() 就跳過
## 幾何重疊檢查）
var is_locked: bool = false
## 擁有此 hitbox 的玩家（由 VsPlayer._ready 設定）。
## 受擊方向一律從它的 position（模擬資料）計算——Node.owner 對程式碼建立的
## 節點是 null，而 global_position 在 rollback 重模擬中可能過期。
var owner_player: Node2D = null

## 0 = 未覆寫，受擊方向沿用 owner_player.facing_dir（近戰判定框的預設行為）；
## 非 0（-1/1）= 直接用這個方向，不管 owner_player 現在面向哪。
##
## 兩種用途：
## 1. VsProjectile 專用：彈道命中時，owner_player（施放者）早就可能轉身/
##    移動到完全不同的方向了（彈道飛行期間施放者的攻擊動作早已結束、能自由
##    行動），若還是讀 owner_player.facing_dir 會導致擊退方向跟著施放者事後
##    的移動亂變。彈道生成時把這個欄位設成彈道自己的飛行方向即可一勞永逸
##    鎖定，不受施放者後續行為影響。
## 2. 多段連擊（combo_hits>1，尤其是 sticky）專用：第一下命中時鎖定方向，
##    後續每一下都沿用同一個值，不再重新讀 owner_player 的當下面向——見
##    VsPlayer._on_hurtbox_hurt() 裡「多段連擊方向鎖定」那段的完整說明，這是
##    2026-07-19 實測抓到「擊退方向跟著攻擊者移動亂變」bug 的真正根因與修法
##    （sticky 連擊時間跨度長，攻擊者早就可能已經打完招式、回到自由操作，
##    後續每一下若還即時讀當下面向就會整個亂跳）。
var direction_override: int = 0

## 打擊偵測統一由 vs_world._simulate_frame() 內的幾何計算驅動，
## 不使用 Area2D 信號（信號有一幀延遲，導致兩端命中時機不同 → HP desync）

## 換招時呼叫，清除已命中記錄以允許再次判定。也清 direction_override（多段
## 連擊用途那份鎖定值只在「這一次施放」有效，下一次重新施放要重新鎖，不能
## 沿用上一次的方向——見該欄位註解）；VsProjectile 每次施放都是全新節點，
## 不會呼叫到這裡，不受影響。
func reset_hits() -> void:
	hit_targets.clear()
	hits_dealt = 0
	hit_cooldown_left = 0.0
	has_hit = false
	is_locked = false
	direction_override = 0

## 每幀遞減連擊間隔倒數，由 vs_world._check_manual_hits(delta) 統一驅動
## （⚠ 必須吃模擬 delta，不能用真實時間——確定性規則）
func tick_cooldown(delta: float) -> void:
	if hit_cooldown_left > 0.0:
		hit_cooldown_left = maxf(hit_cooldown_left - delta, 0.0)

## 命中一次的記帳：遞增次數、套用下次間隔冷卻、sticky 的話鎖定目標、
## 次數用完就標記 has_hit
func register_hit() -> void:
	hits_dealt += 1
	hit_cooldown_left = combo_interval
	if sticky:
		is_locked = true
	if hits_dealt >= combo_hits:
		has_hit = true

## 供狀態 exit() 或狀態內部換階段（如 Art_Clotty_2 降龍的 LOOP→LAND）收尾
## 呼叫，取代直接寫 monitoring=false/reset_hits()：sticky 且「已經鎖定目標、
## 連擊還沒打完」→ 不動它，讓它照原節奏繼續判定到連擊數用完自然關閉——不管
## 呼叫端是同一招內部換階段、還是真正離開整個狀態都一樣放行，讓玩家發起的
## 一次多段連擊（sticky）能完整跑完，即使角色本身早已恢復自由操作也一樣。
## 其餘情況（沒開 sticky、已經打完、或 sticky 但根本沒鎖到任何目標）→
## 強制關閉＋重置。
## ⚠ `is_locked` 檢查是必要的，不能只看 has_hit：sticky 連擊如果完全沒打中
## 任何目標（is_locked 從沒變 true），has_hit 自然也永遠是 false，若只判斷
## `sticky and not has_hit` 會誤判成「還在合理進行中」而永遠不關閉。
##
## ⚠ 2026-07-19 踩過的坑，別重蹈覆轍：這裡曾經一度改成「exit() 一律硬關閉，
## 只有內部換階段才放行」，理由是診斷抓到 HitboxArt2Air（降龍）落地後角色
## 早就恢復自由操作、owner.facing 隨玩家之後移動的方向亂變，導致殘留連擊的
## 擊退方向跟著亂跳。但這個修法讓連擊變成「一旦離開招式就砍斷」，使用者立刻
## 抓到回歸——這正是本來就該修好的原始 bug（sticky 連擊被提前砍斷）。
## **真正的根因不是「連擊活太久」，而是每一下命中都重新讀 owner_player 當下
## 面向**——正確修法是鎖定方向而非砍短連擊時間，見 VsPlayer._on_hurtbox_hurt()
## 「多段連擊方向鎖定」那段：第一下命中時把方向存進 direction_override，
## 後續每一下都直接沿用，不再重新讀當下面向。方向鎖定後，連擊活多久、
## 攻擊者離開招式後做什麼都不影響擊退方向的正確性，這個函式可以放心讓
## sticky 連擊完整跑完，不用再靠「提前關閉」防止方向跑掉。
func close_on_state_exit() -> void:
	if sticky and is_locked and not has_hit:
		return
	monitoring = false
	reset_hits()
