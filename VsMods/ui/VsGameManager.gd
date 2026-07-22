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

## 每個空槽位給予的屬性加成比例——套用在最大生命/衝刺能量回復速率/移速，
## 三項都用同一個比例對各自的角色基準值算百分比（見 VsPlayer.apply_arts_bonus()）
const EMPTY_SLOT_STAT_BONUS_PCT := 0.08

## 武藝正式招式名稱——VsArtInfoPopup 彈窗標題用（跟 ART_DISPLAY 的「武藝N」
## 編號並列顯示，武藝格本身/裝備槽維持顯示「武藝N」不變，只有詳情彈窗會秀
## 這裡的正式招式名）。
const ART_NAMES: Dictionary = {
	"Art_Clotty_1": "逆鱗返",
	"Art_Clotty_2": "升龍",
	"Art_Clotty_3": "寸位斷",
	"Art_Clotty_4": "無影刺",
	"Art_Clotty_5": "零式突氣",
	"Art_Clotty_6": "流星連斬",
}

## 武藝能量顯示縮放：玩家看到的所有武藝能量相關數字（BattleHud 的能量條/
## 徽章耗能數字、這裡的彈窗說明文字）統一乘這個比例——實際數值
## （VsPlayer.arts_energy / VsMartialArt.energy_cost）完全不變，只是顯示縮小
## 一位，全部顯示端共用同一個常數，不要各自維護一份數字（之前 BattleHud 自己
## 放過一份，容易改一邊漏改另一邊，統一搬到這裡）。
const ARTS_ENERGY_DISPLAY_SCALE := 0.1

## 武藝詳情文本——選角/回合間重選畫面的「!」按鈕彈窗用（VsArtInfoPopup）。
## 純玩家視角描述效果，不寫實作細節（連段窗口/摩擦力係數這類）。
const ART_DESCRIPTIONS: Dictionary = {
	"Art_Clotty_1": "原地格擋 2 秒，格下非強破霸攻擊即完全免傷並射出劍氣反擊，隨後獲得 1 秒無敵。無法格擋強破霸攻擊。",
	"Art_Clotty_2": "地面施放：向前上方彈射突進，可接續擊飛連段。空中施放則變成「降龍」：向下俯衝並多次打擊，是完全不同的招式。",
	"Art_Clotty_3": "向前突刺攻擊，可在空中施放。",
	"Art_Clotty_4": "連續斬擊 8 下，可在空中施放；施放期間不受重力影響，原地懸空。",
	"Art_Clotty_5": "發射一發劍氣彈道攻擊，可在空中施放。",
	"Art_Clotty_6": "連續斬擊 3 下，出招時會向前拖出一段滑行距離。",
}

## 武藝徽章——沒有畫圖標的簡化替代方案（使用者要求「簡約美又有效」，美術
## 成本考量後決定不畫圖標）：局內/彈窗顯示用「單字（ART_NAMES 的第一個字）
## 黑底白框」當視覺辨識，不用另外準備任何圖片資源。（曾經試過六招各給一個
## 顏色，使用者後來要求統一黑白，改成純粹靠文字辨識、不靠顏色。）

## 徽章上顯示的單字——直接取正式招式名稱的第一個字，不用另外維護一份資料。
func get_art_badge_char(art_id: String) -> String:
	var art_name := get_art_name(art_id)
	return art_name.substr(0, 1) if art_name != "" else ""

# ── 選擇快取 ──────────────────────────────────────────────────────────────────
var p1_arts: Array = ["", "", ""]   # 3 槽位，空字串 = 未裝
var p2_arts: Array = ["", "", ""]
var p1_character: String = VsCharacterRegistry.DEFAULT_CHARACTER
var p2_character: String = VsCharacterRegistry.DEFAULT_CHARACTER
var selection_confirmed: bool = false

## 雙方在 MapSelectScreen 都確認同一張地圖後寫入，vs_world.gd 的
## _spawn_arena() 依此查 VsArenaRegistry.get_scene()。預設值＝目前唯一的場地，
## 所以直接 F5 跑 vs_world.tscn（略過選場地畫面）也能正常運作。
var selected_arena_id: String = VsArenaRegistry.DEFAULT_ARENA

## 回合間重選武藝的「確認」鍵一次性旗標——ArtsReselectOverlay 的確認按鈕點擊時
## 設 true，InputState.from_input() 下一次讀取時消費掉（清回 false），見該處
## 註解。命名對應 InputState.from_input(1)/(2) 的 player_id 參數，不是網路
## P1/P2 身分——線上模式本機輸入一律走 from_input(1) 那個 slot（不管本機實際
## 網路身分是 P1 還是 P2），只有離線模式才會兩個都用到（兩個本機玩家）。
var pending_confirm_1: bool = false
var pending_confirm_2: bool = false

func get_display_name(art_id: String) -> String:
	return ART_DISPLAY.get(art_id, art_id)

func get_art_name(art_id: String) -> String:
	return ART_NAMES.get(art_id, "")

func empty_slots(arts: Array) -> int:
	return arts.count("")
