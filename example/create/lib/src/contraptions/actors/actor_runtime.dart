// The host side the contraption actors need: the world of a movement context, the server config
// values they read, and the helpers that write blocks or spawn items. The actors themselves only
// see `MovementContext`; this is the one place that reaches the host `World`.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show setBlockState;
import '../../api/payloads.dart' show ItemIdResolver;
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../../core/worlds.dart';
import '../../infrastructure/config/create_configs.dart';
import '../core/movement.dart';
import '../storage/stacks.dart';

/// `AllConfigs.server()` and the kept worlds, installed by `loadActorContent`.
final class ActorRuntime {
  final Worlds worlds;
  final BlockEntityStore blockEntities;
  final CreateConfigs? configs;
  final Logger log;

  /// Resolves item keys for the wire (`ContraptionDisableActorPacket` filters).
  final ItemIdResolver? itemIds;

  ActorRuntime(
    this.worlds,
    this.blockEntities,
    this.configs,
    this.log, {
    this.itemIds,
  });

  static ActorRuntime? current;

  static void install(ActorRuntime runtime) => current = runtime;

  static void uninstall() => current = null;

  /// The host world of a movement context, `null` when it unloaded.
  World? worldOf(MovementContext context) => worlds.byId(context.worldId);

  /// `AllConfigs.server().kinetics.rollerFillDepth`.
  int get rollerFillDepth =>
      configs?.server.kinetics.rollerFillDepth.value ?? 12;

  /// `AllConfigs.server().kinetics.harvesterReplants`.
  bool get harvesterReplants =>
      configs?.server.kinetics.harvesterReplants.value ?? true;

  /// `AllConfigs.server().kinetics.harvestPartiallyGrown`.
  bool get harvestPartiallyGrown =>
      configs?.server.kinetics.harvestPartiallyGrown.value ?? false;

  /// `AllConfigs.server().logistics.psiTimeout`.
  int get psiTimeout => configs?.server.logistics.psiTimeout.value ?? 60;

  /// `AllConfigs.server().logistics.seatHostileMobs`.
  bool get seatHostileMobs =>
      configs?.server.logistics.seatHostileMobs.value ?? true;

  /// `AllConfigs.server().kinetics.moveItemsToStorage`.
  bool get moveItemsToStorage =>
      configs?.server.kinetics.moveItemsToStorage.value ?? true;
}

/// The runtime of the module, `null` before `loadActorContent`.
ActorRuntime? get actors => ActorRuntime.current;

/// `Vec3.atLowerCornerOf(direction.getUnitVec3i())`.
Vec3 unitVec(Direction d) => d.unitVec3;

/// A random source for the small decisions of the actors (`level.getRandom()`).
final math.Random actorRandom = math.Random();

/// `Mth.clamp(int, int, int)`.
int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// `Mth.clamp(float, float, float)`.
double clampDouble(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

final Map<String, int> _maxAge = {};

/// The largest `age` value of the block [blockKey] (`CropBlock.getMaxAge`), read from the host's
/// block states and cached.
int maxAgeOf(String blockKey) => _maxAge.putIfAbsent(blockKey, () {
  final block = BlockRegistry.of(blockKey);
  if (block == null) return 0;
  var max = 0;
  for (final state in block.states) {
    final age = int.tryParse(state.propertyMap['age'] ?? '');
    if (age != null && age > max) max = age;
  }
  return max;
});

/// Writes a block state to the host world (`level.setBlockAndUpdate`).
Future<void> setWorldBlock(
  World world,
  Pos pos,
  BState state, {
  bool neighbors = true,
}) => setBlockState(
  world,
  pos,
  state,
  flags: neighbors ? BlockUpdateFlags.normal : BlockUpdateFlags.clientsOnly,
);

/// Drops a saved stack at [pos] as an item entity.
Future<void> dropStoredStack(
  World world,
  Vec3 pos,
  StoredStack stack, {
  (double, double, double)? velocity,
}) async {
  if (stack.isEmpty) return;
  final item = ItemStack.create(registryKey: stack.item, count: stack.count);
  try {
    await world.dropItem(pos, item, velocity: velocity);
  } finally {
    item.dispose();
  }
}
