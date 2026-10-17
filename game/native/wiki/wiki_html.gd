extends RefCounted
## Turns a reference page into RichTextLabel markup. Only the catalog's small
## HTML subset is understood; figures, scripts and styles are left out, and
## only wiki:// links become clickable. Text is escaped again for BBCode.

static func to_bbcode(html: String, heading: Color, faint: Color, scale := 1.0) -> String:
	var parser := XMLParser.new()
	if parser.open_buffer(("<div>" + html + "</div>").to_utf8_buffer()) != OK: return ""
	var out := ""
	var skipped := 0
	var anchors: Array[bool] = []
	while parser.read() == OK:
		var type := parser.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name().to_lower()
			if skipped > 0:
				if not parser.is_empty(): skipped += 1
				continue
			if tag in ["figure", "script", "style", "svg"]:
				if not parser.is_empty(): skipped = 1
				continue
			match tag:
				"h1": out += "[font_size=%d][color=#%s]" % [roundi(30 * scale), heading.to_html(false)]
				"h2": out += "[font_size=%d] [/font_size]\n[font_size=%d][color=#%s]" % [roundi(10 * scale), roundi(22 * scale), heading.to_html(false)]
				"strong", "b": out += "[b]"
				"em", "i": out += "[i][color=#%s]" % faint.to_html(false)
				"br": out += "\n"
				"li": out += "  •  "
				"table": out += "[table=%d]" % clampi(parser.get_named_attribute_value_safe("data-columns").to_int(), 1, 12)
				"td": out += "[cell padding=6,4,10,4]"
				"th": out += "[cell padding=6,4,10,4][b][color=#%s]" % faint.to_html(false)
				"a":
					var href := parser.get_named_attribute_value_safe("href")
					var allowed := not key_from_url(href).is_empty()
					anchors.append(allowed)
					if allowed: out += "[url=%s]" % href
		elif type == XMLParser.NODE_ELEMENT_END:
			if skipped > 0:
				skipped -= 1
				continue
			match parser.get_node_name().to_lower():
				"h1", "h2": out += "[/color][/font_size]\n"
				"strong", "b": out += "[/b]"
				"em", "i": out += "[/color][/i]"
				"p", "ul": out += "\n[font_size=%d] [/font_size]\n" % roundi(8 * scale)
				"li": out += "\n"
				"table": out += "[/table]\n\n"
				"td": out += "[/cell]"
				"th": out += "[/color][/b][/cell]"
				"a":
					if not anchors.is_empty() and anchors.pop_back(): out += "[/url]"
		elif type == XMLParser.NODE_TEXT and skipped == 0:
			out += parser.get_node_data().replace("[", "[lb]")
	return out.strip_edges()

## The page key of a wiki:// link, or "" for anything else. Generated keys
## hold no brackets, quotes, spaces or path steps, so a link cannot break out
## of its tag.
static func key_from_url(url: String) -> String:
	if not url.begins_with("wiki://"): return ""
	var key := url.trim_prefix("wiki://")
	for bad: String in ["[", "]", "\"", "'", "<", ">", " ", "\n", "\r", "\t", "..", "\\"]:
		if bad in key: return ""
	return key

## Every page a page links to, in order, once each.
static func links(html: String) -> Array:
	var result: Array = []
	for found in RegEx.create_from_string("wiki://([a-z]+/?[a-z0-9]*)").search_all(html):
		var key := found.get_string(1)
		if not key in result: result.append(key)
	return result
