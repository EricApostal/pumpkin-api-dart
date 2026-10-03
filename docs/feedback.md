# Feedback to players

Helpers for talking to players: messages, titles, sounds, particles, boss bars,
sidebars, paginated lists and confirmations. Everything here takes plain
strings or [`Text`] and builds the host `TextComponent`s for you (host
components are *consumed* when sent, so a fresh one is built for every send).

## Messages

`send` takes a `String` with `&`/`§` color codes (`&&` is a literal `&`), a
`Text`, or a ready `TextComponent` (consumed). It exists on `CommandSender` and
`Player`:

```dart
sender.send('&aSaved!');
player.send(Text('Welcome, ').gold() + Text(name).yellow().bold());
sender.send(Text('[Home]').green().runCommand('/home').hover('Teleport home'));
server.broadcastText('&eServer restarts in 1 minute');   // every player
world.broadcastText('&7Round over', overlay: true);       // one world
```

`Text` is plain data: style methods (`green()`, `bold()`, `rgb(r,g,b)`,
`rainbow()`, `runCommand`, `suggestCommand`, `openUrl`, `copyToClipboard`,
`hover`, `insertion`), `+`, `add`, `Text.join(parts, separator: ...)`,
`Text.legacy('&a...')`. Use `MessageFormat.escape(input)` for player supplied
text you put in a color-coded string, and `MessageFormat.stripColors`.

## Templates

```dart
final messages = context.files.messageCatalog('messages.json',
    prefix: '&8[&6Homes&8] &r',
    defaults: {'home.set': '&aHome {name} set!', 'home.list': '{0} of {1} homes'});

sender.sendTemplate(messages, 'home.set', {'name': 'base'});
sender.sendTemplate(messages, 'home.list', [2, 5]);
messages['home.set'].format({'name': 'x'});          // just the string
```

`{name}` reads from a map, `{0}` from a list, `{{`/`}}` are literal braces,
unknown placeholders stay as written, an unknown key shows the key. The JSON
file in the data folder (needs `fs.write.data`) is created and gets missing keys
added, so owners can edit translations. The core, `MessageCatalog`, is pure
Dart and can be built from defaults or `MessageCatalog.fromJson`.

## Titles, sounds, particles

```dart
player.title('&6Round 1', subtitle: '&7Fight!', stay: Duration(seconds: 2));
player.actionBar('&cLow health');
player.sound(Sound.entityPlayerLevelup, volume: 0.5, pitch: 1.2);
player.particle(Particle.flame, count: 10, offset: (0.3, 0.3, 0.3));
world.sound(Sound.blockNoteBlockBell, (x, y, z));
world.particle(Particle.heart, (x, y + 2, z), count: 3);
```

Positions are `(double, double, double)` records. Titles set the timing only
when you pass a duration (otherwise the client's defaults apply).

## Boss bars

`ManagedBossBar` keeps the host bar alive between callbacks:

```dart
final bar = ManagedBossBar('&cBoss', color: BossBarColor.red);
bar.addPlayerById(server, uuid);    // doesn't consume anything
bar.addPlayer(player);              // CONSUMES `player` (the host takes it)
bar.progress = 0.5;                 // 0..1
bar.updateEvery(Duration(seconds: 1), (b) => b.title = '...');
bar.countdown(Duration(seconds: 30), onFinish: (b) => ...);
bar.remove();                       // hides it for everyone and releases it
```

## Sidebar

`Sidebar` holds a title and lines; `render` shows or refreshes it on a
`Scoreboard` and only sends changes:

```dart
final sidebar = Sidebar('stats', title: '&6&lServer', lines: ['&7Online: 3']);
world.showSidebar(sidebar);         // after changing title/lines, call again
world.hideSidebar(sidebar);
```

Duplicate lines are made unique with invisible suffixes; scores are hidden.

## Pagination and confirmations

```dart
final pages = Paginator(homes, pageSize: 8);
sender.sendPage(pages, args.integer('page'), title: 'Homes',
    format: (home, i) => '&7${i + 1}. &f${home.name}', command: '/homes {page}');

final confirmations = ConfirmationManager<void Function()>();
confirmations.request(uuid, () => deleteAll(), ttl: Duration(seconds: 10));
confirmations.confirm(uuid)?.call();   // null if none or expired; one shot
```

`Paginator` page numbers are 1-based and clamped. `ConfirmationManager` takes
an injectable clock and holds no host handles.

## Known issue: enum-based sounds (host bug)

`World.sound`, `Player.sound` and the other calls that take a `Sound` enum value
currently **trap the plugin** on Pumpkin. The host looks the sound up with
`format!("{sound:?}").to_lowercase().replace('_', ".")`, which turns the Rust name
`EntityPlayerLevelup` into `entityplayerlevelup`, a name that never exists in its
registry, so the call fails and the plugin's store is stopped.

Until that's fixed in Pumpkin, play sounds by their registry name instead, with
`customSound(...)` (it takes `'minecraft:entity.player.levelup'`-style names).
The `Sound` enum's `wireName` can't be converted to a registry name reliably
(`block.note_block.bell` and `block.note.block.bell` flatten to the same text).
