class_name PartyNeeds
extends RefCounted
## Pure coverage logic: which encounter needs a set of jobs covers, using the
## `provides` tags in JobCatalog. Holds no nodes and no state.


## Returns {"covered": {need: covering_job_id}, "uncovered": [need, ...]}.
## The first job in `job_ids` that provides a need is its covering job; empty
## job ids (no echo) are ignored. Result order follows `needs`.
static func evaluate(job_ids: Array, needs: Array) -> Dictionary:
	var covered := {}
	var uncovered: Array[StringName] = []
	for need_value: Variant in needs:
		var need := StringName(need_value)
		var covering_job := &""
		for job_value: Variant in job_ids:
			var job_id := StringName(job_value)
			if job_id.is_empty():
				continue
			if JobCatalog.get_provides(job_id).has(need):
				covering_job = job_id
				break
		if covering_job.is_empty():
			uncovered.append(need)
		else:
			covered[need] = covering_job
	return {"covered": covered, "uncovered": uncovered}


static func covered(job_ids: Array, needs: Array) -> Dictionary:
	return evaluate(job_ids, needs)["covered"]


static func uncovered(job_ids: Array, needs: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(evaluate(job_ids, needs)["uncovered"])
	return result


## Choosable jobs that provide `need`, in level-3 choice order.
static func providers(need: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for job_id in HeroProgression.JOB_IDS:
		if JobCatalog.get_provides(job_id).has(need):
			result.append(job_id)
	return result


## Which of `uncovered_needs` a job would newly cover.
static func fills(job_id: StringName, uncovered_needs: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	var provided := JobCatalog.get_provides(job_id)
	for need_value: Variant in uncovered_needs:
		if provided.has(StringName(need_value)):
			result.append(StringName(need_value))
	return result


static func need_label(need: StringName) -> String:
	return String(need).to_upper()


## Level-3 modal annotation, e.g. "Fills Trial need: SUSTAIN ★"; empty when the
## job covers none of the uncovered needs.
static func fill_annotation(job_id: StringName, uncovered_needs: Array) -> String:
	var labels: Array[String] = []
	for need in fills(job_id, uncovered_needs):
		labels.append(need_label(need))
	if labels.is_empty():
		return ""
	return "Fills Trial need: %s ★" % " · ".join(labels)


## Report line for an uncovered need, e.g. "Missing: SUSTAIN → Mender provides SUSTAIN".
static func missing_line(need: StringName) -> String:
	var names: Array[String] = []
	for job_id in providers(need):
		names.append(JobCatalog.get_display_name(job_id))
	var label := need_label(need)
	if names.is_empty():
		return "Missing: %s → no job provides %s" % [label, label]
	return "Missing: %s → %s provides %s" % [label, " or ".join(names), label]
