class_name Block
extends BaseBlock


func _init(kind: String, block_name: String) -> void:
	var block = BlockData.get_block(kind, block_name)
	super(
		block.get("template", ""), 
		block.get("options", {}), 
		BlockData.COLORS.get(kind, Color.WHITE)
	)
