extends VBoxContainer
## Shared title/in-dive spacing controls, backed by the same saved preference.
signal changed
const Spacing=preload("res://native/simulation/world_spacing.gd")
var settings=Spacing.new()
var selector:=OptionButton.new()
var custom:=SpinBox.new()
var explanation:=Label.new()
var custom_row:=HBoxContainer.new()

func configure(preference) -> void:
	settings=preference
	add_theme_constant_override("separation",12)
	selector.name="WorldSpacingPreset"
	for id in Spacing.ORDER:selector.add_item(Spacing.NAMES[id],id)
	selector.custom_minimum_size.y=44
	selector.select(selector.get_item_index(settings.preset));add_child(selector)
	var caption:=Label.new();caption.text="Custom distance (m)";caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	custom_row.add_child(caption);add_child(custom_row)
	custom.name="WorldSpacingCustom";custom.min_value=Spacing.MIN_METERS;custom.max_value=Spacing.ORIGINAL_METERS
	custom.allow_greater=true;custom.step=1;custom.rounded=true;custom.value=settings.custom_meters
	custom.custom_minimum_size=Vector2(170,44);custom_row.add_child(custom)
	custom.get_line_edit().virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER
	custom.tooltip_text="At least 400 metres per map unit. Enter a number, then press Enter or leave the field."
	explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;explanation.add_theme_font_size_override("font_size",15)
	add_child(explanation)
	selector.item_selected.connect(func(index):settings.preset=selector.get_item_id(index);refresh();changed.emit())
	custom.value_changed.connect(func(value):settings.custom_meters=Spacing.valid_meters(value);refresh();changed.emit())
	refresh()

func refresh() -> void:
	custom_row.visible=settings.preset==Spacing.Preset.CUSTOM
	explanation.text="Metres per map unit; distances between stations follow their map positions. Ship and station sizes stay the same.\nCustom minimum: 400 m."
	if settings.preset==Spacing.Preset.ORIGINAL:
		explanation.text+="\nOriginal uses the original game's 18.85 km distance conversion. Expect much longer journeys."
