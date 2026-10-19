// State shared by the decoration behaviours (host side): the module context, optional services of
// other modules, the last block click of each player (the placement context of vanilla's
// `BlockPlaceContext`) and small helpers for items and sounds.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/config.dart';
import '../api/sounds.dart';
import '../api/wrenchable.dart';
import '../common/direction.dart' as d;
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/module.dart';

/// The last block click of a player (`playerUseBlock`): what the host's placement does not tell
/// the `placed` callback.
final class ClickContext {
  final Pos clickedPos;
  final d.Direction face;

  /// Hit location inside the clicked block, 0..1.
  final (double, double, double) cursor;
  final bool sneaking;
  final Hand hand;

  /// The server tick of the click.
  final int tick;

  const ClickContext(this.clickedPos, this.face, this.cursor, this.sneaking, this.hand, this.tick);

  /// `BlockPlaceContext.getClickLocation()` (absolute).
  (double, double, double) get location =>
      (clickedPos.$1 + cursor.$1, clickedPos.$2 + cursor.$2, clickedPos.$3 + cursor.$3);

  /// Whether this click placed a block at [pos] (the clicked block's neighbour, or the clicked
  /// block itself when it was replaced).
  bool placedAt(Pos pos) => clickedPos.relative(face) == pos || clickedPos == pos;
}

/// The decoration module's shared runtime. Fields are set in `onLoad`.
final class DecorationRuntime {
  late CreateContext ctx;
  Logger get log => ctx.log;
  BlockEntityStore get store => ctx.blockEntities;

  CreateSounds? sounds;
  WrenchRegistry? wrench;
  CreateConfigs? configs;

  /// The blocks of the module by key (`create:metal_girder`).
  final Map<String, CreateBlock> blocks = {};

  /// Last block click by player uuid string.
  final Map<String, ClickContext> clicks = {};

  /// Counts server ticks (`serverTickStart`), for the age of clicks.
  int serverTick = 0;

  bool get loaded => _loaded;
  bool _loaded = false;

  void init(CreateContext context) {
    ctx = context;
    sounds = context.services.find<CreateSounds>();
    wrench = context.services.find<WrenchRegistry>();
    configs = context.services.find<CreateConfigs>();
    _loaded = true;
  }

  /// The state of event data for [block] at [stateIndex].
  BState stateOf(String blockKey, int stateIndex) => BState(blockKey, blocks[blockKey]!.stateOf(stateIndex));

  /// `AllConfigs.server().equipment.placementAssistRange`, plus 4 with the extendo grip's modifier.
  int placementRange() => configs?.server.equipment.placementAssistRange.value ?? 12;

  /// Whether a player's block placement at [pos] is under way (the `placed` event of the host comes
  /// first, without the player; the `player-placed` event follows with it).
  bool playerPlacementPending(Pos pos) {
    for (final c in clicks.values) {
      if (serverTick - c.tick <= 2 && c.placedAt(pos)) return true;
    }
    return false;
  }

  /// The click context of [playerId] if it placed a block at [pos].
  ClickContext? clickFor(Uuid? playerId, Pos pos) {
    if (playerId == null) return null;
    final c = clicks[playerId.asString];
    if (c == null || !c.placedAt(pos) || serverTick - c.tick > 2) return null;
    // A click belongs to one placement.
    clicks.remove(playerId.asString);
    return c;
  }

  // -- Sounds -----------------------------------------------------------------------------

  /// Plays a sound event at the block centre.
  void playSound(World world, Pos pos, String sound, {double volume = 1, double pitch = 1}) {
    world.playCustomSound(
      soundName: sound,
      category: SoundCategory.blocks,
      pos: (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
      volume: volume,
      pitch: pitch,
    );
  }

  /// `SoundType.getPlaceSound()` of the block [blockKey], approximated from its name.
  String placeSoundOf(String blockKey) => '${blockSoundPrefix(blockKey)}.place';

  /// `SoundType.getHitSound()`.
  String hitSoundOf(String blockKey) => '${blockSoundPrefix(blockKey)}.hit';

  /// Plays a Create sound by name (`confirm`, `deny`, `wrench_rotate`, ...) when the sound service is there.
  void playCreateSound(World world, Pos pos, String name, {double volume = 1, double pitch = 1}) {
    sounds?.playAtBlock(world, pos, name, volume: volume, pitch: pitch);
  }

  // -- Items ------------------------------------------------------------------------------

  /// Removes [n] items from the stack in [hand] of [player] (`ItemStack.shrink`).
  Future<void> shrinkHeld(Player player, Hand hand, [int n = 1]) async {
    final inv = player.getInventory();
    final held = inv.getItemInHand(hand: hand);
    if (held == null) return;
    final count = await held.getCount();
    if (count <= n) {
      await inv.setItemInHand(hand: hand, item: null);
    } else {
      await held.setCount(count: count - n);
      await inv.setItemInHand(hand: hand, item: held);
    }
  }

  /// `Inventory.placeItemBackInInventory`: gives the item to the player, dropping what does not fit.
  Future<void> giveOrDrop(Player player, World world, Pos pos, String itemKey, {int count = 1}) async {
    final left = await player.giveItem(itemKey, count: count);
    if (left > 0) await dropItem(world, pos, itemKey, count: left);
  }

  /// `Block.popResource`: drops [count] items of [itemKey] at the block.
  Future<void> dropItem(World world, Pos pos, String itemKey, {int count = 1}) async {
    if (count <= 0 || itemKey == 'minecraft:air') return;
    final stack = ItemStack.create(registryKey: itemKey, count: count);
    // `Block.popResource` spawns at a random offset inside the block, 0.25 .. 0.75 above the floor.
    await world.dropItem((pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5), stack);
  }

  /// The registry key of the item in [hand] (`minecraft:air` for an empty hand).
  Future<String> heldKey(ItemStack stack) async => stack.getRegistryKey();

  /// A player by uuid from the server, or null.
  Player? playerOf(Server server, Uuid? id) => id == null ? null : server.getPlayerByUuid(id: id);

  /// The horizontal direction a player looks along (`getDirection()`).
  d.Direction horizontalDirection(Player player) => d.Direction.fromYRot(player.getYaw());

  /// `Direction.orderedByNearest(player)`.
  List<d.Direction> nearestLooking(Player player) {
    final look = player.lookDirection;
    return d.Direction.orderedByNearest(look.$1, look.$2, look.$3);
  }

  /// The world's top build height (`getMaxY`), assuming the usual 384 block range.
  int maxY(World world) => world.getMinY() + 384 - 1;
}

/// The sound event prefix for a block, from its name (`block.stone`, `block.wood`, ...).
String blockSoundPrefix(String blockKey) {
  final path = blockKey.substring(blockKey.indexOf(':') + 1);
  bool any(List<String> parts) => parts.any(path.contains);
  if (any(['glass', 'ice'])) return 'minecraft:block.glass';
  if (any(['copper', 'bars'])) return 'minecraft:block.copper';
  if (any(['iron', 'gold', 'metal', 'chain', 'anvil', 'brass', 'andesite_alloy', 'netherite'])) {
    return 'minecraft:block.metal';
  }
  if (any(['planks', 'log', 'wood', 'door', 'bookshelf', 'barrel', 'crafting', 'chest', 'fence', 'stem', 'hyphae', 'cardboard'])) {
    return 'minecraft:block.wood';
  }
  if (any(['grass', 'leaves', 'moss', 'dirt', 'mud', 'vine'])) return 'minecraft:block.grass';
  if (any(['sand', 'concrete_powder'])) return 'minecraft:block.sand';
  if (any(['gravel'])) return 'minecraft:block.gravel';
  if (any(['wool', 'carpet'])) return 'minecraft:block.wool';
  if (any(['deepslate'])) return 'minecraft:block.deepslate';
  return 'minecraft:block.stone';
}

/// The module runtime for code that has no other way to reach it (block entities).
abstract final class DecorationHost {
  static final DecorationRuntime rt = DecorationRuntime();
}
