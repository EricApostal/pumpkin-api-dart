# Commons - architecture

Commons is a community-server suite for Pumpkin written with `pumpkin_api`:
economy, shop, kits, daily rewards and playtime, mail, chat, announcements and
moderation. It needs no world setup: it works on any server as soon as it loads.

It doubles as the reference for how to structure a larger plugin.

## Layout

```text
bin/main.dart                 runPlugin(CommonsPlugin())
lib/src/plugin.dart           CommonsPlugin: loads modules in dependency order, autosaves, unloads
lib/src/modules.dart          the list of modules
lib/src/load_order.dart       dependency ordering (tested)
lib/src/core/                 shared infrastructure (no module-specific code)
  api.dart                    service interfaces modules offer each other (Economy, ModerationApi, MailApi, RewardsApi)
  clock.dart                  Clock / FakeClock
  storage.dart                StorageBackend, Documents, JsonDocument<T> (dart_mappable value, dirty tracking, corrupt-file recovery)
  storage_pumpkin.dart        StorageBackend on the plugin data folder
  services.dart               Services: provide<T>() / require<T>() / find<T>()
  module.dart                 Module + ModuleHost
  permissions.dart            PermNode
  players.dart                PlayerDirectory service (uuid <-> name, first/last seen)
lib/src/<module>/             one folder per module (see below)
test/                         VM unit tests (no server needed)
docs/<module>.md              what each module does, its commands, permissions and files
```

A module `foo` follows the same shape:

```text
lib/src/foo/
  model.dart          dart_mappable data classes (@MappableClass) + generated model.mapper.dart
  service.dart        the logic: plain Dart, NO server bindings, takes a Clock and JsonDocuments, unit tested
  permissions.dart    the module's PermNodes
  commands.dart       registers commands with context.command(...)
  ui.dart             menus / boss bars / titles, only if needed
  foo_module.dart     FooModule extends Module: wires everything, provides services
```

## Rules

* **Binding-free logic.** Anything that imports `package:pumpkin_api/pumpkin_api.dart`
  (or anything that imports the generated bindings) cannot run in `dart test`.
  Keep `model.dart` and `service.dart` free of it so they are unit tested; put
  server-facing code in `commands.dart`, `ui.dart` and `*_module.dart`.
  (`package:pumpkin_api/src/command_help.dart` and `menu_layout.dart` are
  binding-free and may be imported in tests if needed.)
* **Modules talk through `core/api.dart`.** Never import another module's
  folder. Provide a service with `host.services.provide<Economy>(...)`, list
  the provider in `dependsOn`, and use `host.services.require<Economy>()`
  (or `find<T>()` when the dependency is optional, but then also list it in
  `dependsOn` so it loads first).
* **Data** lives in `JsonDocument`s opened with `host.docs.open(...)`, under
  `<module>/...json`, as dart_mappable classes. No hand-written JSON. Assign
  `doc.value = doc.value.copyWith(...)` (or `modify`) - that marks it dirty and
  the plugin saves every 10 s and on unload. For data that must not be lost
  (money moved, punishments) also call `doc.save()` right away.
* **Money** is `int` whole units, never a double.
* **Time** comes from `host.clock` (or an injected `Clock`), never `DateTime.now()`.
* **Messages**: user-visible text goes through `host.messages({...defaults})`
  so owners can edit `messages/<module>.json`; keys are `area.thing`
  (`pay.sent`). Send with `sender.sendTemplate(messages, key, {...})`. Put
  player-controlled text through `MessageFormat.escape`.
* **Permissions**: nodes are `commons:<module>.<thing>` (e.g.
  `commons:economy.pay`), declared as `PermNode`s with a default
  (`everyone` for normal play, `op` for admin tools), returned from
  `Module.permissions`. Commands built with `context.command(...)` pass
  `permission:` explicitly.
* **Commands** use the builder (`docs/commands.md` of `pumpkin_api`): typed
  args, `requirePlayer()`, `cooldown`, tab completion from real data
  (`PlayerDirectory.names`, the module's own data).
* **Callbacks never throw into the server**: validate and answer the player
  with a message (`ctx.fail(...)` / `CommandException`) instead.
* **Async**: handlers may be `async`, but `ctx`/`sender`/`server` are only valid
  until the first `await` (see `pumpkin_api` `docs/async.md`).
* **Players** are identified by UUID string (`player.asEntity().getUuid().asString`);
  names are display only.
* Style: match `example/teleport` and `pumpkin_api` - doc comments on public
  API, small files, no dead code.

## Building and testing

```sh
dart pub get                                   # from the repo root
cd example/commons
dart run build_runner build                    # after changing a @MappableClass
dart test                                      # VM unit tests
dart analyze
dart run pumpkin_tools build                   # -> build/commons.wasm
```

Copy `build/commons.wasm` to the server's `plugins/` directory and approve the
`fs.write.data` permission.
