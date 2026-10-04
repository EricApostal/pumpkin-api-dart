# Moderation

Warnings, mutes, bans and kicks with a persistent history, warning
escalation, and two staff tools (`/vanish`, `/staffchat`). The module is called
`moderation` and offers `ModerationApi` (`activeMute`, `isVanished`) to the
other modules, which is how the chat module enforces mutes.

## Commands

All commands are for operators by default (see [Permissions](#permissions)).
`<player>` is the name of anyone who ever joined the server, online or not,
and tab completes from real data (everybody who joined; for the `un...`
commands only players that have something to take back; for `/kick` the
players online). An unknown name is refused with a clear message.

| Command | Does |
| --- | --- |
| `/warn <player> <reason...>` | Records a warning and tells the player. Enough warnings punish automatically, see [Escalation](#warning-escalation). |
| `/unwarn <player> [id]` | Takes back the latest active warning, or warning `id`. |
| `/mute <player> [duration] [reason...]` | Mutes. Without a duration the mute lasts `defaultMuteDuration` (permanent unless configured). |
| `/unmute <player>` | Lifts the mute. |
| `/ban <player> [reason...]` | Permanent ban. An online player is removed at once. |
| `/tempban <player> <duration> [reason...]` | Ban that ends by itself. |
| `/unban <player>` | Lifts the ban. |
| `/kick <player> [reason...]` | Removes an online player. Recorded in the history. |
| `/history <player> [page]` | The player's punishments, newest first, with clickable page links. Each line shows the id, type, status (`ACTIVE`, `expired`, `revoked by X`), reason, issuer, age and length. |
| `/punishments [page]` | The latest punishments of everybody. |
| `/punishments active [page]` | Only the mutes and bans in force right now. |
| `/checkban <player>` | Ban, mute and number of active warnings of one player. |
| `/vanish [on\|off]` (`/v`) | Toggles [vanish](#vanish). |
| `/staffchat [message...]` (`/sc`) | Without a message: switches [staff chat](#staff-chat) mode on or off. With a message: sends just that message to staff. Works from the console too. |

**Durations** are written `30m`, `12h`, `7d`, `2w` or `1h30m`; `perm` (also
`permanent`, `forever`) means for ever. A bare number is *not* a duration, so
`/mute Steve 5 minutes of quiet` is a permanent mute with that reason, not a
five second one. Zero and spans over 100 years are refused (`perm` is the way
to say for ever). `/tempban` requires a real duration.

**Reasons** are cut to one line of at most `maxReasonLength` characters, and
an empty one becomes `defaultReason`. Staff are told about every punishment
(and every take-back); the person who ran the command gets the same line, as
the command's reply if they don't have `commons:moderation.notify`.

### What is refused

* Punishing yourself.
* Punishing a protected player (see below), unless you are the console.
* Muting a player who is already muted, or banning one who is already banned:
  the message says how long it still lasts, use `/unmute` or `/unban` first.
* `/kick` of someone who is offline (nothing would happen, so nothing is
  recorded).
* A name nobody joined with, an unusable duration, an id that is not an active
  warning of that player.

### Protection

A player with `commons:moderation.exempt` cannot be warned, muted, banned or
kicked by anyone but the console. The permission is **op by default**, so out
of the box operators cannot punish each other (and a moderator who has been
given op cannot ban the owner). To let some staff be punishable, deny the node
for them.

Permissions can only be checked for players who are online, so the module
remembers who had the node when they last joined or left
(`moderation/protected.json`), and re-checks it at the moment of a command
when the target is online.

## Permissions

| Node | Default | Allows |
| --- | --- | --- |
| `commons:moderation.warn` | op | `/warn` |
| `commons:moderation.unwarn` | op | `/unwarn` |
| `commons:moderation.mute` | op | `/mute` |
| `commons:moderation.unmute` | op | `/unmute` |
| `commons:moderation.ban` | op | `/ban` |
| `commons:moderation.tempban` | op | `/tempban` |
| `commons:moderation.unban` | op | `/unban` |
| `commons:moderation.kick` | op | `/kick` |
| `commons:moderation.history` | op | `/history` |
| `commons:moderation.punishments` | op | `/punishments` |
| `commons:moderation.checkban` | op | `/checkban` |
| `commons:moderation.vanish` | op | `/vanish` |
| `commons:moderation.staffchat` | op | `/staffchat` and reading staff chat |
| `commons:moderation.notify` | op | being told about every punishment and about staff vanishing |
| `commons:moderation.exempt` | op | cannot be punished by anyone but the console |

## Files

All under the plugin's data folder (`plugins/data/commons/`).

| File | Content |
| --- | --- |
| `moderation/config.json` | Settings, created with the defaults on first start. Edit and restart the plugin. Invalid values are reported in the log and replaced by the default in memory (the file is left alone). |
| `moderation/punishments.json` | `{"nextId": n, "records": [...]}`, oldest first. A record has `id`, `type` (`warn`, `mute`, `ban`, `kick`), `targetUuid`, `targetName` (the name when punished), `issuerUuid`, `issuerName` (`console` / `Console` for the console, `auto` / `Auto-moderation` for escalation), `reason`, `issuedAt`, `expiresAt?`, `revokedAt?`, `revokedBy?` (ISO-8601 UTC). Written right after every punishment and take-back. `nextId` is kept in the file, so ids are never reused. |
| `moderation/protected.json` | UUIDs that had `commons:moderation.exempt` when they were last seen. |
| `messages/moderation.json` | Every text the module shows (command replies, notices, the ban screen). Keys missing from the file are added on start. Texts that contain a player's name or reason escape `&` codes, so players cannot color or fake messages. |

A history file that cannot be read is copied to `punishments.json.corrupt-<time>`
and a fresh one is started (nothing is silently lost).

## Config keys (`moderation/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `defaultReason` | `No reason given` | Used when a punishment has no reason. |
| `appeal` | `If you think this is a mistake, contact the staff.` | Last line of the ban screen. Put your Discord or appeal URL here. |
| `defaultMuteDuration` | `perm` | Length of `/mute` without a duration. |
| `warnExpiry` | `30d` | How long a warning stays active (it stays in the history). `perm` for ever. |
| `escalationWarns` | `3` | Active warnings inside the window that trigger the automatic punishment. `0` turns escalation off. |
| `escalationWindow` | `7d` | Only warnings issued this recently count. `perm` counts all active ones. |
| `escalationAction` | `mute` | `mute` or `tempban`. |
| `escalationDuration` | `1h` | Length of the automatic punishment (`perm` for ever). |
| `escalationReason` | `Automatic: {count} warnings within {window}` | Its reason. |
| `mutedCommands` | `msg tell w whisper r reply me say mail` | Commands (no slash) a muted player cannot use. Empty list: none. |
| `sweepSeconds` | `30` | How often finished mutes and bans are cleaned up. |
| `pageSize` | `8` | Lines per page of `/history` and `/punishments`. |
| `maxReasonLength` | `200` | Reasons are cut to this length. |

## Enforcement

### Bans

Bans are enforced **at login**. `Events.playerLogin` is an interceptable
event: the host sends the `kickMessage` of the event and refuses the
connection when the handler sets `cancelled`, so a banned player never gets
into the world. The kick screen is a multi-line message with the reason, who
banned, the time left (or "permanently"), the ban id and the `appeal` text.

As a backstop for a login that slipped through, the join event checks again
and kicks (and logs a warning). An online player who is banned with `/ban` is
removed at once with the same screen (Java and Bedrock).

Bans are by UUID, so a name change does not help. Bans are the plugin's own
list: they are independent of the server's built-in ban list and its `/ban`,
and only apply while this plugin is loaded. There are no IP bans.

### Expiry

A punishment's status is computed from its timestamps, so history is correct
the moment a mute or ban runs out. The login and chat checks also drop an
expired entry from the in-memory index the first time they see it, and a
periodic task (`sweepSeconds`, on the server's tick scheduler) cleans up the
rest and tells online players "your mute has ended". Revoking is a flag in the
record (`revokedAt`, `revokedBy`); nothing is ever deleted from the history.

### Mutes

Mutes live in an in-memory index by UUID (`ModerationApi.activeMute` is one
map lookup), rebuilt from the history on start. **Chat itself is enforced by
the chat module**, which asks `ModerationApi.activeMute`. This module blocks
the commands listed in `mutedCommands` for muted players (the command event is
cancelled with a message), because they would carry text past the mute. If the
chat module is removed from the plugin, muted players can chat again.

### Warning escalation

When a warning makes `escalationWarns` active warnings issued within
`escalationWindow`, the module issues `escalationAction` for
`escalationDuration` itself (issuer `Auto-moderation`). Warnings from before a
player's last automatic punishment are not counted again, so the next one
takes another full set of warnings. A player who is already muted (or banned,
for `tempban`) is left alone, and revoked or expired warnings never count.
Staff are told about the automatic punishment like any other.

## Vanish

`/vanish` hides a staff member as far as the host API allows, and
`ModerationApi.isVanished(uuid)` tells other modules (kept in memory, cleared
when the player leaves or the plugin unloads). It does three things:

* sets the entity's **invisible flag** (the model disappears; no particles or
  effect icon, unlike a potion),
* **unlists** the player from the tab list (and repeats that whenever somebody
  joins, because the list is rebuilt for a new player),
* makes the player **leave silently**: the leave message is cancelled while
  vanished.

Staff with `commons:moderation.notify` are told when somebody vanishes or
shows up again.

What is **not** hidden, because the host offers no way to do it:

* The `hide-player` call of the host API only records a flag that the server
  never consults (checked in Pumpkin's source), so the entity is not removed
  for other players. The module does not call it.
* Armor and held items of an invisible player stay visible, and a name tag may
  too. Footstep sounds, damage and block interactions are normal.
* The player still counts in the player count and the server list ping, and
  other plugins can still see them (use `ModerationApi.isVanished`).
* The tab list is unlisted through a packet to the player's world; players in
  other worlds may keep the entry until it is refreshed.
* Joining silently is not possible (vanish starts after joining). A staff
  member who rejoins is visible again, and everybody is made visible again
  when the plugin unloads, so nobody stays invisible without the plugin that
  can undo it.

## Staff chat

`/staffchat` switches a mode in which everything the player types goes to staff
only (everyone online with `commons:moderation.staffchat`, and the server
log) instead of public chat. `/staffchat <message>` sends a single message
without switching. The interceptor runs before the chat module (highest
priority) and cancels the public message. Membership is dropped when the
player leaves or loses the permission.

## For other modules

```dart
final moderation = host.services.require<ModerationApi>(); // dependsOn: ['moderation']
final mute = moderation.activeMute(uuid);                   // MuteInfo? (reason, until, by)
if (moderation.isVanished(uuid)) { /* hide from lists */ }
```

## Notes and limits

* Names in the history are the name at the time of the punishment; lookups go
  by UUID through the player directory, so a renamed player is found by the
  new name.
* Command links in `/history` pages use the name as a command word, so names
  with spaces (some Bedrock names) cannot be paged by clicking.
* The punishment file is rewritten whole after each change. That is fine for
  tens of thousands of records; move to a database if you need more.
