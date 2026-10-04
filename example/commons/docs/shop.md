# Shop

A chest-menu shop paid in the economy's currency, plus `/buy`, `/sell` and
`/worth` for players who prefer typing. Module name `shop`, depends on
`economy`.

## What it does

`/shop` opens a menu with one button per category. A category opens a paged
list of its items; each item shows its prices and what each click does. Large
purchases ask for confirmation first. Every trade is checked so a player is
never charged without getting the items, and never paid for items they still
have:

* **Buying** checks that the items fit, then withdraws the money, then hands
  the items over. If the hand-over delivers fewer items than paid for (or
  fails), the money for the missing items is refunded.
* **Selling** checks that the player carries the items, takes them, then pays.
* Only **plain** stacks are sold: no custom name, lore, enchantments or
  durability damage. Renamed, enchanted and worn items stay with the player.
* Only the 36 hotbar/storage slots are touched, never armor or the off hand.

## Click mapping (item menu)

| Click | Action |
| --- | --- |
| left | buy `amount` items (1 unless the entry says otherwise) |
| shift + left | buy one `stack` (64 unless the entry says otherwise) |
| right | sell `amount` items |
| shift + right | sell everything the player carries of that item |

The same lines are in each item's lore (`lore.*` messages), and the lore
shows the price of each click. The bottom row has previous/next page, a back
button (left) and the player's balance (right). If a purchase costs at least
`confirmThreshold`, a 3-row confirmation menu opens (green = pay, red =
cancel); a second click on it is ignored.

Feedback of menu clicks is shown above the hotbar (with a sound); commands
answer in chat.

## Commands

| Command | Permission | What |
| --- | --- | --- |
| `/shop [category]` | `commons:shop.use` | open the shop (or one category) |
| `/buy <item> [amount]` | `commons:shop.buy` | buy, default 1 item |
| `/buy confirm` | `commons:shop.buy` | confirm a large purchase (20 s) |
| `/sell <item> [amount]` | `commons:shop.sell` | sell, default 1 |
| `/sell hand [amount]` | `commons:shop.sell` | sell the held item type, default the held stack |
| `/sell all` | `commons:shop.sell` | sell everything the shop buys |
| `/worth [item]` | `commons:shop.use` | buy and sell price (default: held item) |
| `/shopadmin reload` | `commons:shop.admin` | re-read the files, list problems |
| `/shopadmin setprice <item> <buy> [sell]` | `commons:shop.admin` | change prices (`sell 0`: shop does not buy it) |
| `/shopadmin additem <category> <buy> [sell]` | `commons:shop.admin` | list the held item |
| `/shopadmin removeitem <item>` | `commons:shop.admin` | remove an item |
| `/shopadmin log [count]` | `commons:shop.admin` | latest trades (default 10, max 50) |

Item names tab-complete from the catalog (`/sell` also offers `hand` and
`all`). A large `/buy` prints a clickable `[Confirm]`.

## Permissions

| Node | Default |
| --- | --- |
| `commons:shop.use` | everyone |
| `commons:shop.buy` | everyone |
| `commons:shop.sell` | everyone |
| `commons:shop.admin` | operators (level 2) |

An entry can also name its own `permission` node (for example
`myserver:shop.vip`). Those nodes are registered at load and on reload with
the default "operators only", so they must be granted to everybody else; the
entry shows "locked" in the menu to players without it.

## Files (`plugins/data/commons/shop/`)

* `catalog.json`: written with a default catalog (blocks, tools, food,
  redstone, misc) on first run.
* `config.json`: settings, see below.
* `ledger.json`: the latest `ledgerSize` trades (time, player, buy/sell,
  item, amount, total), oldest first.
* `../messages/shop.json`: every text, editable. Keys are added when missing.

### `catalog.json`

```json
{
  "categories": [
    {
      "id": "food",
      "name": "&6Food",
      "icon": "bread",
      "entries": [
        { "item": "bread", "buy": 6 },
        { "item": "ender_pearl", "buy": 60, "sell": 20, "stack": 16 },
        { "item": "golden_apple", "buy": 150, "permission": "myserver:shop.vip" }
      ]
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `id` | category id: 1-24 of `a-z 0-9 _`, unique; at most 28 categories |
| `name` | menu name, `&` colour codes |
| `icon` | item key shown in the category menu |
| `item` | item registry key (`bread` or `minecraft:bread`) |
| `buy` | price per item, at least 1 |
| `sell` | price paid per item. Omitted: `buy * sellPercent / 100` rounded down; `0`: not bought |
| `amount` | items per plain click, default 1 |
| `stack` | items per shift click, default 64, at least `amount` |
| `permission` | node needed to buy and sell it, optional |

Items are validated against the server's item registry (the host has no
lookup call, so a throw-away stack is created: an unknown item comes back as
air). Unknown items, bad numbers, duplicate ids and so on are **skipped and
logged** (and listed by `/shopadmin reload`), they never stop the shop. The
file itself is left untouched so owners can fix the typo. An item listed in
two categories is traded under the first one.

### `config.json`

| Key | Default | Meaning |
| --- | --- | --- |
| `sellPercent` | `50` | sell price of entries without `sell`, in percent of `buy` (limited to 0-100) |
| `confirmThreshold` | `5000` | purchases costing at least this ask for confirmation; `0` = never |
| `prefix` | `&8[&6Shop&8] &r` | put before chat messages |
| `ledgerSize` | `500` | trades kept in `ledger.json`; `0` = no ledger |

## Notes

* Money is whole numbers; there is no rounding of prices (sell prices of
  entries without `sell` are rounded down).
* Admin edits (`setprice`, `additem`, `removeitem`) are written to
  `catalog.json` immediately; the ledger is written by the autosave.
* `/shopadmin reload` that finds a file it can not parse keeps the shop as it
  was and says so.
* Menus that are open during a reload keep their old content until reopened.
