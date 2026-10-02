
import 'bindings.g.dart';

/// Turns [key] into a namespaced registry key. A key without a namespace
/// (`stone`) gets the `minecraft:` namespace (`minecraft:stone`); one that
/// already has a namespace (`custom:ruby_block`) is returned unchanged.
String normalizeRegistryKey(String key) =>
    key.contains(':') ? key : 'minecraft:$key';

/// Whether two registry keys name the same entry, ignoring a leading
/// `minecraft:` namespace on either side (`stone` matches `minecraft:stone`).
bool registryKeysMatch(String a, String b) =>
    normalizeRegistryKey(a) == normalizeRegistryKey(b);


/// Lookups in the server's block registry.
///
/// Keys may be written with or without the `minecraft:` namespace.
///
/// ```dart
/// final stone = BlockRegistry.of('stone');
/// final state = BlockRegistry.stateFromId(1);
/// ```
abstract final class BlockRegistry {
  /// The block registered under [key] (`stone` or `minecraft:stone`), or
  /// `null` if there is none.
  static Block? of(String key) =>
      world.getBlockByName(name: normalizeRegistryKey(key));

  /// Like [of], but throws an [ArgumentError] for unknown keys.
  static Block require(String key) =>
      of(key) ?? (throw ArgumentError.value(key, 'key', 'Unknown block'));

  /// The block with the numeric [id], or `null`.
  static Block? fromId(int id) => world.getBlockById(id: id);

  /// The block that owns the block state [stateId], or `null`.
  static Block? fromStateId(int stateId) =>
      world.getBlockFromStateId(stateId: stateId);

  /// The block state with the numeric [stateId], or `null`.
  static BlockState? stateFromId(int stateId) =>
      world.getBlockStateById(stateId: stateId);

  /// The default state of the block with the numeric [blockId], or `null`.
  static BlockState? defaultStateOfId(int blockId) =>
      world.getDefaultStateFromBlockId(blockId: blockId);

  /// Every state of the block with the numeric [blockId].
  static List<BlockState> statesOfId(int blockId) =>
      world.getStatesForBlockId(blockId: blockId);

  /// All registered blocks.
  static List<Block> get all => world.getAllBlocks();

  /// The names of all registered blocks, as the host reports them.
  static List<String> get names => world.getAllBlockNames();

  /// The number of registered blocks.
  static int get count => world.getBlockCount();

  /// The number of registered block states.
  static int get stateCount => world.getBlockStateCount();

  /// The state id of the block called [key] with the given [properties]
  /// (`{'facing': 'north'}`), or `null` if the block or a property is
  /// unknown. Properties that are left out take their default value.
  static int? resolveState(
    String key, [
    Map<String, String> properties = const {},
  ]) {
    return world.resolveBlockState(
      name: normalizeRegistryKey(key),
      properties: [for (final e in properties.entries) (e.key, e.value)],
    );
  }

  /// The block name and properties of the state [stateId], or `null`.
  static BlockStateInfo? stateInfo(int stateId) =>
      world.blockStateToInfo(stateId: stateId);
}

/// Conveniences for [Block].
extension BlockHelpers on Block {
  /// The namespace of [name], for example `minecraft`.
  String get namespace {
    final i = name.indexOf(':');
    return i < 0 ? 'minecraft' : name.substring(0, i);
  }

  /// [name] without its namespace, for example `stone`.
  String get path => name.substring(name.indexOf(':') + 1);

  /// Whether this block is the one called [key] (`stone` or `minecraft:stone`).
  bool matches(String key) => registryKeysMatch(name, key);

  /// All the states this block can be in.
  List<BlockState> get states => world.getStatesForBlock(block: this);

  /// The state this block has when placed without extra properties.
  BlockState get defaultState => world.getDefaultStateFromBlock(block: this);
}

/// Conveniences for [BlockState].
extension BlockStateHelpers on BlockState {
  /// The block this state belongs to.
  Block get block => world.getBlockFromState(state: this);

  /// [properties] as a map, for example `{'facing': 'north'}`.
  Map<String, String> get propertyMap => {
    for (final (key, value) in properties) key: value,
  };

  /// The value of the property called [name], or `null` if this state doesn't
  /// have it.
  String? property(String name) {
    for (final (key, value) in properties) {
      if (key == name) return value;
    }
    return null;
  }

  /// Whether this state belongs to the block called [key] (`stone` or
  /// `minecraft:stone`).
  bool matches(String key) => registryKeysMatch(blockName, key);
}
