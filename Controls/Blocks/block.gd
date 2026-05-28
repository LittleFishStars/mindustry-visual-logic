class_name Block
extends BaseBlock


var _kind: String
var _block_name: String


func _init(kind: String, block_name: String) -> void:
	self._kind = kind
	self._block_name = block_name
	
	var block = BlockData.get_block(kind, block_name)
	super(
		block.get("template", ""), 
		block.get("options", {}), 
		block.get("export", {}), 
		BlockData.COLORS.get(kind, Color.WHITE)
	)
