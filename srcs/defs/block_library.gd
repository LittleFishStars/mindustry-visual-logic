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
## - `Export` 也可带 `when`；旧写法 `<Pressed>/<Released>` 一律翻译成条件
## - 旧写法（`<Item show>` / `<Br/>` / `<Pressed show>`）继续可解析，解析时就翻译成条件，
##   所以内部只有一种机制

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
	var row: BlockDef.RowDef = null
	var group_condition: ConditionDef = null
	var variant: BlockDef.ExportVariant = null
	var pressed_variant: BlockDef.ExportVariant = null
	# 导出模板：<Export> 里那段文本 / 该模板写进哪个变体（null = 默认模板）
	var export_text := ""
	var export_variant: BlockDef.ExportVariant = null
	var in_export := false
	var export_has_children := false
	# 下一个文本节点该写给谁（Text / Item）
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
							action = null
					"Row":
						if block != null:
							row = _start_row(block, _condition_of(block, attrs))
					"Br":
						row = null
					"Group":
						if block != null:
							var condition := _condition_of(block, attrs)
							group_condition = condition if group_condition == null \
								else ConditionDef.all_of([group_condition, condition])
					"Export":
						if block != null:
							export_text = ""
							in_export = true
							export_has_children = false
							if variant != null:
								export_variant = variant
							else:
								var when_text := String(attrs.get("when", "")).strip_edges()
								if when_text == "":
									export_variant = null
								else:
									var fresh := BlockDef.ExportVariant.new()
									fresh.condition = _condition_of(block, attrs)
									fresh.derive_button_from_condition()
									block.export_variants.append(fresh)
									export_variant = fresh
					"Literal":
						if block != null:
							export_has_children = true
							var part := ExportPart.make_literal("")
							part.space_before = _space_before(attrs)
							_export_target(block, export_variant if export_variant != null else variant).append(part)
							text_target = part
					"Field":
						if block != null:
							export_has_children = true
							var field_part := ExportPart.make_field(StringName(attrs.get("id", "")))
							field_part.space_before = _space_before(attrs)
							_export_target(block, export_variant if export_variant != null else variant).append(field_part)
					"FirstOf":
						if block != null:
							export_has_children = true
							_export_target(block, export_variant if export_variant != null else variant).append(
								ExportPart.make_first_visible(_ids(String(attrs.get("ids", ""))))
							)
					"Item":
						if option_element != null:
							var item := ElementDef.OptionItem.new("")
							item.value = String(attrs.get("value", ""))
							item.legacy_show = _ids(String(attrs.get("show", "")))
							option_element.items.append(item)
							text_target = item
					"Pressed":
						variant = _apply_button_state(block, attrs, true)
						pressed_variant = variant
					"Released":
						variant = _apply_button_state(block, attrs, false)
						pressed_variant = variant
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
				# 结构化子标签（旧写法）优先吃文本；只有"<Export> 里直接写模板"时才累积模板
				if text_target != null:
					var text := xml.get_node_data()
					if text != "":
						text_target.set_text(text)
				elif in_export and not export_has_children:
					export_text += xml.get_node_data()
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
						in_export = false
						# 结构化子标签（旧写法）已经自己填好了段落，这里不要再覆盖
						if not export_has_children:
							var parts := ExportPart.parse_template(export_text.strip_edges())
							if export_variant != null:
								export_variant.parts = parts
							else:
								block.export_parts = parts
						export_text = ""
						export_variant = null
						export_has_children = false
					"Event":
						action = null
					"Pressed", "Released":
						if block != null and pressed_variant != null and not pressed_variant.parts.is_empty():
							block.export_variants.append(pressed_variant)
						pressed_variant = null
						variant = null
					"Block":
						if block != null:
							_translate_legacy_visibility(block)
							_validate_conditions(block)
							block.build_index()
						block = null
					"Kind":
						current_kind = null

	if block != null:
		_translate_legacy_visibility(block)
		block.build_index()


## 整块解析完后统一校验条件（字段是否存在、取值是否合法）。
func _validate_conditions(block: BlockDef) -> void:
	for entry in block.pending_conditions:
		_validate_condition(block, String(entry["text"]), entry["condition"])
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
		match element.type:
			&"Option":
				var legal := PackedStringArray()
				for item in element.items:
					legal.append(item.value_or_text())
				for value in condition.values:
					if not legal.has(value):
						warnings.append("%s：when=\"%s\" —— 字段 %s 没有取值 `%s`（合法值：%s）"
							% [block.id, text, String(condition.field), value, ", ".join(legal)])
			&"Button":
				for value in condition.values:
					if value != "true" and value != "false":
						warnings.append("%s：when=\"%s\" —— 开关 %s 只能与 true / false 比较（实际 `%s`）"
							% [block.id, text, String(condition.field), value])
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
	block.export_parts = ExportPart.parse_template(String(attrs.get("export", "")).strip_edges())
	block.behavior_path = String(attrs.get("script", ""))
	if block.id == &"":
		warnings.append("存在没有 name 的 <Block>（%s）" % current_kind.id)
	elif _by_id.has(block.id):
		warnings.append("块 id 重复：%s" % block.id)
	else:
		_by_id[block.id] = block
		_kind_of[block.id] = current_kind.id
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
	block.pending_conditions.append({"text": text, "condition": condition})
	return condition


## 当前该把导出段写进哪里：处于 <Pressed>/<Released> 内时写进变体，否则写进默认模板。
func _export_target(block: BlockDef, variant: BlockDef.ExportVariant) -> Array[ExportPart]:
	if variant != null:
		return variant.parts
	return block.export_parts


func _space_before(attrs: Dictionary) -> bool:
	if attrs.has("glue"):
		return not _as_bool(attrs.get("glue", "true"))
	return _as_bool(attrs.get("space_before", "true"))


func _as_bool(raw: Variant) -> bool:
	var text := String(raw).strip_edges().to_lower()
	return not (text == "false" or text == "0" or text == "no")


func _apply_button_state(block: BlockDef, attrs: Dictionary, pressed: bool) -> BlockDef.ExportVariant:
	if block == null or block.elements.is_empty():
		return null
	var last: ElementDef = block.elements[-1]
	if last.type != &"Button":
		return null
	var shown := _ids(String(attrs.get("show", "")))
	if pressed:
		last.legacy_pressed = shown
	else:
		last.legacy_released = shown
	# 统一成 when：<Pressed>/<Released> 就是 `开关=true/false` 的导出模板
	var variant := BlockDef.ExportVariant.new()
	variant.condition = ConditionDef.compare(last.id, ["true" if pressed else "false"])
	variant.button = last.id
	variant.pressed = pressed
	block.export_variants.append(variant)
	return variant


#endregion


#region 旧写法 → 条件

## 把 `<Item show="…">` / `<Pressed show>` / `<Released show>` 翻译成元素条件。
##
## 旧语义是「选中项的白名单 ∩ 开关状态的白名单，没被列出的元素一律隐藏」；
## 这里对每个元素、每个"限制来源"各算一份规则再取与：
## [codeblock]
## 某个 Option 对元素 x 的规则 = 或( 选中该项 且 (该项清单为空 或 x 在清单里) )
## 某个 Button 对元素 x 的规则 = 或( 处于该状态 且 (该状态清单为空 或 x 在清单里) )
## [/codeblock]
## 没被任何清单提到的元素，其规则恒假 —— 与旧行为一致（隐藏）。
func _translate_legacy_visibility(block: BlockDef) -> void:
	var options: Array[ElementDef] = []
	var buttons: Array[ElementDef] = []
	for element in block.elements:
		if element.type == &"Option" and not element.items.is_empty():
			for item in element.items:
				if not item.legacy_show.is_empty():
					options.append(element)
					break
		elif element.type == &"Button":
			if not element.legacy_pressed.is_empty() or not element.legacy_released.is_empty():
				buttons.append(element)
	if not options.is_empty() or not buttons.is_empty():
		for element in block.elements:
			var rules: Array[ConditionDef] = []
			for option in options:
				var option_rule := _legacy_option_rule(option, element.id)
				if option_rule != null:
					rules.append(option_rule)
			for button in buttons:
				var button_rule := _legacy_button_rule(button, element.id)
				if button_rule != null:
					rules.append(button_rule)
			if rules.is_empty():
				continue
			var rule := ConditionDef.all_of(rules)
			if element.condition == null:
				element.condition = rule
			else:
				element.condition = ConditionDef.all_of([element.condition, rule])
	for element in block.elements:
		element.clear_legacy()


func _legacy_option_rule(option: ElementDef, element_id: StringName) -> ConditionDef:
	var branches: Array[ConditionDef] = []
	for item in option.items:
		if item.legacy_show.is_empty() or item.legacy_show.has(element_id):
			branches.append(ConditionDef.compare(option.id, [item.value_or_text()]))
	# 每个取值都显示它 = 这条来源不构成限制（避免写出"16 项或"这种同义反复）
	if branches.size() == option.items.size():
		return null
	return ConditionDef.any_of(branches)


func _legacy_button_rule(button: ElementDef, element_id: StringName) -> ConditionDef:
	var branches: Array[ConditionDef] = []
	var total := 0
	if button.legacy_released.is_empty() or button.legacy_released.has(element_id):
		branches.append(ConditionDef.compare(button.id, ["false"]))
	if button.legacy_released.is_empty() or button.legacy_released.has(element_id):
		total += 1
	if button.legacy_pressed.is_empty() or button.legacy_pressed.has(element_id):
		branches.append(ConditionDef.compare(button.id, ["true"]))
	if button.legacy_pressed.is_empty() or button.legacy_pressed.has(element_id):
		total += 1
	if total == 2:
		return null
	return ConditionDef.any_of(branches)

#endregion


#region 杂项

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
