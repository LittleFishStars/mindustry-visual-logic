extends HSplitContainer


@export var list_separation: int = 10

@onready var nBlockKindList: VBoxContainer = $BlockKindList
@onready var nBlockArea: ScrollContainer = $EditorSplit/BlockArea

var _current_kind: String


func _ready() -> void:
	for kind in BlockData.kinds():
		var btn := Button.new()
		btn.text = tr(kind)
		btn.pressed.connect(func(): _show_kind(kind))
		nBlockKindList.add_child(btn)
		var kind_list := VBoxContainer.new()
		kind_list.name = kind
		kind_list.size_flags_horizontal = true
		kind_list.size_flags_vertical = true
		kind_list.add_theme_constant_override("separation", self.list_separation)
		kind_list.hide()
		for block_name in BlockData.blocks()[kind]:
			kind_list.add_child(Block.new(kind, block_name))
		nBlockArea.add_child(kind_list)
	_show_kind(BlockData.kinds()[0])


func _show_kind(kind: String) -> void:
	if kind == _current_kind:
		return
	if _current_kind:
		nBlockArea.get_node(_current_kind).hide()
	_current_kind = kind
	nBlockArea.get_node(kind).show()
