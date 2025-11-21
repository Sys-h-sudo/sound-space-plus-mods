extends Node

signal presets_changed
signal active_preset_changed(name)
signal preset_colors_changed(name)

const PRESET_DIR := "user://mods/note_color_presets"
const PRESET_FILE := PRESET_DIR + "/presets.json"
const DEFAULT_PRESET_NAME := "Default"

var presets := {}
var active_preset_name := DEFAULT_PRESET_NAME
var _active_colors := []
var _loading := false

func _ready():
    _ensure_directories()
    _load_presets()
    call_deferred("_initialize_default")
    if Engine.has_singleton("Rhythia"):
        Rhythia.connect("selected_colorset_changed", self, "_on_rhythia_colorset_changed")

func _initialize_default():
    _sync_default_with_rhythia()
    emit_signal("active_preset_changed", active_preset_name)

func _ensure_directories():
    var dir := Directory.new()
    var target_dir := Globals.p(PRESET_DIR)
    if !dir.dir_exists(target_dir):
        var err := dir.make_dir_recursive(target_dir)
        if err != OK:
            push_error("Failed to create preset directory: %s" % err)

func _load_presets():
    _loading = true
    presets.clear()
    active_preset_name = DEFAULT_PRESET_NAME
    _active_colors = []
    var should_save := false

    var file := File.new()
    if file.file_exists(Globals.p(PRESET_FILE)):
        var err := file.open(Globals.p(PRESET_FILE), File.READ)
        if err == OK:
            var content := file.get_as_text()
            file.close()
            var parse := JSON.parse(content)
            if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
                should_save = _deserialize(parse.result)
            else:
                _create_default_presets()
                should_save = true
        else:
            _create_default_presets()
            should_save = true
    else:
        _create_default_presets()
        should_save = true

    _loading = false
    _apply_active()
    if should_save:
        _save()

func _create_default_presets():
    var default_colors := _get_colors_from_rhythia()
    presets[DEFAULT_PRESET_NAME] = {
        "colors": default_colors
    }
    active_preset_name = DEFAULT_PRESET_NAME

func _deserialize(data: Dictionary) -> bool:
    var changed := false
    var raw_presets = data.get("presets", {})
    if typeof(raw_presets) != TYPE_DICTIONARY:
        raw_presets = {}
        changed = true

    for name in raw_presets.keys():
        if typeof(name) != TYPE_STRING:
            changed = true
            continue
        var entry = raw_presets[name]
        if typeof(entry) != TYPE_DICTIONARY:
            changed = true
            continue
        var colors_data = entry.get("colors", [])
        if typeof(colors_data) != TYPE_ARRAY:
            changed = true
            continue
        var colors := []
        for c in colors_data:
            var color = _parse_color(c)
            if color:
                colors.append(color)
        if colors.empty():
            colors = _get_colors_from_rhythia()
            changed = true
        presets[name] = {"colors": colors}

    if !presets.has(DEFAULT_PRESET_NAME):
        presets[DEFAULT_PRESET_NAME] = {"colors": _get_colors_from_rhythia()}
        changed = true

    var stored_active = data.get("active", DEFAULT_PRESET_NAME)
    if typeof(stored_active) == TYPE_STRING and presets.has(stored_active):
        active_preset_name = stored_active
    else:
        active_preset_name = DEFAULT_PRESET_NAME
        changed = true

    return changed

func _parse_color(value):
    match typeof(value):
        TYPE_STRING:
            return Color(value)
        TYPE_DICTIONARY:
            if value.has("r") and value.has("g") and value.has("b"):
                return Color(value.r, value.g, value.b, value.get("a", 1.0))
        TYPE_ARRAY:
            if value.size() >= 3:
                return Color(value[0], value[1], value[2], value.size() >= 4 ? value[3] : 1.0)
    return null

func _apply_active():
    if presets.empty():
        presets[DEFAULT_PRESET_NAME] = {"colors": _get_colors_from_rhythia()}
        active_preset_name = DEFAULT_PRESET_NAME
    if !presets.has(active_preset_name):
        active_preset_name = DEFAULT_PRESET_NAME
    _active_colors = presets[active_preset_name]["colors"].duplicate()

func get_colors() -> Array:
    return _active_colors.duplicate()

func get_active_preset_name() -> String:
    return active_preset_name

func get_preset_colors(name: String) -> Array:
    if presets.has(name):
        return presets[name]["colors"].duplicate()
    return []

func get_color(key) -> Color:
    if _active_colors.empty():
        return Color.white
    var index := 0
    match typeof(key):
        TYPE_INT:
            index = key
        TYPE_REAL:
            index = int(key)
        TYPE_STRING:
            if key.is_valid_integer():
                index = int(key)
            elif key.begins_with("lane_") and key.substr(5).is_valid_integer():
                index = int(key.substr(5))
        TYPE_DICTIONARY:
            if key.has("lane"):
                index = int(key.lane)
            elif key.has("index"):
                index = int(key.index)
            elif key.has("type"):
                index = int(key.type)
    if _active_colors.empty():
        return Color.white
    return _active_colors[int(posmod(index, _active_colors.size()))]

func set_active_preset(name: String):
    if !presets.has(name):
        return
    if active_preset_name == name:
        return
    active_preset_name = name
    _apply_active()
    _save()
    emit_signal("active_preset_changed", name)

func get_preset_names() -> Array:
    return presets.keys()

func has_preset(name: String) -> bool:
    return presets.has(name)

func is_default(name: String) -> bool:
    return name == DEFAULT_PRESET_NAME

func create_preset(name: String, colors: Array=null):
    if name == "":
        return
    if presets.has(name):
        return
    var preset_colors := colors if colors else get_colors()
    if preset_colors.empty():
        preset_colors = _get_colors_from_rhythia()
    presets[name] = {"colors": _normalize_colors(preset_colors)}
    _save()
    emit_signal("presets_changed")

func clone_preset(source: String, name: String) -> bool:
    if !presets.has(source) or presets.has(name):
        return false
    var colors := presets[source]["colors"].duplicate()
    presets[name] = {"colors": _normalize_colors(colors)}
    _save()
    emit_signal("presets_changed")
    return true

func rename_preset(old_name: String, new_name: String) -> bool:
    if old_name == DEFAULT_PRESET_NAME:
        return false
    if !presets.has(old_name) or presets.has(new_name) or new_name == "":
        return false
    presets[new_name] = presets[old_name]
    presets.erase(old_name)
    if active_preset_name == old_name:
        active_preset_name = new_name
        _apply_active()
        emit_signal("active_preset_changed", new_name)
    _save()
    emit_signal("presets_changed")
    return true

func delete_preset(name: String) -> bool:
    if name == DEFAULT_PRESET_NAME:
        return false
    if !presets.has(name):
        return false
    presets.erase(name)
    if active_preset_name == name:
        active_preset_name = DEFAULT_PRESET_NAME
        _apply_active()
        emit_signal("active_preset_changed", active_preset_name)
    _save()
    emit_signal("presets_changed")
    return true

func update_color(name: String, index: int, color: Color):
    if !presets.has(name):
        return
    var colors: Array = presets[name]["colors"]
    if index < 0 or index >= colors.size():
        return
    colors[index] = color
    if name == active_preset_name:
        _active_colors[index] = color
    _save()
    emit_signal("preset_colors_changed", name)

func add_color(name: String, color: Color):
    if !presets.has(name):
        return
    var colors: Array = presets[name]["colors"]
    colors.append(color)
    if name == active_preset_name:
        _active_colors.append(color)
    _save()
    emit_signal("preset_colors_changed", name)

func remove_color(name: String, index: int):
    if !presets.has(name):
        return
    var colors: Array = presets[name]["colors"]
    if colors.size() <= 1:
        return
    if index < 0 or index >= colors.size():
        return
    colors.remove(index)
    if name == active_preset_name:
        _active_colors.remove(index)
        if _active_colors.empty():
            _active_colors.append_array(_get_colors_from_rhythia())
    _save()
    emit_signal("preset_colors_changed", name)

func ensure_default_consistency():
    _sync_default_with_rhythia()

func _sync_default_with_rhythia():
    var colors := _get_colors_from_rhythia()
    presets[DEFAULT_PRESET_NAME] = {"colors": colors}
    if active_preset_name == DEFAULT_PRESET_NAME:
        _apply_active()
        emit_signal("preset_colors_changed", DEFAULT_PRESET_NAME)
    if !_loading:
        _save()
        emit_signal("presets_changed")

func _get_colors_from_rhythia() -> Array:
    if Engine.has_singleton("Rhythia") and Rhythia.selected_colorset:
        var colorset := Rhythia.selected_colorset.colors
        if colorset and colorset.size() > 0:
            return _normalize_colors(colorset)
    return _normalize_colors([Color("#00ffed"), Color("#ff8ff9")])

func _normalize_colors(colors: Array) -> Array:
    var result := []
    for col in colors:
        if col is Color:
            result.append(col)
        elif typeof(col) == TYPE_STRING:
            result.append(Color(col))
        elif typeof(col) == TYPE_DICTIONARY or typeof(col) == TYPE_ARRAY:
            var parsed = _parse_color(col)
            if parsed:
                result.append(parsed)
    if result.empty():
        result.append(Color.white)
    return result

func _save():
    if _loading:
        return
    var file := File.new()
    var err := file.open(Globals.p(PRESET_FILE), File.WRITE)
    if err != OK:
        push_error("Failed to write presets: %s" % err)
        return
    var data := {
        "active": active_preset_name,
        "presets": {}
    }
    for name in presets.keys():
        var entry := presets[name]
        var colors := []
        for col in entry["colors"]:
            colors.append(col.to_html(true))
        data.presets[name] = {"colors": colors}
    file.store_string(JSON.print(data, "\t"))
    file.close()

func _on_rhythia_colorset_changed(_set):
    _sync_default_with_rhythia()
    if active_preset_name == DEFAULT_PRESET_NAME:
        emit_signal("active_preset_changed", DEFAULT_PRESET_NAME)
