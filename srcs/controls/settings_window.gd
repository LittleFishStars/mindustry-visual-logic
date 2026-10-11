class_name SettingsWindow
extends Window

## 设置窗口：帧率上限 / UI 缩放 / 失焦时自动导出。
##
## 只做一件事：把 [AppSettings] 的值铺到控件上，把控件上的改动写回数据，然后发信号。
## 「应用」（改引擎帧率、改 UI 缩放）是 [Main] 的职责 —— 这个窗口不认识编辑器，
## 于是它能被单独打开、单独测。
##
## 改动[b]即时生效[/b]（拖滑块马上能看到效果），但只有关闭窗口时才写盘：
## 免得拖一次滑块就往磁盘上刷几十次。

## 某个设置变了：主程序据此即时应用。
signal changed()
## 窗口关闭（该写盘了）。
signal closed()

@onready var nMaxFpsSlider: HSlider = %MaxFpsSlider
## 数值用 LineEdit 而不是 SpinBox：SpinBox 的样式长在它内部的 LineEdit 与按钮上，
## 主题里没这两样，它会顶着引擎默认皮肤（亮框 + 白字），跟项目配色对不上。
@onready var nMaxFpsEdit: LineEdit = %MaxFpsEdit
@onready var nUiScaleSlider: HSlider = %UiScaleSlider
@onready var nUiScaleEdit: LineEdit = %UiScaleEdit
@onready var nExportToggle: CheckButton = %ExportOnFocusLost

var settings: AppSettings = null

## 正在「数据 → 控件」地铺值：此时控件发出的 value_changed 不该再写回数据（否则打转）。
var _loading: bool = false


## 打开窗口：每次都从数据重新铺一遍，避免上次没保存的残留值留在控件上。
func open() -> void:
	if settings != null:
		_show_values(settings)
	popup_centered()


## 绑定数据并铺值（[Main] 在 _ready 里调一次）。
func setup(p_settings: AppSettings) -> void:
	settings = p_settings
	_show_values(settings)


func _show_values(data: AppSettings) -> void:
	if data == null:
		return
	_loading = true
	nMaxFpsSlider.value = data.max_fps
	nMaxFpsEdit.text = str(data.max_fps)
	nUiScaleSlider.value = data.ui_scale
	nUiScaleEdit.text = "%.2f" % data.ui_scale
	nExportToggle.button_pressed = data.export_on_focus_lost
	_loading = false


#region 控件回调

func _on_max_fps_changed(value: float) -> void:
	_apply_number(value, AppSettings.MIN_MAX_FPS, AppSettings.MAX_MAX_FPS, _set_max_fps)


func _on_ui_scale_changed(value: float) -> void:
	_apply_number(value, AppSettings.MIN_UI_SCALE, AppSettings.MAX_UI_SCALE, _set_ui_scale)


## 输入框提交（回车或失焦）：认不出的值就退回当前值，不做“猜你想要”。
func _on_max_fps_submitted(_text: String = "") -> void:
	if settings != null:
		_apply_number(_number_in(nMaxFpsEdit, settings.max_fps),
			AppSettings.MIN_MAX_FPS, AppSettings.MAX_MAX_FPS, _set_max_fps)


func _on_ui_scale_submitted(_text: String = "") -> void:
	if settings != null:
		_apply_number(_number_in(nUiScaleEdit, settings.ui_scale),
			AppSettings.MIN_UI_SCALE, AppSettings.MAX_UI_SCALE, _set_ui_scale)


## 数值改动的统一出口：钳进范围 → 写回数据 → 回填控件 → 通知外壳。
func _apply_number(value: float, minimum: float, maximum: float, setter: Callable) -> void:
	if _loading or settings == null:
		return
	setter.call(clampf(value, minimum, maximum))
	_show_values(settings)
	changed.emit()


## 读输入框里的数字；认不出来就用 [param fallback]（= 当前值）。
static func _number_in(edit: LineEdit, fallback: float) -> float:
	var text := edit.text.strip_edges()
	return text.to_float() if text.is_valid_float() else fallback


func _set_max_fps(value: float) -> void:
	settings.max_fps = int(roundf(value))


func _set_ui_scale(value: float) -> void:
	settings.ui_scale = value


func _on_export_toggled(pressed: bool) -> void:
	if _loading or settings == null:
		return
	settings.export_on_focus_lost = pressed
	changed.emit()


func _on_defaults_pressed() -> void:
	if settings == null:
		return
	settings.reset_to_defaults()
	_show_values(settings)
	changed.emit()


func _on_close_pressed() -> void:
	hide()
	closed.emit()

#endregion
