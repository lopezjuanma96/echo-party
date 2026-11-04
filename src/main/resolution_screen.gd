class_name ResolutionScreen
extends Control
## Roster resolution UI shown between runs. It only reads and drives the
## `Roster` it is given; the Echo Anchor count it spends is reported back through
## `resolved`. Keys are modal-only (the tree is paused while it is open).

signal resolved(anchors_left: int)

const MAX_ROWS := 5
const ROW_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const RESULT_IGNORED := &"ignored"
const RESULT_REJECTED := &"rejected"
const RESULT_SELECTED := &"selected"
const RESULT_DESELECTED := &"deselected"
const RESULT_PENDING := &"pending"
const RESULT_COMMITTED := &"committed"
const KIND_MOVE := &"move"
const KIND_DISCARD := &"discard"
const ROW_EMPTY_TEXT_COLOR := Color(0.5, 0.55, 0.64, 1.0)
const ROW_TEXT_COLOR := Color(0.87, 0.9, 0.95, 1.0)

@onready var title_label: Label = $Center/Panel/Margin/Content/Title
@onready var summary_label: Label = $Center/Panel/Margin/Content/Summary
@onready var trial_label: Label = $Center/Panel/Margin/Content/Columns/Info/Trial
@onready var coverage_label: Label = $Center/Panel/Margin/Content/Columns/Info/Coverage
@onready var next_hero_label: Label = $Center/Panel/Margin/Content/Columns/Info/NextHero
@onready var anchors_label: Label = $Center/Panel/Margin/Content/Columns/Info/Anchors
@onready var capacity_label: Label = $Center/Panel/Margin/Content/Columns/Info/Capacity
@onready var outcome_label: Label = $Center/Panel/Margin/Content/Outcome
@onready var discard_button: Button = $Center/Panel/Margin/Content/Buttons/Discard
@onready var confirm_button: Button = $Center/Panel/Margin/Content/Buttons/Confirm
@onready var cancel_button: Button = $Center/Panel/Margin/Content/Buttons/Cancel
@onready var start_button: Button = $Center/Panel/Margin/Content/Buttons/Start
@onready var panel: Control = $Center/Panel
@onready var row_buttons: Array[Button] = [
	$Center/Panel/Margin/Content/Columns/Rows/Row1,
	$Center/Panel/Margin/Content/Columns/Rows/Row2,
	$Center/Panel/Margin/Content/Columns/Rows/Row3,
	$Center/Panel/Margin/Content/Columns/Rows/Row4,
	$Center/Panel/Margin/Content/Columns/Rows/Row5,
]

var roster: Roster
var anchors := 0
var _context := {}
var _row_locations: Array[Dictionary] = []
var _selected := {}
var _pending := {}
var _outcome_text := ""
var _styles := {}


func _ready() -> void:
	_styles = {
		&"normal": _make_style(Color(0.07, 0.09, 0.13, 1.0), Color(0.24, 0.29, 0.38, 1.0), 1),
		&"hover": _make_style(Color(0.1, 0.13, 0.19, 1.0), Color(0.45, 0.52, 0.65, 1.0), 1),
		&"selected": _make_style(Color(0.17, 0.14, 0.05, 1.0), Color(1.0, 0.82, 0.25, 1.0), 3),
		&"loss": _make_style(Color(0.22, 0.07, 0.08, 1.0), Color(0.9, 0.35, 0.35, 1.0), 3),
	}
	for index in row_buttons.size():
		row_buttons[index].pressed.connect(_on_row_pressed.bind(index))
	discard_button.pressed.connect(discard)
	confirm_button.pressed.connect(confirm)
	cancel_button.pressed.connect(cancel)
	start_button.pressed.connect(_on_start_pressed)


## `new_context` keys (all optional): `anchors`, `encounter_id`, `unlocks`,
## `trial_clears`, `title`, `summary`.
func present(new_roster: Roster, new_context: Dictionary = {}) -> void:
	roster = new_roster
	_context = new_context.duplicate(true)
	anchors = maxi(int(_context.get("anchors", 0)), 0)
	_selected = {}
	_pending = {}
	if roster.candidate != null:
		_outcome_text = "Place %s: pick the hero, then pick where it goes." % roster.candidate.display_name
	else:
		_outcome_text = "No hero to place. To swap, pick a row, then the row to swap it with; then start the run."
	show()
	_refresh()


func select_row(zone: StringName, index: int) -> StringName:
	if not visible or roster == null:
		return RESULT_IGNORED
	var location := {"zone": zone, "index": index}
	if _row_index_of(location) < 0:
		return RESULT_IGNORED
	if not _pending.is_empty():
		if _pending["kind"] == KIND_MOVE and _same_location(_pending["dest"], location):
			return confirm()
		_pending = {}
	if _selected.is_empty():
		var record := _record_at(location)
		if record == null:
			_set_outcome("That slot is empty. Pick a hero to move first.")
			return RESULT_REJECTED
		_selected = location
		_set_outcome("Moving %s. Pick a destination (Esc cancels)." % record.display_name)
		return RESULT_SELECTED
	if _same_location(_selected, location):
		_selected = {}
		_set_outcome("Selection cancelled.")
		return RESULT_DESELECTED
	if zone == Roster.ZONE_CANDIDATE:
		var candidate_record := _record_at(location)
		if candidate_record == null:
			_set_outcome("There is no candidate. The candidate row cannot be a destination.")
			return RESULT_REJECTED
		_selected = location
		_set_outcome("Moving %s. Pick a destination (Esc cancels)." % candidate_record.display_name)
		return RESULT_SELECTED
	return _try_move(_selected, location)


## Commits the pending loss or discard (the second confirming press).
func confirm() -> StringName:
	if not visible or _pending.is_empty():
		return RESULT_IGNORED
	var pending := _pending
	_pending = {}
	if pending["kind"] == KIND_DISCARD:
		return _commit_discard()
	var result := roster.move(pending["source"], pending["dest"])
	if not bool(result["ok"]):
		_set_outcome("Cannot move: %s" % String(result["reason"]))
		return RESULT_REJECTED
	_selected = {}
	_set_outcome("Done: %s" % String(pending["text"]))
	return RESULT_COMMITTED


## First press arms the discard; the second press (or Confirm) spends the Anchor.
func discard() -> StringName:
	if not visible or roster == null:
		return RESULT_IGNORED
	if roster.candidate == null:
		_set_outcome("There is no fallen hero to discard.")
		return RESULT_IGNORED
	if anchors <= 0:
		_set_outcome("Discarding %s needs an Echo Anchor, and you have none." % roster.candidate.display_name)
		return RESULT_REJECTED
	if not _pending.is_empty() and _pending["kind"] == KIND_DISCARD:
		return confirm()
	_selected = {}
	_pending = {"kind": KIND_DISCARD, "lost_name": roster.candidate.display_name}
	_set_outcome(
		"Spend 1 Echo Anchor and discard %s for good? Press X again or Enter to confirm, Esc to cancel."
		% roster.candidate.display_name
	)
	return RESULT_PENDING


func cancel() -> bool:
	if not visible or (_selected.is_empty() and _pending.is_empty()):
		return false
	_selected = {}
	_pending = {}
	_set_outcome("Selection cancelled.")
	return true


func can_start() -> bool:
	return visible and roster != null and roster.candidate == null


func start() -> bool:
	if not can_start():
		if visible:
			_set_outcome("Place or discard the fallen hero before starting the run.")
		return false
	_selected = {}
	_pending = {}
	hide()
	resolved.emit(anchors)
	return true


func get_text() -> String:
	var lines: Array[String] = [title_label.text, summary_label.text]
	for index in _row_locations.size():
		lines.append(row_buttons[index].text)
	lines.append_array([
		outcome_label.text,
		trial_label.text,
		coverage_label.text,
		next_hero_label.text,
		anchors_label.text,
		capacity_label.text,
	])
	return "\n".join(lines)


func get_row_text(row_index: int) -> String:
	if row_index < 0 or row_index >= _row_locations.size():
		return ""
	return row_buttons[row_index].text


func get_coverage_text() -> String:
	return coverage_label.text


func get_outcome_text() -> String:
	return outcome_label.text


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var handled := true
	var row_slot := ROW_KEYS.find(key.physical_keycode)
	if row_slot >= 0:
		if row_slot < _row_locations.size():
			_press_row(row_slot)
	elif key.physical_keycode == KEY_BACKSPACE or key.physical_keycode == KEY_ESCAPE:
		cancel()
	elif key.physical_keycode == KEY_X:
		discard()
	elif key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
		if not _pending.is_empty():
			confirm()
		else:
			start()
	else:
		handled = false
	if handled:
		_refresh()
		get_viewport().set_input_as_handled()


func _on_row_pressed(row_index: int) -> void:
	_press_row(row_index)
	_refresh()


func _on_start_pressed() -> void:
	if not start():
		_refresh()


func _press_row(row_index: int) -> void:
	if row_index < 0 or row_index >= _row_locations.size():
		return
	var location := _row_locations[row_index]
	select_row(StringName(location["zone"]), int(location["index"]))


func _try_move(source: Dictionary, dest: Dictionary) -> StringName:
	var preview := roster.preview(source, dest)
	if not bool(preview["ok"]):
		_set_outcome("Cannot move: %s" % String(preview["reason"]))
		return RESULT_REJECTED
	var lost_id := String(preview["lost_id"])
	var text := _describe_move(source, dest, lost_id)
	if not lost_id.is_empty():
		_pending = {
			"kind": KIND_MOVE,
			"source": source,
			"dest": dest,
			"text": text,
			"lost_id": lost_id,
			"lost_name": _name_for_id(lost_id),
		}
		_set_outcome(
			"%s — %s will be lost for good. Press the same row again or Enter to confirm, Esc to cancel."
			% [text, _pending["lost_name"]]
		)
		return RESULT_PENDING
	var result := roster.move(source, dest)
	if not bool(result["ok"]):
		_set_outcome("Cannot move: %s" % String(result["reason"]))
		return RESULT_REJECTED
	_selected = {}
	_set_outcome("Done: %s" % text)
	return RESULT_COMMITTED


func _commit_discard() -> StringName:
	var hero_name := roster.candidate.display_name if roster.candidate != null else ""
	var result := roster.discard_candidate(anchors)
	if not bool(result["ok"]):
		_set_outcome("Cannot discard: %s" % String(result["reason"]))
		return RESULT_REJECTED
	anchors = int(result["anchors_left"])
	_selected = {}
	_set_outcome("%s was discarded. 1 Echo Anchor spent." % hero_name)
	return RESULT_COMMITTED


func _describe_move(source: Dictionary, dest: Dictionary, lost_id: String) -> String:
	var mover := _record_at(source)
	var occupant := _record_at(dest)
	var parts: Array[String] = ["%s → %s" % [mover.display_name, _place_label(dest)]]
	if occupant != null:
		if occupant.runtime_id == lost_id:
			parts.append("%s → LOST" % occupant.display_name)
		elif StringName(source["zone"]) == Roster.ZONE_CANDIDATE:
			parts.append("%s → %s" % [
				occupant.display_name,
				_place_label({"zone": Roster.ZONE_MEMORIAL, "index": roster.memorial.size()}),
			])
		else:
			parts.append("%s → %s" % [occupant.display_name, _place_label(source)])
	return " · ".join(parts)


func _place_label(location: Dictionary) -> String:
	var zone := StringName(location["zone"])
	var index := int(location["index"])
	if zone == Roster.ZONE_CANDIDATE:
		return "Candidate"
	var records := roster.party if zone == Roster.ZONE_PARTY else roster.memorial
	return "%s %d" % ["Party" if zone == Roster.ZONE_PARTY else "Memorial", mini(index, records.size()) + 1]


func _name_for_id(runtime_id: String) -> String:
	for record: HeroRecord in roster.party + roster.memorial:
		if record.runtime_id == runtime_id:
			return record.display_name
	return runtime_id


func _record_at(location: Dictionary) -> HeroRecord:
	var zone := StringName(location["zone"])
	var index := int(location["index"])
	if zone == Roster.ZONE_CANDIDATE:
		return roster.candidate if index == 0 else null
	var records := roster.party if zone == Roster.ZONE_PARTY else roster.memorial
	return records[index] if index >= 0 and index < records.size() else null


func _same_location(a: Dictionary, b: Dictionary) -> bool:
	return StringName(a["zone"]) == StringName(b["zone"]) and int(a["index"]) == int(b["index"])


func _row_index_of(location: Dictionary) -> int:
	for index in _row_locations.size():
		if _same_location(_row_locations[index], location):
			return index
	return -1


func _set_outcome(text: String) -> void:
	_outcome_text = text
	_refresh()


func _refresh() -> void:
	if roster == null:
		return
	_rebuild_row_locations()
	title_label.text = String(_context.get("title", "ROSTER RESOLUTION"))
	summary_label.text = String(_context.get("summary", ""))
	summary_label.visible = not summary_label.text.is_empty()
	for index in row_buttons.size():
		var button := row_buttons[index]
		button.visible = index < _row_locations.size()
		if button.visible:
			_refresh_row(index)
	outcome_label.text = _outcome_text
	var encounter_id := StringName(_context.get("encounter_id", &"bell_court"))
	var needs := EncounterCatalog.get_needs(encounter_id)
	var need_names: Array[String] = []
	for need: Variant in needs:
		need_names.append(PartyNeeds.need_label(StringName(need)))
	trial_label.text = "Next Trial: %s\nNeeds: %s" % [
		EncounterCatalog.get_display_name(encounter_id),
		" · ".join(need_names) if not need_names.is_empty() else "none",
	]
	coverage_label.text = _coverage_text(needs)
	next_hero_label.text = _next_hero_text(needs)
	anchors_label.text = "Echo Anchors: %d" % anchors
	capacity_label.text = RosterCapacity.hint_text(
		_context.get("unlocks", []),
		int(_context.get("trial_clears", 0))
	)
	discard_button.disabled = roster.candidate == null or anchors <= 0
	confirm_button.visible = not _pending.is_empty()
	cancel_button.disabled = _selected.is_empty() and _pending.is_empty()
	start_button.disabled = roster.candidate != null
	start_button.text = "Start run [Enter]" if roster.candidate == null else "Place hero first"


func _rebuild_row_locations() -> void:
	_row_locations.clear()
	_row_locations.append({"zone": Roster.ZONE_CANDIDATE, "index": 0})
	for index in roster.get_party_slots():
		_row_locations.append({"zone": Roster.ZONE_PARTY, "index": index})
	for index in roster.get_memorial_slots():
		_row_locations.append({"zone": Roster.ZONE_MEMORIAL, "index": index})
	if _row_locations.size() > MAX_ROWS:
		_row_locations.resize(MAX_ROWS)


func _refresh_row(row_index: int) -> void:
	var location := _row_locations[row_index]
	var button := row_buttons[row_index]
	var record := _record_at(location)
	var zone := StringName(location["zone"])
	var heading := "CANDIDATE"
	if zone == Roster.ZONE_PARTY:
		heading = "PARTY %d" % (int(location["index"]) + 1)
	elif zone == Roster.ZONE_MEMORIAL:
		heading = "MEMORIAL %d" % (int(location["index"]) + 1)
	var content := "— none —" if zone == Roster.ZONE_CANDIDATE else "— empty —"
	if record != null:
		content = hero_label(record)
	var prefix := ""
	var style_name := &"normal"
	if not _selected.is_empty() and _same_location(_selected, location):
		prefix = "▶ "
		style_name = &"selected"
	elif (
		not _pending.is_empty()
		and _pending["kind"] == KIND_MOVE
		and _same_location(_pending["dest"], location)
	):
		prefix = "✖ "
		style_name = &"loss"
	button.text = "%s[%d] %s · %s" % [prefix, row_index + 1, heading, content]
	button.add_theme_stylebox_override(&"normal", _styles[style_name])
	button.add_theme_stylebox_override(&"pressed", _styles[style_name])
	button.add_theme_stylebox_override(
		&"hover",
		_styles[style_name] if style_name != &"normal" else _styles[&"hover"]
	)
	button.add_theme_color_override(
		&"font_color",
		ROW_TEXT_COLOR if record != null else ROW_EMPTY_TEXT_COLOR
	)
	button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	button.add_theme_color_override(&"font_pressed_color", ROW_TEXT_COLOR)


func _coverage_text(needs: Array) -> String:
	if needs.is_empty():
		return "Roster covers: no Trial needs"
	var coverage := PartyNeeds.evaluate(roster.party_job_ids(), needs)
	var covered: Dictionary = coverage["covered"]
	var parts: Array[String] = []
	for need_value: Variant in needs:
		var need := StringName(need_value)
		if covered.has(need):
			parts.append("%s ✓ %s" % [PartyNeeds.need_label(need), JobCatalog.get_display_name(covered[need])])
		else:
			parts.append("%s ✗" % PartyNeeds.need_label(need))
	return "Roster covers: %s" % " · ".join(parts)


func _next_hero_text(needs: Array) -> String:
	var uncovered := PartyNeeds.uncovered(roster.party_job_ids(), needs)
	if uncovered.is_empty():
		return "Every Trial need is covered by the roster ✓"
	var lines: Array[String] = []
	for need in uncovered:
		lines.append(PartyNeeds.missing_line(need).trim_prefix("Missing: "))
	return "Your next hero should fill: %s" % "; ".join(lines)


func _make_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


static func hero_label(record: HeroRecord) -> String:
	var recorded := record.replay_progression()
	return "%s · %s · Lv %d" % [
		record.display_name,
		JobCatalog.get_display_name(recorded.get_job_id()),
		recorded.level,
	]


func _record_state(record: HeroRecord) -> Dictionary:
	var recorded := record.replay_progression()
	return {
		"id": record.runtime_id,
		"name": record.display_name,
		"job_id": String(recorded.get_job_id()),
		"level": recorded.level,
	}


func _mcp_state() -> Dictionary:
	var party_state: Array[Dictionary] = []
	var memorial_state: Array[Dictionary] = []
	var row_texts: Array[String] = []
	var candidate_state := {}
	if roster != null:
		for record: HeroRecord in roster.party:
			party_state.append(_record_state(record))
		for record: HeroRecord in roster.memorial:
			memorial_state.append(_record_state(record))
		if roster.candidate != null:
			candidate_state = _record_state(roster.candidate)
		for index in _row_locations.size():
			row_texts.append(row_buttons[index].text)
	var selected_text := ""
	if not _selected.is_empty():
		selected_text = "%s:%d" % [String(_selected["zone"]), int(_selected["index"])]
	return {
		"visible": visible,
		"candidate": candidate_state,
		"party": party_state,
		"memorial": memorial_state,
		"party_slots": roster.get_party_slots() if roster != null else 0,
		"memorial_slots": roster.get_memorial_slots() if roster != null else 0,
		"anchors": anchors,
		"can_start": can_start(),
		"coverage_text": coverage_label.text,
		"next_hero_text": next_hero_label.text,
		"capacity_text": capacity_label.text,
		"outcome_text": outcome_label.text,
		"summary_text": summary_label.text,
		"rows": row_texts,
		"selected": selected_text,
		"pending_kind": String(_pending.get("kind", "")),
		"pending_lost_name": String(_pending.get("lost_name", "")),
		"discard_enabled": not discard_button.disabled,
	}
