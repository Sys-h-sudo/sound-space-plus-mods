extends VBoxContainer

var _updating: bool = false
var _current_colors: Array = []

onready var preset_selector: OptionButton = $PresetSelectorRow/PresetSelector
onready var create_button: Button = $PresetActions/CreateButton
onready var clone_button: Button = $PresetActions/CloneButton
onready var rename_button: Button = $PresetActions/RenameButton
onready var delete_button: Button = $PresetActions/DeleteButton
onready var default_info: Label = $DefaultInfo
onready var color_list: VBoxContainer = $ColorScroll/Scroll/ColorList
onready var color_template: HBoxContainer = $ColorScroll/Scroll/ColorList/ColorTemplate
onready var add_color_button: Button = $ColorControls/AddColorButton

func _ready():
    color_template.visible = false
    preset_selector.connect("item_selected", self, "_on_preset_selected")
    create_button.connect("pressed", self, "_on_create_pressed")
    clone_button.connect("pressed", self, "_on_clone_pressed")
    rename_button.connect("pressed", self, "_on_rename_pressed")
    delete_button.connect("pressed", self, "_on_delete_pressed")
    add_color_button.connect("pressed", self, "_on_add_color_pressed")
    NoteColorPresets.connect("presets_changed", self, "_on_presets_changed")
    NoteColorPresets.connect("active_preset_changed", self, "_on_active_preset_changed")
    NoteColorPresets.connect("preset_colors_changed", self, "_on_preset_colors_changed")
    _refresh_presets()

func _on_presets_changed():
    _refresh_presets()

func _on_active_preset_changed(name):
    _select_preset(name)
    _refresh_colors()

func _on_preset_colors_changed(name):
    if name == NoteColorPresets.get_active_preset_name():
        _refresh_colors()

func _select_preset(name: String):
    _updating = true
    for i in range(preset_selector.get_item_count()):
        if preset_selector.get_item_text(i) == name:
            preset_selector.select(i)
            break
    _updating = false

func _refresh_presets():
    var names: Array = Array(NoteColorPresets.get_preset_names())
    names.sort()
    var ordered: Array = []
    if NoteColorPresets.has_preset(NoteColorPresets.DEFAULT_PRESET_NAME):
        ordered.append(NoteColorPresets.DEFAULT_PRESET_NAME)
    for name in names:
        if name != NoteColorPresets.DEFAULT_PRESET_NAME:
            ordered.append(name)
    _updating = true
    preset_selector.clear()
    var active_name: String = NoteColorPresets.get_active_preset_name()
    var active_index := 0
    for i in range(ordered.size()):
        var name: String = ordered[i]
        if !NoteColorPresets.has_preset(name):
            continue
        preset_selector.add_item(name)
        if name == active_name:
            active_index = preset_selector.get_item_count() - 1
    preset_selector.select(active_index)
    _updating = false
    _refresh_colors()

func _refresh_colors():
    _updating = true
    var active_name: String = NoteColorPresets.get_active_preset_name()
    _current_colors = NoteColorPresets.get_preset_colors(active_name)
    if _current_colors.empty():
        _current_colors = [Color.white]
    for child in color_list.get_children():
        if child != color_template:
            child.queue_free()
    var editable: bool = !NoteColorPresets.is_default(active_name)
    default_info.visible = !editable
    rename_button.disabled = !editable
    delete_button.disabled = !editable
    add_color_button.disabled = !editable
    for i in range(_current_colors.size()):
        var row: HBoxContainer = color_template.duplicate()
        row.visible = true
        row.name = "ColorRow_%s" % i
        var label: Label = row.get_node("Label")
        label.text = "Color %s" % (i + 1)
        var picker: ColorPickerButton = row.get_node("Picker")
        picker.color = _current_colors[i]
        picker.disabled = !editable
        if picker.is_connected("color_changed", self, "_on_color_changed"):
            picker.disconnect("color_changed", self, "_on_color_changed")
        picker.connect("color_changed", self, "_on_color_changed", [i])
        var remove_button: Button = row.get_node("RemoveButton")
        remove_button.disabled = !editable or _current_colors.size() <= 1
        remove_button.visible = editable
        if remove_button.is_connected("pressed", self, "_on_remove_color_pressed"):
            remove_button.disconnect("pressed", self, "_on_remove_color_pressed")
        remove_button.connect("pressed", self, "_on_remove_color_pressed", [i])
        color_list.add_child(row)
    _updating = false

func _on_preset_selected(index: int):
    if _updating:
        return
    var name: String = preset_selector.get_item_text(index)
    NoteColorPresets.set_active_preset(name)

func _on_create_pressed():
    var name = yield(_ask_for_name("Create Note Preset", "Enter a name for the new note color preset", "New Preset"), "completed")
    if name == "":
        return
    var base_colors = NoteColorPresets.get_preset_colors(NoteColorPresets.DEFAULT_PRESET_NAME)
    NoteColorPresets.create_preset(name, base_colors)
    NoteColorPresets.set_active_preset(name)

func _on_clone_pressed():
    var source := NoteColorPresets.get_active_preset_name()
    var suggestion := "%s Copy" % source
    var name = yield(_ask_for_name("Clone Note Preset", "Enter a name for the cloned preset", suggestion), "completed")
    if name == "" or name == source:
        return
    if NoteColorPresets.clone_preset(source, name):
        NoteColorPresets.set_active_preset(name)

func _on_rename_pressed():
    var active := NoteColorPresets.get_active_preset_name()
    if NoteColorPresets.is_default(active):
        return
    var name = yield(_ask_for_name("Rename Note Preset", "Enter a new name for the preset", active, active), "completed")
    if name == "" or name == active:
        return
    if NoteColorPresets.rename_preset(active, name):
        NoteColorPresets.set_active_preset(name)

func _on_delete_pressed():
    var active := NoteColorPresets.get_active_preset_name()
    if NoteColorPresets.is_default(active):
        return
    Globals.confirm_prompt.open(
        "Delete preset '%s'? This cannot be undone." % active,
        "Delete Note Preset",
        [
            { text = "Cancel" },
            { text = "Delete" }
        ]
    )
    Globals.confirm_prompt.s_alert.play()
    var response: int = yield(Globals.confirm_prompt, "option_selected")
    Globals.confirm_prompt.close()
    if response == 1:
        Globals.confirm_prompt.s_next.play()
        yield(Globals.confirm_prompt, "done_closing")
        NoteColorPresets.delete_preset(active)
    else:
        Globals.confirm_prompt.s_back.play()

func _on_add_color_pressed():
    var active := NoteColorPresets.get_active_preset_name()
    if NoteColorPresets.is_default(active):
        return
    var new_color: Color = _current_colors[-1] if _current_colors.size() > 0 else Color.white
    NoteColorPresets.add_color(active, new_color)

func _on_remove_color_pressed(index: int):
    var active := NoteColorPresets.get_active_preset_name()
    if NoteColorPresets.is_default(active):
        return
    NoteColorPresets.remove_color(active, index)

func _on_color_changed(color: Color, index: int):
    if _updating:
        return
    var active := NoteColorPresets.get_active_preset_name()
    if NoteColorPresets.is_default(active):
        return
    NoteColorPresets.update_color(active, index, color)

func _ask_for_name(title: String, body: String, initial_text: String="", existing_name: String="") -> GDScriptFunctionState:
    return _ask_for_name_impl(title, body, initial_text, existing_name)

func _ask_for_name_impl(title: String, body: String, initial_text: String, existing_name: String) -> String:
    var prompt_title := title
    var current_text := initial_text
    while true:
        Globals.string_prompt.open(body, prompt_title, current_text, [
            { text = "OK" },
            { text = "Cancel", wait = 0 }
        ])
        Globals.string_prompt.input.text = current_text
        Globals.string_prompt.input.caret_position = Globals.string_prompt.input.text.length()
        Globals.string_prompt.s_alert.play()
        var response: int = yield(Globals.string_prompt, "option_selected")
        var value: String = Globals.string_prompt.input.get_text().strip_edges()
        Globals.string_prompt.close()
        if response != 0:
            return ""
        if value == "":
            prompt_title = "Name cannot be empty"
            current_text = value
            continue
        if value != existing_name and NoteColorPresets.has_preset(value):
            prompt_title = "Preset already exists"
            current_text = value
            continue
        return value
