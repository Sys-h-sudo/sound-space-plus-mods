extends Node

const MAX_ENTRIES_PER_MAP:int = 25
const MAX_NEAR_ENTRIES:int = 5
const SAVE_PATH:String = "user://leaderboard.json"
const REMOTE_CACHE_SECONDS:int = 60
const REMOTE_RETRY_SECONDS:int = 15

const REMOTE_SETTING_KEYS:Array = [
"application/networking/leaderboard_api",
"application/networking/leaderboard_url"
]

signal data_changed(song_id)
signal remote_data_changed(song_id)

var _data:Dictionary = {}
var _save_scheduled:bool = false

var _remote_cache:Dictionary = {}
var _remote_meta:Dictionary = {}
var _remote_configured:bool = false
var _pending_remote_song_id:String = ""
var _http:HTTPRequest = null

func _ready():
        _load()
        _remote_configured = _has_remote_config()
        _http = HTTPRequest.new()
        _http.name = "LeaderboardRemoteRequest"
        _http.use_threads = true
        _http.timeout = 15
        add_child(_http)
        _http.connect("request_completed", self, "_on_http_request_completed")

func _load():
        _data.clear()
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
                                        print("[Leaderboard] Failed to parse leaderboard data: %s" % result.error_string)
                else:
                        file.close()

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

func has_remote_config() -> bool:
        return _remote_configured

func get_remote_meta(song:Song) -> Dictionary:
        if !song:
                return _default_remote_meta()
        var song_id := String(song.id)
        var meta := _ensure_remote_meta(song_id)
        return meta.duplicate(true)

func is_remote_loading(song:Song) -> bool:
        if !song:
                return false
        return _pending_remote_song_id != "" and _pending_remote_song_id == String(song.id)

func has_remote_data(song:Song) -> bool:
        if !song:
                return false
        var song_id := String(song.id)
        if !_remote_cache.has(song_id):
                return false
        var bundle:Dictionary = _remote_cache[song_id]
        var top:Array = bundle.get("top", [])
        var near:Array = bundle.get("near", [])
        var player_entry:Dictionary = bundle.get("player", {})
        return top.size() > 0 or near.size() > 0 or !player_entry.empty()

func get_display_bundle(song:Song) -> Dictionary:
        if !song:
                return {"mode": "none", "top": [], "near": [], "player": {}}
        var song_id := String(song.id)
        if _remote_cache.has(song_id):
                return _remote_cache[song_id].duplicate(true)
        return _build_local_bundle(song)

func get_remote_bundle(song:Song) -> Dictionary:
        if !song:
                return {}
        var song_id := String(song.id)
        if !_remote_cache.has(song_id):
                return {}
        return _remote_cache[song_id].duplicate(true)

func refresh_remote(song:Song, force:bool=false) -> void:
        if !song:
                return
        _remote_configured = _has_remote_config()
        var song_id := String(song.id)
        var url := _get_leaderboard_url(song)
        if url != "":
                _remote_configured = true
        if url == "":
                if _remote_cache.has(song_id):
                        _remote_cache.erase(song_id)
                if _remote_meta.has(song_id):
                        var meta := _ensure_remote_meta(song_id)
                        meta.loading = false
                        meta.status = _remote_configured ? "idle" : "disabled"
                        meta.error_type = ""
                        meta.status_code = 0
                        meta.result_code = 0
                emit_signal("remote_data_changed", song_id)
                return
        var meta := _ensure_remote_meta(song_id)
        var now:int = OS.get_unix_time()
        if meta.get("loading", false) and _pending_remote_song_id == song_id:
                return
        if !force:
                var last_request:int = int(meta.get("last_request", 0))
                if last_request > 0 and now - last_request < REMOTE_RETRY_SECONDS:
                        return
                if _remote_cache.has(song_id):
                        var cached:Dictionary = _remote_cache[song_id]
                        var fetched_at:int = int(cached.get("fetched_at", 0))
                        if fetched_at > 0 and now - fetched_at < REMOTE_CACHE_SECONDS:
                                return
        if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
                _http.cancel_request()
        meta.loading = true
        meta.status = "loading"
        meta.error_type = ""
        meta.status_code = 0
        meta.result_code = 0
        meta.last_request = now
        _pending_remote_song_id = song_id
        var err := _http.request(url)
        if err != OK:
                meta.loading = false
                meta.status = "error"
                meta.error_type = "network"
                meta.result_code = err
                _pending_remote_song_id = ""
                emit_signal("remote_data_changed", song_id)


func record_local_result(song:Song, payload:Dictionary) -> Dictionary:
        if !song:
                return {}
        var map_id := String(song.id)
        if map_id == "":
                return {}
        var entry := _build_entry_from_payload(payload)
        var entries:Array = _get_entries(map_id)
        for i in range(entries.size() - 1, -1, -1):
                var existing:Dictionary = entries[i]
                if existing.get("mod_key", "") == entry.mod_key:
                        if _is_entry_better(entry, existing):
                                entries.remove(i)
                        else:
                                return {"rank": i + 1, "entry": existing}
        entries.append(entry)
        entries.sort_custom(self, "_sort_entries_desc")
        if entries.size() > MAX_ENTRIES_PER_MAP:
                entries.resize(MAX_ENTRIES_PER_MAP)
        _data[map_id] = entries
        _schedule_save()
        emit_signal("data_changed", map_id)
        return {"rank": entries.find(entry) + 1, "entry": entry}

func get_entries_for_song(song:Song) -> Array:
        if !song:
                return []
        var entries:Array = _get_entries(String(song.id))
        var copy:Array = []
        for e in entries:
                if e is Dictionary:
                        copy.append(e.duplicate(true))
        return copy

func get_entry_for_mod(song:Song, mod_key:String) -> Dictionary:
        if !song or mod_key == "":
                return {}
        var entries:Array = _get_entries(String(song.id))
        for i in range(entries.size()):
                var entry:Dictionary = entries[i]
                if entry.get("mod_key", "") == mod_key:
                        return {"rank": i + 1, "entry": entry.duplicate(true)}
        return {}

func is_remote_available() -> bool:
        return _remote_configured

func describe_active_modifiers() -> Array:
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

func get_current_mod_key() -> String:
        return Rhythia.generate_pb_str(true)

func _get_entries(map_id:String) -> Array:
        if !_data.has(map_id):
                _data[map_id] = []
        return _data[map_id]

func _default_remote_meta() -> Dictionary:
        return {
                "loading": false,
                "status": _remote_configured ? "idle" : "disabled",
                "error_type": "",
                "status_code": 0,
                "result_code": 0,
                "last_request": 0
        }

func _ensure_remote_meta(song_id:String) -> Dictionary:
        if !_remote_meta.has(song_id):
                _remote_meta[song_id] = _default_remote_meta()
        return _remote_meta[song_id]

func _has_remote_config() -> bool:
        return _is_network_enabled() and _get_leaderboard_base_url() != ""

func _is_network_enabled() -> bool:
        if ProjectSettings.has_setting("application/networking/enabled"):
                return bool(ProjectSettings.get_setting("application/networking/enabled"))
        return false

func _get_leaderboard_base_url() -> String:
        for key in REMOTE_SETTING_KEYS:
                if ProjectSettings.has_setting(key):
                        var value = ProjectSettings.get_setting(key)
                        if typeof(value) == TYPE_STRING:
                                var text := String(value).strip_edges()
                                if text != "":
                                        return text
        return ""

func _get_leaderboard_url(song:Song) -> String:
        if !song:
                return ""
        if song.custom_data.has("leaderboard_url"):
                var custom_url = String(song.custom_data.get("leaderboard_url"))
                if custom_url.strip_edges() != "":
                        return custom_url.strip_edges()
        if song.custom_data.has("leaderboard") and song.custom_data.leaderboard is String:
                var embedded_url := String(song.custom_data.leaderboard)
                if embedded_url.strip_edges() != "":
                        return embedded_url.strip_edges()
        var base := _get_leaderboard_base_url()
        if base == "":
                return ""
        if base.find("%s") != -1:
                return base % song.id
        var trimmed := base.rstrip("/")
        return "%s/%s" % [trimmed, String(song.id)]

func _on_http_request_completed(result:int, response_code:int, _headers:PoolStringArray, body:PoolByteArray) -> void:
        var song_id := _pending_remote_song_id
        _pending_remote_song_id = ""
        if song_id == "":
                return
        var meta := _ensure_remote_meta(song_id)
        meta.loading = false
        meta.result_code = result
        meta.status_code = response_code
        if result != HTTPRequest.RESULT_SUCCESS:
                meta.status = "error"
                meta.error_type = "network"
                _remote_cache.erase(song_id)
                emit_signal("remote_data_changed", song_id)
                return
        if response_code != 200:
                meta.status = "error"
                meta.error_type = "http"
                _remote_cache.erase(song_id)
                emit_signal("remote_data_changed", song_id)
                return
        var text := body.get_string_from_utf8()
        var parsed := JSON.parse(text)
        if parsed.error != OK or !(parsed.result is Dictionary):
                meta.status = "error"
                meta.error_type = "parse"
                _remote_cache.erase(song_id)
                emit_signal("remote_data_changed", song_id)
                return
        var bundle := _build_remote_bundle(parsed.result)
        if bundle.get("top", []).size() == 0 and bundle.get("near", []).size() == 0 and bundle.get("player", {}).empty():
                meta.status = "error"
                meta.error_type = "empty"
                _remote_cache.erase(song_id)
                emit_signal("remote_data_changed", song_id)
                return
        bundle["fetched_at"] = OS.get_unix_time()
        bundle["mode"] = "remote"
        _remote_cache[song_id] = bundle
        meta.status = "success"
        meta.error_type = ""
        emit_signal("remote_data_changed", song_id)

func _build_remote_bundle(payload:Dictionary) -> Dictionary:
        var top:Array = []
        var near:Array = []
        var player_entry:Dictionary = {}
        var top_source:Array = _extract_remote_array(payload, ["top", "leaderboard", "scores", "entries"])
        for entry in top_source:
                var sanitized := _sanitize_remote_entry(entry)
                if sanitized.size() > 0:
                        top.append(sanitized)
        var near_source:Array = _extract_remote_array(payload, ["around", "near", "neighbors", "window", "context"])
        for entry in near_source:
                var sanitized := _sanitize_remote_entry(entry)
                if sanitized.size() > 0:
                        near.append(sanitized)
        var player_source:Dictionary = _extract_remote_dict(payload, ["player", "self", "you", "personal", "entry"])
        if player_source.size() > 0:
                player_entry = _sanitize_remote_entry(player_source)
        if player_entry.size() > 0:
                player_entry["highlight"] = true
                var player_rank:int = int(player_entry.get("rank", 0))
                for entry in top:
                        if player_rank > 0 and int(entry.get("rank", 0)) == player_rank:
                                entry["highlight"] = true
                var contains_player:bool = false
                for entry in near:
                        if player_rank > 0 and int(entry.get("rank", 0)) == player_rank:
                                entry["highlight"] = true
                                contains_player = true
                if !contains_player:
                        near.append(player_entry.duplicate(true))
        top.sort_custom(self, "_remote_sort")
        near.sort_custom(self, "_remote_sort")
        if near.size() > MAX_NEAR_ENTRIES:
                        near.resize(MAX_NEAR_ENTRIES)
        return {
                "top": top,
                "near": near,
                "player": player_entry
        }

func _extract_remote_array(payload:Dictionary, keys:Array) -> Array:
        for key in keys:
                if payload.has(key):
                        var value = payload.get(key)
                        if value is Array:
                                return value
        return []

func _extract_remote_dict(payload:Dictionary, keys:Array) -> Dictionary:
        for key in keys:
                if payload.has(key):
                        var value = payload.get(key)
                        if value is Dictionary:
                                return value
        return {}

func _sanitize_remote_entry(entry) -> Dictionary:
        if !(entry is Dictionary):
                return {}
        var data:Dictionary = entry
        var result:Dictionary = {}
        result["rank"] = int(data.get("rank", data.get("position", data.get("place", 0))))
        result["score"] = int(data.get("score", data.get("points", 0)))
        if data.has("accuracy"):
                result["accuracy"] = float(data.get("accuracy"))
        elif data.has("acc"):
                result["accuracy"] = float(data.get("acc"))
        elif data.has("accuracy_percent"):
                result["accuracy"] = float(data.get("accuracy_percent"))
        var mods = data.get("mods", data.get("modifiers", []))
        if mods is Array:
                var mod_labels:Array = []
                for m in mods:
                        mod_labels.append(String(m))
                result["mods"] = mod_labels
        elif mods != null:
                result["mods"] = [String(mods)]
        result["name"] = String(data.get("name", data.get("player", data.get("username", ""))))
        result["country"] = String(data.get("country", data.get("flag", "")))
        if data.has("timestamp"):
                result["timestamp"] = int(data.get("timestamp"))
        elif data.has("submitted_at"):
                result["timestamp"] = int(data.get("submitted_at"))
        if data.has("time") and !(data.time is int):
                result["time"] = String(data.time)
        if data.has("max_combo"):
                result["max_combo"] = int(data.get("max_combo"))
        if data.has("misses"):
                result["misses"] = int(data.get("misses"))
        if data.has("pauses"):
                result["pauses"] = int(data.get("pauses"))
        if data.has("passed"):
                result["passed"] = bool(data.get("passed"))
        if data.has("highlight"):
                result["highlight"] = bool(data.get("highlight"))
        result["source"] = "remote"
        return result

func _remote_sort(a:Dictionary, b:Dictionary) -> bool:
        return int(a.get("rank", 0)) < int(b.get("rank", 0))

func _build_local_bundle(song:Song) -> Dictionary:
        var entries:Array = get_entries_for_song(song)
        var top:Array = []
        for i in range(entries.size()):
                var entry:Dictionary = entries[i]
                if entry is Dictionary:
                        var copy:Dictionary = entry.duplicate(true)
                        copy["rank"] = i + 1
                        copy["source"] = "local"
                        copy["highlight"] = false
                        top.append(copy)
        var near:Array = []
        var player_entry:Dictionary = {}
        var mod_key:String = get_current_mod_key()
        if mod_key != "":
                var match:Dictionary = get_entry_for_mod(song, mod_key)
                if !match.empty():
                        player_entry = match.get("entry", {}).duplicate(true)
                        var rank:int = int(match.get("rank", 0))
                        player_entry["rank"] = rank
                        player_entry["source"] = "local"
                        player_entry["highlight"] = true
                        if rank > 0 and entries.size() > 0:
                                var index:int = clamp(rank - 1, 0, entries.size() - 1)
                                var start:int = max(index - 2, 0)
                                var end:int = min(index + 3, entries.size())
                                for j in range(start, end):
                                        var near_copy:Dictionary = entries[j].duplicate(true)
                                        near_copy["rank"] = j + 1
                                        near_copy["source"] = "local"
                                        near_copy["highlight"] = (j == index)
                                        near.append(near_copy)
        if near.size() == 0 and !player_entry.empty():
                near.append(player_entry.duplicate(true))
        if near.size() > MAX_NEAR_ENTRIES:
                near.resize(MAX_NEAR_ENTRIES)
        var player_rank:int = int(player_entry.get("rank", 0))
        if player_rank > 0:
                for entry in top:
                        if int(entry.get("rank", 0)) == player_rank:
                                entry["highlight"] = true
                                break
        return {
                "mode": "local",
                "top": top,
                "near": near,
                "player": player_entry,
                "player_rank": player_rank
        }

func _build_entry_from_payload(payload:Dictionary) -> Dictionary:
        var entry:Dictionary = {}
        entry.score = int(payload.get("score", 0))
        entry.accuracy = float(payload.get("accuracy", 0.0))
        entry.timestamp = int(payload.get("timestamp", OS.get_unix_time()))
        entry.mods = _stringify_array(payload.get("mods", []))
        entry.mod_key = String(payload.get("mod_key", ""))
        entry.max_combo = int(payload.get("max_combo", 0))
        entry.misses = int(payload.get("misses", 0))
        entry.pauses = int(payload.get("pauses", 0))
        entry.duration = float(payload.get("duration", 0.0))
        entry.passed = bool(payload.get("passed", true))
        return entry

func _stringify_array(value) -> Array:
        var result:Array = []
        if value is Array:
                for v in value:
                        result.append(String(v))
        else:
                result.append(String(value))
        return result

func _is_entry_better(candidate:Dictionary, existing:Dictionary) -> bool:
        var new_score:int = int(candidate.get("score", 0))
        var old_score:int = int(existing.get("score", 0))
        if new_score == old_score:
                var new_accuracy:float = float(candidate.get("accuracy", 0.0))
                var old_accuracy:float = float(existing.get("accuracy", 0.0))
                if new_accuracy == old_accuracy:
                        return int(candidate.get("timestamp", 0)) > int(existing.get("timestamp", 0))
                return new_accuracy > old_accuracy
        return new_score > old_score

func _sort_entries_desc(a:Dictionary, b:Dictionary) -> bool:
        var score_a:int = int(a.get("score", 0))
        var score_b:int = int(b.get("score", 0))
        if score_a == score_b:
                var acc_a:float = float(a.get("accuracy", 0.0))
                var acc_b:float = float(b.get("accuracy", 0.0))
                if acc_a == acc_b:
                        return int(a.get("timestamp", 0)) > int(b.get("timestamp", 0))
                return acc_a > acc_b
        return score_a > score_b
