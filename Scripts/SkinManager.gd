extends Node

const SKIN_CLASSIC := "classic"
const SKIN_NEON := "neon"

static func current_skin() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_meta("skin_id"):
		return str(tree.root.get_meta("skin_id"))
	return SKIN_CLASSIC
