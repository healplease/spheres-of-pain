class_name Scoring
extends RefCounted

## Pure scoring helper — the "how cleanly did you end the suffering" reckoning. Static-only;
## no nodes, no logging; every input is a plain int the controller already has, so GridModel
## stays pure. Score is never shown as a raw arcade counter (see the controller's diegetic
## surfacing) — it resolves into one verdict word at the end.
##
## The skill axis the genre rewards is ISOLATION: detaching a big mass with one shot (our
## orphan sweep) pays super-linearly, while the matched pop itself stays modest. So a clever
## cluster-drop dwarfs brute-forcing many small 3-matches.

enum Tier { CLEANLY, FREED, BARELY }

const MATCH_POINTS := 10  # modest, linear, per sphere in the matched 3+ cluster
const ISOLATION_POINTS := 25  # weight on the super-linear (quadratic) orphan-sweep term
const ALL_CLEAR_BONUS := 1000  # flat marquee reward for emptying the board in one suffering
const ECONOMY_PER_SPARE_SHOT := 50  # per shot left unused under par

## Par-relative slack for the middle verdict tier: clear within par is CLEANLY, within
## par+TIER_PAR_SLACK is FREED, anything slower is BARELY.
const TIER_PAR_SLACK := 2


## Points for one resolved attach. The matched cluster pays a modest linear amount; the
## orphan sweep it triggers pays the SQUARE of its mass — engineering one big detachment
## (e.g. 5 orphans -> 625) far out-earns several small ones (5 x [1 orphan -> 25] = 125).
## (A capped-geometric curve is the alternative: ISOLATION_POINTS*(pow(1.6, orphaned)-1),
## clamped — steeper, but it needs an explicit cap; quadratic self-bounds via board size.)
static func shot_score(popped: int, orphaned: int) -> int:
	return popped * MATCH_POINTS + ISOLATION_POINTS * orphaned * orphaned


## Flat reward for clearing the whole board (the win shot). The marquee all-clear event.
static func all_clear_bonus() -> int:
	return ALL_CLEAR_BONUS


## Reward for finishing under par. 0 when par is unset (0) — an un-tuned level offers no
## yardstick — and never negative (going over par simply earns nothing here).
static func economy_bonus(par_shots: int, shots_used: int) -> int:
	if par_shots <= 0:
		return 0
	return maxi(0, par_shots - shots_used) * ECONOMY_PER_SPARE_SHOT


## The end-screen verdict tier from how the clear compared to par. With no par set we never
## claim CLEANLY (there's nothing to have been clean against) and report the neutral FREED.
static func tier(par_shots: int, shots_used: int) -> Tier:
	if par_shots <= 0:
		return Tier.FREED
	if shots_used <= par_shots:
		return Tier.CLEANLY
	if shots_used <= par_shots + TIER_PAR_SLACK:
		return Tier.FREED
	return Tier.BARELY


## The fiction word for a tier, for the end-screen epitaph ("CLEANLY. 41 freed...").
static func tier_word(t: Tier) -> String:
	match t:
		Tier.CLEANLY:
			return "CLEANLY"
		Tier.FREED:
			return "FREED"
		_:
			return "BARELY"
