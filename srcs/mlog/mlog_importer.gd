class_name MlogImporter
extends RefCounted

## mlog 文本 → 逻辑节点。
##
## 反向利用块定义里的[b]导出模板[/b]：行首字面量定位块类型，其余段按模板顺序回填字段。
## 旧版靠一张手写的命令表（45 个命令 → 场景路径）加上逐块实现的 `load_value()`，
## 每加一个块就要在表里加一行、在块脚本里补一个反序列化函数；
## 这里模板就是唯一的真相，新块自动可导入。
##
## 解析只产出「尚未入图」的节点（id 由传入的图分配），插入与撤销由编辑器标签页负责。

## 解析整段文本；无法识别的行会被跳过并记进 [param warnings]。
## [param src_lines] 与返回值平行：第 i 个节点在文本里的 0 基物理行号。
## 它是「把 mlog 的 jump 行号绑回块引用」的唯一线索（见 [method bind_links]）。
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
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for line_index in lines.size():
		var line := String(lines[line_index]).strip_edges()
		if line == "":
			continue
		# 注释行：整行余下部分就是文本
		if line.begins_with("#"):
			if library.has(&"Expression"):
				out.append(_make_node(graph, library.by_id(&"Expression"), {&"text": line.substr(1).strip_edges()}, {}))
				src_lines.append(line_index)
			continue
		var tokens := tokenize(line)
		if tokens.is_empty():
			continue
		var candidates: Array = index.get(StringName(tokens[0]), [])
		var hit: Variant = _try_defs(candidates, tokens)
		if hit == null:
			hit = _try_defs(fallback, tokens)
		if hit == null:
			warnings.append("无法识别的 mlog 行：%s" % line)
			continue
		out.append(_make_node(graph, hit["def"], hit["values"], hit["states"]))
		src_lines.append(line_index)
	return out


## 把刚导入的节点里「数字行号」形式的跳转目标绑回块引用。
##
## mlog 的 `jump` 目标是[b]绝对行号[/b]，而图上存的是块引用（`#<节点 id>`）；
## 行号→节点的对应关系由 [method MlogExporter.line_table] 给出 —— 导出与导入用同一套
## 遍历顺序，所以这里排一遍就能把两边对齐。[param line_offset] 是「插入点之前已有的行数」
## （追加导入时非 0，因为 jump 的行号是整段程序的绝对行号）。
##
## 返回成功绑定的引用个数。绑定写的是 [method LogicGraph.set_field]，撤销/重做与视图刷新都照常。
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
			# 旧实现用 -1 表示「没有锁定目标」
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


## 按空格切分，但引号内的空格不切（`print "hello world"` 是一个参数）。
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


## 一个块可以导入的模板形状：每个导出变体一种（带它要求的开关状态），默认模板一种。
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


## 把导出段合并成「token 模板」：`space_before` 为真处开一个新 token，
## 紧贴的段并进当前 token（字段 + 前后字面量）。
static func _parts_to_tokens(parts: Array[ExportPart]) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	for part in parts:
		var text := ""
		var field: StringName = &""
		match part.kind:
			ExportPart.Kind.LITERAL:
				text = part.literal
			ExportPart.Kind.FIELD:
				field = part.field
			_:
				if not part.fields.is_empty():
					field = part.fields[0]
		if tokens.is_empty() or part.space_before:
			tokens.append({"literal": text, "field": field, "suffix": ""})
			continue
		var token: Dictionary = tokens[-1]
		if token.get("field", &"") == &"" and field != &"":
			token["field"] = field
			token["suffix"] = text
		elif field == &"":
			if token.get("field", &"") == &"":
				token["literal"] = String(token["literal"]) + text
			else:
				token["suffix"] = String(token["suffix"]) + text
	return tokens


## 尝试一组候选块；成功返回 {def, values, states}，失败返回 null。
static func _try_defs(defs: Array, tokens: PackedStringArray) -> Variant:
	for def in defs:
		for shape in _shapes(def):
			var values: Variant = _match(shape["tokens"], tokens)
			if values != null:
				return {"def": def, "values": values, "states": shape["states"]}
	return null


## 模板与 token 逐一对照；成功返回字段值（可能为空字典），失败返回 null。
static func _match(template: Array, tokens: PackedStringArray) -> Variant:
	if template.size() != tokens.size():
		return null
	var values: Dictionary = {}
	for i in template.size():
		var slot: Dictionary = template[i]
		var token := tokens[i]
		var literal := String(slot.get("literal", ""))
		var field: StringName = slot.get("field", &"")
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
		values[field] = token
	return values

#endregion
