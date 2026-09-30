extends RefCounted


## Attaches held props (socket name -> PackedScene) to a character model's skeleton. Each prop goes
## on a BoneAttachment3D for the bone its socket maps to in the rig's SocketMap, so bone names live
## only in the SocketMap. Prop alignment lives in the prop scene (a wrapper with a child Transform3D).
static func attach(model_node: Node, socket_map: SocketMap, held_props: Dictionary, owner_name: String) -> void:
	if held_props.is_empty():
		return
	var skeletons: Array[Node] = model_node.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or not socket_map:
		push_warning("%s: held_props set but no Skeleton3D or socket_map" % owner_name)
		return
	var skeleton := skeletons[0] as Skeleton3D
	for socket in held_props:
		var bone := socket_map.get_bone(socket)
		if skeleton.find_bone(bone) == -1:
			push_warning("%s: socket '%s' maps to missing bone '%s'" % [owner_name, socket, bone])
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Socket_" + socket
		attachment.bone_name = bone
		skeleton.add_child(attachment)
		attachment.add_child((held_props[socket] as PackedScene).instantiate())
