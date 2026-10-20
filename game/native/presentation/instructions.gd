extends RefCounted
## The phone game's Help: its Instructions, ten topics of the imported
## text (e.a titles, e.b bodies; the first gathers the tutorial's own
## cards), and its Controls, the same actions on this engine's keys.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const TOPICS := [[19,[631,633,642,643,641,664]],[62,[353]],[81,[354]],[37,[356]],[328,[355]],[235,[357]],[267,[358]],[73,[361,362]],[64,[363]],[63,[364]]]
## The phone's keys the texts speak of, and what does their work here.
const KEYS := [["0","Dock / enter the S.T.R.E.A.M.","E"],["5","Fire","Space (left mouse button: guns)"],["1","Change weapon","Tab"],["7","Auto fire","Q"],["9","Autopilot","R (hold: quest)"],["3","Boost","Shift"],["*  0  #","Camera","C"]]

## The imported texts that name a phone key, by text id: each key and the
## action that does its work here, so the card names the control in use.
## "help" is the phone's 0 on a station screen, which opened its Help; here
## that is the station's System page.
const KEYED_TEXTS := {637:{"0":"help"},638:{"0":"help"},270:{"0":"dock"},271:{"0":"dock"},342:{"0":"dock","9":"autopilot"},343:{"0":"dock","9":"autopilot"},346:{"3":"boost"},633:{"9":"autopilot"},641:{"9":"autopilot"},642:{"1":"bank","7":"auto_fire"},649:{"1":"bank"}}

static func with_controls(id: int, text: String, control_name: Callable) -> String:
	"""Text id with its phone keys replaced by control_name(action). Only a
	key standing alone is one, never a digit inside a number or a word, so
	"[TRAVELLING 1]" keeps its 1 and every language's text works alike."""
	if not KEYED_TEXTS.has(id) or not control_name.is_valid():return text
	var keys: Dictionary=KEYED_TEXTS[id]
	var pattern:=RegEx.create_from_string("(?<![\\w.])([%s])(?!\\w)"%"".join(keys.keys()))
	var result:="";var last:=0
	for found in pattern.search_all(text):
		result+=text.substr(last,found.get_start()-last)+str(control_name.call(keys[found.get_string(1)]))
		last=found.get_end()
	return result+text.substr(last)

static func topics(content, control_name:=Callable()) -> Array:
	var result: Array=[]
	for topic in TOPICS:
		var title: String=content.text(int(topic[0]))
		var lines: Array=[]
		for id in topic[1]:
			var line: String=with_controls(int(id),content.text(int(id)),control_name)
			if not line.is_empty():lines.append(line)
		if title.is_empty() or lines.is_empty():continue
		result.append({"title":title,"text":"\n\n".join(lines)})
	return result

static func key_note() -> String:
	var lines: Array=[EngineLanguage.translate("The instructions name the phone's keys. Here:")]
	var keys: Array=[["0",EngineLanguage.translate("Dock / enter the S.T.R.E.A.M."),"E"],["5",EngineLanguage.translate("Fire"),EngineLanguage.translate("Space (left mouse button: guns)")],["1",EngineLanguage.translate("Change weapon"),"Tab"],["7",EngineLanguage.translate("Auto fire"),"Q"],["9",EngineLanguage.translate("Autopilot"),EngineLanguage.translate("R (hold: quest)")],["3",EngineLanguage.translate("Boost"),"Shift"],["*  0  #",EngineLanguage.translate("Camera"),"C"]]
	for entry in keys:lines.append("  %s  ·  %s  →  %s"%[entry[0],entry[1],entry[2]])
	return "\n".join(lines)
