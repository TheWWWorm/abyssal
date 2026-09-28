extends RefCounted
## Colours and frames for the menus: translucent glass panels with cut corners
## and a lit cyan edge, over the docked station. With every medal at gold the
## whole interface turns gold, as the phone game's does.

static func palette(gold: bool) -> Dictionary:
	if gold:
		return {"accent":Color("f1d27a"),"text":Color("f6ecd0"),"dim":Color("bfae84"),"faint":Color("8a7a55"),
			"value":Color("ffe39a"),"good":Color("c9e89a"),"bad":Color("f0907a"),
			"panel":Color(.1,.08,.03,.86),"card":Color(.14,.11,.04,.72),"card_hi":Color(.29,.22,.08,.9),
			"edge":Color("8a774d"),"edge_hi":Color("f1d27a"),"glow":Color(.95,.8,.4,.22),
			"go":Color(.2,.24,.08,.92),"go_hi":Color(.3,.36,.1,.95),"go_edge":Color("d8e27a"),"go_text":Color("f6f8d8")}
	return {"accent":Color("5fd4f0"),"text":Color("e3f4fa"),"dim":Color("93bccb"),"faint":Color("5d8797"),
		"value":Color("e9d27c"),"good":Color("8fe6a4"),"bad":Color("f08a7a"),
		"panel":Color(.016,.07,.1,.86),"card":Color(.03,.11,.15,.74),"card_hi":Color(.05,.21,.28,.92),
		"edge":Color("2b7894"),"edge_hi":Color("8eeaff"),"glow":Color(.25,.8,1.0,.2),
		"go":Color(.05,.22,.14,.9),"go_hi":Color(.08,.33,.2,.95),"go_edge":Color("6fe39a"),"go_text":Color("e2ffe9")}

static func frame(fill: Color, edge: Color, cut: int, width := 1, glow := Color(0,0,0,0), glow_size := 0) -> StyleBoxFlat:
	"""Cut top-right and bottom-left corners, square elsewhere."""
	var style := StyleBoxFlat.new()
	style.bg_color=fill;style.border_color=edge;style.set_border_width_all(width)
	style.corner_detail=1;style.anti_aliasing=true
	style.corner_radius_top_right=cut;style.corner_radius_bottom_left=cut
	style.corner_radius_top_left=mini(3,cut);style.corner_radius_bottom_right=mini(3,cut)
	if glow_size>0: style.shadow_color=glow;style.shadow_size=glow_size
	return style

static func panel(gold: bool) -> StyleBoxFlat:
	var colours := palette(gold)
	var style := frame(colours.panel,colours.edge.lerp(colours.edge_hi,.35),18,1,colours.glow,10)
	style.content_margin_left=24;style.content_margin_right=24;style.content_margin_top=16;style.content_margin_bottom=12
	return style

static func card(gold: bool, lit := false, cut := 12) -> StyleBoxFlat:
	var colours := palette(gold)
	var style := frame(colours.card_hi if lit else colours.card,colours.edge_hi if lit else colours.edge,cut,2 if lit else 1,colours.glow,8 if lit else 0)
	style.set_content_margin_all(12)
	return style

static func button_state(gold: bool, state: String, primary := false, cut := 8) -> StyleBoxFlat:
	var colours := palette(gold)
	var lit: bool=state in ["focus","hover","pressed"]
	var style: StyleBoxFlat
	if state=="disabled":
		style=frame(Color(colours.card,.4),Color(colours.edge,.45),cut)
	elif primary:
		style=frame(colours.go_hi if lit else colours.go,colours.go_edge.lightened(.3) if lit else colours.go_edge,cut,2 if lit else 1,Color(colours.go_edge,.3),10 if lit else 5)
	else:
		style=frame(colours.card_hi if lit else colours.card,colours.edge_hi if lit else colours.edge,cut,2 if lit else 1,colours.glow,8 if lit else 0)
	style.content_margin_left=14;style.content_margin_right=16;style.content_margin_top=6;style.content_margin_bottom=6
	return style

static func spaced(base: Font, spacing: int, bold := false) -> FontVariation:
	"""The wide tracking of the headings."""
	var font := FontVariation.new();font.base_font=base;font.spacing_glyph=spacing
	if bold: font.variation_embolden=.5
	return font

static var _marks := {}
static func mark(kind: String, tint: Color, extent: int) -> ImageTexture:
	"""Small drawn textures for the lists: a chevron, a lit dot for the
	chosen item and an empty square of the same size to keep text aligned."""
	var key := "%s/%s/%d"%[kind,tint.to_html(),extent]
	if _marks.has(key): return _marks[key]
	var scale := 4
	var side := extent*scale
	var image := Image.create(side,side,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	match kind:
		"down":
			var width := side*.11
			for y in side:
				for x in side:
					var u := float(x)/side-.5;var v := float(y)/side-.5
					# Two strokes meeting at the bottom centre.
					var d := minf(_segment(Vector2(u,v),Vector2(-.3,-.12),Vector2(0,.16)),_segment(Vector2(u,v),Vector2(.3,-.12),Vector2(0,.16)))
					if d*side<width:image.set_pixel(x,y,tint)
		"dot":
			for y in side:
				for x in side:
					var r := Vector2(float(x)/side-.5,float(y)/side-.5).length()
					if r<.22:image.set_pixel(x,y,tint)
					elif r<.3:image.set_pixel(x,y,Color(tint,.25))
	image.resize(extent,extent,Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_marks[key]=texture
	return texture

static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
	return p.distance_to(a+(b-a)*t)

static func style_popup(popup: PopupMenu, gold: bool, touch := false) -> void:
	"""A dropdown's list: the panel glass, a lit row under the pointer and a
	dot beside the current choice."""
	var colours := palette(gold)
	var back := frame(Color(colours.panel,.97),colours.edge_hi.lerp(colours.edge,.4),10,1,colours.glow,10)
	back.content_margin_left=6;back.content_margin_right=6;back.content_margin_top=6;back.content_margin_bottom=6
	popup.add_theme_stylebox_override("panel",back)
	var lit := frame(colours.card_hi,colours.edge_hi,6,1)
	popup.add_theme_stylebox_override("hover",lit)
	popup.add_theme_stylebox_override("focus",lit)
	popup.add_theme_color_override("font_color",colours.text)
	popup.add_theme_color_override("font_hover_color",Color.WHITE)
	popup.add_theme_color_override("font_disabled_color",colours.faint)
	popup.add_theme_color_override("font_separator_color",colours.dim)
	popup.add_theme_font_size_override("font_size",20 if touch else 16)
	popup.add_theme_constant_override("v_separation",22 if touch else 12)
	popup.add_theme_constant_override("h_separation",12)
	popup.add_theme_constant_override("item_start_padding",12)
	popup.add_theme_constant_override("item_end_padding",16)
	var size := 18 if touch else 14
	popup.add_theme_icon_override("radio_checked",mark("dot",colours.value,size))
	popup.add_theme_icon_override("radio_unchecked",mark("none",colours.value,size))
	popup.add_theme_icon_override("checked",mark("dot",colours.value,size))
	popup.add_theme_icon_override("unchecked",mark("none",colours.value,size))

static func style_option(node: OptionButton, gold: bool, touch := false) -> void:
	"""A dropdown in the station's frame, with its list to match."""
	var colours := palette(gold)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := button_state(gold,state)
		style.content_margin_left=14;style.content_margin_right=12
		node.add_theme_stylebox_override(state,style)
	node.add_theme_color_override("font_color",colours.text)
	node.add_theme_color_override("font_hover_color",Color.WHITE)
	node.add_theme_color_override("font_focus_color",Color.WHITE)
	node.add_theme_color_override("font_pressed_color",Color.WHITE)
	node.add_theme_color_override("font_disabled_color",colours.faint)
	node.add_theme_font_size_override("font_size",18 if touch else 15)
	node.add_theme_icon_override("arrow",mark("down",colours.accent,18 if touch else 14))
	node.add_theme_constant_override("arrow_margin",10)
	style_popup(node.get_popup(),gold,touch)

static func style_field(node: LineEdit, gold: bool, touch := false) -> void:
	"""A text field in the same frame: dim until it has focus."""
	var colours := palette(gold)
	var idle := frame(Color(colours.card,.6),colours.edge,8)
	var lit := frame(colours.card_hi,colours.edge_hi,8,2,colours.glow,6)
	for style in [idle,lit]:
		style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=6;style.content_margin_bottom=6
	node.add_theme_stylebox_override("normal",idle)
	node.add_theme_stylebox_override("focus",lit)
	node.add_theme_stylebox_override("read_only",idle)
	node.add_theme_color_override("font_color",colours.text)
	node.add_theme_color_override("font_placeholder_color",colours.faint)
	node.add_theme_color_override("caret_color",colours.accent)
	node.add_theme_color_override("selection_color",Color(colours.accent,.35))
	node.add_theme_font_size_override("font_size",18 if touch else 15)
