class_name AppSettings
extends RefCounted

## 应用级设置：与逻辑图无关的那点偏好（帧率上限、UI 缩放、失焦自动导出）。
##
## 纯数据 + 一个 JSON 存盘，不认识任何控件 —— 「谁来应用、什么时候应用」是 [Main] 的事，
## 这样设置本身能被单独读写和断言（[member path] 可以改，测试指向别处即可）。
##
## 旧实现把这些塞在一个 `EditorConfig` 资源里、并且还额外做了一个「Configure 块」
## 让用户在画布上摆设置；设置属于应用而不是程序逻辑，这里只保留前者。

## 存盘路径。默认落用户目录；调用方可以改它（测试就靠这个避免写到真实用户目录）。
static var path: String = "user://settings.json"

const DEFAULT_MAX_FPS: int = 60
const DEFAULT_UI_SCALE: float = 1.0
const MIN_MAX_FPS: int = 10
const MAX_MAX_FPS: int = 400
const MIN_UI_SCALE: float = 0.5
const MAX_UI_SCALE: float = 2.0

## 帧率上限（0 = 不限，这里不给这个选项，避免用户把编辑器拖到不可用）。
var max_fps: int = DEFAULT_MAX_FPS
## 整个 UI 的缩放系数（对应 [member Window.content_scale_factor]）。
var ui_scale: float = DEFAULT_UI_SCALE
## 窗口失焦时把当前标签页的 mlog 导出到剪贴板（旧实现叫 compile_when_close）。
var export_on_focus_lost: bool = false


## 从磁盘读设置；文件不存在或读不动时返回一份默认值（不会失败）。
static func load_from_disk() -> AppSettings:
	var settings := AppSettings.new()
	if not FileAccess.file_exists(path):
		return settings
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return settings
	var text := file.get_as_text()
	file.close()
	return from_json(text)


## 写回磁盘；返回错误码（[constant OK] 表示成功）。
func save_to_disk() -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json())
	file.close()
	return OK


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


func to_dict() -> Dictionary:
	return {
		"max_fps": max_fps,
		"ui_scale": ui_scale,
		"export_on_focus_lost": export_on_focus_lost,
	}


## 解析（容错）：认不出的字段用默认值，超范围的钳回范围内。
static func from_json(text: String) -> AppSettings:
	var settings := AppSettings.new()
	# 用 JSON.parse() 而不是 JSON.parse_string()：前者失败只返回错误码，
	# 后者会在控制台报一条引擎错误 —— 配置文件手改坏了不该看着像崩了。
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return settings
	var data: Dictionary = json.data
	settings.max_fps = clampi(int(data.get("max_fps", DEFAULT_MAX_FPS)), MIN_MAX_FPS, MAX_MAX_FPS)
	settings.ui_scale = clampf(float(data.get("ui_scale", DEFAULT_UI_SCALE)), MIN_UI_SCALE, MAX_UI_SCALE)
	settings.export_on_focus_lost = bool(data.get("export_on_focus_lost", false))
	return settings


func reset_to_defaults() -> void:
	max_fps = DEFAULT_MAX_FPS
	ui_scale = DEFAULT_UI_SCALE
	export_on_focus_lost = false
