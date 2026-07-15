extends Node
## 跨場景快取：角色選擇、武藝裝備
## 登錄為 autoload（project.godot）

# ── Clotty 武藝池 ────────────────────────────────────────────────────────────
const CLOTTY_ARTS: Array = [
	"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
	"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
]

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
var selection_confirmed: bool = false

func get_display_name(art_id: String) -> String:
	return ART_DISPLAY.get(art_id, art_id)

func empty_slots(arts: Array) -> int:
	return arts.count("")
