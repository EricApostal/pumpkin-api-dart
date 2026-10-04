# Mail

Offline messaging between players. A player can mail anybody who has joined the
server before, online or not. Messages wait in the recipient's inbox until they
are read and deleted.

Provides the `MailApi` service (`unreadCount(uuid)`), which the chat module uses
for its welcome summary.

## Commands

| Command | Does |
| --- | --- |
| `/mail` | Lists your inbox, newest first, unread messages highlighted, with clickable `[Read]`, `[Reply]` and `[Delete]` on every line |
| `/mail read` | Same as `/mail` |
| `/mail read <id>` | Shows one message and marks it read |
| `/mail page <n>` | Shows page `n` of the inbox (the `« Prev | Next »` footer uses it) |
| `/mail send <player> <message...>` | Sends a message. The player must be known to the server (tab completion lists them). An online recipient is notified at once: a chat line with a clickable `[Read]`, an action bar message and a sound |
| `/mail delete <id>` | Deletes one message |
| `/mail delete read` | Deletes every message that was read |
| `/mail delete all` | Deletes the whole inbox, after a confirmation (`[Confirm]` or `/mail clear confirm` within 15 seconds) |
| `/mail clear` | Same as `/mail delete all` |
| `/mail sent [page]` | What you sent recently, and whether it was read, still unread or deleted by the recipient |
| `/mail block <player>` | Stops a player from mailing you |
| `/mail unblock <player>` | Lets them mail you again |
| `/mail blocked` | Lists the players you blocked |

The `<id>` is the number shown as `#12`. Ids are unique for the whole server and
are never reused, so a `[Delete]` button in an old chat line can only ever delete
the message it was made for.

## Rules

* The message is cleaned (no `§`, control characters or double spaces), plain
  text only: color codes in mail are shown as typed.
* A blocked sender gets a neutral "could not be delivered" message, the same
  wording whatever the reason behind it, and nothing is stored.
* Muted players (`ModerationApi.activeMute`) cannot send mail. They are told the
  reason and how long the mute lasts. If the moderation module is not installed
  nobody is muted.
* A full inbox refuses new mail until something is deleted.
* There is a cooldown between two sent messages per sender. Only a message that
  was sent starts it.

## Notifications

Mail only notifies when a message **arrives** (online recipients). Telling
players about unread mail when they join is the job of the chat module's welcome
summary, so they are not told twice. If the chat module is not installed, set
`notifyOnJoin` to `true` in `mail/config.json` and mail shows a chat line with a
`[Read]` button two seconds after joining.

## Permissions

| Node | Default | Allows |
| --- | --- | --- |
| `commons:mail.read` | everyone | `/mail`, reading, deleting, `/mail sent` |
| `commons:mail.send` | everyone | `/mail send` |
| `commons:mail.block` | everyone | `/mail block`, `unblock`, `blocked` |
| `commons:mail.bypass` | op | sending without the cooldown |

## Files

| File | Content |
| --- | --- |
| `mail/config.json` | settings, created on first start |
| `mail/mail.json` | all inboxes, outboxes and blocks (saved every 10 seconds and on unload) |
| `messages/mail.json` | every text shown to players, editable |

`mail/mail.json` looks like this:

```json
{
  "nextId": 4,
  "inboxes": {
    "<uuid>": [
      { "id": 3, "fromUuid": "<uuid>", "fromName": "Alex", "text": "hi",
        "sentAt": "2026-01-01T12:00:00.000Z", "read": false }
    ]
  },
  "sent": { "<uuid>": [ { "id": 3, "toUuid": "<uuid>", "toName": "Steve", "text": "hi", "sentAt": "..." } ] },
  "blocked": { "<uuid>": ["<uuid>"] }
}
```

The sender's name is stored with the message, so it stays readable when the
sender changes their name later.

## Configuration (`mail/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `maxInboxSize` | `50` | Messages per inbox |
| `maxMessageLength` | `256` | Characters per message |
| `sendCooldownSeconds` | `30` | Pause between two sent messages, `0` for none |
| `sentHistorySize` | `20` | Messages `/mail sent` remembers per player, `0` turns the outbox off |
| `allowBlocking` | `true` | Whether `/mail block` works |
| `notifyOnJoin` | `false` | Mail's own join reminder, see above |
| `pageSize` | `6` | Messages per page |

Missing keys use the defaults. Changes need a restart.
