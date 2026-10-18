import 'bindings.g.dart';
import 'host_result.dart';

/// Ready-made [BlockFlagsFlag] sets for the bulk block functions
/// ([WorldBulkBlocks]) and structure placement.
abstract final class BlockUpdateFlags {
  /// Notify neighbours and clients: what a normal block change does.
  static const Set<BlockFlagsFlag> normal = {
    BlockFlagsFlag.notifyNeighbors,
    BlockFlagsFlag.notifyListeners,
  };

  /// Like [normal], and also update the neighbours of the neighbours (strong
  /// redstone power needs it).
  static const Set<BlockFlagsFlag> withIndirect = {
    BlockFlagsFlag.notifyNeighbors,
    BlockFlagsFlag.notifyListeners,
    BlockFlagsFlag.updateIndirectNeighbours,
  };

  /// Only resend the block to clients: no neighbour or shape updates.
  static const Set<BlockFlagsFlag> clientsOnly = {BlockFlagsFlag.notifyListeners};

  /// A contraption disassembling: blocks are moved, not broken, so nothing
  /// drops, shapes are not updated and block entities are not spilled.
  static const Set<BlockFlagsFlag> moved = {
    BlockFlagsFlag.notifyNeighbors,
    BlockFlagsFlag.notifyListeners,
    BlockFlagsFlag.moved,
    BlockFlagsFlag.skipDrops,
    BlockFlagsFlag.skipShapeUpdate,
  };
}

/// One block of [WorldBulkBlocks.placeBlocks].
final class BlockPlacementChange {
  final BlockPos pos;

  /// The block state id to write.
  final int state;

  /// Vanilla block entity data as binary NBT with an `id` (the position comes
  /// from [pos]).
  final List<int>? blockEntityNbt;

  /// A plugin block entity to create at [pos]: the registered type key, the
  /// compound saved with the chunk and the one sent to watching players.
  final String? pluginBlockEntityType;
  final NbtTree? pluginBlockEntitySave;
  final NbtTree? pluginBlockEntityClient;

  const BlockPlacementChange(
    this.pos,
    this.state, {
    this.blockEntityNbt,
    this.pluginBlockEntityType,
    this.pluginBlockEntitySave,
    this.pluginBlockEntityClient,
  }) : assert(
         (pluginBlockEntityType == null) == (pluginBlockEntitySave == null),
         'A plugin block entity needs its type and save data',
       );

  BlockChange toWire() => BlockChange(
    pos: pos,
    state: state,
    blockEntityNbt: blockEntityNbt,
    pluginBlockEntity: pluginBlockEntityType == null
        ? null
        : PluginBlockEntityChange(
            typeKey: pluginBlockEntityType!,
            saveData: pluginBlockEntitySave!,
            clientData: pluginBlockEntityClient,
          ),
  );
}

/// Bulk block changes and block events of a [World] (`world.wit`), for
/// contraptions, schematics and area tools.
extension WorldBulkBlocks on World {
  /// Writes many blocks in one call. All blocks are written first, then the
  /// neighbour, shape and light updates run once for the batch, so a block does
  /// not see half placed neighbours. Positions outside the build height or in
  /// unloaded chunks are skipped. Returns the number of blocks that changed;
  /// throws a [HostException] when a block entity could not be created (after
  /// everything else was placed).
  Future<int> placeBlocks(
    List<BlockPlacementChange> changes, {
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
  }) => unwrapHostAsync(
    setBlocks(changes: [for (final c in changes) c.toWire()], updateFlags: flags),
    'Placing ${changes.length} blocks',
  );

  /// Replaces many positions with air (water for waterlogged blocks) in one
  /// call. Returns the number of blocks that changed.
  Future<int> clearBlocks(
    List<BlockPos> positions, {
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
  }) => removeBlocks(positions: positions, updateFlags: flags);

  /// Breaks the block at [pos] like a player does: break events, [drop]ped loot
  /// (decided by the tool of [breaker] when it is a player), the break
  /// particles and sound, and neighbour updates. Returns whether a block was
  /// broken (false for air or a cancelled event).
  Future<bool> breakBlock(
    BlockPos pos, {
    bool drop = true,
    Entity? breaker,
    bool particles = true,
  }) => destroyBlock(pos: pos, drop: drop, player: breaker, withParticles: particles);

  /// Sends the shape updates to the six neighbours of [pos], as if the block
  /// there changed.
  Future<void> updateNeighborShapes(BlockPos pos) => updateShapeAround(pos: pos);

  /// Tells clients and neighbours that the state at [pos] went from [oldState]
  /// to [newState] without writing anything.
  Future<void> notifyBlockChange(
    BlockPos pos, {
    required int oldState,
    required int newState,
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
  }) => markAndNotify(pos: pos, oldState: oldState, newState: newState, updateFlags: flags);

  /// Creates an entity from its saved binary NBT (an `id` and the rest, like a
  /// structure entity or `Entity.writeNbt`) and spawns it at [pos] with a new
  /// uuid. `null` for an unknown entity type or a cancelled spawn.
  Future<Entity?> spawnFromNbt(List<int> nbt, (double, double, double) pos) =>
      spawnEntityFromNbt(nbt: nbt, pos: pos);
}
