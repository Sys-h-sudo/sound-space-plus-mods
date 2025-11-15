extends ReferenceRect

const MAX_TOP_ENTRIES:int = 10

onready var _subtitle_label:Label = $Layout/Subtitle
onready var _notice_label:Label = $Layout/Notice
onready var _top_header:Label = $Layout/TopPanel/TopMargin/TopContent/TopHeader
onready var _top_entries:VBoxContainer = $Layout/TopPanel/TopMargin/TopContent/TopScroll/TopEntries
onready var _top_empty_label:Label = $Layout/TopPanel/TopMargin/TopContent/TopEmpty
onready var _near_panel:PanelContainer = $Layout/NearPanel
onready var _near_header:Label = $Layout/NearPanel/NearMargin/NearContent/NearHeader
onready var _near_entries:VBoxContainer = $Layout/NearPanel/NearMargin/NearContent/NearEntries
onready var _near_empty_label:Label = $Layout/NearPanel/NearMargin/NearContent/NearEmpty

func _ready():
        if has_node("/root/Rhythia"):
                if !Rhythia.is_connected("selected_song_changed", self, "_refresh_leaderboard"):
                        Rhythia.connect("selected_song_changed", self, "_refresh_leaderboard")
                if !Rhythia.is_connected("mods_changed", self, "_refresh_leaderboard"):
                        Rhythia.connect("mods_changed", self, "_refresh_leaderboard")
        var leaderboard = get_node_or_null("/root/Leaderboard")
        if leaderboard:
                if !leaderboard.is_connected("data_changed", self, "_on_leaderboard_changed"):
                        leaderboard.connect("data_changed", self, "_on_leaderboard_changed")
                if !leaderboard.is_connected("remote_data_changed", self, "_on_remote_leaderboard_changed"):
                        leaderboard.connect("remote_data_changed", self, "_on_remote_leaderboard_changed")
        _refresh_leaderboard()

func _on_leaderboard_changed(song_id:String):
        if has_node("/root/Rhythia"):
                var song:Song = Rhythia.selected_song
                if song and song.id == song_id:
                        _refresh_leaderboard()
        else:
                _refresh_leaderboard()

func _on_remote_leaderboard_changed(song_id:String):
        _on_leaderboard_changed(song_id)

func _refresh_leaderboard(_arg=null):
        var song:Song = null
        if has_node("/root/Rhythia"):
                song = Rhythia.selected_song
        $Layout/Title.text = tr("Leaderboard")
        if !song:
                _subtitle_label.text = tr("Select a song to view leaderboard data.")
                _top_header.text = tr("Best Scores on This Device")
                _near_header.text = tr("Your best with current modifiers")
                _clear_container(_top_entries)
                _top_empty_label.text = tr("No song selected.")
                _top_empty_label.visible = true
                _near_panel.visible = false
                _notice_label.visible = false
                return
        _subtitle_label.text = "%s — %s" % [song.name, song.creator]
        var leaderboard = get_node_or_null("/root/Leaderboard")
        var display:Dictionary = {"mode": "local", "top": [], "near": [], "player": {}}
        var remote_meta:Dictionary = {}
        if leaderboard:
                leaderboard.refresh_remote(song)
                display = leaderboard.get_display_bundle(song)
                remote_meta = leaderboard.get_remote_meta(song)
        else:
                remote_meta = {"status": "disabled"}
        var mode:String = String(display.get("mode", "local"))
        var top_entries:Array = display.get("top", [])
        var near_entries:Array = display.get("near", [])
        var player_entry:Dictionary = display.get("player", {})
        if mode == "remote":
                _top_header.text = tr("Top Players")
                _near_header.text = tr("Near You")
        else:
                _top_header.text = tr("Best Scores on This Device")
                _near_header.text = tr("Your best with current modifiers")
        _apply_notice_for_mode(mode, leaderboard, remote_meta, player_entry)
        _populate_top_entries(top_entries, mode)
        _populate_near_entries(near_entries, mode, player_entry)

func _populate_top_entries(entries:Array, mode:String):
        _clear_container(_top_entries)
        if entries.size() == 0:
                if mode == "remote":
                        _top_empty_label.text = tr("No leaderboard data available.")
                else:
                        _top_empty_label.text = tr("Play this song to record your first score on this device.")
                _top_empty_label.visible = true
                return
        _top_empty_label.visible = false
        var limit:int = min(entries.size(), MAX_TOP_ENTRIES)
        for i in range(limit):
                var entry = entries[i]
                if entry is Dictionary:
                        _top_entries.add_child(_create_entry(entry, mode))

func _populate_near_entries(entries:Array, mode:String, player_entry:Dictionary):
        _clear_container(_near_entries)
        if entries.size() == 0 and mode == "remote" and !player_entry.empty():
                entries = [player_entry.duplicate(true)]
        if entries.size() == 0:
                _near_panel.visible = true
                _near_empty_label.visible = true
                if mode == "remote":
                        _near_empty_label.text = tr("No nearby scores to display.")
                else:
                        _near_empty_label.text = tr("No score recorded for the current modifiers yet.")
                return
        _near_panel.visible = true
        _near_empty_label.visible = false
        for entry in entries:
                if entry is Dictionary:
                        _near_entries.add_child(_create_entry(entry, mode))

func _create_entry(entry:Dictionary, mode:String) -> Control:
        var wrapper := MarginContainer.new()
        wrapper.add_constant_override("margin_left", 4)
        wrapper.add_constant_override("margin_right", 4)
        wrapper.add_constant_override("margin_top", 2)
        wrapper.add_constant_override("margin_bottom", 2)
        wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

        var background := ColorRect.new()
        var highlight:bool = bool(entry.get("highlight", false))
        background.color = highlight ? Color(0.278431, 0.490196, 0.580392, 0.4) : Color(0, 0, 0, 0.25)
        background.rect_min_size.y = 56
        background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        background.mouse_filter = Control.MOUSE_FILTER_IGNORE
        wrapper.add_child(background)

        var hbox := HBoxContainer.new()
        hbox.anchor_right = 1.0
        hbox.anchor_bottom = 1.0
        hbox.margin_left = 16
        hbox.margin_right = -16
        hbox.margin_top = 8
        hbox.margin_bottom = -8
        hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        hbox.custom_constants.separation = 16
        background.add_child(hbox)

        var rank_label := Label.new()
        var rank:int = int(entry.get("rank", 0))
        rank_label.text = rank > 0 ? "#%d" % rank : "--"
        rank_label.rect_min_size = Vector2(70, 0)
        hbox.add_child(rank_label)

        var info_box := VBoxContainer.new()
        info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        info_box.custom_constants.separation = 2
        hbox.add_child(info_box)

        var primary_label := Label.new()
        primary_label.text = _format_primary_line(entry, mode)
        if highlight:
                primary_label.add_color_override("font_color", Color(0.82, 0.95, 1.0))
        info_box.add_child(primary_label)

        var secondary_label := Label.new()
        secondary_label.text = _format_secondary_line(entry, mode)
        secondary_label.add_color_override("font_color", Color(0.75, 0.78, 0.8))
        info_box.add_child(secondary_label)

        var time_label := Label.new()
        time_label.rect_min_size = Vector2(220, 0)
        time_label.align = Label.ALIGN_RIGHT
        time_label.valign = Label.VALIGN_CENTER
        time_label.clip_text = true
        time_label.text = _format_timestamp(entry, mode)
        hbox.add_child(time_label)

        return wrapper

func _apply_notice_for_mode(mode:String, leaderboard, remote_meta:Dictionary, player_entry:Dictionary) -> void:
        if mode == "remote":
                var summary := _format_remote_summary(player_entry)
                _notice_label.visible = summary != ""
                if _notice_label.visible:
                        _notice_label.text = summary
                return
        var message:String = ""
        if leaderboard and leaderboard.has_method("has_remote_config") and leaderboard.has_remote_config():
                if bool(remote_meta.get("loading", false)):
                        message = tr("Loading global leaderboard… Showing local best scores for now.")
                else:
                        var status:String = String(remote_meta.get("status", ""))
                        if status == "error":
                                message = _format_remote_error(remote_meta)
                        elif status == "success":
                                message = tr("Showing local best scores.")
                        else:
                                message = tr("Global leaderboard unavailable. Showing local best scores.")
        else:
                message = tr("Global leaderboard unavailable. Showing local best scores.")
        _notice_label.visible = message != ""
        if _notice_label.visible:
                _notice_label.text = message

func _format_primary_line(entry:Dictionary, mode:String) -> String:
        if mode == "remote":
                var name:String = String(entry.get("name", "")).strip_edges()
                if name == "":
                        name = tr("Unknown player")
                return name
        var parts:Array = []
        var score_value:int = int(entry.get("score", 0))
        if score_value > 0:
                parts.append(tr("Score %s") % Globals.comma_sep(score_value))
        else:
                parts.append(tr("Score N/A"))
        if entry.has("accuracy"):
                var accuracy_text := _format_accuracy_text(entry.get("accuracy"))
                if accuracy_text != "":
                        parts.append(accuracy_text)
        parts.append(entry.get("passed", true) ? tr("Clear") : tr("Failed"))
        return " • ".join(parts)

func _format_secondary_line(entry:Dictionary, mode:String) -> String:
        var parts:Array = []
        if mode == "remote":
                var score_value:int = int(entry.get("score", 0))
                if score_value > 0:
                        parts.append(tr("Score %s") % Globals.comma_sep(score_value))
                if entry.has("accuracy"):
                        var accuracy_text := _format_accuracy_text(entry.get("accuracy"))
                        if accuracy_text != "":
                                parts.append(accuracy_text)
        if entry.has("mods"):
                var mods = entry.get("mods", [])
                var mod_labels:Array = []
                if mods is Array:
                        for mod in mods:
                                mod_labels.append(tr(String(mod)))
                elif mods != null:
                        mod_labels.append(tr(String(mods)))
                if mod_labels.size() == 0:
                        mod_labels.append(tr("No modifiers"))
                parts.append(", ".join(mod_labels))
        elif mode != "remote":
                parts.append(tr("No modifiers"))
        var stats:Array = []
        var combo:int = int(entry.get("max_combo", 0))
        if combo > 0:
                stats.append(tr("Combo %s") % Globals.comma_sep(combo))
        if entry.has("misses"):
                stats.append(tr("Misses %s") % Globals.comma_sep(int(entry.get("misses", 0))))
        if entry.has("pauses"):
                var pauses:int = int(entry.get("pauses", 0))
                if pauses > 0:
                        stats.append(tr("Pauses %s") % Globals.comma_sep(pauses))
        if stats.size() > 0:
                parts.append(" | ".join(stats))
        if mode == "remote":
                var country := String(entry.get("country", "")).strip_edges()
                if country != "":
                        parts.append(country.to_upper())
                if entry.has("passed"):
                        var status_text:String = entry.get("passed", true) ? tr("Clear") : tr("Failed")
                        if parts.find(status_text) == -1:
                                parts.append(status_text)
        return " • ".join(parts)

func _format_timestamp(entry:Dictionary, mode:String) -> String:
        if entry.has("time"):
                var time_value = entry.get("time")
                if typeof(time_value) == TYPE_STRING:
                        var text := String(time_value).strip_edges()
                        if text != "":
                                return text
        var timestamp:int = int(entry.get("timestamp", 0))
        if timestamp <= 0:
                return mode == "remote" ? "" : tr("Unknown time")
        return Time.get_datetime_string_from_unix_time(timestamp, true)

func _format_remote_error(meta:Dictionary) -> String:
        var error_type:String = String(meta.get("error_type", ""))
        match error_type:
                "network":
                        return tr("Global leaderboard unavailable (network error). Showing local best scores.")
                "http":
                        var status_code:int = int(meta.get("status_code", 0))
                        if status_code > 0:
                                return tr("Global leaderboard unavailable (HTTP %d). Showing local best scores.") % status_code
                        return tr("Global leaderboard unavailable (server error). Showing local best scores.")
                "parse":
                        return tr("Global leaderboard unavailable (invalid data). Showing local best scores.")
                "empty":
                        return tr("Global leaderboard returned no scores. Showing local best scores.")
        return tr("Global leaderboard unavailable. Showing local best scores.")

func _format_remote_summary(player_entry:Dictionary) -> String:
        if player_entry.empty():
                return ""
        var parts:Array = []
        var rank:int = int(player_entry.get("rank", 0))
        if rank > 0:
                parts.append(tr("Your rank: #%d") % rank)
        var score_value:int = int(player_entry.get("score", 0))
        if score_value > 0:
                parts.append(tr("Score %s") % Globals.comma_sep(score_value))
        if player_entry.has("accuracy"):
                var accuracy_text := _format_accuracy_text(player_entry.get("accuracy"))
                if accuracy_text != "":
                        parts.append(accuracy_text)
        return " • ".join(parts)

func _format_accuracy_text(value) -> String:
        if typeof(value) == TYPE_REAL or typeof(value) == TYPE_INT:
                var acc:float = float(value)
                if acc > 1.0:
                        return "%.2f%%" % acc
                return "%.2f%%" % (acc * 100.0)
        return ""

func _clear_container(node:Node):
        for child in node.get_children():
                child.queue_free()
