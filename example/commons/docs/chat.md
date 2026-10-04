# Chat

Formatted chat with ranks and mentions, anti-spam, private messages, ignoring,
join and leave messages and a welcome summary for joining players.

The module needs the economy, mail, rewards and moderation modules loaded first
(`dependsOn`). Of those it only uses their services when they are there at run
time: a part of the welcome summary is left out when its service is missing.

## Chat lines

Pumpkin's `player-chat-event` lets a plugin change the message text but not the
line the server builds, and its recipient list is empty. So the module
**cancels the event and sends the formatted line itself** to every online
player, as a system message. The limitations that come with that:

* chat lines are not signed, so the client's "report chat message" has nothing
  to report, and they do not use the vanilla `chat.type.text` translation;
* other plugins that listen for chat see a cancelled event, and a message that
  another handler already cancelled (the moderation module's staff chat) is left
  alone;
* the server's own console line for chat is not printed, the module logs
  `<name> message` instead.

The line is built from `format` in `chat/config.json`, default
`{prefix}{name}{suffix}&8: &f{message}`:

* `{prefix}`, `{suffix}` and the color of `{name}` come from the player's **rank**:
  `ranks` is an ordered list of `{permission, prefix, suffix, color}` and the
  first rank whose permission node the player has wins. Nobody matching gets
  `defaultRank`. Granting the nodes is up to your permission manager. The nodes
  of the default ranks are `commons:chat.rank.admin` (operators),
  `commons:chat.rank.moderator` and `commons:chat.rank.vip` (nobody until granted).
  Other nodes you add to the list are registered for you, denied by default.
* The name can be clicked (puts `/msg <name> ` in the chat box) and shows a hover.
* Text of the template that sets a color before `{message}` (`&a{message}`)
  carries into the message.
* **Colors:** `&` codes in messages only work for players with
  `commons:chat.color`. For everybody else the message is escaped, so nobody can
  inject formatting (`&`, `§` and control characters are neutralised).
* **Mentions:** `@name` of an online (not vanished) player is highlighted, and
  that player gets a sound (`mentionSound`) and an action bar message. Set
  `mentions` to `false` to turn it off.
* **Muted players** are refused with the reason and the remaining time
  (`ModerationApi.activeMute`).
* **Ignoring:** a player who ignores the sender does not get the line.

### Anti-spam

Every message must pass `spam` (skipped with `commons:chat.bypass`):

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | |
| `cooldownMillis` | `1000` | Shortest pause between two messages |
| `maxMessages` / `windowSeconds` | `5` / `10` | At most this many messages in any window (`maxMessages: 0` for no limit) |
| `repeatSeconds` | `30` | The same message (ignoring case, spaces and punctuation) is refused again for this long |

A refused message is not recorded, so waiting out the time shown is enough.

## Private messages

| Command | Does |
| --- | --- |
| `/msg <player> <message...>` (`/tell`, `/w`, `/m`) | Sends a private message to an online player |
| `/reply <message...>` (`/r`) | Answers the last player you talked to (either direction) |
| `/ignore <player>` | Starts ignoring a player; run it again to stop. Works on offline players |
| `/ignorelist` (`/ignores`) | Lists who you ignore, with `[Unignore]` buttons |
| `/spy [on\|off]` | Staff: see everybody's private messages |

* `/msg` and `/reply` have a one second cooldown (`commons:chat.bypass` skips it)
  and are refused for muted players.
* The partner of `/reply` is remembered per player and forgotten when they leave.
* Vanished players are reported as "not online" to `/msg`, except for players
  with `commons:chat.seevanished`. `/reply` to someone who started the
  conversation always works, so staff can write from vanish.
* **Ignoring is silent for the ignored player**: they see their message as sent,
  it just never arrives. Ignoring only affects chat and private messages, not
  mail (see `/mail block`). Players with `commons:chat.ignore.exempt` (operators)
  cannot be ignored.
* Spying is off by default, per session: it is switched off when the player
  leaves, and spies don't see conversations they take part in.

The look of private messages is configured with `pmSentFormat`,
`pmReceivedFormat` and `spyFormat` (`{player}`/`{from}`/`{to}` and `{message}`).

## Join and leave

`joinFormat`, `leaveFormat` and `firstJoinFormat` replace the vanilla messages.
Placeholders: `{prefix}`, `{suffix}`, `{name}`, `{online}` and, for the first join,
`{count}` (which player to join this is). An empty text shows no message.
**Vanished players** (`ModerationApi.isVanished`) get no join or leave message.

A player's first visit is detected from the player directory: the server runs
blocking event handlers (like this one) before the core records the join, so a
player it doesn't know yet is a new one.

## Welcome summary

A moment after joining (`welcome.delaySeconds`) the player gets a title and a few
chat lines:

* `{online} of {max} players online`;
* their balance, if the economy is installed;
* unread mail with a clickable `[Read]`, if there is any;
* the daily reward with a clickable `[Claim]` (runs `/daily`), if it can be
  claimed.

The summary is the only join reminder about mail (mail itself only notifies when
a message arrives). `welcome.title`, `subtitle`, `firstTitle` and `firstSubtitle`
(with `{name}`) set the title, an empty title turns it off, and
`welcome.enabled: false` turns the whole summary off.

## Permissions

| Node | Default | Allows |
| --- | --- | --- |
| `commons:chat.msg` | everyone | `/msg`, `/reply` |
| `commons:chat.ignore` | everyone | `/ignore`, `/ignorelist` |
| `commons:chat.color` | op | `&` color codes in chat and private messages |
| `commons:chat.spy` | op | `/spy` |
| `commons:chat.bypass` | op | no anti-spam, no `/msg` cooldown |
| `commons:chat.ignore.exempt` | op | cannot be ignored |
| `commons:chat.seevanished` | op | `/msg` to vanished players |
| `commons:chat.rank.admin` | op | the `[Admin]` rank |
| `commons:chat.rank.moderator` | nobody | the `[Mod]` rank |
| `commons:chat.rank.vip` | nobody | the `[VIP]` rank |

## Files

| File | Content |
| --- | --- |
| `chat/config.json` | everything below, created on first start (needs a restart to change) |
| `chat/ignores.json` | who ignores whom, by UUID |
| `messages/chat.json` | the notices shown to players, editable |

## Configuration (`chat/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `format` | `{prefix}{name}{suffix}&8: &f{message}` | A chat line |
| `joinFormat` / `leaveFormat` / `firstJoinFormat` | see above | Join, leave and first join messages |
| `pmSentFormat` / `pmReceivedFormat` / `spyFormat` | | Private message layouts |
| `ranks` | admin, moderator, VIP | Ordered `{permission, prefix, suffix, color}` |
| `defaultRank` | gray name | Used when no rank matches |
| `mentions` / `mentionSound` | `true` / `minecraft:block.note_block.pling` | `@name` pings |
| `spam` | see above | Anti-spam |
| `welcome` | enabled | `enabled`, `delaySeconds`, `title`, `subtitle`, `firstTitle`, `firstSubtitle` |

Every text is a template with `&` color codes; missing keys use the defaults.
