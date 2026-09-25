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
	if primary:
		style=frame(colours.go_hi if lit else colours.go,colours.go_edge.lightened(.3) if lit else colours.go_edge,cut,2 if lit else 1,Color(colours.go_edge,.3),10 if lit else 5)
	elif state=="disabled":
		style=frame(Color(colours.card,.4),Color(colours.edge,.45),cut)
	else:
		style=frame(colours.card_hi if lit else colours.card,colours.edge_hi if lit else colours.edge,cut,2 if lit else 1,colours.glow,8 if lit else 0)
	style.content_margin_left=14;style.content_margin_right=16;style.content_margin_top=6;style.content_margin_bottom=6
	return style

static func spaced(base: Font, spacing: int, bold := false) -> FontVariation:
	"""The wide tracking of the headings."""
	var font := FontVariation.new();font.base_font=base;font.spacing_glyph=spacing
	if bold: font.variation_embolden=.5
	return font
