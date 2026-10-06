# Batch 1: Money and home

Three features that put weight on the week: selling your own things, rent,
and the court date after a bust. All three live mostly in `GameState` and
reuse rooms and NPCs that already exist. No new scene file is needed.

## 1. The apartment empties out

### Belongings

Five things in the apartment are yours to sell. Each one is a
`REQUEST_POOL` entry with `"store": "home"` and `"no_order": true`, so no
regular ever orders one and existing item lookups (`item_name_for`,
`item_info`) just work.

| id       | name                 | pawn value | where it is in the apartment                            |
|----------|----------------------|-----------:|---------------------------------------------------------|
| `tv`     | your TV              | $24        | the existing `TV` node (its Glow light and Static sound go too) |
| `radio`  | the old radio        | $8         | the `Radio` model on the existing crate (the crate stays) |
| `guitar` | your guitar          | $30        | **new**: an acoustic guitar from primitives, leaning on the east wall |
| `coat`   | your winter coat     | $10        | **new**: a coat on a hook by the door (batch 3's cold nights reads it) |
| `ring`   | your mother's ring   | $45        | **new**: a small box on the radio crate                 |

`GameState.belongings: Dictionary` maps each id to `"home"`, `"carried"`,
`"pawned"` or `"gone"`. It starts every run with all five `"home"`.

### Taking something to sell

- Each belonging gets an `Interactable3D` zone (new
  `interactables/Belonging3D.gd`, with the id in metadata). Using it opens
  a `ChoiceMenu`: "Take it" / "Leave it", with a line that fits the thing.
  The ring's line is the heaviest one.
- Taking it adds the id to `inventory`, sets it to `"carried"`, hides the
  node in the room and writes a diary line ("Took the TV off its box.").
- `Apartment3D._ready()` hides every belonging that isn't `"home"`.
- They're yours, not stolen, so:
  - `get_busted()` keeps belongings in your pockets (everything else is
    still evidence).
  - The bartender's fence (`fence_everything`) won't take them ("I'm not a
    pawnshop").
  - The patrol cop's "carrying goods" suspicion ignores them.
  - Shelter cot theft **can** take one. It's then `"gone"` for good.

### The pawnshop

- `PawnBroker3D.offer_for()` pays full pawn value for `"home"` items (no
  serial-number cut).
- Selling one writes a pawn ticket: `pawn_tickets[id] = day`. The item is
  `"pawned"`.
- **Buying back:** the pawnbroker's menu lists each ticket as "Buy back
  your TV -- $36 (holds till day 7)". The price is `ceil(value * 1.5)` and
  the ticket holds for `PAWN_HOLD_DAYS = 4` days. When a day starts past
  that, the item is sold to someone else and becomes `"gone"`, with a
  diary line.
- A bought-back item goes into your pockets as `"carried"`. Walking into
  the apartment with it puts it back (`"home"`, node shown again) with one
  line: "You put the guitar back where it goes."

### Seeing it

- Entering the apartment with 3+ belongings not home plays one narrated
  line, once per run ("The room echoes now.").
- All five gone writes "Nothing left to sell." in the diary.
- The notebook's Notes page lists open pawn tickets and their last day.

## 2. Rent day

- `RENT = 35`, due every `RENT_PERIOD = 5` days, by midnight at the end of
  `rent_due_day` (starts at 5). That's about one good order a week, enough
  to compete with the fix without crushing a run.
- **Paying:** a new `RentSlot` zone on the apartment wall by the door
  ("the envelope slot to the landlord's office"). It pays the current
  amount any time, then sets `rent_due_day += RENT_PERIOD`.
- **Reminders:** on the morning of the due day, the HUD toast says "Rent's
  due tonight: $35." The notebook always shows the next due day, and a
  paper notice (`Label3D`) appears on the inside of the apartment door on
  the due day.
- **Missing it** (checked when the day rolls over), `rent_stage`:
  - `0` paid up.
  - `1` **final notice**: `rent_owed = RENT + LATE_FEE (10)` and one more
    day to pay.
  - `2` **locked out**: the lock is changed. `rent_owed += LOCKSMITH (20)`.
- **Locked out:**
  - The City's `DoorToHome` checks `rent_stage` before loading the room.
    It opens a `ChoiceMenu` instead: "Buzz the landlord" (08-22) to pay
    everything owed, if you have it, or walk away.
  - If you're inside the apartment when the lockout hits, the landlord
    bangs on the door and you're shown out (the same pattern as
    `WorldRoot3D._show_out`).
  - Belongings still at home are out of reach, not lost. Paying gets you
    back in with everything where it was.
  - The shelter cots are where you sleep in the meantime, and they
    already exist.
  - Paying in full resets `rent_stage = 0` and `rent_due_day = day + 5`.

## 4. Court date and probation

The police station's door, which is just a mesh today, becomes an
interactable `PoliceDoor` zone on the City block, open for business 09-17.
All of the court logic sits behind it, so no courtroom scene is needed.

### Court

- A bust that doesn't end the run sets `court_day = day + 2` (09-12). A
  second bust before then just moves the date.
- **Showing up** (`PoliceDoor` during court hours):
  - If you're **in the treatment program**, it's drug court. Your case is
    diverted and **one strike comes off** (`strikes -= 1`, min 0). This
    gives a real reason to enroll.
  - Otherwise, **probation**: check in at the same door on each of the
    next 3 days (09-17).
- **Missing court** (it's past 12:00 on `court_day`) sets `warrant = true`.

### Probation check-ins

Each check-in is a drug test. It fails if you used anything off the
street in the last 24 game hours. That's tracked by a new
`last_street_use` (`now_minutes()` of the last dose that sets
`used_today`). Treatment doses and cannabis don't count, the same as the
existing `used_today` rule.

- **Pass:** that day is ticked off.
- **Fail:** a probation violation. `get_busted()` adds a strike, the scene
  changes to the jail cell, and probation ends.
- **Miss a check-in day:** `warrant = true`.

### Warrant

- `PatrolCop3D` gets `RATE_WARRANT = 0.9` suspicion per second whenever
  you're in its cone, even if you're not carrying anything. When that
  fills, it's the usual chase.
- **Clearing it:**
  - Get busted (the usual strike; this also sets a new court date).
  - Or **turn yourself in** at the `PoliceDoor`. You go to the cell with no
    strike and no fine, the warrant clears and court is reset to
    `day + 2`.
- The HUD shows a small red "WARRANT" tag. The notebook writes it in red
  ink.

## Shared changes

- **`GameState`**: new fields `belongings`, `pawn_tickets`,
  `rent_due_day`, `rent_owed`, `rent_stage`, `court_day`,
  `probation_days` (Array of day numbers still to check in), `warrant`,
  `last_street_use`, `apartment_echo_seen`. All are reset in `start_run()`
  and added to `SaveGame.FIELDS`. Day-rollover checks (pawn tickets
  expiring, rent stage, missed court and check-ins) go in one
  `_on_new_day()` that both `advance_clock` and `sleep` call.
- **HUD**: one compact line under the debt panel, for whichever is most
  urgent: "Rent $35 due tonight", "Court 09-12 today", "Check in at the
  station", or "WARRANT".
- **Notebook** Notes page: rent, court and probation dates, open pawn
  tickets.
- **Room builder** (`dev-tools/build_rooms_3d.gd`): guitar, coat hook, ring
  box, belonging zones and the rent slot in the apartment. The PoliceDoor
  zone on the City. The scenes are rebuilt with
  `godot --headless --path . res://dev-tools/BuildRooms3D.tscn`.

## Testing

New sections in `dev-tools/smoke_test_3d.gd`, using the existing
`_section` / `_check` style and a stopped clock:

1. Take the TV: it's in inventory, hidden in the room, survives a bust,
   the fence refuses it, the pawn pays $24, buyback costs $36, it expires
   after 4 days, and a bought-back TV goes home on entering.
2. Rent: due day 5, paying moves it to 10, skipping gives final notice
   then a lockout, the City door refuses entry, paying the landlord
   restores it, and you're shown out if you're inside at lockout.
3. Court: a bust sets court +2, appearing while in treatment removes a
   strike, appearing otherwise starts probation, a clean check-in passes,
   a dirty one busts you, a missed day gives a warrant, the patrol spots
   you with a warrant, and turning yourself in clears it without a
   strike.
4. Save/continue round-trips every new field.

Then a full headless run of the smoke test, and `full_playthrough.gd`, to
check nothing old broke.

## Out of scope

Phone calls about rent or court (batch 3). Cold nights reading the coat
(batch 3). A courtroom scene or cutscene stills (the door dialogue
carries it; stills can come later through `gen_cutscenes.py`).
