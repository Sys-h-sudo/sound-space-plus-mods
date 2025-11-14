# AGENTS.md — Custom Note Color Presets for Sound Space Plus Mods

## 0. Purpose of this document

This file is a **system-level guide for AI coding agents (e.g. OpenAI Codex)** working on  
<https://github.com/Sys-h-sudo/sound-space-plus-mods>.

Goal:  
Add a **fully user-configurable “Note Color Presets” system** so players can:

- Define multiple named note color presets.
- Edit those presets via an in-game UI (color pickers).
- Save/load presets from the user folder (per-user).
- Select which preset is active at runtime, without breaking existing behavior.

The repo is a **Godot-based** fork of `David20122/sound-space-plus`, focused on customization-oriented mods.  
All changes must respect this:

- **Do not break vanilla behavior** when presets are not used.
- **Do not break existing mods** (as far as reasonably possible).
- Follow the repo’s existing structure, naming, and style.

---

## 1. Repository & tech context (for orientation)

- Engine: Godot (see `project.godot` at repo root).
- Main directories:
  - `scenes/` — Godot scenes for menus, gameplay, etc.
  - `scripts/` — GDScript logic.
  - `assets/` — art, textures, shaders, etc.
  - `localization/` — strings/translations.
  - Root files like `uitheme.tres`, `default_env.tres` and others define global look & feel.
- The upstream project (`sound-space-plus`) is a **rhythm-based aim game** where **“notes” / “blocks”** fall / appear and are hit by cursor movement.

You (the agent) should **first scan the codebase** to understand:

1. Where notes are instantiated and rendered.
2. Where note colors are defined (constants, theme data, shaders, etc.).
3. How user settings and mods are loaded/saved (likely via some settings script & user folder paths).

---

## 2. High-level feature requirements

### 2.1 Functional requirements

1. **Multiple named presets**
   - Users can have multiple presets (e.g. “Default”, “Pastel”, “High Contrast”, “Monochrome”).
   - Each preset defines the colors for **all note types/lanes that are currently colorized** in the game.
     - Whatever the game currently uses (e.g. per-direction, per-lane, per-note-type), mirror that structure in the preset.

2. **Editable in UI**
   - Add a menu in the **Settings / Mod / Appearance** area (where it fits best with existing UX) that allows:
     - Choosing the **active preset** from a list.
     - Creating a **new preset** (copying from an existing one or from defaults).
     - Renaming a preset.
     - Deleting a preset (except the built-in default).
     - Editing colors in a preset via color pickers.

3. **Persistent storage**
   - Presets must be stored in the **user folder** (not within the game’s installation directory).
   - Use `user://` paths (e.g. `user://mods/note_color_presets.json`) or follow the existing settings pattern.
   - On startup:
     - Load the presets file if it exists.
     - If missing/corrupted, recreate with **fallback default preset** that reproduces current vanilla colors.

4. **Runtime behavior**
   - The **active preset** is applied to any newly spawned notes.
   - Changing presets in the menu should **immediately apply to subsequent notes**, without requiring a full game restart.
   - Existing notes already on screen may remain in their previous colors (simpler, acceptable). If it’s easy & safe, you may optionally update them.

5. **Backwards compatibility**
   - If the user **never touches the presets system**, the game must look **identical** to current behavior.
   - If the presets file is missing, invalid or partially invalid, revert to **vanilla colors** for any problematic values.

---

## 3. Non-goals / constraints

- Do **not** rework core gameplay mechanics (hit detection, scoring, timing).
- Do **not** change map formats.
- Do **not** introduce a complex theme engine beyond what’s needed for configurable note colors.
- Keep external dependencies unchanged (no new third-party libs).

---

## 4. Data model for presets

### 4.1 General design

You will need a **data structure** representing a note color preset. The exact fields depend on how the game currently assigns colors to notes.


Your job as agent is to:

Scan the code for note color usage (e.g. Color(...), set_modulate, modulate, or material.set_shader_param("color", ...)).

Extract this into a generalized set of keys used for all presets.

## 4.2 Storage format
Use whats already being used. 

Implementation details for you:

Use Godot’s File / FileAccess + JSON utilities.

Ensure robust error handling:

Wrap parsing in match / if with checks.

If parse fails, log a warning and recreate a default file.

## 4.3 Default preset
Reproduce exactly the current note colors in a Default preset.

This ensures the user’s first experience is unchanged.

## 5. Implementation plan (step-by-step)
### 5.1 Discovery phase (required before coding)
Locate the note spawn & rendering logic:

Likely in scripts/ under names like Note.gd, HitObject.gd, Game.gd, Playfield.gd, or similar.

Search for:

Color( or .modulate or .self_modulate.

Any const / var arrays for colors (e.g. NOTE_COLORS, LANE_COLORS).

### Identify:

Where colors are applied:

Directly on sprites/meshes?

Via shaders/materials?

### Locate settings management code:

Look for scripts dealing with user settings, configuration, or mod options.

Examples: Settings.gd, Config.gd, OptionsMenu.gd or similar.

### Locate UI scenes for settings:

Under scenes/, find menus for game settings / graphics / mods.

Identify which scene is best to extend with a “Note Color Presets” section.

Do not start refactoring until you have a clear picture and minimal list of the places where note colors are set.

## 5.2 Introduce a presets manager
### Create a dedicated manager to own presets:

Possible file: scripts/note_color_presets.gd (or whatever matches repo conventions).

### Responsibilities:

Load presets from user://mods/note_color_presets.json (or the chosen path).

Provide accessors:

get_active_preset()

set_active_preset(name: String)

get_color(key: String) -> Color

CRUD for presets (create, rename, delete, clone).

Ensure Default preset always exists.

Save presets back to disk when:

The user edits them.

The active preset changes (optional, but recommended).

Implementation hints:

Consider using a singleton / autoload:

If the project already uses autoloads for global managers, add this file there.

Otherwise, integrate into the existing global settings manager.

5.3 Wiring preset colors into note rendering
Modify note rendering logic so that every time a note needs a color, it goes through the presets manager.

For example (pseudocode):

gdscript
Copy code
# OLD (example, you must adapt to actual code):
sprite.modulate = NOTE_COLORS[direction]

# NEW:
var key = get_note_color_key(direction, note_type)  # You implement this helper.
sprite.modulate = NoteColorPresets.get_color(key)
Key steps:

Implement a helper function for deriving a string key from note properties:

get_note_color_key(direction, note_type) → "lane_up", "lane_down", "hold_up", etc.

Replace hard-coded color arrays or constants so they read from presets instead.

Preserve exact same output for the default preset:

Use the original color values when constructing Default.

5.4 Adding UI for Note Color Presets
Integrate into existing settings UI.

Goals for the UI:

Display:

A list of presets.

Buttons for:

Add (New preset, from scratch or cloned from current).

Rename.

Delete (disabled for Default).

Set Active / “Use this”.

Show controls for editing:

A list of note color keys (e.g. each lane/direction/type).

A color picker for each key.

A preview (optional) of notes using that color.

Implementation details:

Add a new scene or panel:

Example: scenes/ui/NoteColorPresetMenu.tscn.

Script: scripts/ui/note_color_preset_menu.gd.

Hook it into the existing Settings / Mods menu:

Add a button or tab like “Note Colors” or “Note Presets”.

For each preset:

Bind UI to the manager’s methods.

Ensure changes update the underlying data structure and call save.

UX considerations:

If presets are many, allow scrolling.

Confirmation dialogs on delete:

“Are you sure you want to delete preset ‘XYZ’?”

If renaming to an existing preset name, show an error or prevent it.

5.5 Persistence & migration
When saving:

Write out JSON with all presets and the active preset name.

Ensure any new keys added in future versions are:

Given default values if missing in an older file.

Never cause a crash during load.

Migration logic (pseudo):

gdscript
Copy code
func _ensure_preset_has_all_keys(preset: Dictionary) -> void:
    for key in REQUIRED_COLOR_KEYS:
        if not preset["colors"].has(key):
            preset["colors"][key] = default_colors[key]
Where REQUIRED_COLOR_KEYS and default_colors are derived from the original game behavior.

6. Coding standards & style
When writing or modifying GDScript:

Match the existing style in this repo:

Indentation (spaces vs tabs).

Naming conventions (snake_case vs camelCase).

Typed vs untyped GDScript (depending on Godot version & current project style).

Keep functions small & focused:

1 responsibility per function where possible.

Add concise comments only where logic is non-obvious.

Example style (adjust to repo’s convention):

gdscript
Copy code
extends Node

class_name NoteColorPresets

var presets: Array = []
var active_preset_name: String = "Default"

func get_color(key: String) -> Color:
    var preset := _get_active_preset()
    if preset and preset.colors.has(key):
        return preset.colors[key]
    return _get_default_color_for_key(key)
7. Testing & verification checklist
Before considering the task done, perform / automate the following checks:

7.1 Functional checks
 Game starts with no preset file present:

 Notes appear with the same colors as the current build (no regressions).

 A new presets file is created with a Default preset.

 Creating a new preset:

 New preset appears in the list.

 Editing its colors via the UI is reflected in newly spawned notes.

 Switching presets:

 Active preset changes.

 Newly spawned notes use the new preset’s colors.

 Deleting a preset:

 Cannot delete Default.

 Can delete user-defined presets.

 If you delete the active preset, active preset falls back to Default (or another sane choice).

 Restarting the game:

 The active preset and user-created presets persist.

7.2 Robustness checks
 Corrupted JSON:

Manually corrupt the presets file and start the game.

Expectation:

No crash.

Warning logged.

Default preset recreated or fallback applied.

 Partial preset (missing some keys):

 Missing keys revert to default colors, not black/white or errors.

7.3 Performance checks
 Preset lookups (e.g., get_color) are not placed inside heavy loops with expensive operations:

Ideally O(1) dictionary lookups with minimal allocations.

 No noticeable frame drops when notes spawn.

8. Documentation
Update / add documentation as needed:

README.md or a new docs/ entry describing:

Where presets are stored (path).

How to edit them in-game.

How advanced users can manually edit JSON for bulk tweaks.

Ensure instructions are clear for non-technical players.

9. Summary for the agent
Your mission:

Map out where note colors are defined and applied.

Design and implement a NoteColorPresets system:

Data model, manager, persistence.

Wire it into note rendering so that presets drive all note colors.

Expose controls in the UI so players can create, edit, and switch presets.

Guarantee backward compatibility:

Default experience must be identical if presets are untouched.

Test thoroughly (startup, switching, saving, corrupted files).

When in doubt, prefer:

Minimal breaking changes.

Clear, maintainable code.

Behavior that matches existing visual style by default.
