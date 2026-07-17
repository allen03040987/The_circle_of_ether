class_name VsMartialArt
extends VsPlayerState
## 武藝基底契約（比照主遊戲 MartialArt.gd 的設計精神，整合進 VsStateMachine
## 的 VsState 生命週期）。每個武藝就是一個動態掛載的 VsState，跟 VsAttack/
## VsIdle 等地位相同（`enter`/`physics_update`/`exit`/`save_state`/
## `restore_state`/`sync_anim`），只是掛載時機在 `art_slots` 決定之後
## （`VsPlayer._load_arts()`，由 vs_world 在注入 art_slots 後呼叫），不是
## 場景固定的靜態子節點——這點跟 VsAttack/VsAirAttack/VsSkill 不同。
##
## 規則落地方式：
## - 「消耗若干能量施放」：`energy_cost` 由 `VsPlayerState._check_art_cast()`
##   （共用施放檢查，見 VsPlayerState.gd）統一扣款，個別武藝不用自己扣。
## - 「全程具有霸體或以上等級狀態」：`VsPlayer.get_armor_tier()` 只要偵測到
##   `state_machine.current_state is VsMartialArt` 就至少給 HYPER，這裡不用
##   個別武藝自己管理無敵/霸體旗標；想要更高一階（強霸體）就把
##   `armor_tier_override_strong` 設 true。
## - 「每招的功能不一」：具體招式繼承這個類別、覆寫 `enter`/`physics_update`
##   等生命週期方法自訂效果，比照主遊戲 Art_Katana_N 的做法。
## - 「可打斷普攻來施放」：`_check_art_cast()` 已經接在 VsAttack/VsAirAttack
##   的打斷優先權第 3 順位（衝刺/防禦之後、連段派生之前）。

@export var art_id:         String = ""     # 對應 VsGameManager 武藝池的字串名稱
@export var art_name:       String = "未命名武藝"
@export var energy_cost:    float  = 10.0
@export var can_use_in_air: bool   = false
## 大多數武藝維持 false（霸體，免疫非破霸攻擊）就符合規則下限；
## 想要強霸體（免疫非強破霸攻擊 + 50% 減傷）才設 true。
@export var armor_tier_override_strong: bool = false

var elapsed: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed += delta
	return &""

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed = d.get("elapsed", 0.0)
