extends Node

const SAVE_PATH:String = "user://progression.json"
const DEFAULT_DATA:Dictionary = {
        "total_rp": 0.0,
        "rank": "Unranked",
        "entries": {}
}

const RANK_THRESHOLDS:Array = [
        {"name": "Unranked", "rp": 0},
        {"name": "Bronze", "rp": 500},
        {"name": "Silver", "rp": 1500},
        {"name": "Gold", "rp": 3000},
        {"name": "Platinum", "rp": 5000},
        {"name": "Diamond", "rp": 8000},
        {"name": "Master", "rp": 12000}
]

var _data:Dictionary = DEFAULT_DATA.duplicate(true)
var _save_scheduled:bool = false

func _ready():
        _load()

func get_data() -> Dictionary:
        return _data.duplicate(true)

func get_rank() -> String:
        return String(_data.get("rank", "Unranked"))

func get_total_rp() -> float:
        return float(_data.get("total_rp", 0.0))


func _ensure_entries() -> Dictionary:
        if !_data.has("entries") or !(_data["entries"] is Dictionary):
                _data["entries"] = {}
        return _data["entries"]

func record_song_result(song:Song, payload:Dictionary) -> Dictionary:
        if !song:
                return {}
        var accuracy:float = clamp(float(payload.get("accuracy", 0.0)), 0.0, 1.0)
        var difficulty:int = int(song.difficulty)
        var modifiers:Array = payload.get("mods", [])
        if modifiers.empty():
                modifiers = _describe_active_modifiers()
        var mod_key:String = String(payload.get("mod_key", _get_current_mod_key()))
        var rp := _calculate_rp(accuracy, difficulty, payload)
        var song_id := String(song.id)
        var entry := {
                "song_id": song_id,
                "song_name": song.name,
                "rp": rp,
                "accuracy": accuracy,
                "difficulty": difficulty,
                "modifiers": modifiers,
                "mod_key": mod_key,
                "score": int(payload.get("score", 0)),
                "max_combo": int(payload.get("max_combo", 0)),
                "misses": int(payload.get("misses", 0)),
                "duration": float(payload.get("duration", 0.0)),
                "total_notes": int(payload.get("total_notes", 0)),
                "timestamp": OS.get_unix_time()
        }
        var gained := _apply_entry(song_id, entry)
        _schedule_save()
        return {
                "gained_rp": gained,
                "total_rp": _data.total_rp,
                "rank": _data.rank,
                "entry": _ensure_entries().get(song_id, {})
        }

func _apply_entry(song_id:String, entry:Dictionary) -> float:
        var previous:Dictionary = _ensure_entries().get(song_id, {})
        var previous_rp:float = float(previous.get("rp", 0.0))
        var gained:float = max(entry.rp - previous_rp, 0.0)
        if previous.empty() or entry.rp >= previous_rp:
                _ensure_entries()[song_id] = entry
        _data.total_rp = max(_data.total_rp + gained, 0.0)
        _data.rank = _get_rank_for_rp(_data.total_rp)
        return gained

func _calculate_rp(accuracy:float, difficulty:int, payload:Dictionary) -> float:
        var difficulty_mult := _difficulty_multiplier(difficulty)
        var modifier_mult := _modifier_multiplier()
        var combo_factor := _combo_factor(int(payload.get("max_combo", 0)), int(payload.get("total_notes", 0)))
        var rp:float = accuracy * 1000.0 * difficulty_mult * modifier_mult * combo_factor
        return stepify(rp, 0.01)

func _combo_factor(max_combo:int, total_notes:int) -> float:
        if total_notes <= 0:
                return 1.0
        var ratio := clamp(float(max_combo) / float(total_notes), 0.0, 1.0)
        return lerp(0.85, 1.15, ratio)

func _difficulty_multiplier(difficulty:int) -> float:
        match difficulty:
                -1:
                        return 0.75
                0:
                        return 1.0
                1:
                        return 1.1
                2:
                        return 1.25
                3:
                        return 1.4
                4:
                        return 1.55
                _:
                        return 1.0

func _modifier_multiplier() -> float:
        var mult:float = 1.0
        if Rhythia.mod_extra_energy:
                mult *= 0.85
        if Rhythia.mod_no_regen:
                mult *= 1.05
        if Rhythia.mod_sudden_death:
                mult *= 1.12
        if Rhythia.mod_nofail:
                mult *= 0.75
        if Rhythia.mod_ghost:
                mult *= 1.05
        if Rhythia.mod_nearsighted:
                mult *= 1.02
        if Rhythia.mod_chaos:
                mult *= 1.08
        if Rhythia.mod_earthquake:
                mult *= 1.03
        if Rhythia.mod_flashlight:
                mult *= 1.06
        if Rhythia.mod_hardrock:
                mult *= 1.04
        if Rhythia.mod_mirror_x or Rhythia.mod_mirror_y:
                mult *= 1.01
        var speed_mult:float = Globals.speed_multi[Rhythia.mod_speed_level]
        if speed_mult > 1.0:
                mult *= 1.0 + ((speed_mult - 1.0) * 0.5)
        elif speed_mult < 1.0:
                mult *= 1.0 - ((1.0 - speed_mult) * 0.5)
        return mult

func _describe_active_modifiers() -> Array:
        if has_node("/root/Leaderboard"):
                return get_node("/root/Leaderboard").describe_active_modifiers()
        var mods:Array = []
        if Rhythia.mod_extra_energy:
                mods.append("Easy Mode")
        if Rhythia.mod_no_regen:
                mods.append("Hard Mode")
        if Rhythia.mod_sudden_death:
                mods.append("Sudden Death")
        if Rhythia.mod_nofail:
                mods.append("No Fail")
        if Rhythia.mod_mirror_x:
                mods.append("Mirror X")
        if Rhythia.mod_mirror_y:
                mods.append("Mirror Y")
        if Rhythia.mod_nearsighted:
                mods.append("Nearsight")
        if Rhythia.mod_ghost:
                mods.append("Ghost")
        if Rhythia.mod_chaos:
                mods.append("Chaos")
        if Rhythia.mod_earthquake:
                mods.append("Earthquake")
        if Rhythia.mod_flashlight:
                mods.append("Flashlight")
        if Rhythia.mod_hardrock:
                mods.append("Hard Rock")
        match Rhythia.mod_speed_level:
                Globals.SPEED_MMM:
                        mods.append("Speed ---")
                Globals.SPEED_MM:
                        mods.append("Speed --")
                Globals.SPEED_M:
                        mods.append("Speed -")
                Globals.SPEED_P:
                        mods.append("Speed +")
                Globals.SPEED_PP:
                        mods.append("Speed ++")
                Globals.SPEED_PPP:
                        mods.append("Speed +++")
                Globals.SPEED_PPPP:
                        mods.append("Speed ++++")
                Globals.SPEED_CUSTOM:
                        mods.append("Speed x%.2f" % Rhythia.custom_speed)
        if Rhythia.health_model == Globals.HP_OLD:
                mods.append("Legacy HP")
        if Rhythia.visual_mode:
                mods.append("Visual Mode")
        if Rhythia.invert_mouse:
                mods.append("Invert Mouse")
        return mods

func _get_current_mod_key() -> String:
        if has_node("/root/Leaderboard"):
                return get_node("/root/Leaderboard").get_current_mod_key()
        return Rhythia.generate_pb_str(true)

func _get_rank_for_rp(rp:float) -> String:
        var result := "Unranked"
        for threshold in RANK_THRESHOLDS:
                if rp >= float(threshold.rp):
                        result = String(threshold.name)
        return result

func _schedule_save():
        if _save_scheduled:
                return
        _save_scheduled = true
        call_deferred("_save")

func _save():
        _save_scheduled = false
        var dir := Directory.new()
        dir.make_dir_recursive(Globals.p("user://"))
        var file := File.new()
        var err := file.open(Globals.p(SAVE_PATH), File.WRITE)
        if err != OK:
                return
        file.store_string(JSON.print(_data))
        file.close()

func _load():
        _data = DEFAULT_DATA.duplicate(true)
        var file := File.new()
        var path := Globals.p(SAVE_PATH)
        if file.file_exists(path):
                var err := file.open(path, File.READ)
                if err == OK:
                        var text := file.get_as_text()
                        file.close()
                        if text.strip_edges() != "":
                                var result := JSON.parse(text)
                                if result.error == OK and result.result is Dictionary:
                                        _data = result.result
                                else:
                                        print("[Progression] Failed to parse progression data: %s" % result.error_string)
                else:
                        file.close()
        _ensure_entries()
        _data.rank = _get_rank_for_rp(float(_data.get("total_rp", 0.0)))
