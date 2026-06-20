extends GutTest

## Tests for Scoring — the pure "how cleanly did you end it" reckoning. The design intent that
## these pin: the isolation sweep is super-linear and must dominate brute-forced small matches.

# --- per-shot score ------------------------------------------------------------


func test_matched_pop_is_linear() -> void:
	assert_eq(Scoring.shot_score(3, 0), 30, "3 matched, no sweep")
	assert_eq(Scoring.shot_score(6, 0), 60, "matched component is linear in popped")


func test_isolation_is_quadratic() -> void:
	assert_eq(Scoring.shot_score(0, 1), 25, "1 orphan")
	assert_eq(Scoring.shot_score(0, 2), 100, "2 orphans -> 4x, not 2x")
	assert_eq(Scoring.shot_score(0, 5), 625, "5 orphans -> 25x one orphan")


func test_isolation_is_super_linear() -> void:
	# One big detachment must beat splitting the same mass across smaller ones.
	assert_gt(
		Scoring.shot_score(0, 4),
		2 * Scoring.shot_score(0, 2),
		"4-in-one sweep out-earns two 2-sweeps"
	)


func test_isolation_dominates_matching() -> void:
	# A modest match with a big sweep must beat a huge match with no sweep — the skill axis.
	assert_gt(Scoring.shot_score(3, 5), Scoring.shot_score(12, 0), "isolation is the marquee event")


func test_empty_shot_scores_zero() -> void:
	assert_eq(Scoring.shot_score(0, 0), 0, "a dud scores nothing")


# --- bonuses -------------------------------------------------------------------


func test_all_clear_bonus_is_flat() -> void:
	assert_eq(Scoring.all_clear_bonus(), 1000, "flat all-clear reward")


func test_economy_rewards_spare_shots() -> void:
	assert_eq(Scoring.economy_bonus(10, 7), 150, "3 shots under par * 50")
	assert_eq(Scoring.economy_bonus(10, 10), 0, "exactly par earns no economy")


func test_economy_never_negative() -> void:
	assert_eq(Scoring.economy_bonus(10, 14), 0, "over par earns nothing, never negative")


func test_economy_zero_when_par_unset() -> void:
	assert_eq(Scoring.economy_bonus(0, 5), 0, "no par -> no economy yardstick")


# --- verdict tier --------------------------------------------------------------


func test_tier_boundaries() -> void:
	assert_eq(Scoring.tier(10, 9), Scoring.Tier.CLEANLY, "under par is cleanly")
	assert_eq(Scoring.tier(10, 10), Scoring.Tier.CLEANLY, "exactly par is cleanly")
	assert_eq(Scoring.tier(10, 12), Scoring.Tier.FREED, "par+2 is freed")
	assert_eq(Scoring.tier(10, 13), Scoring.Tier.BARELY, "past par+2 is barely")


func test_tier_freed_when_par_unset() -> void:
	assert_eq(Scoring.tier(0, 99), Scoring.Tier.FREED, "no par -> neutral FREED, never CLEANLY")


func test_tier_word_round_trips() -> void:
	assert_eq(Scoring.tier_word(Scoring.Tier.CLEANLY), "CLEANLY")
	assert_eq(Scoring.tier_word(Scoring.Tier.FREED), "FREED")
	assert_eq(Scoring.tier_word(Scoring.Tier.BARELY), "BARELY")
