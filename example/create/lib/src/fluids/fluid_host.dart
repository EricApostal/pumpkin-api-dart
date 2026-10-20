// The host side of the fluid logic: the [FluidWorld] over a host world, the
// conversions between the module's [FStack] and the host's `FluidStack`, and the
// [FluidStorage] view over a host fluid handler. Everything that touches
// `package:pumpkin_api` for the fluids module lives here; the algorithms are in
// the pure files next to this one.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../api/block_state.dart';
import '../api/blocks.dart' show HostBlockGetter;
import '../api/config.dart' show CreateConfigs;
import '../api/effect/open_pipe_effect_handler.dart' as api_effect;
import '../common/bounds.dart';
import '../common/direction.dart';
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../decoration/bracketed_behaviour.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';
import 'open_pipe_effects.dart';
import 'potion_data.dart';

/// A block entity of this module that exposes a fluid handler to the pipe logic
/// (`Capabilities.Fluid.BLOCK` of the Create block entity). The host world's
/// [HostFluidWorld.fluidCapability] asks for this before it falls back to the
/// host's own handler of a plugin block entity.
abstract interface class FluidCapable {
  /// The handler of this block entity, `null` while it has none.
  FluidStorage? get fluidHandler;
}

/// A [FluidCapable] whose handler depends on the side it is seen from
/// (`Capabilities.Fluid.BLOCK` with a context); checked before [FluidCapable].
abstract interface class SidedFluidCapable {
  FluidStorage? fluidHandlerAt(Direction? side);
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

  /// Releases the host handler (a kept resource) when the world goes away.
  void dispose() => handler.dispose();
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

  /// Resolves the server for the effects only players can receive (`MilkEffectHandler`,
  /// `PotionEffectHandler`, `TeaEffectHandler`); `null` while the server is gone.
  final Server? Function()? serverProvider;

  final math.Random _random = math.Random();
  final HostBlockGetter _blocks;
  final Map<(int, int, int, int), HostFluidStorage> _handlers = {};

  HostFluidWorld(
    this.world,
    this.worldId,
    this.store,
    this.config, {
    this.onAward,
    this.serverProvider,
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
  /// `EnvironmentAttributes.WATER_EVAPORATES` of the dimension: only the Nether-like dimensions
  /// set it, so water placed there turns to nothing instead of a source block.
  @override
  bool get waterEvaporates {
    final dimension = world.dimension;
    return dimension == 'minecraft:the_nether' ||
        dimension == 'minecraft:nether' ||
        dimension.endsWith(':the_nether');
  }

  @override
  PipeNodeView? pipeAt(Pos p) {
    // The node is the `FluidTransportBehaviour` the block entity owns, not the block
    // entity: a pipe block entity is not a `PipeNodeView` (the pump's is a `PumpPeer`).
    final be = store.at(worldId, p.toBlockPos());
    return be == null ? null : pipeNodeIn(be.behaviours);
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
    if (be is SidedFluidCapable)
      return (be as SidedFluidCapable).fluidHandlerAt(side);
    if (be is FluidCapable) return (be as FluidCapable).fluidHandler;
    final key = (p.$1, p.$2, p.$3, side?.index ?? -1);
    final cached = _handlers[key];
    if (cached != null) return cached;
    // The host releases a handler when the callback that received it returns; the pipe
    // network keeps it across ticks, so it has to be kept (`ResourceKeep.keep`).
    final handler = FluidHandlers.at(
      world,
      p.toBlockPos(),
      side: side?.toHost(),
    )?.keep();
    if (handler == null) return null;
    final storage = HostFluidStorage(handler);
    _handlers[key] = storage;
    return storage;
  }

  /// Forgets the host handlers at [p]: the block there may have changed, so the next
  /// lookup asks the host again (`FluidHandlers.at`).
  void _invalidateHandlers(Pos p) {
    final keys = [
      for (final key in _handlers.keys)
        if (key.$1 == p.$1 && key.$2 == p.$2 && key.$3 == p.$3) key,
    ];
    for (final key in keys) {
      _handlers.remove(key)?.dispose();
    }
  }

  /// Releases the kept host handlers (world unload).
  void dispose() {
    for (final storage in _handlers.values) {
      storage.dispose();
    }
    _handlers.clear();
  }

  @override
  bool hasBracket(Pos p) {
    final be = store.at(worldId, p.toBlockPos());
    return be
            ?.getBehaviour<BracketedBlockEntityBehaviour>()
            ?.isBracketPresent ??
        false;
  }

  @override
  bool isUnbreakable(Pos p) => world.getBlock(pos: p.toBlockPos()).hardness < 0;

  // -- writes ------------------------------------------------------------------------------

  @override
  void setBlock(Pos p, BState state, {bool quiet = false}) {
    final id = BlockRegistry.resolveState(state.key, state.props);
    if (id == null) return;
    _invalidateHandlers(p);
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
  void updateComparators(Pos p) =>
      unawaited(world.updateComparators(pos: p.toBlockPos()));

  @override
  bool hasShaftTowards(Pos p, Direction face) {
    final id = world.getBlockStateId(pos: p.toBlockPos());
    final info = BlockStates.info(id);
    if (info == null) return false;
    // The same three families the kinetic placement rules use: `axis` shafts, the blocks whose
    // shaft leaves through `facing`, and those whose shaft points along `facing`.
    if (BlockStates.isTag(id, 'create:shafts')) {
      return info.properties['axis'] == face.axis.name;
    }
    final facing = info.properties['facing'];
    if (facing == null) return false;
    if (BlockStates.isTag(id, 'create:facing_shafts')) {
      return facing == face.opposite.serializedName;
    }
    if (BlockStates.isTag(id, 'create:reverse_facing_shafts')) {
      return facing == face.serializedName;
    }
    return false;
  }

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
    // Handlers registered through the public API (`OpenPipeEffectHandler.REGISTRY`) run first.
    final external = api_effect.OpenPipeEffects.of(
      FluidKeys.still(fluid.fluid),
    );
    if (external != null) {
      external.apply(area, fluid);
      return;
    }

    final effect = OpenPipeEffects.ofWorld(this, fluid.fluid);
    if (effect == null) return;
    if (!OpenPipeEffects.shouldApply(gameTime, effect)) return;

    switch (effect) {
      case OpenPipeEffect.water:
        // `WaterEffectHandler`: entities stop burning and open fire is doused.
        for (final snapshot in _entitiesIn(area)) {
          final entity = world.getEntityById(id: snapshot.id);
          if (entity == null || entity.getFireTicks() <= 0) continue;
          entity.setFireTicks(ticks: 0);
        }
        for (final pos in OpenPipeEffects.positionsIn(area)) {
          final state = OpenPipeEffects.dousedState(this, pos);
          if (state == null) continue;
          final current = stateAt(pos);
          if (current.key == 'minecraft:campfire' ||
              current.key == 'minecraft:soul_campfire') {
            playSound(pos, 'minecraft:entity.generic.extinguish_fire');
          }
          setBlock(pos, state);
        }
      case OpenPipeEffect.lava:
        // `LavaEffectHandler`: everything that is not fire immune burns for 3 s.
        for (final snapshot in _entitiesIn(area)) {
          if (_fireImmune.contains(
            snapshot.entityTypeKey.replaceFirst('minecraft:', '').replaceAll('_', '-'),
          ))
            continue;
          final entity = world.getEntityById(id: snapshot.id);
          if (entity == null) continue;
          entity.setFireTicks(ticks: 300);
        }
      case OpenPipeEffect.milk:
        _forEachPlayerIn(area, (player) => player.clearEffects());
      case OpenPipeEffect.potion:
        final data = PotionFluidData.decode(fluid.data);
        if (data == null) return;
        final effects = PotionEffects.of(data);
        if (effects.isEmpty) return;
        _forEachPlayerIn(area, (player) {
          for (final e in effects) {
            final type = _statusEffectType(e.effect);
            if (type == null) continue;
            unawaited(
              player
                  .addEffect(
                    effect: StatusEffectInstance(
                      effectType: type,
                      duration: e.duration,
                      amplifier: e.amplifier,
                      ambient: e.ambient,
                      showParticles: e.visible,
                      showIcon: true,
                    ),
                  )
                  .catchError((Object _) {}),
            );
          }
        });
      case OpenPipeEffect.tea:
        _forEachPlayerIn(area, (player) {
          unawaited(
            player
                .addEffect(
                  effect: const StatusEffectInstance(
                    effectType: StatusEffectType.haste,
                    duration: 21,
                    amplifier: 0,
                    ambient: false,
                    showParticles: false,
                    showIcon: false,
                  ),
                )
                .catchError((Object _) {}),
          );
        });
    }
  }

  /// The entities whose position is inside [area] (`getEntities(null, area)`).
  List<EntitySnapshot> _entitiesIn(Aabb area) => [
    for (final snapshot in world.getEntitiesInBox(
      min: (area.minX, area.minY, area.minZ),
      max: (area.maxX, area.maxY, area.maxZ),
      filter: const EntityFilterAll(),
    ))
      if (area.contains(snapshot.position)) snapshot,
  ];

  /// Runs [action] for every player in [area].
  void _forEachPlayerIn(Aabb area, void Function(Player player) action) {
    final server = serverProvider?.call();
    if (server == null) return;
    for (final snapshot in world.getEntitiesInBox(
      min: (area.minX, area.minY, area.minZ),
      max: (area.maxX, area.maxY, area.maxZ),
      filter: const EntityFilterPlayers(),
    )) {
      if (!area.contains(snapshot.position)) continue;
      final player = server.getPlayerByUuid(id: snapshot.uuid);
      if (player != null) action(player);
    }
  }

  static StatusEffectType? _statusEffectType(String id) {
    final path = id.contains(':') ? id.substring(id.indexOf(':') + 1) : id;
    return StatusEffectType.fromWireName(path.replaceAll('_', '-'));
  }

  /// The vanilla entities of `Entity.fireImmune()`.
  static const Set<String> _fireImmune = {
    'blaze',
    'magma-cube',
    'ghast',
    'wither',
    'wither-skeleton',
    'zombified-piglin',
    'piglin',
    'piglin-brute',
    'strider',
    'ender-dragon',
  };

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
