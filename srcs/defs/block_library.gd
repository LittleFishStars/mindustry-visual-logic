class_name BlockLibrary
extends RefCounted

## 块定义库：把 `blocks/{locale}/*.xml` 解析成 [BlockDef] 对象。
##
## 这是旧 `BlockParse` 的替代品，但有两点不同：
## [br]1. 解析结果有类型（[BlockDef] / [ElementDef] / [ExportPart] / [ActionDef]），
##    视图与导出不必再按字符串键猜结构；
## [br]2. 解析器[b]不认识具体元素种类[/b]：任何没有特殊语义的标签都会变成一个
##    通用元素（属性原样收进 [member ElementDef.attrs]），所以新增元素类型不必改本文件。
##
## 兼容旧写法：`export="drawflush %display"` 仍然可用；新增的结构化写法：
## [codeblock]
## <Block name="Print">
##   <Text id="T1">Print</Text>
##   <LineBox id="value" placeholder="text" />
##   <Export>
##     <Literal>print</Literal>          <!-- 字面量可以含空格 -->
##     <Field id="value" />
##   </Export>
##   <Event on="field_changed" field="value">
##     <SetField id="x" value="0" />
##     <SetVisible ids="T1 !T2" />
##   </Event>
##   <!-- 自定义控件：候选取自 blocks/selectors/{kind}.json -->
##   <Selector id="unit" kind="units" />
##   <!-- 复杂交互：挂一个脚本，实现约定钩子即可 -->
##   <Script path="res://srcs/defs/behaviors/unit_bind.gd" />
## </Block>
## [/codeblock]

class Kind extends RefCounted:
	var id: StringName = &""
	var color: Color = Color.WHITE
	var blocks: Array[BlockDef] = []

	func _init(p_id: StringName = &"", p_color: Color = Color.WHITE) -> void:
		id = p_id
		color = p_color


const DIR: String = "res://blocks"
const FALLBACK_LANG: String = "en_US"

## 解析过程中的问题（缺文件、重名等），供编辑器提示用。
var warnings: PackedStringArray = []
var kinds: Array[Kind] = []

var _by_id: Dictionary[StringName, BlockDef] = {}
var _kind_of: Dictionary[StringName, StringName] = {}


## 读取当前语言的定义；该语言目录不存在时回退到 [constant FALLBACK_LANG]。
static func load_localized(locale: String = "") -> BlockLibrary:
	var library := BlockLibrary.new()
	var lang := locale if locale != "" else OS.get_locale()
	var dir := DIR.path_join(lang)
	if not DirAccess.dir_exists_absolute(dir):
		dir = DIR.path_join(FALLBACK_LANG)
	library.load_dir(dir)
	return library


func load_dir(dir: String) -> void:
	kinds.clear()
	_by_id.clear()
	_kind_of.clear()
	warnings.clear()
	if not DirAccess.dir_exists_absolute(dir):
		warnings.append("块定义目录不存在：%s" % dir)
		return
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file_name in files:
		if file_name.get_extension().to_lower() != "xml":
			continue
		_parse_file(dir.path_join(file_name))


func by_id(block_id: StringName) -> BlockDef:
	return _by_id.get(block_id)


func has(block_id: StringName) -> bool:
	return _by_id.has(block_id)


func block_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_by_id.keys())
	return out


func kind_of(block_id: StringName) -> StringName:
	return _kind_of.get(block_id, &"")


func kind(kind_id: StringName) -> Kind:
	for item in kinds:
		if item.id == kind_id:
			return item
	return null


#region 解析

func _parse_file(path: String) -> void:
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		warnings.append("无法打开块定义：%s" % path)
		return
	var current_kind: Kind = null
	var block: BlockDef = null
	var option_element: ElementDef = null
	var action: ActionDef = null
	# 处于 <Pressed>/<Released> 内时的导出变体
	var variant_target: BlockDef.ExportVariant = null
	# 下一个文本节点该写给谁（Text / Item / Literal）
	var text_target: Variant = null
	var order := 0

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name()
				var attrs := _attrs(xml)
				var self_closing := xml.is_empty()
				text_target = null
				match tag:
					"Kind":
						current_kind = Kind.new(
							StringName(attrs.get("name", "")),
							_parse_hex_color(String(attrs.get("color", "#FFFFFF")))
						)
						order = 0
						kinds.append(current_kind)
					"Block":
						if current_kind == null:
							warnings.append("%s：<Block> 不在 <Kind> 内" % path)
						else:
							block = _make_block(attrs, current_kind, order)
							order += 1
					"Export":
						pass
					"Literal":
						if block != null:
							var part := ExportPart.make_literal("")
							part.space_before = _space_before(attrs)
							_export_target(block, variant_target).append(part)
							text_target = part
					"Field":
						if block != null:
							var field_part := ExportPart.make_field(StringName(attrs.get("id", "")))
							field_part.space_before = _space_before(attrs)
							_export_target(block, variant_target).append(field_part)
					"FirstOf":
						if block != null:
							_export_target(block, variant_target).append(
								ExportPart.make_first_visible(_ids(String(attrs.get("ids", ""))))
							)
					"Item":
						if option_element != null:
							var item := ElementDef.OptionItem.new("", _visibility(attrs.get("show", "")))
							item.value = String(attrs.get("value", ""))
							option_element.items.append(item)
							text_target = item
					"Pressed":
						variant_target = _begin_button_state(block, attrs, true)
					"Released":
						variant_target = _begin_button_state(block, attrs, false)
					"Event":
						if block != null:
							action = ActionDef.new()
							action.trigger = ActionDef.trigger_from(String(attrs.get("on", "field_changed")))
							action.field = StringName(attrs.get("field", ""))
							block.actions.append(action)
					"SetField":
						if action != null:
							action.do = ActionDef.Do.SET_FIELD
							action.target = StringName(attrs.get("id", ""))
							action.value = attrs.get("value", "")
					"SetVisible":
						if action != null:
							action.do = ActionDef.Do.SET_VISIBLE
							action.ids = _ids(String(attrs.get("ids", "")))
					"Call":
						if action != null:
							action.do = ActionDef.Do.CALL_BEHAVIOR
							action.target = StringName(attrs.get("method", attrs.get("id", "")))
					"Script":
						if block != null:
							block.behavior_path = String(attrs.get("path", ""))
					_:
						if block != null:
							var element := _make_element(tag, attrs)
							block.elements.append(element)
							if tag == "Option":
								option_element = element
							if tag == "Text":
								text_target = element
				if self_closing:
					text_target = null
					if tag == "Option":
						option_element = null
			XMLParser.NODE_TEXT:
				if text_target != null:
					var text := xml.get_node_data()
					if text != "":
						text_target.set_text(text)
			XMLParser.NODE_ELEMENT_END:
				match xml.get_node_name():
					"Text", "Item", "Literal":
						text_target = null
					"Option":
						option_element = null
					"Event":
						action = null
					"Pressed", "Released":
						_end_button_state(block, variant_target)
						variant_target = null
					"Block":
						if block != null:
							block.build_index()
						block = null
					"Kind":
						current_kind = null

	if block != null:
		block.build_index()


func _make_block(attrs: Dictionary, current_kind: Kind, order: int) -> BlockDef:
	var block := BlockDef.new(StringName(attrs.get("name", "")), current_kind.id)
	block.color = current_kind.color
	block.order = order
	block.export_parts = _legacy_export_parts(String(attrs.get("export", "")))
	block.behavior_path = String(attrs.get("script", ""))
	if block.id == &"":
		warnings.append("存在没有 name 的 <Block>（%s）" % current_kind.id)
	elif _by_id.has(block.id):
		warnings.append("块 id 重复：%s" % block.id)
	else:
		_by_id[block.id] = block
		_kind_of[block.id] = current_kind.id
	# 索引等元素全部解析完后再建（见 NODE_ELEMENT_END 的 Block 分支）
	current_kind.blocks.append(block)
	return block


func _make_element(tag: String, attrs: Dictionary) -> ElementDef:
	var element := ElementDef.new(StringName(tag), StringName(attrs.get("id", "")))
	element.attrs = attrs.duplicate()
	element.text = String(attrs.get("text", ""))
	element.placeholder = String(attrs.get("placeholder", ""))
	element.selector_kind = StringName(attrs.get("kind", ""))
	element.visible = _visibility(attrs.get("show", ""))
	if tag == "Option":
		element.default_index = int(attrs.get("default", 0))
	else:
		element.default_value = String(attrs.get("default", element.placeholder))
	return element


## 进入 <Pressed>/<Released>：记下可见性，并准备一个导出变体（只有真写了模板才会入表）。
func _begin_button_state(block: BlockDef, attrs: Dictionary, pressed: bool) -> BlockDef.ExportVariant:
	if block == null:
		return null
	if not block.elements.is_empty():
		var last: ElementDef = block.elements[-1]
		if last.type == &"Button":
			var visibility := _visibility(attrs.get("show", ""))
			if pressed:
				last.pressed_visible = visibility
			else:
				last.visible = visibility
			var variant := BlockDef.ExportVariant.new()
			variant.button = last.id
			variant.pressed = pressed
			return variant
	return null


func _end_button_state(block: BlockDef, variant: BlockDef.ExportVariant) -> void:
	if block != null and variant != null and not variant.parts.is_empty():
		block.export_variants.append(variant)


## 当前该把导出段写进哪里：处于 <Pressed>/<Released> 内时写进变体，否则写进默认模板。
func _export_target(block: BlockDef, variant: BlockDef.ExportVariant) -> Array[ExportPart]:
	if variant != null:
		return variant.parts
	return block.export_parts


## 旧写法：空格分隔的导出串（字面量不能含空格）。新写法请用 <Export> 子标签。
func _legacy_export_parts(raw: String) -> Array[ExportPart]:
	var out: Array[ExportPart] = []
	var trimmed := raw.strip_edges()
	if trimmed == "":
		return out
	for token in trimmed.split(" ", false):
		out.append(ExportPart.from_legacy_token(token))
	return out


## 解析可见性字符串：`T1 T2 !T3`。
func _visibility(raw: Variant) -> ElementDef.Visibility:
	var visibility := ElementDef.Visibility.new()
	for piece in _ids(String(raw)):
		# `!id` 表示黑名单
		if String(piece).begins_with("!"):
			visibility.hidden_ids.append(StringName(String(piece).substr(1)))
		else:
			visibility.visible_ids.append(piece)
	return visibility


func _ids(raw: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for piece in raw.strip_edges().split(" ", false):
		if piece != "":
			out.append(StringName(piece))
	return out


## `space_before="false"` 或 `glue="true"` 表示本段紧贴上一段（不插空格）。
func _space_before(attrs: Dictionary) -> bool:
	if attrs.has("glue"):
		return not _as_bool(attrs.get("glue", "true"))
	return _as_bool(attrs.get("space_before", "true"))


func _as_bool(raw: Variant) -> bool:
	var text := String(raw).strip_edges().to_lower()
	return not (text == "false" or text == "0" or text == "no")


func _attrs(xml: XMLParser) -> Dictionary:
	var out: Dictionary = {}
	for i in xml.get_attribute_count():
		out[xml.get_attribute_name(i)] = xml.get_attribute_value(i)
	return out


func _parse_hex_color(hex: String) -> Color:
	var digits := hex.strip_edges().lstrip("#")
	if digits.length() < 6:
		return Color.WHITE
	return Color(
		digits.substr(0, 2).hex_to_int() / 255.0,
		digits.substr(2, 2).hex_to_int() / 255.0,
		digits.substr(4, 2).hex_to_int() / 255.0
	)

#endregion
