extends RefCounted
## Unrelated UI checks choose Not now explicitly. Reconstruction's dedicated
## checks exercise the prompt, generation and cancellation instead.
const Dialog = preload("res://native/presentation/reconstruction_dialog.gd")

static func attach(tree: SceneTree) -> void:
	if not tree.process_frame.is_connected(decline):tree.process_frame.connect(decline)

static func decline() -> void:
	if not Dialog.is_open():return
	var dialog=Dialog.current.get_ref()
	if not dialog.busy and dialog.work==null and dialog.actions.has_node("Later"):dialog.choose("later")
