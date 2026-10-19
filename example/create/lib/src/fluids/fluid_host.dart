// The host side of the fluid logic: the [FluidWorld] over a host world, the
// conversions between the module's [FStack] and the host's `FluidStack`, and the
// [FluidStorage] view over a host fluid handler. Everything that touches
// `package:pumpkin_api` for the fluids module lives here; the algorithms are in
// the pure files next to this one.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show HostBlockGetter;
import '../api/config.dart' show CreateConfigs;
import '../common/bounds.dart';
import '../common/direction.dart';
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';

/// A block entity of this module that exposes a fluid handler to the pipe logic
/// (`Capabilities.Fluid.BLOCK` of the Create block entity). The host world's
/// [HostFluidWorld.fluidCapability] asks for this before it falls back to the
/// host's own handler of a plugin block entity.
abstract interface class FluidCapable {
  /// The handler of this block entity, `null` while it has none.
  FluidStorage? get fluidHandler;
}

/// The module's [FStack] from the host's stack (`null` is empty).
FStack fromHostFluid(FluidStack? stack) => stack == null || stack.amount <= 0
    ? FStack.empty
    : FStack(stack.fluid, stack.amount, stack.data);

/// The host's stack of [stack].
FluidStack toHostFluid(FStack stack) =>
    FluidStack(fluid: stack.fluid, amount: stack.amount, data: stack.data);

/// A [FluidStorage] over a host fluid handler. The host handler is synchronous
/// (`fluid-handler.wit`), so the pipe network can drive it directly.
final class HostFluidStorage implements FluidStorage {
  final FluidHandler handler;

  HostFluidStorage(this.handler);

  @override
  int get tanks => handler.tankCount();

  @override
  FStack fluidInTank(int tank) => fromHostFluid(handler.getFluid(tank: tank));

  @override
  int tankCapacity(int tank) => handler.getTankCapacity(tank: tank);

  @override
  bool isFluidValid(int tank, FStack stack) =>
      stack.isNotEmpty &&
      handler.isFluidValid(tank: tank, fluidKey: stack.fluid);

  @override
  int fill(FStack resource, {required bool simulate}) => resource.isEmpty
      ? 0
      : handler.fill(stack: toHostFluid(resource), simulate: simulate);

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty) return FStack.empty;
    return fromHostFluid(
      handler.drainFluid(
        fluidKey: resource.fluid,
        maxAmount: resource.amount,
        simulate: simulate,
      ),
    );
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) => maxDrain <= 0
      ? FStack.empty
      : fromHostFluid(handler.drain(maxAmount: maxDrain, simulate: simulate));
}

/// `CFluids` over the live config of the infrastructure module.
final class ConfigsFluidsConfig implements FluidsConfig {
  final CreateConfigs configs;

  const ConfigsFluidsConfig(this.configs);

  @override
  int get fluidTankCapacity => configs.server.fluids.fluidTankCapacity.value;
  @override
  int get fluidTankMaxHeight => configs.server.fluids.fluidTankMaxHeight.value;
  @override
  int get mechanicalPumpRange =>
      configs.server.fluids.mechanicalPumpRange.value;
  @override
  int get hosePulleyRange => configs.server.fluids.hosePulleyRange.value;
  @override
  int get hosePulleyBlockThreshold =>
      configs.server.fluids.hosePulleyBlockThreshold.value;
  @override
  bool get fillInfinite => configs.server.fluids.fillInfinite.value;
  @override
  BottomlessFluidMode get bottomlessFluidMode => BottomlessFluidMode.parse(
    configs.server.fluids.bottomlessFluidMode.value,
  );
  @override
  bool get fluidFillPlaceFluidSourceBlocks =>
      configs.server.fluids.fluidFillPlaceFluidSourceBlocks.value;
  @override
  bool get pipesPlaceFluidSourceBlocks =>
      configs.server.fluids.pipesPlaceFluidSourceBlocks.value;
}

/// The [FluidWorld] over a host [World]: block reads through [HostBlockGetter],
/// Create block entities through the [BlockEntityStore], and everything else
/// through the host API. Writes are fire and forget, like the block entity ticks
/// that issue them.
final class HostFluidWorld extends BlockGetter implements FluidWorld {
  final World world;
  final String worldId;
  final BlockEntityStore store;
  @override
  final FluidsConfig config;

  /// `AdvancementBehaviour.tryAward(level, pos, advancement)`.
  final void Function(Pos pos, String advancement)? onAward;

  final math.Random _random = math.Random();
  final HostBlockGetter _blocks;
  final Map<(int, int, int, int), HostFluidStorage> _handlers = {};

  HostFluidWorld(
    this.world,
    this.worldId,
    this.store,
    this.config, {
    this.onAward,
  }) : _blocks = HostBlockGetter(world);

  /// `Level.getGameTime()`.
  @override
  int get gameTime => world.getWorldAge();

  @override
  BState stateAt(Pos p) => _blocks.stateAt(p);

  @override
  bool isLoaded(Pos p) => _blocks.isLoaded(p);

  @override
  bool isFaceSturdy(Pos p, Direction face) => _blocks.isFaceSturdy(p, face);

  @override
  List<BlockBox> collisionBoxes(Pos p) => _blocks.collisionBoxes(p);

  @override
  bool supportShapeEmpty(Pos p) => _blocks.supportShapeEmpty(p);

  @override
  bool canBeReplaced(Pos p) => _blocks.canBeReplaced(p);

  @override
  bool hasTag(Pos p, String tag) => _blocks.hasTag(p, tag);

  @override
  bool isWater(Pos p) => _blocks.isWater(p);

  @override
  FluidInfo fluidAt(Pos p) {
    final f = world.getFluidState(pos: p.toBlockPos());
    if (f == null || f.fluid == 'minecraft:empty') return FluidInfo.none;
    return FluidInfo(
      f.fluid,
      f.level,
      isSource: f.isSource,
      isFalling: f.isFalling,
    );
  }

  @override
  bool get waterEvaporates => false;

  @override
  PipeNodeView? pipeAt(Pos p) {
    final be = store.at(worldId, p.toBlockPos());
    if (be is! PipeNodeView) return null;
    final node = be as PipeNodeView;
    return node.isRemoved ? null : node;
  }

  @override
  PumpPeer? pumpAt(Pos p) {
    final be = store.at(worldId, p.toBlockPos());
    return be is PumpPeer ? be as PumpPeer : null;
  }

  @override
  bool hasBlockEntity(Pos p) =>
      store.at(worldId, p.toBlockPos()) != null ||
      world.getBlockEntity(pos: p.toBlockPos()) != null;

  @override
  FluidStorage? fluidCapability(Pos p, Direction? side) {
    final be = store.at(worldId, p.toBlockPos());
    if (be is FluidCapable) return (be as FluidCapable).fluidHandler;
    final key = (p.$1, p.$2, p.$3, side?.index ?? -1);
    final cached = _handlers[key];
    if (cached != null) return cached;
    final handler = FluidHandlers.at(
      world,
      p.toBlockPos(),
      side: side?.toHost(),
    );
    if (handler == null) return null;
    final storage = HostFluidStorage(handler);
    _handlers[key] = storage;
    return storage;
  }

  @override
  bool hasBracket(Pos p) => false;

  @override
  bool isUnbreakable(Pos p) => world.getBlock(pos: p.toBlockPos()).hardness < 0;

  // -- writes ------------------------------------------------------------------------------

  @override
  void setBlock(Pos p, BState state, {bool quiet = false}) {
    final id = BlockRegistry.resolveState(state.key, state.props);
    if (id == null) return;
    _handlers.clear();
    final flags = quiet
        ? {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate}
        : BlockUpdateFlags.normal;
    unawaited(
      world
          .setBlockState(pos: p.toBlockPos(), state: id, updateFlags: flags)
          .catchError((Object e, StackTrace s) {
            return;
          }),
    );
  }

  @override
  void neighboursChanged(Pos p) =>
      unawaited(world.updateShapeAround(pos: p.toBlockPos()));

  @override
  bool fluidHasTag(String fluid, String tag) => Tags.fluid(fluid, tag);

  @override
  void dropResources(Pos p) {
    unawaited(
      world
          .getBlockDrops(pos: p.toBlockPos(), tool: null)
          .then((drops) async {
            for (final stack in drops) {
              await world.dropItem(p.center, stack);
            }
          })
          .catchError((Object e, StackTrace s) {}),
    );
  }

  @override
  bool canSurvive(Pos p) => true;

  @override
  void scheduleFluidTick(Pos p, String fluid, int delay) =>
      world.scheduleFluidTick(pos: p.toBlockPos(), delay: delay.clamp(0, 255));

  @override
  void placeFluidSource(Pos p, String fluid) =>
      world.tryPlaceFluid(pos: p.toBlockPos(), fluidKey: fluid);

  @override
  FStack pickupFluidSource(Pos p) =>
      fromHostFluid(world.tryPickupFluid(pos: p.toBlockPos()));

  @override
  void playSound(Pos p, String sound, {double volume = 1, double pitch = 1}) {
    try {
      world.playCustomSound(
        soundName: sound,
        category: SoundCategory.blocks,
        pos: (p.x + .5, p.y + .5, p.z + .5),
        volume: volume,
        pitch: pitch,
      );
    } on HostException {
      // The sound is unknown to the host; the state change still happened.
    }
  }

  @override
  void destroyBlock(Pos p, double effectChance) =>
      unawaited(BlockHelper.destroyBlock(world, p, effectChance));

  @override
  void applyOpenPipeEffect(FStack fluid, Aabb area) {
    final still = FluidKeys.still(fluid.fluid);
    final lava = still == FluidKeys.lava;
    final water = still == FluidKeys.water;
    if (!lava && !water) return;
    final entities = world.getEntitiesInBox(
      min: (area.minX, area.minY, area.minZ),
      max: (area.maxX, area.maxY, area.maxZ),
      filter: const EntityFilterAll(),
    );
    for (final snapshot in entities) {
      if (!area.contains(snapshot.position)) continue;
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      entity.setFireTicks(ticks: lava ? 300 : 0);
    }
  }

  @override
  void splash(Pos p, FStack fluid) {
    // The splash packet only spawns client particles (out of scope, see the brief).
  }

  @override
  void award(Pos p, String advancement) => onAward?.call(p, advancement);

  @override
  double nextDouble() => _random.nextDouble();

  @override
  int nextInt(int bound) => bound <= 0 ? 0 : _random.nextInt(bound);

  /// Forgets the cached host handlers (the block at a position changed).
  void forgetHandlers() => _handlers.clear();
}

/// `Level.setBlock(pos, state, flags)`, fire and forget. Does nothing for an
/// unknown state or while the world is not loaded.
void setFluidBlock(
  World? world,
  Pos pos,
  BState state, {
  Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
}) {
  if (world == null) return;
  final id = BlockRegistry.resolveState(state.key, state.props);
  if (id == null) return;
  unawaited(
    world
        .setBlockState(pos: pos.toBlockPos(), state: id, updateFlags: flags)
        .catchError((Object e, StackTrace s) {}),
  );
}
