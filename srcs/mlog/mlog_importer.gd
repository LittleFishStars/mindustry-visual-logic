class_name MlogImporter
extends RefCounted

## mlog 文本 → 逻辑节点（尚未入图）。反向利用导出模板：行首字面量定位块类型，其余段按模板顺序回填字段 —— 模板是唯一真相，新增块自动可导入。
## [param src_lines] 与返回值平行：第 i 个节点在文本里的 0 基行号（行号绑引用的唯一线索）。
## 结构块（XML `<Block marker="if">`）导出时会在指令行尾留一份字段快照 `#if 字段=值…`：导入靠它把这一行认回结构块、
## 还原字段与巢。没有标记的行照旧 —— 模板里 `<AfterSubtree/>` 那一格匹配不上，结构块导出的 jump 会当成普通 Jump 导进来。
const AFTER_KEY: StringName = &"@after"


static func parse(
	text: String,
	library: BlockLibrary,
	graph: LogicGraph,
	warnings: Array[String] = [],
	src_lines: Array[int] = []
) -> Array[LogicNode]:
	var out: Array[LogicNode] = []
	if text == "" or library == null or graph == null:
		return out
	var index := _build_index(library)
	var fallback := _fallback_candidates(library)
	var markers := _marker_index(library)
	## 与 out 平行：结构块的巢结束指令序号（-1 = 不是结构块）
	var ends: Array[int] = []
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for line_index in lines.size():
		var line := String(lines[line_index]).strip_edges()
		if line == "":
			continue
		# 注释行：整行余下部分就是注释块的文本（行尾标记只认指令行）
		if line.begins_with("#"):
			if library.has(&"Expression"):
				out.append(_make_node(graph, library.by_id(&"Expression"), {&"text": line.substr(1).strip_edges()}, {}))
				ends.append(-1)
				src_lines.append(line_index)
			continue
		var marker := _read_marker(line, markers, warnings)
		for piece in split_statements(line):
			var statement := piece.strip_edges()
			if statement == "":
				continue
			var tokens := tokenize(statement)
			if tokens.is_empty():
				continue
			# 带标记的行：按结构块自己的模板认，`<AfterSubtree/>` 那一格就是巢结束的行号
			if not marker.is_empty():
				var marked: Variant = _match_marked(marker["def"], tokens)
				if marked != null:
					var values: Dictionary = marked["values"]
					var raw_after := String(values.get(AFTER_KEY, ""))
					var after := raw_after.to_int() if raw_after.is_valid_int() else -1
					if after < 0:
						warnings.append("结构标记 %s 的巢结束行号不是数字：%s" % [marker["def"].marker, raw_after])
					values.erase(AFTER_KEY)
					# 注释里的字段为准：模板里的比较是取反导出的，从行里认不回来
					values.merge(marker["fields"], true)
					out.append(_make_node(graph, marker["def"], values, marked["states"]))
					ends.append(after)
					src_lines.append(line_index)
					continue
				warnings.append("结构标记 %s 与这一行不符，已按普通语句导入：%s" % [marker["def"].marker, statement])
			var candidates: Array = index.get(StringName(tokens[0]), [])
			var hit: Variant = _try_defs(candidates, tokens)
			if hit == null:
				hit = _try_defs(fallback, tokens)
			if hit == null:
				warnings.append("无法识别的 mlog 行：%s" % statement)
				continue
			out.append(_make_node(graph, hit["def"], hit["values"], hit["states"]))
			ends.append(-1)
			src_lines.append(line_index)
	_build_structure(out, ends, library, warnings)
	return out


## 把 [method parse] 的结果摊成若干棵子树（每棵是根在前、深度优先的节点表），形状正好给
## [method LogicGraph.insert_subtree] 用 —— 结构块的子节点已经挂在它的槽位里，不能再逐个插进链里。
static func subtrees(nodes: Array[LogicNode]) -> Array:
	var by_id: Dictionary = {}
	for node in nodes:
		by_id[node.id] = node
	var nested: Dictionary = {}
	for node in nodes:
		for slot_id in node.slots:
			for child_id in node.peek_slot(slot_id):
				nested[int(child_id)] = true
	var out: Array = []
	for node in nodes:
		if nested.has(node.id):
			continue
		var group: Array[LogicNode] = []
		_collect_subtree(by_id, node, group)
		out.append(group)
	return out


static func _collect_subtree(by_id: Dictionary, node: LogicNode, out: Array[LogicNode]) -> void:
	out.append(node)
	for slot_id in node.slots:
		for child_id in node.peek_slot(slot_id):
			var child: LogicNode = by_id.get(int(child_id))
			if child != null:
				_collect_subtree(by_id, child, out)


## 把一行切成若干条语句：`;` 分隔语句，`#` 起行尾注释（引号里的不算，同 LParser）。
static func split_statements(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quote := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
			current += ch
		elif not in_quote and ch == "#":
			break
		elif not in_quote and ch == ";":
			out.append(current)
			current = ""
		else:
			current += ch
	out.append(current)
	return out


## 把刚导入节点里「数字行号」的跳转目标绑回块引用（返回绑定个数）；[param line_offset] 是插入点之前已有的行数。
static func bind_links(
	nodes: Array[LogicNode],
	src_lines: Array[int],
	line_offset: int,
	graph: LogicGraph,
	library: BlockLibrary,
	warnings: Array[String] = []
) -> int:
	if graph == null or library == null or nodes.is_empty():
		return 0
	var line_of: Dictionary = MlogExporter.line_table(graph, library).get("line_of", {})
	var node_at: Dictionary = {}
	for id in line_of:
		node_at[line_of[id]] = id
	var bound := 0
	for i in nodes.size():
		var node := nodes[i]
		var def := library.by_id(node.type_id)
		if def == null:
			continue
		for field_id in def.reference_fields():
			var raw := String(node.get_field(field_id, "")).strip_edges()
			if raw == "" or not raw.is_valid_int():
				continue
			var want := int(raw)
			if want < 0:
				graph.set_field(node.id, field_id, "")
				continue
			var line := line_offset + want
			if node_at.has(line):
				graph.set_field(node.id, field_id, LogicGraph.make_link_ref(int(node_at[line])))
				bound += 1
			else:
				warnings.append("mlog 第 %d 行的跳转目标（第 %d 行）不在程序里，已按未锁定处理"
					% [int(src_lines[i]) + 1 if i < src_lines.size() else 0, want + 1])
				graph.set_field(node.id, field_id, "")
	return bound


static func tokenize(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quote := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
			current += ch
		elif ch == " " and not in_quote:
			if current != "":
				out.append(current)
				current = ""
		else:
			current += ch
	if current != "":
		out.append(current)
	return out


#region 内部

static func _make_node(graph: LogicGraph, def: BlockDef, values: Dictionary, states: Dictionary) -> LogicNode:
	var node := graph.new_node(def.id)
	def.apply_defaults(node)
	for field_id in values:
		node.fields[field_id] = values[field_id]
	for button_id in states:
		node.fields[button_id] = "true" if bool(states[button_id]) else "false"
	return node


static func _build_index(library: BlockLibrary) -> Dictionary:
	var index: Dictionary = {}
	for block_id in library.block_ids():
		var def := library.by_id(block_id)
		for shape in _shapes(def):
			var tokens: Array = shape["tokens"]
			if tokens.is_empty():
				continue
			var head := String(tokens[0].get("literal", ""))
			if head == "":
				continue
			var bucket: Array = index.get(StringName(head), [])
			if not bucket.has(def):
				bucket.append(def)
			index[StringName(head)] = bucket
	return index


## 行首没有字面量的块（如 JumpLabel 的 `label:`）无法进索引，单独兜底。
static func _fallback_candidates(library: BlockLibrary) -> Array:
	var out: Array = []
	for block_id in library.block_ids():
		var def := library.by_id(block_id)
		for shape in _shapes(def):
			var tokens: Array = shape["tokens"]
			if tokens.size() == 1 and String(tokens[0].get("literal", "")) == "" and tokens[0].get("field", &"") != &"":
				out.append(def)
				break
	return out


static func _shapes(def: BlockDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for variant in def.export_variants:
		out.append({
			"tokens": _parts_to_tokens(variant.parts),
			"states": {variant.button: variant.pressed},
		})
	if not def.export_parts.is_empty():
		out.append({"tokens": _parts_to_tokens(def.export_parts), "states": {}})
	return out


## 把导出段合并成 token 模板（`space_before` 处开新 token，紧贴的段并进当前）；<FirstOf> 要带上整串候选，只带第一个会把值回填到错字段上。
static func _parts_to_tokens(parts: Array[ExportPart]) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	for part in parts:
		var text := ""
		var string_field := false
		var field: StringName = &""
		var candidates: Array[StringName] = []
		var after := false
		match part.kind:
			ExportPart.Kind.LITERAL:
				text = part.literal
			ExportPart.Kind.FIELD:
				field = part.field
				string_field = part.as_string
			ExportPart.Kind.AFTER_SUBTREE:
				after = true
			_:
				candidates = part.fields
				if not candidates.is_empty():
					field = candidates[0]
		if tokens.is_empty() or part.space_before:
			tokens.append({"literal": text, "field": field, "suffix": "",
				"string": string_field, "fields": candidates, "after": after})
			continue
		var token: Dictionary = tokens[-1]
		token["after"] = bool(token.get("after", false)) or after
		if token.get("field", &"") == &"" and field != &"":
			token["field"] = field
			token["string"] = string_field
			token["fields"] = candidates
			token["suffix"] = text
		elif field == &"":
			if token.get("field", &"") == &"":
				token["literal"] = String(token["literal"]) + text
			else:
				token["suffix"] = String(token["suffix"]) + text
	return tokens


## 试一组候选块，返回 {def, values, states} 或 null；按选项取值合法性打分取最高 —— ucontrol 那种模板同构的变体只能这样分开。
static func _try_defs(defs: Array, tokens: PackedStringArray) -> Variant:
	var best: Variant = null
	var best_score := -2147483648
	for def in defs:
		for shape in _shapes(def):
			var values: Variant = _match(def, shape["tokens"], shape["states"], tokens)
			if values == null:
				continue
			var normalized := _canonicalize(def, values)
			var score := _score(def, normalized)
			if score > best_score:
				best_score = score
				best = {"def": def, "values": normalized, "states": shape["states"]}
	return best


## 选项字段取值不合法就扣分（不是直接丢掉：认不出的新类型也比丢行强）。
static func _score(def: BlockDef, values: Dictionary) -> int:
	var score := 0
	for field_id in values:
		var element := def.option_element(field_id)
		if element != null and element.canonical_value(String(values[field_id])) == "":
			score -= 100
	return score


## 把选项字段的旧名字换成现在的名字（XML 里 `<Item value="angle" alias="atan2">`）。
static func _canonicalize(def: BlockDef, values: Dictionary) -> Dictionary:
	var out := values.duplicate()
	for field_id in out:
		var element := def.option_element(field_id)
		if element == null:
			continue
		var canonical := element.canonical_value(String(out[field_id]))
		if canonical != "":
			out[field_id] = canonical
	return out


## 模板与 token 逐一对照，返回字段值或 null；允许行比模板短（缺的参数保持默认，同 LogicIO.read）。
## [param allow_after]：只有带结构标记的行才允许 `<AfterSubtree/>` 那一格（它存的就是巢结束的行号）。
static func _match(def: BlockDef, template: Array, states: Dictionary, tokens: PackedStringArray,
		allow_after: bool = false) -> Variant:
	if tokens.size() > template.size():
		return null
	var values: Dictionary = {}
	var value_of := _value_reader(def, values, states)
	for i in tokens.size():
		var slot: Dictionary = template[i]
		var token := tokens[i]
		if bool(slot.get("after", false)):
			if not allow_after:
				return null
			values[AFTER_KEY] = token
			continue
		var literal := String(slot.get("literal", ""))
		var field: StringName = slot.get("field", &"")
		var candidates: Array = slot.get("fields", [])
		if candidates.size() > 1:
			# 多候选的一格：按已解析出的选项值挑生效那支（与导出共用 is_field_active）
			var chosen: StringName = &""
			for candidate in candidates:
				if def.is_field_active(candidate, value_of):
					chosen = candidate
					break
			if chosen == &"":
				continue
			field = chosen
		if field == &"":
			if token != literal:
				return null
			continue
		if literal != "":
			if not token.begins_with(literal):
				return null
			token = token.substr(literal.length())
		var suffix := String(slot.get("suffix", ""))
		if suffix != "":
			if not token.ends_with(suffix):
				return null
			token = token.substr(0, token.length() - suffix.length())
		# 字符串字段：必须带引号，去引号后再解码转义（与导出的加引号对称）
		if bool(slot.get("string", false)):
			if not MlogText.is_literal(token):
				return null
			values[field] = MlogText.unescape(token.substr(1, token.length() - 2))
			continue
		values[field] = token
	return values

## 匹配时的取值来源：先看本行已解析出的字段，再看字段默认值（与 `apply_defaults` 对齐）。
static func _value_reader(def: BlockDef, values: Dictionary, states: Dictionary) -> Callable:
	return func(field_id: StringName) -> String:
		if states.has(field_id):
			return "true" if bool(states[field_id]) else "false"
		if values.has(field_id):
			return String(values[field_id])
		var element := def.element(field_id)
		return element.default_value if element != null else ""


## 行尾注释（不在引号里的第一个 `#` 之后的部分）；没有则返回 ""。
static func trailing_comment(line: String) -> String:
	var in_quote := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
		elif ch == "#" and not in_quote:
			return line.substr(i + 1).strip_edges()
	return ""


## marker 名 → 块定义（结构块在 XML 里用 `<Block marker="if">` 声明）。
static func _marker_index(library: BlockLibrary) -> Dictionary:
	var out: Dictionary = {}
	for block_id in library.block_ids():
		var def := library.by_id(block_id)
		if def != null and def.marker != "":
			out[StringName(def.marker)] = def
	return out


## 解析行尾标记：`#<名字> 字段=值 …`（值可带引号）；不是本程序的标记就返回空字典。
static func _read_marker(line: String, markers: Dictionary, warnings: Array[String]) -> Dictionary:
	var tokens := tokenize(trailing_comment(line))
	if tokens.is_empty():
		return {}
	var def: BlockDef = markers.get(StringName(tokens[0]))
	if def == null:
		return {}
	var fields: Dictionary = {}
	var known := def.field_ids()
	for i in range(1, tokens.size()):
		var at := tokens[i].find("=")
		var field_id := StringName(tokens[i].substr(0, at)) if at > 0 else &""
		if at <= 0 or not known.has(field_id) or def.is_reference_field(field_id):
			warnings.append("结构标记 %s 里认不出的字段：%s" % [def.marker, tokens[i]])
			continue
		var raw := tokens[i].substr(at + 1)
		fields[field_id] = MlogText.unescape(raw.substr(1, raw.length() - 2)) if MlogText.is_literal(raw) else raw
	return {"def": def, "fields": fields}


## 标记行的匹配：与普通行同一套模板，只是允许 `<AfterSubtree/>` 那一格取行号。
static func _match_marked(def: BlockDef, tokens: PackedStringArray) -> Variant:
	for shape in _shapes(def):
		var values: Variant = _match(def, shape["tokens"], shape["states"], tokens, true)
		if values != null:
			return {"values": values, "states": shape["states"]}
	return null


## 按结构块的巢结束序号把扁表还原成嵌套：挂进槽位后顺序不变，仍是文档顺序。
static func _build_structure(nodes: Array[LogicNode], ends: Array[int], library: BlockLibrary,
		warnings: Array[String]) -> void:
	var open: Array[LogicNode] = []
	var slots: Array[StringName] = []
	var open_ends: Array[int] = []
	var instruction := 0
	for i in nodes.size():
		var node := nodes[i]
		# 走到下一条指令前，先把已经到头的结构块收掉
		while not open_ends.is_empty() and open_ends[-1] <= instruction:
			open_ends.pop_back()
			slots.pop_back()
			open.pop_back()
		if not open.is_empty():
			open[-1].slot(slots[-1]).append(node.id)
		var def := library.by_id(node.type_id)
		if ends[i] >= 0:
			var slot := _nest_slot(def)
			if slot == &"":
				warnings.append("结构块 %s 没有槽位，巢放不进去" % node.type_id)
			elif ends[i] <= instruction:
				warnings.append("结构块 %s 的巢结束行号（%d）在自己这一行之前" % [node.type_id, ends[i]])
			else:
				open.append(node)
				slots.append(slot)
				open_ends.append(ends[i])
		if def != null and MlogExporter.is_instruction(MlogExporter.render_node(def, node)):
			instruction += 1


## 结构块装巢的槽位：它的第一个槽位（XML 里的 `<Nest>`）。
static func _nest_slot(def: BlockDef) -> StringName:
	if def == null:
		return &""
	var slots := def.slot_ids()
	return slots[0] if not slots.is_empty() else &""

#endregion
