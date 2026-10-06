# Batch 2: The street gets dangerous

Three features that put other people's lives and livelihoods on the block:
someone going over in the alley, a contaminated supply, and a rival
shoplifter. They reuse the outreach desk, the headlines, the regulars'
rep, store heat and the beat cop. Each one is a new small script that
`City3D` adds, like `Temptation` and `StreetScenes`.

## 5. Someone goes over in the alley

### When

- `world/AlleyOverdose.gd`, a node `City3D` adds. Once a day it rolls
  whether tonight someone goes down: 25% on an ordinary day, 100% on a
  bad batch day (feature 6), never on day 1. If so, it picks a start
  time between 18:00 and 01:00. The roll is stored in GameState
  (`od_event`: `{day, minute, who, state}`) so it saves and doesn't
  reroll.
- **Who:** one of the six Dive Bar regulars (`DiveBar3D.PATRON_NAMES`)
  who's still alive, so it's always someone you might know.

### What you see

- From the start time, they're on the ground at the far end of the
  dumpster (about x = 21.5, z = -3.6). They're the regular's own
  character model playing its `Death` clip and holding the last frame. A
  faint groaning breath plays at a slow interval.
- The HUD toast when you're on the block: "Someone's down in the alley
  by the dumpster."
- They have `OD_WINDOW = 90` real seconds (6 game hours) from when you
  first see them. Rooms the player isn't in don't run, so the clock only
  counts while you're on the block. If you leave and come back, they're
  still there, and so is the time they had left.

### What you can do (a `ChoiceMenu` when you walk up)

| Choice | Needs | Outcome |
|---|---|---|
| **Use your naloxone** | `naloxone >= 1` | They come round, gasping. Saved. `rep +3`. You spend one kit. |
| **Shout for help, run for the payphone** | nothing | An ambulance comes (a siren), and so does a cop: a `PatrolCop3D` spawns at the alley mouth, walking. If you're carrying stolen goods or have a warrant, the usual suspicion applies. Saved. `rep +2`. |
| **Go through their pockets** | nothing | `+$8-20` and maybe their order item. They die. |
| **Walk away** | nothing | Two in three die; one in three, someone else calls it in. |

If the window runs out, it's the same as walking away.

### Consequences

- **Saved:** a diary line and a cutscene-free narrated line from them.
  The next time you see them in the bar: "You were there. I don't
  remember it, but I know."
- **Died:**
  - A diary line, "<name> died in the alley.", with the existing
    `overdose_floor` still.
  - They're added to `GameState.dead_regulars`, so `DiveBar3D` never seats
    them again, and they're dropped from the notebook's who-feels-what.
  - The next day's headline is forced to a new `"vigil"` event: candles at
    the alley mouth (a few `OmniLight3D`s and `Label3D` "RIP <name>"). Also
    on the vigil day, the pusher's prices go down 10%, because the corner
    is quiet with grief and police. This is the one thing on the block
    that changes for it.
- **Robbed them:** as "died", plus a 50% chance someone saw. If seen, every
  living regular gets `rep -2`.

## 6. Bad batch, and test strips

### The headline

- A new `Headlines` event `"bad_batch"` (weight 2): "A bad batch is going
  around. Two people went over on the next block last night. Outreach is
  handing out test strips."
- On a bad batch day, every opioid bought from the pusher has a
  `BAD_BATCH_CHANCE = 0.4` chance to be **contaminated**. Contaminated
  means its OD risk ×3 for that dose.

### Test strips

- The outreach worker gets a fourth option: **"Take test strips"**, two
  strips, once a day (`daily_available("shelter_strips")`).
  `GameState.test_strips: int`.
- After the pusher's handoff, if you have a strip and what you got is an
  opioid, a `ChoiceMenu` comes up before it takes effect:
  - **Test it first** spends a strip. It reveals the truth: whether it's
    fentanyl when you asked for something else (the existing fake
    mechanic), and whether it's contaminated. Then:
    - **Take it anyway** (the normal dose)
    - **Take a little at a time**: half the relief, half the risk
      (`dose_scale = 0.5`)
    - **Throw it away**: the money's gone, and you get no relief
  - **Just take it** skips the test.
- `GameState.take_drug(drug_id, dose_scale := 1.0, risk_mult := 1.0)` gets
  the two optional parameters. `dose_scale` scales both relief and risk,
  and the load it adds. `risk_mult` carries the contamination. Every
  existing caller is unchanged.

## 7. A rival booster

### Who

- **Tasha**, a new character (CharacterCast role `booster`, a female body
  in a dark hoodie). She's on the block on `BOOSTER_DAYS = 40%` of days
  (rolled at day start, stored in GameState so it saves), 10:00-20:00.
- She's never there on day 1 or on a vigil day.

### What she does

- Every game hour she's out, she "works" one of the five stores. She
  stands by its door for the hour, and at the end of the hour it's hit:
  `set_store_heat(store, 1.3, 1)`. The toast reads "Someone just hit the
  liquor store. Staff will be jumpy." That store is harder for you for
  the rest of the day.
- Her current store and the stores she's hit show on the notebook's Map
  page (a small "T" by the store).

### What you can do (a `ChoiceMenu` when you walk up)

- **Team up** (once a day): she picks a store with you and works the
  clerk.
  - For the rest of the day, that store's alertness is ×0.6
    (`set_store_heat(store, 0.6, 1)`), and she stops hitting other stores.
  - Her price: half of the next order payout you collect
    (`GameState.booster_cut_pending = true`, applied in `sell_item`, with
    one line from her when she collects).
- **Rat her out**: she's picked up within the hour and gone for the rest
  of the run (`booster_gone = true`).
  - Every store she hit today has its heat cleared.
  - If you have a warrant, the cop "loses the paperwork": it's cleared.
  - The street notices: Ray's trust is set to 0, and every living regular
    gets `rep -1`.
- **Leave her be.**

## Shared changes

- **`GameState`**: `od_event`, `dead_regulars`, `test_strips`,
  `booster_day`, `booster_gone`, `booster_cut_pending`, `booster_hit`
  (store ids hit today). All are reset in `start_run`, saved in
  `SaveGame.FIELDS`, and rolled in `_on_new_day` (from batch 1).
- **`Headlines`**: `bad_batch` and `vigil` events. Vigil has weight 0 and
  is forced by a death, like `track_shut`. Add `pusher_price_mult` 0.9
  for vigil, and `od_risk_mult()` (1.0, or what bad batch implies).
- **`DiveBar3D`**: skip `dead_regulars` when seating and when taking
  orders.
- **`Outreach3D`**: the strips option.
- **`Pusher3D._handoff`**: contamination and the test-strip menu.
- **`CharacterCast`**: a `booster` role.

## Testing

New `smoke_test_3d.gd` sections plus a `dev-tools/smoke_batch2.gd`
runner:

1. **Overdose:**
   - The roll is 25% (seeded, many trials) and forced on a bad batch day.
   - The victim is a living regular and appears in the alley at the
     start time.
   - Each of the four choices gives its outcome.
   - The window expiring counts as walking away.
   - A dead regular is never seated or ordering again.
   - The vigil headline follows a death.
2. **Bad batch:**
   - The contamination rate is about 40% over many purchases.
   - Contaminated risk is ×3.
   - A strip reveals fentanyl and contamination.
   - A half dose halves relief and risk.
   - Throwing it away gives nothing.
   - Strips are once a day at outreach.
3. **Booster:**
   - She appears on her days, never on day 1.
   - Hits add store heat.
   - Teaming up lowers one store's heat and takes half of the next order.
   - Ratting clears the heat she caused and any warrant, costs rep, and
     she's gone.
4. Save/continue round-trips every new field.

Plus a full smoke run.

## Out of scope

New cutscene stills (the vigil and the alley use existing stills or
none). Phone calls about any of it (batch 3). Ratting on anyone else.
