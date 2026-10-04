# Announcements

Rotating server announcements, shown in chat, above the hotbar, as a title or on
a boss bar, plus `/announce` for one-off broadcasts.

## Commands

All of them need `commons:announcements.admin` (operators by default).

| Command | Does |
| --- | --- |
| `/announce <message...>` | Broadcasts a message to everybody now, as a chat line (color codes and the placeholders work) |
| `/announcements` or `/announcements list` | Shows the interval, the order and every configured message with its mode and filters |
| `/announcements next` | Shows the next message of the rotation right now and restarts the timer |
| `/announcements reload` | Reads `announcements/config.json` again and lists what is wrong with it. A file that cannot be read changes nothing and is not overwritten |

## How the rotation works

A one second tick asks the `AnnouncementService` whether an announcement is due.
Every `intervalSeconds` it returns the next message:

* in order (wrapping around), or at random without ever repeating the same
  message twice in a row (`random: true`);
* messages nobody online can see (permission or world filter) are skipped. If
  nobody can see anything, the turn is simply used up.

Because the interval is checked against a clock, `reload` can change it without
rescheduling anything. A reload starts the rotation over, and the next message
comes one interval later.

## Message entries

Each entry of `messages`:

| Key | Meaning |
| --- | --- |
| `text` | The text, with `&` color codes and the placeholders `{online}` (players online, vanished ones not counted), `{max}` and `{time}` (`HH:mm`, see `utcOffsetMinutes`) |
| `mode` | `chat` (default), `actionbar`, `bossbar` or `title` |
| `subtitle` | The subtitle of a `title` |
| `command` | Chat only: a command (`/daily`) that runs when the line is clicked |
| `url` | Chat only: a link that opens when the line is clicked (`command` wins) |
| `hover` | Chat only: text shown when the line is hovered |
| `permission` | Only players with this permission node see it |
| `world` | Only players in this world see it (`overworld`, `the_nether`, `minecraft:the_end`...) |

Modes:

* **chat**: one line, with `chatPrefix` in front. Click and hover actions work.
* **actionbar**: shown above the hotbar and sent again every two seconds for
  `displaySeconds` (the client hides it after about three).
* **title**: a title and optional subtitle that stay for `displaySeconds`.
* **bossbar**: a bar with the text that drains over `displaySeconds` and then
  disappears. Only one bar exists at a time; a newer one replaces it. Players who
  join while a bar is showing get it too (if they may see the message).

## Configuration (`announcements/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Turns the rotation off (`/announce` and `next` still work) |
| `intervalSeconds` | `300` | Time between announcements (at least 5 is recommended) |
| `random` | `false` | Random order instead of in order |
| `displaySeconds` | `10` | How long bars, action bar messages and titles stay |
| `bossBarColor` | `yellow` | `pink`, `blue`, `red`, `green`, `yellow`, `purple` or `white` |
| `chatPrefix` | `&8[&6!&8] &r` | Put before chat announcements |
| `utcOffsetMinutes` | `0` | Shifts `{time}` (`120` is UTC+2) |
| `messages` | four examples | The entries above |

A fresh install writes a file with one example for each of chat, chat with a
click action, boss bar and action bar. On load and on `reload`, mistakes (unknown
color, click actions on a non-chat entry, a link that is not `http(s)`, an empty
text...) are logged as warnings and listed to whoever ran `reload`.

## Permissions

| Node | Default | Allows |
| --- | --- | --- |
| `commons:announcements.admin` | op | `/announce` and `/announcements` |

## Files

| File | Content |
| --- | --- |
| `announcements/config.json` | the configuration above |

Nothing else is written: announcements keep no state.
