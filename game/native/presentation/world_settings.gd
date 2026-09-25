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
	var caption:=Label.new();caption.text="Grid square (km)";caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	custom_row.add_child(caption);add_child(custom_row)
	# Stored as metres per map unit, as before; entered as the size of a square.
	custom.name="WorldSpacingCustom";custom.min_value=Spacing.square_kilometers(Spacing.MIN_METERS);custom.max_value=Spacing.square_kilometers(Spacing.ORIGINAL_METERS)
	custom.allow_greater=true;custom.step=0.025;custom.value=Spacing.square_kilometers(settings.custom_meters)
	custom.custom_minimum_size=Vector2(170,44);custom_row.add_child(custom)
	custom.get_line_edit().virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER
	custom.tooltip_text="At least %s. Enter a number, then press Enter or leave the field."%Spacing.square_text(Spacing.MIN_METERS)
	explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;explanation.add_theme_font_size_override("font_size",15)
	add_child(explanation)
	selector.item_selected.connect(func(index):settings.preset=selector.get_item_id(index);refresh();changed.emit())
	custom.value_changed.connect(func(value):settings.custom_meters=Spacing.valid_meters(value*1000.0/Spacing.GRID_UNITS);refresh();changed.emit())
	refresh()

func refresh() -> void:
	custom_row.visible=settings.preset==Spacing.Preset.CUSTOM
	explanation.text="How wide one square of the map's grid is: %s. Distances between stations follow their map positions. Ship and station sizes stay the same.\nCustom minimum: %s."%[Spacing.square_text(settings.meters()),Spacing.square_text(Spacing.MIN_METERS)]
	if settings.preset==Spacing.Preset.ORIGINAL:
		explanation.text+="\nOriginal uses the original game's distance conversion. Expect much longer journeys."

static func gate_text(split: bool) -> String:
	return "S.T.R.E.A.M. gates · "+("Separate · arrive by IN, leave by OUT" if split else "Shared · one gate both ways")
