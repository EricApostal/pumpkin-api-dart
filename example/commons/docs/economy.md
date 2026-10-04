# Economy

One whole-number currency for the server: balances, `/pay`, a richest-players
list, admin tools, and a small IPC interface so other plugins can charge and
pay players. The module is called `economy` and provides `Economy`
(`core/api.dart`) to the other modules (shop, rewards, ...).

Money is always an `int` of whole units. There are no decimals, so there is
nothing to round. Balances never go below 0 and never above `maxBalance`.

## Commands

`<player>` is the name of anyone who ever joined the server, online or not (it
tab completes from the list of everybody who joined). Anything else is refused
with a message.

| Command | Does |
| --- | --- |
| `/balance` (`/bal`) | Your balance. |
| `/balance <player>` | The balance of another player (needs `commons:economy.balance.others`). From the console a player must be named. |
| `/balance history [player]` | The last 10 transactions: age, change, what it was (deposit, to/from a player, set) and the reason. Someone else's history needs `commons:economy.balance.others`. |
| `/pay <player> <amount>` | Gives money to another player. The receiver is told in chat and on the action bar if online. |
| `/pay confirm` / `/pay cancel` | Answers a large payment, see below. The confirmation message also has clickable buttons. |
| `/baltop [page]` (`/balancetop`) | The richest players, 10 per page with clickable previous/next links, the money in circulation, and your own place. Players with 0 are not listed. |
| `/eco give <player> <amount>` | Adds money. |
| `/eco take <player> <amount>` | Removes money. Refused if the player has less (nothing is taken). |
| `/eco set <player> <amount>` | Sets the balance (0 is allowed). |
| `/eco reset <player>` | Gives the starting balance again. |

`/eco` (alias `/economy`) works for the console too; the target is told about
`give`, `take` and `set` if online, and every use is logged.

**Amounts** are whole numbers: `250`, `1,500`, or with a suffix `k`
(thousand), `m`, `b`, `t`: `2k`, `1.5m`. They are computed with integers, so
`1.5k` is exactly 1500 and `1.0005k` is refused. Negative numbers, decimals
without a suffix, and anything above 9,007,199,254,740,991 are refused.

### `/pay` rules

A payment is refused, with a message that says why, when

* it is to yourself,
* the recipient never joined this server,
* it is below `payMinimum`,
* you have less than the amount (the message shows your balance),
* the recipient could not hold that much (`maxBalance`).

Above `confirmAbove` the payment is not made at once: the player is shown the
amount and receiver with `[Confirm]` / `[Cancel]` buttons and has
`confirmSeconds` to type `/pay confirm`. A confirmation is used once, and all
the rules are checked again when it is confirmed (the money may have moved in
the meantime). `confirmAbove: 0` turns confirmations off.

## Permissions

| Node | Default | Allows |
| --- | --- | --- |
| `commons:economy.balance` | everyone | `/balance`, `/balance history` for yourself |
| `commons:economy.balance.others` | op | the balance and history of other players |
| `commons:economy.pay` | everyone | `/pay` |
| `commons:economy.baltop` | everyone | `/baltop` |
| `commons:economy.admin` | op | `/eco ...` |

## Files

All in the plugin's data folder.

| File | Content |
| --- | --- |
| `economy/config.json` | The settings below. Written with the defaults on first start; edit and reload to change. Values that make no sense (a `maxBalance` of 0, a negative minimum, ...) are corrected when loading. |
| `economy/accounts.json` | `{"balances": {"<uuid>": 120, ...}}`. Written **immediately** after every change, so a crash cannot lose money. |
| `economy/history.json` | The most recent `historyPerAccount` transactions of each account, as `at`, `kind`, `change`, `balance` (after), `other` (the other player of a transfer) and `reason`. Saved by the plugin's autosave (every 10 s) and on unload; only the audit trail can lose the last seconds in a crash, never a balance. |
| `messages/economy.json` | Every text the module sends, with `{placeholders}`. Edit to translate or restyle. |

A player gets an account (with the starting balance) when they join. A known
player without an account reads as having the starting balance and gets the
account the first time money moves. A UUID the server has never seen has no
account and cannot be paid or charged.

## Config keys

| Key | Default | Meaning |
| --- | --- | --- |
| `currencySingular` | `coin` | Name of one unit. |
| `currencyPlural` | `coins` | Name of several units; also `Economy.currencyName`. |
| `symbol` | empty | If set, amounts read `<symbol>1,250` instead of `1,250 coins`. |
| `startingBalance` | `100` | Balance of a new account (also what `/eco reset` sets). |
| `payMinimum` | `1` | Smallest `/pay`. |
| `confirmAbove` | `1000` | `/pay` above this asks for confirmation; `0` never asks. |
| `confirmSeconds` | `15` | How long a confirmation stays valid. |
| `maxBalance` | `1000000000000` | Largest balance. Capped at 9,007,199,254,740,991 so that plugins in any language can read it exactly. |
| `historyPerAccount` | `25` | Transactions remembered per account (`0` keeps none, at most 500). |
| `ipcEnabled` | `true` | Whether other plugins may use the economy through IPC. |

## Atomicity

Every money movement is checked completely first and applied in one step, so
a `transfer` either moves the money from one account to the other or changes
nothing, and a failed call does not even create an account. `Economy.transfer`
returns `invalidAmount` for a transfer to yourself and for a receiver that
cannot hold the amount, `insufficientFunds` when the payer has too little and
`unknownAccount` for a UUID nobody knows.

## For other plugins (IPC)

Other plugins can use the economy through the host's plugin-to-plugin
messages. The recipient is the plugin **`commons`**. The call is synchronous:
the answer is the return value of the host call. Messages are JSON in the typed
envelope of `pumpkin_api` (`{"type": ..., "data": ...}`), so from a
`pumpkin_api` plugin:

```dart
final charge = IpcChannel<Map<String, Object?>>(
  'economy.charge', (m) => m, (json) => json as Map<String, Object?>);

final reply = charge.request('commons',
    {'player': 'Steve', 'amount': 50, 'reason': 'Bought a sword'}) as Map;
if (reply['ok'] == true) {
  // reply['balance'] is the new balance, reply['formatted'] e.g. "150 coins"
} else {
  // reply['error'] is one of the codes below
}
```

or, with the raw call, `ipc.requestJson('commons', {'type': 'economy.charge',
'data': {...}})`. A plugin written in another language sends the same JSON
bytes (UTF-8) as the message.

**`player` / `from` / `to`** are a UUID (canonical lower case text,
`8-4-4-4-12`) or a player name (any case) of someone who joined the server.
**`amount`** is a positive JSON integer. **`reason`** is optional free text; it
is stored in the player's history as `<calling plugin>: <reason>`, so owners
can see who moved their money.

### Messages

| `type` | `data` | Does |
| --- | --- | --- |
| `economy.info` | anything (ignored) | Describes the currency. |
| `economy.balance` | `{"player": ...}` | The balance of a player. |
| `economy.charge` | `{"player": ..., "amount": n, "reason"?: ...}` | Takes money from a player. |
| `economy.pay` | `{"player": ..., "amount": n, "reason"?: ...}` | Gives money to a player. |
| `economy.transfer` | `{"from": ..., "to": ..., "amount": n, "reason"?: ...}` | Moves money between players. |

`economy.info` replies

```json
{"singular": "coin", "plural": "coins", "symbol": "", "maxBalance": 1000000000000}
```

The other four reply with an **`EconomyReply`**:

```json
{"ok": true, "balance": 150, "formatted": "150 coins"}
{"ok": false, "error": "insufficient_funds", "balance": 20, "formatted": "20 coins"}
```

`balance` is the balance of the (first) player after the operation, or the
current one when it failed (it is left out when the player is unknown). When
`ok` is `false` nothing was changed. The error codes:

| `error` | Meaning |
| --- | --- |
| `unknown_player` | No known player has that name (or one of the names of a transfer is unknown). |
| `unknown_account` | A UUID that has no account and is not a known player. |
| `insufficient_funds` | The player has less than `amount`. |
| `invalid_amount` | `amount` is not positive, a transfer to oneself, or the receiver cannot hold that much. |
| `disabled` | The server owner set `ipcEnabled` to `false`. |

A payload that is not an object, or lacks `player`/`amount`, makes the host call
fail with an `IpcException` of reason `rejected` (the message is the
description of what was wrong) instead of replying. Plugin-internal code of
the same plugin uses the `Economy` service (`host.services.require<Economy>()`)
rather than IPC, since a plugin cannot message itself.

The payload classes are `BalanceQuery`, `MoneyRequest`, `TransferRequest`,
`EconomyReply` and `CurrencyInfo` in `lib/src/economy/rpc.dart` (dart_mappable
classes, round trip tested), and `EconomyRpc` is the binding-free logic behind
the channels that `economy_module.dart` registers.

## For other modules

```dart
final economy = host.services.require<Economy>();  // list 'economy' in dependsOn
final result = economy.withdraw(uuid, 50, reason: 'Shop');
if (!result.isOk) { /* result.failure says why */ }
sender.send('Balance: ${economy.format(economy.balance(uuid))}');
```
