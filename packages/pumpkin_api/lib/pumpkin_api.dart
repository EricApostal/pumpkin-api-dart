/// Dart API for writing Pumpkin Minecraft server plugins.
///
/// This is a typed wrapper over the bindings generated from
/// `pumpkin-plugin-wit` (see `tool/generate_bindings.sh`). Everything the host
/// exposes is available, and the parts that are awkward to use directly --
/// commands, events, tasks, errors -- have a nicer API on top:
///
/// * [Plugin] and [runPlugin] to define a plugin,
/// * `Context.listen`/`Context.intercept` with the typed [Events],
/// * [CommandHandler]s as closures, typed [ArgumentTypes] and argument access,
/// * `runLater`/`runRepeating` for scheduling and [logger] for logging.
library;

export 'package:wasm_components/wasm_components.dart'
    show Option, Result, OkResult, ErrorResult;

export 'src/bindings.g.dart'
    hide definePlugin, PluginExports, Metadata, PluginMetadata;
export 'src/ai.dart' hide aiGoals;
export 'src/blocks.dart';
export 'src/items.dart';
export 'src/inventory.dart';
export 'src/datapacks.dart';
export 'src/game_rules.dart';
export 'src/forms.dart';
export 'src/enchantments.dart';
export 'src/recipes.dart';
export 'src/teams.dart';
export 'src/persistent_data.dart';
export 'src/advancements.dart';
export 'src/attributes.dart';
export 'src/display.dart';
export 'src/mobs.dart';
export 'src/player_ext.dart';
export 'src/server_list_ping.dart';
export 'src/uuid_ext.dart';
export 'src/commands.dart' hide commandErrorFor, commandHandlers, suggestionHandlers;
export 'src/events.dart' hide eventHandlers;
export 'src/events.g.dart';
export 'src/logger.dart';
export 'src/permissions.dart';
export 'src/plugin.dart' show Plugin, PluginInfo, runPlugin;
export 'src/scheduler.dart';
export 'src/worldgen.dart' hide chunkGenerators;
