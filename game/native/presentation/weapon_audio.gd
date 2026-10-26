extends RefCounted
## Individual prepared launch designs; no runtime synthesis or stat-based repitch.
## Source hashes and the reproducible layer recipes live in provenance/weapon-audio.json.
const RATE := 48000
const VARIATIONS := 3
const FAMILIES := ["gun","beam","plasma","mass","torpedo","eclipse"]
const BANKS := ["gun","gun-ii","gun-iii","beam","beam-ii","beam-iii","plasma","plasma-ii","plasma-iii","mass","mass-ii","mass-iii","torpedo","torpedo-ii","torpedo-iii","eclipse"]
const EQUIPMENT_BANK := {0:"gun",1:"gun-ii",2:"gun-iii",3:"beam",4:"beam-ii",5:"beam-iii",6:"plasma",7:"plasma-ii",8:"plasma-iii",9:"mass",10:"mass-ii",11:"mass-iii",12:"torpedo",13:"torpedo-ii",14:"torpedo-iii",42:"eclipse"}
# Calibrated mix trims complement the distinct source bodies; they do not
# change pitch, charge time or the authored propulsion/decay envelopes.
const LEVEL_DB := {"gun":1.5,"gun-ii":2.0,"gun-iii":3.0,"beam":1.0,"beam-ii":2.0,"beam-iii":3.0,"plasma":0.0,"plasma-ii":.8,"plasma-iii":1.0,"mass":0.0,"mass-ii":1.5,"mass-iii":2.8,"torpedo":0.0,"torpedo-ii":.6,"torpedo-iii":1.8,"eclipse":3.0}
const DIRECTORY := "res://audio/weapons/"

static func profile(weapon) -> Dictionary:
	var kind:=bank(weapon)
	return {"bank":kind,"pitch":1.0,"db":float(LEVEL_DB.get(kind,0.0))}

static func path(kind: String, variation: int=0) -> String:
	return DIRECTORY+"%s-%d.wav"%[kind,posmod(variation,VARIATIONS)+1]

static func sample(kind: String, variation: int=0) -> AudioStreamWAV:
	return load(path(kind,variation)) as AudioStreamWAV

static func bank(weapon) -> String:
	if weapon.fishing:return "harpoon"
	if EQUIPMENT_BANK.has(weapon.equipment_id):return EQUIPMENT_BANK[weapon.equipment_id]
	# Shared NPC pools can carry only the original projectile model identity.
	if weapon.model_id in [6754,6755,6756]:return EQUIPMENT_BANK[weapon.model_id-6754]
	if weapon.model_id in [6760,6761,6762,6763,6764,6765]:return EQUIPMENT_BANK[weapon.model_id-6754]
	return family(weapon)

static func family(weapon) -> String:
	if weapon.fishing:return "harpoon"
	if weapon.homing:return "torpedo"
	if weapon.beam:return "beam"
	if weapon.equipment_id==42 or weapon.model_id in [6766,6767]:return "eclipse"
	if weapon.equipment_id in [9,10,11] or weapon.model_id in [6763,6764,6765]:return "mass"
	if weapon.equipment_id in [6,7,8] or weapon.model_id in [6760,6761,6762]:return "plasma"
	return "gun"
