# Kits

Sets of items players claim from a menu or with `/kit <name>`: a one-time
starter kit, a daily kit, permission-gated or paid kits. Module name `kits`,
depends on `economy` (for prices).

## What it does

* A kit has items, a **cooldown** (how long to wait between claims), a
  **one-time** flag, an optional **price** and a permission
  `commons:kits.kit.<name>`.
* A claim never half-applies. The module checks permission, one-time and
  cooldown, then that **all** stacks fit into **empty** slots, then charges the
  price, then hands over the items. If the hand-over fails the price is
  refunded and no claim is recorded, so the player can simply try again.
  Kits are never merged into stacks a player already has.
* Claims are stored per player (`claims.json`) and written **immediately**, so
  cooldowns and one-time limits survive crashes. Deleting a kit keeps its
  history.
* New players get the starter kit automatically (see below).

## Click mapping (`/kit` menu)

| Click | Action |
| --- | --- |
| left | claim the kit |
| right | open a read-only preview |

The icon's lore shows the state (available, on cooldown with the time left,
already claimed, locked), price, cooldown and the first items. Kits you can
claim glow. In the preview nothing can be taken; the arrow at the bottom goes
back to the list. Menu feedback is shown above the hotbar with a sound.

## Commands

| Command | Permission | What |
| --- | --- | --- |
| `/kit` (alias `/kits`) | `commons:kits.use` | open the kit menu |
| `/kit <name>` | `commons:kits.use` + the kit's node | claim a kit |
| `/kit list` | `commons:kits.use` | text list with states |
| `/kit preview <name>` | `commons:kits.use` | open the preview |
| `/kit create <name>` | `commons:kits.admin` | save your inventory (36 slots) as a kit; an existing kit keeps its settings and gets the new items |
| `/kit delete <name>` | `commons:kits.admin` | delete a kit |
| `/kit reload` | `commons:kits.admin` | re-read the files, list problems |

`/kit <name>` tab-completes the kits you may claim. The names `list`,
`preview`, `create`, `delete` and `reload` are reserved.

`/kit create` copies names and lore as **plain text** (the host does not
report colors) and enchantments with their levels. Edit `kits.json` to add
colors or settings such as cooldown and price.

## Permissions

| Node | Default |
| --- | --- |
| `commons:kits.use` | everyone |
| `commons:kits.admin` | operators (level 2) |
| `commons:kits.bypass` | operators: claim ignoring cooldowns and the one-time limit |
| `commons:kits.kit.<name>` | everyone, or operators if the kit is `"restricted": true` |

The kit nodes are registered at load, after `create`, and after `reload`. A
node's default is fixed when it is first registered: changing `restricted`
later needs a server restart (or granting the node explicitly).

## Files (`plugins/data/commons/kits/`)

* `kits.json`: written with defaults on first run: `starter` (one-time),
  `daily` (every 24 h), `vip` (restricted, every 7 days).
* `config.json`: settings.
* `claims.json`: `{ "players": { "<uuid>": { "<kit>": { "lastClaimed": "...", "count": 3 } } } }`.
* `../messages/kits.json`: every text, editable.

### `kits.json`

```json
{
  "kits": [
    {
      "name": "vip",
      "displayName": "&bVIP crate",
      "icon": "diamond",
      "cooldownSeconds": 604800,
      "oneTime": false,
      "price": 0,
      "restricted": true,
      "items": [
        {
          "item": "diamond_pickaxe",
          "count": 1,
          "name": "&bVIP pickaxe",
          "lore": ["&7A gift for our supporters"],
          "enchantments": { "efficiency": 3, "unbreaking": 2 }
        },
        { "item": "diamond", "count": 8 }
      ]
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `name` | 1-32 of `a-z 0-9 _ -`, unique, not a reserved word |
| `displayName` | menu name with `&` codes (default: `name`) |
| `icon` | item key for the menu (default `chest`) |
| `cooldownSeconds` | wait between claims, `0` = none |
| `oneTime` | claimable once per player, ever |
| `price` | cost per claim, `0` = free |
| `restricted` | permission is for operators unless granted |
| `items[].item` | item key, required |
| `items[].count` | 1-256 (counts above the item's stack size are split) |
| `items[].name`, `lore`, `enchantments` | optional; enchantment keys without namespace, level 1-255 |

Items and enchantments are validated against the server. A kit with **any**
invalid item is skipped as a whole (a kit silently giving less than it
advertises would be worse); it is logged and listed by `/kit reload`. At most
36 stacks per kit.

### `config.json`

| Key | Default | Meaning |
| --- | --- | --- |
| `giveStarterKit` | `true` | give `starterKit` to players joining for the first time |
| `starterKit` | `starter` | name of that kit |
| `prefix` | `&8[&6Kits&8] &r` | put before chat messages |

## Starter kit on first join

Two seconds after a player joins (so the join has finished) the module checks
that the player is **new** (the core's player directory first saw them less
than a minute ago) and has **never claimed** the starter kit, that the kit
exists and is free. Then it gives the kit, shows a title and records the
claim. If the inventory has no room the player is told to make room and use
`/kit starter`. Note that players who played on the server before Commons was
installed count as new on their first join afterwards.

## Cooldown display

Times use `formatDuration` of `pumpkin_api`: `1h 30m`, `45s`, `2d 3h`.
