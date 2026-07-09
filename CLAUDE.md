# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"以太之圓" (The Circle of Ether) — a Godot 4.2 (GL Compatibility renderer) 2D game written in GDScript. The project bundles **two largely independent gameplay systems** in one repo:

- **Main game** — a single-player action game (top-down movement, jump, weapon combat, interact, save stones, bosses).
- **VsMods** — a separate 1v1 versus fighting-game mode (P1/P2 controls, character select, ultimates/skills, stocks/cooldowns).

These two systems do not share a state machine or combat framework — see Architecture below.

## Development

There is no build step, package manager, linter, or test suite in this repo — it's a Godot project edited and run through the Godot 4.2 editor (or `godot` executable/CLI for headless runs). Scenes (`.tscn`) and scripts (`.gd`) are edited together; most gameplay logic lives in `.gd` scripts attached to nodes, so understanding a feature usually requires opening the paired `.tscn` in the editor to see the node tree, not just reading the script.

`project.godot` defines the autoloads, input map, and physics layers — check it when a script references a global (`Game.`, `CombatManager.`, `AudioManager.`, `VsGameManager.`) or an input action (`p1_attack`, `art_1`, `martial_modifier`, etc.) that isn't obviously defined nearby.

## Architecture

### Main game state machine (`classes/`, `player/state/`)

`classes/State.gd` is a minimal contract (`enter()`, `exit()`, `update(delta)`, `physics_update(delta)`, all no-ops by default). `classes/StateMachine.gd` auto-discovers its child `State` nodes into a dict keyed by lowercase node name, injects `player`/`state_machine` back-references, and drives the current state's `update`/`physics_update` each frame. `transition_to(name)` guards against re-entrant transitions. States are wired as child nodes in the Player scene (`player/state/Idle.gd`, `Run.gd`, `Jump.gd`, `Fall.gd`, `Hurt.gd`, `Dying.gd`, `SwapWeapon.gd`, ...).

### Weapon system (`player/`)

`player/Weapon.gd` is the base contract for equippable weapons (`start_light_attack`, `start_heavy_attack`, `get_current_velocity`, `is_attack_finished`, `cancel_attack`, `requires_sheath`, plus a 3-slot "武藝卡帶" special-move system via `martial_slots` / `execute_martial_art(slot)`). Concrete weapons (`Katana.gd`, `Spear.gd`, `Sickle.gd`, `Talisman.gd`) extend `Weapon`.

Combos are **data-table driven, not one-State-per-move**: each weapon defines dictionaries (e.g. `DICT_LIGHT_GROUND`, `DICT_LIGHT_AIR`, `DICT_HEAVY_ULT`) mapping numeric combo-step codes to animation name, hitbox name, damage, knockback, sfx, and action type; an integer `combo_step` drives branching logic in the weapon script itself. Individual `State` subclasses only exist for the broad player states (Idle/Run/Jump/SwapWeapon/...), not for each attack — don't look for a `KatanaAttack1.gd` file, look inside `Katana.gd`'s combo dictionaries.

`MartialArt.gd` is a separate, smaller contract for the special "art" moves (`Art_Katana_1.gd`, etc.) — its own setup/enter/cancel lifecycle, unrelated to `classes/StateMachine.gd`. `ScabbardContainer.gd` handles cosmetic sheath/ghost-trail VFX on weapon swap.

### VsMods (`VsMods/`)

A fully parallel framework, isolated from `classes/` — do not mix the two. `VsMods/StateMachine/VsStateMachine.gd` extends `Node2D` directly (not `classes/StateMachine.gd`) and holds an explicit `@export` slot per state type rather than auto-discovering children; `VsState`/`VsPlayerState` objects return the *next state* from their process/input/physics methods, which is a different transition pattern than the main game's `transition_to(name)` calls.

`VsMods/VsPlayer.gd` (`CharacterBody2D`) implements dual P1/P2 control, HP/stamina/MP, and a stock-based cooldown system (`skill_cooldowns` dict with `charges`/`max_charges`). Characters are one folder each under `VsMods/` (`Clotty/`, `Mechl/`) extending `VsPlayer`, with individual skill scripts as `VsPlayerState` subclasses (`ClottySkill_K1.gd`, `ClottySkill_U2.gd`, ...) — this is the pattern to follow when adding a new character or skill.

### Combat/hit detection — two separate implementations

Main game: `classes/Hurtbox.gd` (Area2D) just emits a `hurt(hitbox)` signal; `classes/Hitbox.gd` (Area2D) owns damage/knockback/poise, multi-hit tracking (`hit_targets`), and dispatches spark/shake/audio via the `CombatManager`/`AudioManager` autoloads before calling into the hurtbox. `classes/Damage.gd` is the payload (type LIGHT/HEAVY/THROW/NO_STUN; source_type MELEE/PROJECTILE/ASSIST).

VsMods: `VsMods/state/VsHitbox.gd` is a completely separate Area2D class with fighting-game-specific fields (hitstun_time, guard_break, armor_break, ground/air knockback, causes_down, OTG, bleed DOT, refresh_cd_slot). Character-specific hitboxes (e.g. `VsMods/Clotty/Hitbox_BD.gd`) wrap this as a `VsPlayerState`. No code is shared between the main-game and VsMods hit systems — know which mode you're editing before touching either.

### Global autoloads (declared in `project.godot`)

| Autoload | Script | Responsibility |
|---|---|---|
| `Game` | `globals/game.gd` (`GameManager`) | Settings persistence (ConfigFile), fullscreen, custom keybindings, cross-scene world/player stats |
| `CombatManager` | `Explod/CombatManager.gd` | `Engine.time_scale` arbitration (domain slowdown/time-stop vs. UI pause — no hitstop, the game deliberately doesn't use it), camera shake, hit-spark VFX spawning |
| `AudioManager` | `sound/AudioManager.gd` | SFX/hit-SFX playback (`play_sfx`, `play_hit_sfx`) |
| `VsGameManager` | `VsMods/ui/VsGameManager.gd` | Cross-scene P1/P2 character & custom-skill selection cache for VsMods |
| `Vignette`, `PauseMenu` | scene autoloads | Screen vignette effect; pause UI |

Hitbox/Weapon code guards autoload calls with `has_method()` checks — treat this as the existing convention when adding new cross-autoload calls, not as something to "clean up".

## Conventions to know before editing

- Comments are bilingual (Traditional Chinese + English) with emoji section banners (`# ==...==`) — match this style in files that already use it.
- Player/weapon code frequently uses duck-typed `.get("property_name")` lookups instead of typed references — this is intentional loose coupling, not an oversight to "fix" with static typing.
- `PixelBaker/PixelBaker.gd.gd` has a doubled extension — this is the actual filename on disk, not a typo to silently rename.
