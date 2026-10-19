// The runtime shared by the parts of the logistics module (created in `LogisticsModule.onLoad`):
// the context, the link directory and manager, the stack conversions, the payload bus.
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../api/config.dart';
import '../../api/payloads.dart';
import '../../api/sounds.dart';
import '../../content/components.dart' show createComponents;
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart' show RegistryKind;
import '../../core/world_state.dart';
import '../../core/worlds.dart';
import '../model/manager.dart';
import '../model/network.dart';
import '../model/stack.dart';
import '../model/stack_wire.dart';
import 'stack_io.dart';

/// The overworld, whose ticks drive the networks (`GlobalLogisticsManager.tick`).
const String overworldId = 'minecraft:overworld';

final class LgRuntime {
  final CreateContext ctx;
  final Random random = Random();

  /// Game ticks since the plugin loaded (the clock of the caches and promises).
  int tick = 0;

  late final LinkDirectory links = LinkDirectory(() => tick);
  late final LogisticsManager manager = LogisticsManager(
    links,
    () => tick,
    random: random,
  );
  late final GlobalLogisticsManager global = GlobalLogisticsManager(
    onDirty: _markGlobalDirty,
  );
  late final StackWire wire;
  late final StackIo io;

  /// The saved data of the networks (`create_logistics`), in the overworld.
  late final SavedDataType<LogisticsSavedData> savedType =
      SavedDataType<LogisticsSavedData>(
        'create_logistics',
        create: LogisticsSavedData.new,
        fromMap: LogisticsSavedDataMapper.fromMap,
        toMap: (_) => global.save().toMap(),
      );

  LgRuntime(this.ctx) {
    wire = StackWire(
      items: ctx.services.require<ItemIdResolver>(),
      componentIdOf: _componentId,
      componentNameOf: _componentName,
    );
    io = StackIo(wire, [for (final c in createComponents) c.key]);
  }

  Logger get log => ctx.log;
  BlockEntityStore get store => ctx.blockEntities;
  Worlds get worlds => ctx.worlds;
  PayloadBus get bus => ctx.services.require<PayloadBus>();
  CreateSounds? get sounds => ctx.services.find<CreateSounds>();
  CreateAdvancements? get advancements =>
      ctx.services.find<CreateAdvancements>();
  CreateConfigs? get configs => ctx.services.find<CreateConfigs>();

  // -- ids ----------------------------------------------------------------------------------------

  Map<int, String>? _componentNames;

  int? _componentId(String name) => name.startsWith('create:')
      ? ctx.ids.of(RegistryKind.dataComponents, name)
      : VanillaIds.dataComponentTypes.idOf(name);

  String? _componentName(int id) {
    final vanilla = VanillaIds.dataComponentTypes.keyOf(id);
    if (vanilla != null) return vanilla;
    _componentNames ??= {
      for (final e in ctx.ids.all(RegistryKind.dataComponents).entries)
        e.value: e.key,
    };
    return _componentNames![id];
  }

  /// The numeric id of the item [key] (vanilla or plugin).
  int? itemId(String key) => wire.items.idOf(key);

  // -- configuration --------------------------------------------------------------------------------

  /// `logistics.packagePortRange`.
  int get packagePortRange =>
      configs?.server.logistics.packagePortRange.value ?? 5;

  /// `logistics.factoryGaugeTimer`.
  int get factoryGaugeTimer =>
      configs?.server.logistics.factoryGaugeTimer.value ?? 100;

  // -- worlds and players -------------------------------------------------------------------------------

  World? world(String id) => worlds.byId(id);

  /// The online player with [uuid], or `null`.
  Player? player(String uuid) {
    for (final p in bus.roster.players) {
      try {
        if (p.getId().asString == uuid) return p;
      } on Object {
        // a handle that went invalid
      }
    }
    return null;
  }

  /// A random version 4 UUID in canonical text.
  String newUuid() {
    String hex(int digits) => List.generate(
      digits,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final variant = '89ab'[random.nextInt(4)];
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  /// The id of [player]'s world. The owned handle is released; use [world] for the kept one.
  String playerWorldId(Player player) {
    final w = player.getWorld();
    final id = w.getId();
    w.dispose();
    return id;
  }

  // -- stacks -------------------------------------------------------------------------------------------

  Future<LStack> read(ItemStack? stack) => io.read(stack);

  Future<ItemStack?> write(LStack stack) => io.write(stack);

  // -- the global networks ------------------------------------------------------------------------------

  void _markGlobalDirty() => ctx.savedData.markDirty(overworldId, savedType);

  /// Loads the saved networks when the overworld appears.
  void loadGlobal(World overworld) {
    final data = ctx.savedData.get(overworld, savedType);
    global.load(data);
  }
}

/// Access to the runtime from block handlers (built in `register()`, before it exists).
abstract final class Lg {
  static LgRuntime? _instance;

  static LgRuntime get i =>
      _instance ?? (throw StateError('The logistics module is not loaded'));

  static bool get loaded => _instance != null;

  static void install(LgRuntime runtime) => _instance = runtime;

  static void clear() => _instance = null;
}
