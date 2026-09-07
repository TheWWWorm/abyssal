extends RefCounted
## al mission state. Narrative and chapter templates are imported owner content.
const Math = preload("res://native/simulation/fixed_math.gd")
var kind := -1
var sponsor := ""
var sponsor_faction := 0
var portrait: Array = []
var reward := 0
var deposit := 0
var destination := 0
var destination_name := ""
var difficulty := 0
var jump_limit := -1
var jumps := -1
var terminal := false
var story := false
var failed := false
var completed := false
var briefing := false
var item_id := 0
var item_count := 0
var target_kind := 0
var total := 0
var minimum := 0
var percentage := 0
var threshold := 0

func from_record(record: Dictionary) -> void:
	kind=int(record.get("a:int",-1)); sponsor=str(record.get("a:java.lang.String",""))
	sponsor_faction=int(record.get("b:int",0)); reward=int(record.get("c:int",0)); deposit=int(record.get("d:int",0))
	destination=int(record.get("e:int",0)); destination_name=str(record.get("b:java.lang.String",""))
	difficulty=int(record.get("f:int",0)); jump_limit=int(record.get("g:int",-1)); jumps=int(record.get("h:int",-1))
	terminal=record.get("a:boolean",false); story=record.get("b:boolean",false)
	failed=record.get("c:boolean",false); completed=record.get("d:boolean",false); briefing=record.get("e:boolean",false)
	item_id=int(record.get("l:int",0)); item_count=int(record.get("m:int",0))
	target_kind=int(record.get("n:int",0)); total=int(record.get("o:int",0)); minimum=int(record.get("p:int",0))
	percentage=int(record.get("q:int",0)); threshold=int(record.get("r:int",0))

func parameters(target: int, count: int, survivors: int) -> void:
	target_kind=target; total=count; minimum=survivors
	percentage=int(Math.f32(Math.f32(float(survivors)/float(count))*100.0))

func count_jump() -> void:
	if jump_limit > -1: jumps+=1

func expired() -> bool:
	return jumps > jump_limit

func normalized_difficulty(rank: int) -> int:
	return difficulty/clampi(rank/2,1,20)

func values() -> Array:
	return [kind,reward,destination,difficulty,jump_limit,jumps,terminal,story,failed,completed,briefing,item_id,item_count,target_kind,total,minimum,percentage,threshold]
