class_name EnemyTargeting
extends RefCounted


static func nearest_friendly(source: Node2D) -> Node2D:
	if source == null or not source.is_inside_tree():
		return null
	var best: Node2D
	var best_distance_squared := INF
	for actor_node in source.get_tree().get_nodes_in_group(&"friendly_actors"):
		var actor := actor_node as Node2D
		if not _is_valid_target(actor):
			continue
		var distance_squared := source.global_position.distance_squared_to(actor.global_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and (best == null or actor.name.naturalnocasecmp_to(best.name) < 0)
			)
		):
			best = actor
			best_distance_squared = distance_squared
	return best


## Lowest health fraction within `max_dist`; ties go to the nearer actor, then
## to natural node-name order.
static func weakest_friendly(source: Node2D, max_dist: float) -> Node2D:
	if source == null or not source.is_inside_tree():
		return null
	var best: Node2D
	var best_fraction := INF
	var best_distance_squared := INF
	for actor_node in source.get_tree().get_nodes_in_group(&"friendly_actors"):
		var actor := actor_node as Node2D
		if not _is_valid_target(actor):
			continue
		var distance_squared := source.global_position.distance_squared_to(actor.global_position)
		if distance_squared > max_dist * max_dist:
			continue
		var maximum_health := float(actor.get("max_health"))
		if maximum_health <= 0.0:
			continue
		var health_fraction := float(actor.get("health")) / maximum_health
		var is_tie := is_equal_approx(health_fraction, best_fraction)
		if (
			health_fraction < best_fraction and not is_tie
			or (
				is_tie
				and (
					distance_squared < best_distance_squared
					or (
						is_equal_approx(distance_squared, best_distance_squared)
						and actor.name.naturalnocasecmp_to(best.name) < 0
					)
				)
			)
		):
			best = actor
			best_fraction = health_fraction
			best_distance_squared = distance_squared
	return best


static func _is_valid_target(actor: Node2D) -> bool:
	return (
		actor != null
		and not actor.is_queued_for_deletion()
		and not bool(actor.get("is_defeated"))
	)
