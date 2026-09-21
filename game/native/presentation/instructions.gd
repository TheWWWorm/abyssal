extends RefCounted
## The phone game's Help: its Instructions, ten topics of the imported
## text (e.a titles, e.b bodies; the first gathers the tutorial's own
## cards), and its Controls, the same actions on this engine's keys.
const TOPICS := [[19,[631,633,642,643,641,664]],[62,[353]],[81,[354]],[37,[356]],[328,[355]],[235,[357]],[267,[358]],[73,[361,362]],[64,[363]],[63,[364]]]
## The phone's keys the texts speak of, and what does their work here.
const KEYS := [["0","Dock / enter the S.T.R.E.A.M.","E"],["5","Fire","Left mouse button / Space"],["1","Change weapon","Q / mouse wheel"],["7","Auto fire","Toggled in Controls"],["9","Autopilot","R (hold: quest)"],["3","Boost","Shift"],["*  0  #","Camera","C"]]

static func topics(content) -> Array:
	var result: Array=[]
	for topic in TOPICS:
		var title: String=content.text(int(topic[0]))
		var lines: Array=[]
		for id in topic[1]:
			var line: String=content.text(int(id))
			if not line.is_empty():lines.append(line)
		if title.is_empty() or lines.is_empty():continue
		result.append({"title":title,"text":"\n\n".join(lines)})
	return result

static func key_note() -> String:
	var lines: Array=["The instructions name the phone's keys. Here:"]
	for entry in KEYS:lines.append("  %s  ·  %s  →  %s"%[entry[0],entry[1],entry[2]])
	return "\n".join(lines)
