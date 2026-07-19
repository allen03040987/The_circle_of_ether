extends Node
## 跨場景快取：角色選擇、武藝裝備
## 登錄為 autoload（project.godot）

const ART_DISPLAY: Dictionary = {
	"Art_Clotty_1": "武藝一",
	"Art_Clotty_2": "武藝二",
	"Art_Clotty_3": "武藝三",
	"Art_Clotty_4": "武藝四",
	"Art_Clotty_5": "武藝五",
	"Art_Clotty_6": "武藝六",
	"": "（空）",
}

## 每個空槽位給予的能量回復加成（/s）
const EMPTY_SLOT_REGEN_BONUS := 5.0

# ── 選擇快取 ──────────────────────────────────────────────────────────────────
var p1_arts: Array = ["", "", ""]   # 3 槽位，空字串 = 未裝
var p2_arts: Array = ["", "", ""]
var p1_character: String = VsCharacterRegistry.DEFAULT_CHARACTER
var p2_character: String = VsCharacterRegistry.DEFAULT_CHARACTER
var selection_confirmed: bool = false

## 回合間重選武藝的「確認」鍵一次性旗標——ArtsReselectOverlay 的確認按鈕點擊時
## 設 true，InputState.from_input() 下一次讀取時消費掉（清回 false），見該處
## 註解。命名對應 InputState.from_input(1)/(2) 的 player_id 參數，不是網路
## P1/P2 身分——線上模式本機輸入一律走 from_input(1) 那個 slot（不管本機實際
## 網路身分是 P1 還是 P2），只有離線模式才會兩個都用到（兩個本機玩家）。
var pending_confirm_1: bool = false
var pending_confirm_2: bool = false

func get_display_name(art_id: String) -> String:
	return ART_DISPLAY.get(art_id, art_id)

func empty_slots(arts: Array) -> int:
	return arts.count("")
