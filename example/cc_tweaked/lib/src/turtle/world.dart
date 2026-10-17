// What a turtle needs from the world it stands in: a thin adapter interface so
// that the turtle model and its commands stay binding-free and the host glue
// (`plugin/world_turtles.dart`) is the only code that talks to the server.
//
// The interface lists exactly the world capabilities the commands use; what
// the host cannot do is documented where the adapter implements it, and in
// docs/host-requirements.md ("Turtles").
import 'direction.dart';
import 'stack.dart';

/// A block as the commands see it.
final class BlockInfo {
  /// `minecraft:stone`.
  final String name;
  final int stateId;
  final bool isAir;
  final bool isLiquid;
  final bool replaceable;

  /// `-1` for unbreakable blocks.
  final double hardness;

  /// The block state properties (`facing: north`, `waterlogged: false`).
  final Map<String, String> properties;

  /// The item of the block (`Block.asItem`), `null` if it has none.
  final String? itemKey;

  const BlockInfo({
    required this.name,
    required this.stateId,
    required this.isAir,
    required this.isLiquid,
    required this.replaceable,
    required this.hardness,
    this.properties = const {},
    this.itemKey,
  });

  /// `WorldUtil.isEmptyBlock || canBeReplaced`: a place a turtle can enter
  /// (air, water, lava, grass, ...).
  bool get canEnter => isAir || replaceable || isLiquid;
}

/// An inventory in the world (a chest, a furnace, a hopper...) that a turtle
/// can drop into and suck from. Slots hold [TurtleStack]s; changes are written
/// back with [setStack].
///
/// [stackAt] reads a snapshot of the slots taken when the view was made (the
/// host answers asynchronously), [setStack] writes to the host.
abstract interface class ContainerView {
  int get size;

  TurtleStack? stackAt(int slot);

  Future<void> setStack(int slot, TurtleStack? stack);
}

/// The world a turtle acts in. The reads are synchronous, what changes the
/// world is asynchronous (the host applies it later).
abstract interface class TurtleWorld implements ItemInfo {
  /// The block at [pos].
  BlockInfo blockAt(WorldPos pos);

  /// Whether [pos] is inside the world (build height, world border, loaded
  /// chunk). Null means fine, a message explains why a move is refused.
  String? whyCannotEnter(WorldPos pos);

  /// An entity in the way of a block at [pos] (a player, a mob), as a message
  /// for the failed move, or null.
  String? entityObstruction(WorldPos pos);

  /// Moves the turtle block with its block entity to [to] (the old position
  /// becomes air, or water if the turtle was waterlogged) and updates the
  /// turtle's position. Returns false if the move failed.
  Future<bool> moveTurtle(WorldPos to);

  /// Turns the turtle block to face [direction].
  Future<void> setFacing(Dir direction);

  /// Replaces the block at [pos] by air (water for a waterlogged block).
  Future<void> removeBlock(WorldPos pos);

  /// Places the block of the item [itemKey] at [pos], oriented for a player
  /// facing [direction]. Returns false if the item has no block or the host
  /// refuses.
  Future<bool> placeBlock(WorldPos pos, String itemKey, Dir direction);

  /// Replaces the block at [pos] by the block called [blockName] (default
  /// state, with [properties] where the block has them): hoeing, flattening.
  Future<bool> replaceBlock(WorldPos pos, String blockName, {Map<String, String> properties = const {}});

  /// The inventory of the block at [pos], if it is one.
  Future<ContainerView?> containerAt(WorldPos pos);

  /// Damages the first living entity in the block at [pos]. Returns whether
  /// something was hit.
  Future<bool> attack(WorldPos pos, double damage);

  /// Sends the turtle's client data (animation, fuel, upgrades, ...) to the
  /// players that watch it.
  Future<void> syncClient();
}

/// Where the world of a turtle comes from: called for every command.
typedef TurtleWorldProvider = TurtleWorld? Function();
