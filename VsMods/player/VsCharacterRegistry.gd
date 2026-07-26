class_name VsCharacterRegistry
## 角色 id → 場景路徑/武藝池的對照表。跟 VsArtRegistry 同一套 pattern
## （純靜態 Dictionary + lookup function，不掛 autoload）。
##
## 目前只有 "Clotty" 一個角色，scene_path 指向既有的 VsPlayer.tscn——
## 之後 Part B（Inherited Scene 拆分）完成、驗證過 VsPlayerClotty.tscn 沒問題後，
## 只需要改這裡的 scene_path 一行，不影響其他程式碼。
const CHARACTERS: Dictionary = {
	"Clotty": {
		"display_name": "Clotty",
		"scene_path": "res://VsMods/player/VsPlayerClotty.tscn",
		"arts": [
			"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
			"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
		],
	},
	"Naihe": {
		# 佔位測試角色——場景是 VsPlayerClotty.tscn 的原樣複製（VsPlayerNaihe.tscn，
		# 只換了 uid），純粹為了驗證選角畫面能不能正確處理「兩個角色」，還不是
		# 真正的第二角色。武藝也直接沿用 Clotty 的六招（duplicate 出來的場景節點
		# 結構跟動畫庫完全相同，Art_Clotty_* 腳本能原樣運作）。使用者之後會把
		# 主遊戲 Boss 奈何橋的素材移植進來取代這裡的內容（無法直接搬，細節待定），
		# 屆時只需要換這裡的 scene_path/arts/display_name，不用改選角邏輯本身。
		"display_name": "奈何",
		"scene_path": "res://VsMods/player/VsPlayerNaihe.tscn",
		"arts": [
			"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
			"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
		],
	},
}

const DEFAULT_CHARACTER := "Clotty"

static func get_scene(character_id: String) -> PackedScene:
	var path: String = CHARACTERS.get(character_id, {}).get("scene_path", "")
	return load(path) if path != "" else null

static func get_arts(character_id: String) -> Array:
	return CHARACTERS.get(character_id, {}).get("arts", [])

static func get_display_name(character_id: String) -> String:
	return CHARACTERS.get(character_id, {}).get("display_name", character_id)

static func all_ids() -> Array:
	return CHARACTERS.keys()
