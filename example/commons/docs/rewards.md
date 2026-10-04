# Rewards

A daily reward with a login streak and a calendar menu, plus playtime tracking
with playtime rewards. The module is called `rewards`, depends on `economy`
(all money goes through the `Economy` service) and provides `RewardsApi`
(`canClaimDaily(uuid)`) to the other modules.

## Commands

| Command | Does |
| --- | --- |
| `/daily` | Claims today's reward. If it was already claimed it says how long until the next one, your streak and what the next reward is. |
| `/rewards` | Opens the reward calendar (a chest menu). |
| `/playtime [player]` (`/pt`) | How long a player has played. For yourself it also shows the next playtime reward and how far away it is. Other players need `commons:rewards.playtime.others`. |
| `/playtop [page]` | The players with the most playtime, 10 per page with clickable page links. |

When a player joins, a few seconds later they are reminded with a clickable
`[Claim]` if the reward is ready (`joinReminder`), and reward items that did
not fit earlier are handed over.

## The daily reward

### What a day is

A **day** runs from `resetHourUtc` (default 00:00 UTC) to the same hour the
next day. A player claims **once per day**; the rolling-24-hours alternative was
rejected because the claim time would drift later every day, and a player who
claims at 23:59 would then not be able to claim at 00:01 the next night. Every
player sees the same reset time, which `/daily` shows as a countdown.

### Streak

* The first claim is day 1 of a streak. Each claim on a following day makes it
  one longer.
* Missing days is forgiven up to `graceDays` whole days (default 1): claim on
  Monday, skip Tuesday, claim on Wednesday and the streak continues. Skip more
  and it starts again at day 1 (`/daily` and the calendar say so). The best
  streak is remembered.
* The streak counts claims, so after a forgiven gap the next day number is just
  one higher.
* If the server clock ever goes backwards, a player who claimed "in the future"
  counts as having claimed today: nobody can claim twice because of it.

### Reward

The reward of streak day *d* is

```
baseAmount + incrementPerDay * (min(d, maxGrowthDays) - 1)
```

so with the defaults (100, 25, 7) it is 100, 125, ... 250 on day 7 and 250 for
every later day. The streak itself has no cap.

**Milestones** add a bonus (`currency` and/or `items`) on an exact streak day,
for example day 7 (default: 500 coins and 3 diamonds). A streak that was lost
and builds up again earns its milestones again.

If the money cannot be paid (the player's balance is at its maximum) the claim
fails with a message and nothing is recorded, so it can be repeated. Items go
to the inventory (stacks are topped up first); what does not fit is remembered
(`pendingItems`) and handed over on the next `/daily`, `/rewards` claim or join
instead of being lost.

On a claim the player sees a title, hears a sound (by registry name, e.g.
`minecraft:entity.player.levelup`, a more festive one for milestones; the
`Sound` enum path is avoided because of the host bug in `pumpkin_api`'s
`docs/feedback.md`), and gets a chat message with the amount and new balance.

### Calendar

`/rewards` shows four weeks (28 days) in a 6 row chest, the page that holds the
next day to claim. Each day is an item whose count is the day number:

| State | Looks like | Click |
| --- | --- | --- |
| claimed (part of the current streak) | green pane / emerald for a milestone | nothing |
| available (can be claimed now) | glowing chest / nether star for a milestone | claims it |
| next (today's is taken) | clock / nether star, with the time left | nothing |
| locked | grey pane / diamond for a milestone | nothing |

The lore shows the reward and any milestone bonus. The clock at the top shows
the streak, best streak, claims so far and the next reward; arrows at the
bottom flip through the weeks. After a click the menu is redrawn.

## Playtime

Time online is added up per player. It counts from joining to leaving, and
there is **no AFK detection**.

To be safe against crashes, every `tickSeconds` (default 60) the time of
everyone online is added to their total and saved, and the list of players
online is read from the server. A crash or kill therefore loses at most one
tick per player (a clean shutdown and every leave lose nothing). After a crash,
players still online are picked up again by the first tick. If a player is
missing from the tick without a leave event they stop counting; no time is
invented for them. A clock that jumps backwards adds nothing.

**Playtime milestones** pay money once when a player's total reaches
`minutes` (defaults: 1 hour 250, 10 hours 1,500, 50 hours 5,000). The player
gets a chat message, an action bar line and a sound. If the payment cannot be
made (balance full) it is tried again at the next tick. Milestones are
remembered per player by their `minutes`, so editing the list later pays only
new entries.

## Permissions

| Node | Default | Allows |
| --- | --- | --- |
| `commons:rewards.daily` | everyone | `/daily` |
| `commons:rewards.calendar` | everyone | `/rewards` |
| `commons:rewards.playtime` | everyone | `/playtime` for yourself |
| `commons:rewards.playtime.others` | everyone | `/playtime <player>` |
| `commons:rewards.playtop` | everyone | `/playtop` |

## Files

| File | Content |
| --- | --- |
| `rewards/config.json` | The settings below, written with the defaults on first start. Out of range values are corrected when loading. |
| `rewards/daily.json` | Per player UUID: `lastClaimAt`, `streak`, `bestStreak`, `totalClaims`, `pendingItems`. Saved right after every claim. |
| `rewards/playtime.json` | Per player UUID: `seconds` and the `paidMilestones`. Saved at every tick, on every leave and on unload. |
| `messages/rewards.json` | Every text the module sends and the names and lore of the calendar items. |

## Config keys

`rewards/config.json` has two sections.

**`daily`**

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Turns `/daily` and the calendar claims off. |
| `baseAmount` | `100` | Reward of streak day 1. |
| `incrementPerDay` | `25` | Added for each further day up to the cap. |
| `maxGrowthDays` | `7` | Streak day at which the reward stops growing. |
| `resetHourUtc` | `0` | The hour (0-23, UTC) a new day starts. |
| `graceDays` | `1` | Whole days that may be skipped without losing the streak. |
| `joinReminder` | `true` | Remind players who can claim when they join. |
| `milestones` | days 7, 14, 30 | A list of `{"day": 7, "currency": 500, "items": [{"item": "diamond", "count": 3}], "label": "Weekly bonus"}`. |

**`playtime`**

| Key | Default | Meaning |
| --- | --- | --- |
| `tickSeconds` | `60` | How often playtime is added up and saved (at least 5). |
| `milestones` | 60, 600, 3000 minutes | A list of `{"minutes": 60, "currency": 250}`. |
