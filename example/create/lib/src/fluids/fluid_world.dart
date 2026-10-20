// The world as the fluid logic sees it (pure). The host implements it in `host_fluid_world.dart`;
// the tests use an in-memory one. Reads are synchronous, writes are fire and forget (the host
// applies them asynchronously and logs failures), like the block entity ticks that issue them.
import '../api/block_state.dart';
import '../common/bounds.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'pipe_connection.dart' show PipeConnection;

/// `FluidState` of a block: the still fluid, its level (8 for a source) and whether it is a source.
final class FluidInfo {
  /// The still fluid key, empty for none.
  final String fluid;
  final int level;
  final bool isSource;
  final bool isFalling;

  const FluidInfo(this.fluid, this.level, {this.isSource = false, this.isFalling = false});

  static const FluidInfo none = FluidInfo('', 0);

  bool get isEmpty => fluid.isEmpty;
}

/// `FluidManipulationBehaviour.BottomlessFluidMode`.
enum BottomlessFluidMode {
  allowAll,
  denyAll,
  allowByTag,
  denyByTag;

  static BottomlessFluidMode parse(String name) => switch (name) {
    'ALLOW_ALL' => allowAll,
    'DENY_ALL' => denyAll,
    'DENY_BY_TAG' => denyByTag,
    _ => allowByTag,
  };
}

/// `CFluids`: the values of the `fluids` section of the server config.
abstract interface class FluidsConfig {
  /// `fluidTankCapacity`: buckets per tank block.
  int get fluidTankCapacity;
  int get fluidTankMaxHeight;
  int get mechanicalPumpRange;
  int get hosePulleyRange;
  int get hosePulleyBlockThreshold;
  bool get fillInfinite;
  BottomlessFluidMode get bottomlessFluidMode;
  bool get fluidFillPlaceFluidSourceBlocks;
  bool get pipesPlaceFluidSourceBlocks;
}

/// The default values of `CFluids`.
final class DefaultFluidsConfig implements FluidsConfig {
  const DefaultFluidsConfig();

  @override
  int get fluidTankCapacity => 8;
  @override
  int get fluidTankMaxHeight => 32;
  @override
  int get mechanicalPumpRange => 16;
  @override
  int get hosePulleyRange => 128;
  @override
  int get hosePulleyBlockThreshold => 10000;
  @override
  bool get fillInfinite => false;
  @override
  BottomlessFluidMode get bottomlessFluidMode => BottomlessFluidMode.allowByTag;
  @override
  bool get fluidFillPlaceFluidSourceBlocks => true;
  @override
  bool get pipesPlaceFluidSourceBlocks => true;
}

/// A mechanical pump as the pipe logic sees it (`PumpBlockEntity`).
abstract interface class PumpPeer {
  /// `isFront(side)`: [side] is the pump's facing direction.
  bool isFront(Direction side);

  /// `isPullingOnSide(front)`.
  bool isPullingOnSide(bool front);

  /// `updatePipesOnSide(side)`.
  void updatePipesOnSide(Direction side);
}

/// `FluidTransportBehaviour` as the network code sees it.
abstract interface class PipeNodeView {
  /// `getConnection(side)`: the connection data of the face, or `null` if the pipe has none there.
  PipeConnection? getConnection(Direction side);

  /// `getProvidedOutwardFluid(side)`.
  FStack getProvidedOutwardFluid(Direction side);

  /// `canHaveFlowToward(state, direction)`.
  bool canHaveFlowToward(BState state, Direction direction);

  /// `hasAnyPressure()`.
  bool get hasAnyPressure;

  /// `addPressure(side, inbound, pressure)`.
  void addPressure(Direction side, bool inbound, double pressure);

  /// `wipePressure()`.
  void wipePressure();

  /// Whether the owning block entity was removed.
  bool get isRemoved;

  /// `instanceof PumpFluidTransferBehaviour`.
  bool get isPumpNode;
}

/// `FluidPropagator.getPipe` (`BlockEntityBehaviour.get(reader, pos,
/// FluidTransportBehaviour.TYPE)`): the pipe node among the [behaviours] of the block
/// entity at a position, `null` when it has none (or the node was removed). The node of a
/// pipe is its transport behaviour; the block entity that owns it is not a node itself.
PipeNodeView? pipeNodeIn(Iterable<Object?> behaviours) {
  for (final behaviour in behaviours) {
    if (behaviour is! PipeNodeView) continue;
    return behaviour.isRemoved ? null : behaviour;
  }
  return null;
}

/// The world for the fluid logic: the block getter plus fluids, the pipes and the writes the
/// logic issues.
abstract class FluidWorld extends BlockGetter {
  /// `getGameTime()`.
  int get gameTime;

  FluidsConfig get config;

  /// `FluidState` at [p].
  FluidInfo fluidAt(Pos p);

  /// `EnvironmentAttributes.WATER_EVAPORATES` of the dimension (`ultraWarm`).
  bool get waterEvaporates;

  /// The transport behaviour of the block entity at [p] (not a removed one), or `null`.
  PipeNodeView? pipeAt(Pos p);

  /// The pump block entity at [p], or `null`.
  PumpPeer? pumpAt(Pos p);

  /// Whether a block entity exists at [p] (`level.getBlockEntity(pos) != null`).
  bool hasBlockEntity(Pos p);

  /// `Capabilities.Fluid.BLOCK` of the block entity at [p] seen from [side]: a Create block
  /// entity's handler or the host's tank of a plugin block entity. `null` without one.
  FluidStorage? fluidCapability(Pos p, Direction? side);

  /// Whether the block entity at [p] carries a bracket (`BracketedBlockEntityBehaviour.isBracketPresent`).
  bool hasBracket(Pos p);

  /// `getDestroySpeed(...) == -1` (bedrock and the like).
  bool isUnbreakable(Pos p);

  // -- writes ------------------------------------------------------------------------------

  /// `Level.updateNeighbourForOutputSignal(pos, block)`: tells the comparators next to [p] to
  /// read the block again, because its analog output changed.
  void updateComparators(Pos p);

  /// `IRotate.hasShaftTowards(level, neighbourPos, neighbourState, face)`: the neighbour at [p]
  /// has a shaft pointing out of [face].
  bool hasShaftTowards(Pos p, Direction face);

  /// `Level.setBlock(pos, state, UPDATE_ALL)`; with [quiet] the flags are `2 | 16` (clients are
  /// told, the neighbours' shapes are not updated).
  void setBlock(Pos p, BState state, {bool quiet = false});

  /// `Level.updateNeighborsAt(pos, block)`.
  void neighboursChanged(Pos p);

  /// Whether the fluid [fluid] is in the fluid tag [tag] (`Fluid.is(tag)`).
  bool fluidHasTag(String fluid, String tag);

  /// `Block.dropResources(state, level, pos)`.
  void dropResources(Pos p);

  /// `BlockState.canSurvive(level, pos)` for the block at [p].
  bool canSurvive(Pos p);

  /// `Level.scheduleTick(pos, fluid, delay)`.
  void scheduleFluidTick(Pos p, String fluid, int delay);

  /// Places the source block of [fluid] at [p].
  void placeFluidSource(Pos p, String fluid);

  /// Takes the source of the fluid at [p] out of the world (`tryPickupFluid`); empty if none.
  FStack pickupFluidSource(Pos p);

  void playSound(Pos p, String sound, {double volume = 1, double pitch = 1});

  /// `BlockHelper.destroyBlock(level, pos, effectChance)`.
  void destroyBlock(Pos p, double effectChance);

  /// `OpenPipeEffectHandler.apply(level, area, fluid)`.
  void applyOpenPipeEffect(FStack fluid, Aabb area);

  /// `NetworkHelper.sendToClientsAround(FluidSplashPacket)`.
  void splash(Pos p, FStack fluid);

  /// `AdvancementBehaviour.tryAward(level, pos, advancement)`.
  void award(Pos p, String advancement);

  /// `Level.getRandom().nextFloat()`.
  double nextDouble();

  /// `Level.getRandom().nextInt(bound)`.
  int nextInt(int bound);
}
