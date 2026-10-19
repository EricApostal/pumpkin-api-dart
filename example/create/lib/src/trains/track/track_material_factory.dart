// `TrackMaterialFactory` (pure): the builder of [TrackMaterial]s.
import 'track_material.dart';

class TrackMaterialFactory {
  final String id;
  String? _langName;
  String Function()? _trackBlock;

  /// Absent ingredient = `Optional.empty()`. Defaults: rails from iron and zinc nuggets.
  List<String>? _sleeperIngredient;
  List<String>? _railsIngredient = const ['#c:nuggets/iron', '#c:nuggets/zinc'];
  String? _particle;
  TrackType _trackType = TrackType.STANDARD;
  TrackBlockFactory? _customFactory;
  Object? _modelHolder;

  TrackMaterialFactory(this.id);

  /// `make(id)`.
  static TrackMaterialFactory make(String id) => TrackMaterialFactory(id);

  TrackMaterialFactory lang(String langName) {
    _langName = langName;
    return this;
  }

  TrackMaterialFactory block(String Function() trackBlock) {
    _trackBlock = trackBlock;
    return this;
  }

  TrackMaterialFactory defaultModels() {
    _modelHolder = 'default';
    return this;
  }

  /// `sleeper(Ingredient)` / `sleeper(ItemLike...)`: item keys or `#tag`s.
  TrackMaterialFactory sleeper(List<String> items) {
    _sleeperIngredient = items;
    return this;
  }

  /// `rails(Ingredient)` / `rails(ItemLike...)`.
  TrackMaterialFactory rails(List<String> items) {
    _railsIngredient = items;
    return this;
  }

  TrackMaterialFactory noRecipeGen() {
    _railsIngredient = null;
    _sleeperIngredient = null;
    return this;
  }

  TrackMaterialFactory particle(String particle) {
    _particle = particle;
    return this;
  }

  TrackMaterialFactory trackType(TrackType trackType) {
    _trackType = trackType;
    return this;
  }

  /// `standardModels()` (was `defaultModels`): `block/track/<path>/{tie,segment_left,segment_right}`.
  TrackMaterialFactory standardModels() {
    final ns = id.split(':').first;
    final prefix = 'block/track/${id.split(':').last}/';
    _modelHolder = ['$ns:${prefix}tie', '$ns:${prefix}segment_left', '$ns:${prefix}segment_right'];
    return this;
  }

  TrackMaterialFactory customModels(String tie, String leftSegment, String rightSegment) {
    _modelHolder = [tie, leftSegment, rightSegment];
    return this;
  }

  TrackMaterialFactory customBlockFactory(TrackBlockFactory factory) {
    _customFactory = factory;
    return this;
  }

  TrackMaterial build() {
    assert(_trackBlock != null);
    assert(_langName != null);
    assert(_particle != null);
    return TrackMaterial(
      id,
      _langName!,
      _trackBlock!,
      _particle!,
      _sleeperIngredient,
      _railsIngredient,
      _trackType,
      _modelHolder,
      _customFactory,
    );
  }
}
