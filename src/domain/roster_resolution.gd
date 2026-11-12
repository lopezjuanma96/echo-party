class_name RosterResolution
extends RefCounted


static func default_choice(roster: Roster) -> Dictionary:
	if roster.party.size() < roster.get_party_slots():
		return {"zone": Roster.ZONE_PARTY, "index": roster.party.size()}
	if roster.memorial.size() < roster.get_memorial_slots():
		return {"zone": Roster.ZONE_MEMORIAL, "index": roster.memorial.size()}
	return {"zone": Roster.ZONE_PARTY, "index": 0}
