class_name Block
extends BaseBlock


var BlockData := preload("res://Scripts/block_data.gd").new()

var kinds: Array[String] = self.BlockData.BLOCKS.keys()
var blocks: Array[String] = kinds.reduce(func(acc, k): 
	acc[k] = self.BlockData.BLOCKS.get(k).keys()
	return acc
, {})


func _init(kind: String, block_name: String) -> void:
	var block: Dictionary[String, Dictionary] = self.BlockData.BLOCKS.get(kind, {}).get(block_name, {})
	var template: String = block.get("template", "")
	var options: Dictionary[String, Dictionary] = block.get("options", "")
	super(template, options)
