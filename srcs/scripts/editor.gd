extends Control


@export var list_separation: int = 10

@onready var nBlockKindList: VBoxContainer = $Editor/BlockKindList
@onready var nBlockArea: ScrollContainer = $Editor/EditorSplit/BlockArea

@onready var nArea: SubViewportContainer = $Editor/EditorSplit/EditArea
@onready var nSpace: SubViewport = $Editor/EditorSplit/EditArea/EditSpace
@onready var nCamera: Camera2D = $Editor/EditorSplit/EditArea/EditSpace/Camera
@onready var nDragger: Node2D = $Dragger

var _block_data: Dictionary
var _current_kind: String


func _ready() -> void:
	_block_data = BlockParse.new().parse()
	for kind in _block_data:
		# 类别列表
		var btn := Button.new()
		btn.text = kind
		btn.pressed.connect(func(): _show_kind(kind))
		nBlockKindList.add_child(btn)
		
		# 块列表
		var kind_list := VBoxContainer.new()
		kind_list.name = kind
		kind_list.size_flags_horizontal = true
		kind_list.size_flags_vertical = true
		kind_list.add_theme_constant_override("separation", self.list_separation)
		kind_list.hide()
		
		# 填充块列表
		for block_name in _block_data[kind]["blocks"]:
			var block := Block.new(
				_block_data[kind]["blocks"][block_name], 
				_block_data[kind]["color"]
			)
			block.drag_started.connect(nDragger.start_drag.bind(block, true))
			kind_list.add_child(block)
		nBlockArea.add_child(kind_list)
	_show_kind(_block_data.keys()[0])


## 切换类别显示
func _show_kind(kind: String) -> void:
	if kind == _current_kind:
		return
	if _current_kind:
		nBlockArea.get_node(_current_kind).hide()
	_current_kind = kind
	nBlockArea.get_node(kind).show()
