class_name BlockLibrary
extends RefCounted

## 块定义库：把 `blocks/{locale}/*.xml` 解析成 [BlockDef] 对象。
##
## 布局的存储形态：**显式的行 + 条件**。
## [codeblock]
## <Block name="Draw">
##   <Row><Text>Draw</Text><Option id="mode">…</Option></Row>
##   <Row when="mode=clear | mode=color">
##     <Text>R</Text><LineBox id="r" placeholder="255" />
##   </Row>
##   <Text when="mode=color">A</Text><LineBox id="a" when="mode=color" placeholder="255" />
##   <LineBox id="prot" when="mode=poly | mode=linePoly | mode=image" placeholder="0" />
## </Block>
## [/codeblock]
##
## - `Row` 显式分行（取代 `<Br/>`）；行与元素都可带 `when`，条件支持 `&` `|` `~` 与括号
## - `Group` 给一串连续元素共享一个条件（不换行），解析时并入元素条件
## - `Export` 也可带 `when`；`<Br/>` / `<Pressed>` / `<Item show>` 等旧写法已不再支持（会给出解析警告）

class Kind extends RefCounted:
	var id: StringName = &""
	var color: Color = Color.WHITE
	var blocks: Array[BlockDef] = []

	func _init(p_id: StringName = &"", p_color: Color = Color.WHITE) -> void:
		id = p_id
		color = p_color


const DIR: String = "res://blocks"
const FALLBACK_LANG: String = "en_US"

## 解析过程中的问题（缺文件、重名、条件写错等），供编辑器提示用。
var warnings: PackedStringArray = []
var kinds: Array[Kind] = []

var _by_id: Dictionary[StringName, BlockDef] = {}


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
	var row: BlockDef.RowDef = null
	var group_condition: ConditionDef = null
	var variant: BlockDef.ExportVariant = null
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
							# 解析上下文按块重置：否则后续块会把单元格塞进上一个块的行里
							row = null
							group_condition = null
							variant = null
							option_element = null
					"Row":
						if block != null:
							row = _start_row(block, _condition_of(block, attrs))
					"Br", "Pressed", "Released":
						warnings.append("%s：<%s> 是旧写法，已不再支持（分行用 <Row [when]>，开关状态用 when 条件）"
							% [block.id if block != null else "?", tag])
					"Group":
						if block != null:
							var condition := _condition_of(block, attrs)
							group_condition = condition if group_condition == null \
								else ConditionDef.all_of([group_condition, condition])
					"Export":
						if block != null:
							variant = _start_variant(block, attrs)
					"Literal":
						if block != null:
							var part := ExportPart.make_literal("")
							part.space_before = _space_before(attrs)
							_export_target(block, variant).append(part)
							text_target = part
					"Field":
						if block != null:
							var field_part := ExportPart.make_field(StringName(attrs.get("id", "")))
							field_part.space_before = _space_before(attrs)
							field_part.link = _as_bool(attrs.get("link", "false"))
							_export_target(block, variant).append(field_part)
					"FirstOf":
						if block != null:
							_export_target(block, variant).append(
								ExportPart.make_first_visible(_ids(String(attrs.get("ids", ""))))
							)
					"Item":
						if option_element != null:
							var item := ElementDef.OptionItem.new("")
							item.value = String(attrs.get("value", ""))
							option_element.items.append(item)
							text_target = item
					_:
						if block != null:
							if not ElementRegistry.has(tag):
								warnings.append("%s：未知元素种类 <%s>（已注册：%s）"
									% [block.id, tag, _join_ids(ElementRegistry.types())])
							else:
								var element := _make_element(tag, attrs, block, group_condition)
								block.elements.append(element)
								if row == null:
									row = _start_row(block, null)
								row.cells.append(element)
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
					"Row":
						row = null
					"Group":
						group_condition = null
					"Export":
						variant = null
					"Block":
						if block != null:
							_validate_conditions(block)
							block.build_index()
						block = null
					"Kind":
						current_kind = null

	if block != null:
		block.build_index()


## 整块解析完后统一校验条件：语法错误、字段是否存在、取值是否合法。
func _validate_conditions(block: BlockDef) -> void:
	for entry in block.pending_conditions:
		var text := String(entry["text"])
		for message in entry["errors"]:
			warnings.append("%s：when=\"%s\" —— %s" % [block.id, text, message])
		_validate_condition(block, text, entry["condition"])
	block.pending_conditions.clear()


func _validate_condition(block: BlockDef, text: String, condition: ConditionDef) -> void:
	if condition == null:
		return
	if condition.kind == ConditionDef.Kind.COMPARE:
		if condition.field == &"":
			return
		var element := block.element(condition.field)
		if element == null:
			warnings.append("%s：when=\"%s\" —— 未知字段：%s（本块字段：%s）"
				% [block.id, text, String(condition.field), _join_ids(block.field_ids())])
			return
		for value in condition.values:
			var problem := ElementRegistry.validate_value(element, value)
			if problem != "":
				warnings.append("%s：when=\"%s\" —— %s" % [block.id, text, problem])
		return
	for child in condition.children:
		_validate_condition(block, text, child)
	if condition.child != null:
		_validate_condition(block, text, condition.child)


static func _join_ids(ids: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(String(id))
	return ", ".join(parts)


func _start_row(block: BlockDef, condition: ConditionDef) -> BlockDef.RowDef:
	var row := BlockDef.RowDef.new()
	row.condition = condition
	block.rows.append(row)
	return row


func _make_block(attrs: Dictionary, current_kind: Kind, order: int) -> BlockDef:
	var block := BlockDef.new(StringName(attrs.get("name", "")), current_kind.id)
	block.color = current_kind.color
	block.order = order
	if block.id == &"":
		warnings.append("存在没有 name 的 <Block>（%s）" % current_kind.id)
	elif _by_id.has(block.id):
		warnings.append("块 id 重复：%s" % block.id)
	else:
		_by_id[block.id] = block
	current_kind.blocks.append(block)
	return block


func _make_element(tag: String, attrs: Dictionary, block: BlockDef, group: ConditionDef) -> ElementDef:
	var element := ElementDef.new(StringName(tag), StringName(attrs.get("id", "")))
	element.attrs = attrs.duplicate()
	element.text = String(attrs.get("text", ""))
	element.placeholder = String(attrs.get("placeholder", ""))
	element.selector_kind = StringName(attrs.get("kind", ""))
	element.condition = _condition_of(block, attrs)
	if element.condition == null:
		element.condition = group
	elif group != null:
		element.condition = ConditionDef.all_of([group, element.condition])
	if tag == "Option":
		element.default_index = int(attrs.get("default", 0))
	else:
		element.default_value = String(attrs.get("default", element.placeholder))
	return element


## 解析 `when="…"`；没有就返回 null（无法解析时也返回 null，并记进 warnings）。
func _condition_of(block: BlockDef, attrs: Dictionary) -> ConditionDef:
	var text := String(attrs.get("when", "")).strip_edges()
	if text == "":
		return null
	# 不在解析中途校验：条件可能引用本块后面才声明的字段（<Export when> 通常写在元素前），
	# 那时校验会把合法条件误判成"未知字段"并丢弃 —— 校验推迟到整块解析完（_validate_conditions）
	var result := ConditionParser.parse(text)
	var condition: ConditionDef = result["condition"]
	# 语法错误也一并记下：整块解析完后由 _validate_conditions 报进 warnings
	block.pending_conditions.append({"text": text, "condition": condition, "errors": result["errors"]})
	return condition


func _start_variant(block: BlockDef, attrs: Dictionary) -> BlockDef.ExportVariant:
	var text := String(attrs.get("when", "")).strip_edges()
	var variant := BlockDef.ExportVariant.new()
	if text != "":
		var condition := _condition_of(block, attrs)
		variant.condition = condition
		variant.derive_button_from_condition()
		block.export_variants.append(variant)
		return variant
	# 没有 when 的块级 <Export>：就是默认模板
	block.export_parts = variant.parts
	return null


func _export_target(block: BlockDef, variant: BlockDef.ExportVariant) -> Array[ExportPart]:
	if variant != null:
		return variant.parts
	return block.export_parts


#endregion


#region 杂项

func _space_before(attrs: Dictionary) -> bool:
	if attrs.has("glue"):
		return not _as_bool(attrs.get("glue", "true"))
	return _as_bool(attrs.get("space_before", "true"))


func _as_bool(raw: Variant) -> bool:
	var text := String(raw).strip_edges().to_lower()
	return not (text == "false" or text == "0" or text == "no")


func _ids(raw: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for piece in raw.strip_edges().split(" ", false):
		if piece != "":
			out.append(StringName(piece))
	return out


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
