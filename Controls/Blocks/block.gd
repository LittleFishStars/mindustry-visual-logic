class_name Block
extends BaseBlock


static func kinds() -> Array[String]:
	return BlockData.kinds()

static func blocks() -> Dictionary:
	return BlockData.blocks()


func _init(kind: String, block_name: String) -> void:
	var block = BlockData.get_block(kind, block_name)
	super(block.get("template", ""), block.get("options", {}))
