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
## - 「從普攻連段窗口取消進武藝」（2026-07-20 定案，全角色通用）：`VsAttack`/
##   `VsAirAttack` 的 `_check_art_cast()` 呼叫現在包在 `if vs.can_combo:` 裡面，
##   只有動畫軌道開啟連段窗口的那一刻才能取消進武藝，跟接續下一段普攻同待遇
##   ——**不是**舊規則講的「武藝可以在普攻的任何時點打斷」（已經拿掉，那個
##   規則會讓玩家在普攻的前搖/攻擊判定幀甚至後搖任何一刻都能取消，是先前
##   一直用空中普攻無限連對手的根因之一）。VsIdle/VsRun/VsJump/VsFall/VsSkill
##   不受影響，這幾個不是「普攻」，武藝施放權限維持原樣（隨時可放）。
##
## ⚠ 每支具體武藝的 `physics_update()` 都是**完全覆寫**（不呼叫 `super`），
## 所以下面這條全域規則沒辦法放在這個基底類別統一處理，每支新武藝都要自己
## 在 `physics_update()` 最前面手動補上，忘記加就是「這招放出來按衝刺完全
## 沒反應」的 bug（Art_Clotty_1~6 全部都曾經漏掉，一支一支修過一輪）：
## ```
## if input.dodge and (player as VsPlayer).use_dash_energy(30.0):
##     return &"vsdodge"
## ```

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
