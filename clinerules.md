# 核心開發與 AI 互動準則

## 0. AI 互動與效能守則 (Agent Behavior)
- **直接執行，禁止寒暄**：收到指令後請直接分析並給出解答或修改程式碼，不需要回覆「好的」、「我看見了」等無意義的問候。
- **精準讀取**：除非使用者明確要求，否則**絕對禁止**主動掃描全域目錄，或讀取 `.tscn`、`.import`、`.godot/` 等非程式碼檔案。請專注於當前開啟或使用者指定的 `.gd` 腳本。
- **語言偏好**：回覆與註解請統一使用**繁體中文**。

## 1. 物理與位移機制 (Physics & Movement)
- **禁用原生函數**：嚴禁在任何腳本直接呼叫原生的 `move_and_slide()`。
- **統一介面**：所有涉及物理移動的代碼，絕對、必須、只能使用 `player.custom_move_and_slide()`，以確保時停與緩速系統正常運作。
- **執行時機**：`custom_move_and_slide()` 必須寫在各個狀態腳本（如 VsPlayerState.gd 或惡魔城狀態腳本）的 `process_physics` 中（通常在重力與速度計算完畢後，落地判定之前）。

## 2. 狀態機與面向控制 (State Machine & Facing)
- **霸體與鎖死面向**：對於「不可打斷且不可中途轉向」的突進技，進入狀態時必須將面向存入 `locked_facing_dir`，並在 `process_physics` 中強制覆寫，同時拔除 `check_interrupts()`。

## 3. 戰鬥、傷害與計時 (Combat & Timing)
- **傷害判定**：禁止直接操作血量（如 `victim.current_hp -= damage`），必須統一使用 `victim.take_damage(damage_per_hit)`。
- **戰鬥計時器**：遊戲內招式、霸體、冷卻、延遲判定等「跟關卡同步」的計時，一律透過 `CombatManager.get_skill_timer(duration)`（回傳 SceneTreeTimer）。
- **禁止使用**：嚴禁改用 `get_tree().create_timer(...)`、`Timer` 節點或自行 new 計時器，以免和暫停或魔女時間（`Engine.time_scale`）產生衝突。（例外：選單 UI 或純現實時間倒數方可使用，但需寫明註解）。

## 4. 動畫與安全防護 (Animation & Safety)
- **防止崩潰**：播放動畫時，統一使用 `player.play_safe_anim("動畫名")`，利用撐大網格的方式防止 Godot 底層的越界報錯崩潰。

## 5. 專案邊界與修改習慣 (Project Scope)
- **專案焦點**：目前專注於「惡魔城」模式開發，除非明確要求，否則**絕對不要**改動 `VsMods/` 資料夾下的格鬥模組。
- **修改原則**：改動盡量小範圍，嚴格對齊既有命名、註解風格與狀態機/信號用法。與場景綁定的邏輯優先改對應的 `.gd` 檔，避免憑空假設未存在的節點路徑。