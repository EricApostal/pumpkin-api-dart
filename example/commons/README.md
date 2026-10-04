# Commons

A community-server suite for [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin),
written in Dart with `pumpkin_api`. It needs no world setup: drop it into
`plugins/` and everything works.

| Module | What it gives you | Docs |
| --- | --- | --- |
| economy | balances, `/pay`, `/baltop`, admin tools, an IPC API for other plugins | [economy](docs/economy.md) |
| rewards | `/daily` login streaks, a calendar menu, playtime and milestones | [rewards](docs/rewards.md) |
| shop | chest-menu shop, `/buy`, `/sell`, `/worth`, an editable catalog | [shop](docs/shop.md) |
| kits | claimable kits with cooldowns, prices and permissions | [kits](docs/kits.md) |
| mail | offline messages with an inbox, blocking and limits | [mail](docs/mail.md) |
| chat | formatting, rank prefixes, mentions, `/msg`, `/ignore`, anti-spam, join summary | [chat](docs/chat.md) |
| announcements | rotating chat, action bar, boss bar and title announcements | [announcements](docs/announcements.md) |
| moderation | warn, mute, ban, kick, history, vanish, staff chat | [moderation](docs/moderation.md) |

Every module has its own folder, config, messages (`messages/<module>.json`)
and permission nodes (`commons:<module>.<thing>`), and can be left out in
[`lib/src/modules.dart`](lib/src/modules.dart). See
[ARCHITECTURE.md](ARCHITECTURE.md) for how it is put together.

## Install

```sh
dart pub get                     # from the repository root
cd example/commons
dart run pumpkin_tools build     # -> build/commons.wasm
```

Copy `build/commons.wasm` into the server's `plugins/` folder and approve the
`fs.write.data` permission. The plugin writes its files below
`plugins/data/commons/` (the first start creates every config with defaults).

## Development

```sh
dart run build_runner build      # after changing a @MappableClass
dart test                        # unit tests, no server needed
dart analyze
```

The logic of every module is plain Dart and unit tested. What has not been
tested yet is everything that needs a connected player: menus, titles, boss
bars, chat formatting, and commands run by a player (the console paths were
run against a real server).
