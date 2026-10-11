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
		# 一行可以放多条语句（`;` 分隔），也可以跟行尾注释（`#`）——
		# 两者都在引号外才生效，与 Mindustry 的 `LParser` 同一套规则。
		for piece in split_statements(line):
			var statement := piece.strip_edges()
			if statement == "":
				continue
			var tokens := tokenize(statement)
			if tokens.is_empty():
				continue
			var candidates: Array = index.get(StringName(tokens[0]), [])
			var hit: Variant = _try_defs(candidates, tokens)
			if hit == null:
				hit = _try_defs(fallback, tokens)
			if hit == null:
				warnings.append("无法识别的 mlog 行：%s" % statement)
				continue
			out.append(_make_node(graph, hit["def"], hit["values"], hit["states"]))
			src_lines.append(line_index)
	return out


## 把一行切成若干条语句：`;` 分开多条语句，`#` 起行尾注释（引号里的都不算）。
##
## Mindustry 的 `LParser` 就是这么切的（`\n` 与 `;` 都是语句结束符，`#` 之后全是注释），
## 所以从教程或游戏里拄来的代码常常是一行多句加尾注释。
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
##
## 多候选的那一格（`<FirstOf ids="…">`）把[b]整串候选[/b]带进模板：
## 哪一支生效取决于同行的选项字段（`draw` 的 mode、`ucontrol` 的类型……），
## 只看第一个候选的话，`draw rotate 0 0 45 0 0 0` 会把 45 回填到 `r` 上。
static func _parts_to_tokens(parts: Array[ExportPart]) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	for part in parts:
		var text := ""
		var string_field := false
		var field: StringName = &""
		var candidates: Array[StringName] = []
		match part.kind:
			ExportPart.Kind.LITERAL:
				text = part.literal
			ExportPart.Kind.FIELD:
				field = part.field
				string_field = part.as_string
			_:
				candidates = part.fields
				if not candidates.is_empty():
					field = candidates[0]
		if tokens.is_empty() or part.space_before:
			tokens.append({"literal": text, "field": field, "suffix": "",
				"string": string_field, "fields": candidates})
			continue
		var token: Dictionary = tokens[-1]
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


## 尝试一组候选块；成功返回 {def, values, states}，失败返回 null。
##
## [b]候选之间要看选项取值合不合法[/b]：`ucontrol` 的十几个变体共用同一个首 token ——
## 模板结构也是一模一样的（`ucontrol <类型> <p1>…<p5>`），只看结构的话 `ucontrol boost …`
## 会被绑给「移动」那块：块上显示的类型与实际字段对不上（导出时又把错的值写出去）。
## 所以给每个结构匹配打分：选项字段取值不合法扣分，取分最高的那个。
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


## 模板与 token 逐一对照；成功返回字段值（可能为空字典），失败返回 null。
##
## 允许行比模板[b]短[/b]：Mindustry 的 `LogicIO.read` 就是「有第 i 个 token 才填第 i 个字段」，
## 缺的参数保持默认值 —— 手写的 `ucontrol idle`、`draw clear 255 0 0` 在游戏里能用，
## 在这里也得能导进来。
static func _match(def: BlockDef, template: Array, states: Dictionary, tokens: PackedStringArray) -> Variant:
	if tokens.size() > template.size():
		return null
	var values: Dictionary = {}
	var value_of := _value_reader(def, values, states)
	# 只走「实际有的 token」：模板剩下的段（多半是字面量默认值）不参与匹配
	for i in tokens.size():
		var slot: Dictionary = template[i]
		var token := tokens[i]
		var literal := String(slot.get("literal", ""))
		var field: StringName = slot.get("field", &"")
		var candidates: Array = slot.get("fields", [])
		if candidates.size() > 1:
			# 多候选的一格：按当前已知的选项值挑生效的那支（与导出用同一套判定）
			var chosen: StringName = &""
			for candidate in candidates:
				if def.is_field_active(candidate, value_of):
					chosen = candidate
					break
			if chosen == &"":
				# 这一格与当前模式无关：值丢掉（游戏也忽略它），不因此判整行不匹配
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
		# 字符串字段：必须是带引号的字面量，去引号后再解码转义（与导出对称）
		if bool(slot.get("string", false)):
			if not MlogText.is_literal(token):
				return null
			values[field] = MlogText.unescape(token.substr(1, token.length() - 2))
			continue
		values[field] = token
	return values

## 匹配过程中的取值来源：先看本行已经解析出的字段，再看该字段的默认值
## （新块入图时 [method BlockDef.apply_defaults] 会灌上默认值，这里得与它对齐 ——
##  否则 `mode` 还没解析到时，`<FirstOf>` 的候选会挑错）。
static func _value_reader(def: BlockDef, values: Dictionary, states: Dictionary) -> Callable:
	return func(field_id: StringName) -> String:
		if states.has(field_id):
			return "true" if bool(states[field_id]) else "false"
		if values.has(field_id):
			return String(values[field_id])
		var element := def.element(field_id)
		return element.default_value if element != null else ""


#endregion
