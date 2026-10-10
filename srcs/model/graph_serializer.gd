class_name GraphSerializer
extends RefCounted

## 逻辑图的存盘格式（JSON）。
##
## 与旧版的关键差别：[b]旧版存的是 PackedScene（.tscn 整棵节点树）[/b]，
## 参数值靠"控件 + @export 属性"被序列化器顺带保存；新架构存的是**纯数据**，
## 与控件、场景、引擎版本都无关，因此能被测试、能迁移、能手工查看。
##
## 文件结构：
## [codeblock]
## {
##   "format": "mvl-graph",
##   "version": 1,
##   "name": "未命名",
##   "graph": { "next_id":…, "next_chain":…, "chains":…, "chain_positions":…, "nodes":[…] }
## }
## [/codeblock]

const FORMAT_ID: String = "mvl-graph"
const FORMAT_VERSION: int = 1
const FILE_EXTENSION: String = ".json"

static var _last_error: String = ""


## 最近一次失败的原因（[method from_json] / [method load_from_file] 失败后可用）。
static func last_error() -> String:
	return _last_error


static func to_dict(graph: LogicGraph, name: String = "") -> Dictionary:
	return {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"name": name,
		"graph": graph.to_dict() if graph != null else {},
	}


static func from_dict(data: Dictionary) -> LogicGraph:
	_last_error = ""
	if data.is_empty():
		_last_error = "文件为空"
		return null
	var format := String(data.get("format", ""))
	if format != FORMAT_ID:
		_last_error = "不是 MVL 逻辑图文件（format = %s）" % (format if format != "" else "缺失")
		return null
	var version := int(data.get("version", 0))
	if version > FORMAT_VERSION:
		_last_error = "文件版本 %d 高于当前支持的 %d" % [version, FORMAT_VERSION]
		return null
	var raw: Dictionary = data.get("graph", {})
	return LogicGraph.from_dict(raw)


static func to_json(graph: LogicGraph, name: String = "", indent: String = "\t") -> String:
	return JSON.stringify(to_dict(graph, name), indent)


## 解析失败返回 null，原因见 [method last_error]。
static func from_json(text: String) -> LogicGraph:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_last_error = "JSON 解析失败"
		return null
	return from_dict(parsed)


static func save_to_file(graph: LogicGraph, path: String, name: String = "") -> Error:
	_last_error = ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_last_error = "无法写入 %s（错误码 %d）" % [path, FileAccess.get_open_error()]
		return FileAccess.get_open_error()
	file.store_string(to_json(graph, name))
	file.close()
	return OK


## 读取失败返回 null，原因见 [method last_error]。
static func load_from_file(path: String) -> LogicGraph:
	_last_error = ""
	if not FileAccess.file_exists(path):
		_last_error = "文件不存在：%s" % path
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_error = "无法读取 %s（错误码 %d）" % [path, FileAccess.get_open_error()]
		return null
	var text := file.get_as_text()
	file.close()
	return from_json(text)


