/// Block helpers for all modules (published by the `decoration` module): the host implementation of
/// [BlockGetter], state writes, waterlogging (`ProperWaterloggedBlock`) and the conversion of a
/// manifest block into a [CreateBlock].
///
/// ```dart
/// final level = HostBlockGetter(world);                 // read neighbours through BState
/// final s = level.stateAt((x, y, z));                   // BState('create:shaft', {'axis': 'x'})
/// await setBlockState(world, (x, y, z), s.setValue('axis', 'y'));
///
/// registry.block(manifestBlock('metal_girder', behavior: ..., shapeRules: ...));
/// ```
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/direction.dart' as dir;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/blocks.dart';
import '../manifest/manifest.dart';
import 'block_state.dart';

export 'block_state.dart';

// -- Reading ---------------------------------------------------------------------------------

/// What the host tells about a block state that the neighbour logic needs.
final class _StateShapeInfo {
  final bool isAir;
  final bool replaceable;
  final bool isFullCube;
  final List<bool> sideSolid; // by Direction ordinal
  final List<BlockBox> collision;

  _StateShapeInfo(this.isAir, this.replaceable, this.isFullCube, this.sideSolid, this.collision);
}

/// The [BlockGetter] over a host [World]. States are decoded once per state id and cached for the
/// life of the plugin (state ids never change while the server runs).
final class HostBlockGetter extends BlockGetter {
  final World world;

  HostBlockGetter(this.world);

  static final Map<int, BState> _states = {};
  static final Map<int, _StateShapeInfo> _shapes = {};
  static final Map<(int, String), bool> _tags = {};

  /// The state with global id [id].
  static BState stateOfId(int id) {
    final cached = _states[id];
    if (cached != null) return cached;
    final info = BlockStates.info(id);
    final s = info == null ? BState.air : BState(info.key, info.properties);
    _states[id] = s;
    return s;
  }

  static _StateShapeInfo _shapeOf(int id) {
    final cached = _shapes[id];
    if (cached != null) return cached;
    final st = BlockRegistry.stateFromId(id);
    final _StateShapeInfo info;
    if (st == null) {
      info = _StateShapeInfo(true, true, false, List.filled(6, false), const []);
    } else {
      info = _StateShapeInfo(
        st.isAir,
        st.replaceable,
        st.isFullCube,
        [
          st.downSideSolid,
          st.upSideSolid,
          st.northSideSolid,
          st.southSideSolid,
          st.westSideSolid,
          st.eastSideSolid,
        ],
        [
          for (final b in st.collisionShapes)
            BlockBox(b.min.$1, b.min.$2, b.min.$3, b.max.$1, b.max.$2, b.max.$3),
        ],
      );
    }
    _shapes[id] = info;
    return info;
  }

  /// The state id at [p].
  int idAt(Pos p) => world.getBlockStateId(pos: p.toBlockPos());

  @override
  BState stateAt(Pos p) => stateOfId(idAt(p));

  @override
  bool isLoaded(Pos p) => world.isLoaded(pos: p.toBlockPos());

  @override
  bool isFaceSturdy(Pos p, dir.Direction face) => _shapeOf(idAt(p)).sideSolid[face.index];

  @override
  List<BlockBox> collisionBoxes(Pos p) => _shapeOf(idAt(p)).collision;

  @override
  bool supportShapeEmpty(Pos p) => _shapeOf(idAt(p)).collision.isEmpty;

  @override
  bool canBeReplaced(Pos p) {
    final i = _shapeOf(idAt(p));
    return i.replaceable || i.isAir;
  }

  @override
  bool hasTag(Pos p, String tag) {
    final id = idAt(p);
    return _tags.putIfAbsent((id, tag), () => BlockStates.isTag(id, tag));
  }

  @override
  bool isWater(Pos p) {
    final f = world.getFluidState(pos: p.toBlockPos());
    return f != null && f.fluid == 'minecraft:water' && f.isSource;
  }
}

// -- Writing ---------------------------------------------------------------------------------

final Map<String, int?> _resolved = {};

/// The global state id of [s], or `null` if the block or a value is unknown.
int? stateIdOf(BState s) {
  final k = s.toString();
  if (_resolved.containsKey(k)) return _resolved[k];
  final id = BlockRegistry.resolveState(s.key, s.props);
  _resolved[k] = id;
  return id;
}

/// Whether the block [s.key] has a state with exactly these property values (a value outside a
/// property's domain makes the lookup fail).
bool stateExists(BState s) => stateIdOf(s) != null;

/// `Level.setBlock(pos, state, flags)`; does nothing for an unknown state.
Future<void> setBlockState(
  World world,
  Pos pos,
  BState state, {
  Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
}) async {
  final id = stateIdOf(state);
  if (id == null) return;
  await world.setBlockState(pos: pos.toBlockPos(), state: id, updateFlags: flags);
}

/// `Level.removeBlock` / `setBlock(AIR)`.
Future<void> removeBlock(World world, Pos pos, {Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal}) =>
    setBlockState(world, pos, BState.air, flags: flags);

// -- Waterlogging (ProperWaterloggedBlock) -----------------------------------------------------

/// `ProperWaterloggedBlock.updateWater`: waterlogged blocks keep their fluid ticking.
void updateWater(World world, Pos pos, BState state) {
  if (state.flag('waterlogged')) world.scheduleFluidFlow(pos.toBlockPos(), delayTicks: 5);
}

/// `ProperWaterloggedBlock.withWater`: whether [pos] holds a water source, which a block placed
/// there takes along.
bool replacesWater(World world, Pos pos) => HostBlockGetter(world).isWater(pos);

// -- Manifest blocks ---------------------------------------------------------------------------

/// The manifest entry of a block by its key (without the `create:` namespace).
final Map<String, ManifestBlock> manifestBlocksByKey = {for (final b in kBlocks) b.key: b};

/// The vanilla `MapColor` ids by constant name.
const Map<String, int> mapColorIds = {
  'NONE': 0, 'GRASS': 1, 'SAND': 2, 'WOOL': 3, 'FIRE': 4, 'ICE': 5, 'METAL': 6, 'PLANT': 7, 'SNOW': 8,
  'CLAY': 9, 'DIRT': 10, 'STONE': 11, 'WATER': 12, 'WOOD': 13, 'QUARTZ': 14, 'COLOR_ORANGE': 15,
  'COLOR_MAGENTA': 16, 'COLOR_LIGHT_BLUE': 17, 'COLOR_YELLOW': 18, 'COLOR_LIGHT_GREEN': 19,
  'COLOR_PINK': 20, 'COLOR_GRAY': 21, 'COLOR_LIGHT_GRAY': 22, 'COLOR_CYAN': 23, 'COLOR_PURPLE': 24,
  'COLOR_BLUE': 25, 'COLOR_BROWN': 26, 'COLOR_GREEN': 27, 'COLOR_RED': 28, 'COLOR_BLACK': 29,
  'GOLD': 30, 'DIAMOND': 31, 'LAPIS': 32, 'EMERALD': 33, 'PODZOL': 34, 'NETHERRACK': 35,
  'TERRACOTTA_WHITE': 36, 'TERRACOTTA_ORANGE': 37, 'TERRACOTTA_MAGENTA': 38,
  'TERRACOTTA_LIGHT_BLUE': 39, 'TERRACOTTA_YELLOW': 40, 'TERRACOTTA_LIGHT_GREEN': 41,
  'TERRACOTTA_PINK': 42, 'TERRACOTTA_GRAY': 43, 'TERRACOTTA_LIGHT_GRAY': 44, 'TERRACOTTA_CYAN': 45,
  'TERRACOTTA_PURPLE': 46, 'TERRACOTTA_BLUE': 47, 'TERRACOTTA_BROWN': 48, 'TERRACOTTA_GREEN': 49,
  'TERRACOTTA_RED': 50, 'TERRACOTTA_BLACK': 51, 'CRIMSON_NYLIUM': 52, 'CRIMSON_STEM': 53,
  'CRIMSON_HYPHAE': 54, 'WARPED_NYLIUM': 55, 'WARPED_STEM': 56, 'WARPED_HYPHAE': 57,
  'WARPED_WART_BLOCK': 58, 'DEEPSLATE': 59, 'RAW_IRON': 60, 'GLOW_LICHEN': 61,
};

/// The host block property of a manifest property.
BlockProperty hostProperty(ManifestProperty p) => switch (p.type) {
  'bool' => BlockProperty.boolean(p.name),
  'int' => BlockProperty.intRange(p.name, int.parse(p.values.first), int.parse(p.values.last)),
  _ => BlockProperty.enumeration(p.name, p.values),
};

PistonBehavior _piston(String reaction) => switch (reaction) {
  'DESTROY' || 'POPPED' => PistonBehavior.destroy,
  'BLOCK' => PistonBehavior.block,
  'IGNORE' => PistonBehavior.ignore,
  'PUSH_ONLY' => PistonBehavior.pushOnly,
  _ => PistonBehavior.normal,
};

/// A [CreateBlock] for the manifest block [key] (`metal_girder`): properties, default state,
/// stats, item and sound come from the manifest; the caller adds behaviour, shapes, placement and
/// the drops that differ from "the block item".
CreateBlock manifestBlock(
  String key, {
  BlockBehavior? behavior,
  List<PlacementRule> placement = const [],
  BlockShape? collisionShape,
  BlockShape? selectionShape,
  List<ShapeRule> shapeRules = const [],
  BlockDrops? drops,
  String? blockEntityType,
  List<String> tags = const [],
}) {
  final m = manifestBlocksByKey[key] ?? (throw ArgumentError.value(key, 'key', 'not in the block manifest'));
  return CreateBlock(
    key: 'create:${m.key}',
    properties: [for (final p in m.properties) hostProperty(p)],
    defaultState: m.defaultState,
    hardness: m.hardness,
    blastResistance: m.blastResistance,
    requiresCorrectTool: m.requiresCorrectTool,
    soundType: m.soundType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_'),
    luminance: m.lightLevel,
    canOcclude: !m.noOcclusion,
    replaceable: m.replaceable,
    mapColor: mapColorIds[m.mapColor] ?? 0,
    collisionShape: collisionShape ?? (m.noCollision ? BlockShape.empty : BlockShape.fullCube),
    selectionShape: selectionShape ?? BlockShape.fullCube,
    shapeRules: shapeRules,
    drops: drops ?? BlockDrops.selfItem,
    tags: tags,
    pistonBehavior: _piston(m.pushReaction),
    placement: placement,
    hasItem: m.blockItem != null,
    blockEntityType: blockEntityType,
    behavior: behavior,
  );
}

/// The `create:blocks/<key>` loot table of a block (the data pack's drops for slabs, doors, glass).
BlockDrops lootTableOf(String key) => BlockDrops.lootTable('create:blocks/$key');

/// The directions of the host's `BlockDirection` as [dir.Direction]s.
dir.Direction toDirection(BlockDirection d) => dir.Direction.values[d.index];
