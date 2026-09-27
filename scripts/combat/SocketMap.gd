class_name SocketMap
extends Resource

## Maps logical socket names ("hand_r", "hand_l") to one rig's bone names.
## One SocketMap per rig: when a rig changes, update its .tres and nothing else.
@export var bones: Dictionary = {}


func get_bone(socket: String) -> String:
	return str(bones.get(socket, ""))
