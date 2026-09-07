extends RefCounted
## Source geometry is always loaded from the owner's converted JAR.
static func prefetch() -> void: pass
static func collect_ready() -> void: pass
static func entry_for(_id: int) -> Dictionary: return {}
static func path_for(_id: int) -> String: return ""
static func create(_id: int, _bounds: AABB) -> Node3D: return null
static func all_meshes(node: Node) -> Array:
	var result: Array=[]
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(all_meshes(child))
	return result

static func apply_materials(_node: Node, _entry: Dictionary) -> void: pass
