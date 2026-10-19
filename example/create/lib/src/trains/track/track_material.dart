// `TrackMaterial` and `TrackType` (pure). A material names a track block; `ANDESITE` is the only
// one Create ships, add-ons build their own with [TrackMaterialFactory] before the registry is
// applied (`TrackMaterial.ALL` is what the track block entity type accepts).
//
// Java -> Dart: `Identifier` -> `create:andesite` text; `NonNullSupplier<..TrackBlock>` -> the key
// of the block (`blockKey`, resolved lazily so add-ons can register the block later); the model
// holders and ingredient fields are client / data generation only and kept as plain data.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'track_block.dart';
import 'track_material_factory.dart';

/// `TrackMaterial.TrackType.TrackBlockFactory`.
typedef TrackBlockFactory = TrackBlock Function(TrackMaterial material);

class TrackMaterial {
  /// `ALL`: every material by id.
  static final Map<String, TrackMaterial> ALL = <String, TrackMaterial>{};

  static final TrackMaterial ANDESITE = TrackMaterialFactory.make('create:andesite')
      .lang('Andesite')
      .block(() => 'create:track')
      .particle('create:block/palettes/stone_types/polished/andesite_cut_polished')
      .defaultModels()
      .build();

  /// `id`.
  final String id;
  final String langName;

  /// The block of the material (`getBlockSupplier().get()` is the key; see [getBlockKey]).
  final String Function() trackBlock;

  /// Item keys / `#tags` of the sleeper and rail ingredients (recipe generation only).
  final List<String>? sleeperIngredient;
  final List<String>? railsIngredient;
  final String particle;
  final TrackType trackType;
  final TrackBlockFactory? _customFactory;

  /// Names of the client models (unused on the server, kept so add-ons can describe them).
  final Object? modelHolder;

  TrackMaterial(
    this.id,
    this.langName,
    this.trackBlock,
    this.particle,
    this.sleeperIngredient,
    this.railsIngredient,
    this.trackType,
    this.modelHolder, [
    TrackBlockFactory? customFactory,
  ]) : _customFactory = customFactory {
    ALL[id] = this;
  }

  /// The key of the track block (`getBlock()`).
  String getBlockKey() => trackBlock();

  /// The key of the track block's item.
  String getItemKey() => trackBlock();

  /// `createBlock(properties)`: the logic object of the block of this material.
  TrackBlock createBlock() => (_customFactory ?? trackType.factory)(this);

  bool isFromMod(String modId) => id.split(':').first == modId;

  static List<TrackMaterial> allFromMod(String modid) => [
    for (final tm in _all().values)
      if (tm.isFromMod(modid)) tm,
  ];

  /// [ALL] with [ANDESITE] guaranteed to be created (static fields initialise lazily).
  static Map<String, TrackMaterial> _all() {
    ANDESITE.id;
    return ALL;
  }

  /// `allBlocksFromMod(modid)`: the block keys.
  static List<String> allBlocksFromMod(String modid) => [for (final m in allFromMod(modid)) m.getBlockKey()];

  /// `allBlocks()`: the block keys of all materials (what the block entity type is valid for).
  static List<String> allBlocks() => [for (final m in _all().values) m.getBlockKey()];

  /// `resourceName()`.
  String resourceName() => id.split(':').last;

  /// `deserialize(serializedName)`: [ANDESITE] for blank or unknown names.
  static TrackMaterial deserialize(String serializedName) {
    if (serializedName.trim().isEmpty) return ANDESITE; // Data migrating from 0.5
    final id = serializedName.contains(':') ? serializedName : 'minecraft:$serializedName';
    final found = _all()[id];
    if (found != null) return found;
    onDeserializeFailure?.call(serializedName);
    return ANDESITE;
  }

  /// Called with the name that `deserialize` could not find (the module logs it).
  static void Function(String serializedName)? onDeserializeFailure;

  /// `fromItem(item)`: the material of a track block item key, [ANDESITE] otherwise.
  static TrackMaterial fromItem(String itemKey) {
    for (final m in _all().values) {
      if (m.getItemKey() == itemKey) return m;
    }
    return ANDESITE;
  }

  @override
  String toString() => 'TrackMaterial($id)';
}

/// `TrackMaterial.TrackType`.
class TrackType {
  static final TrackType STANDARD = TrackType('create:standard', (material) => TrackBlock(material));

  final String id;
  final TrackBlockFactory factory;

  TrackType(this.id, this.factory);
}
