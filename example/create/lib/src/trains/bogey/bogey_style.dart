// ignore_for_file: constant_identifier_names, non_constant_identifier_names
//
// `BogeyStyle` and `AllBogeyStyles` (pure): the style registry, the cycle groups and the sizes of
// a style with their blocks. The rendering parts of Java (`SizeRenderer`, `BogeyVisual`...) are
// client only and not ported; the block of every size is kept as a block key and resolved through
// [AbstractBogeyBlock.byKey].
import '../../redstone/support/text.dart' show Txt;
import '../util/ctag.dart';
import 'abstract_bogey_block.dart';
import 'bogey_sizes.dart';

/// `BogeyStyle`.
class BogeyStyle {
  /// The resource location (`create:standard`).
  final String id;

  /// `cycleGroup`: the styles of one group cycle into each other with the wrench.
  final String cycleGroup;

  /// `displayName`.
  final Txt displayName;

  /// The sound event id (`AllSoundEvents.TRAIN2::getMainEvent`).
  final String soundEvent;

  /// The particle type ids (`ParticleTypes.CRIT` / `POOF`).
  final String contactParticle;
  final String smokeParticle;

  /// `defaultData`.
  final CTag defaultData;

  final Map<BogeySize, String> _sizes;

  BogeyStyle(
    this.id,
    this.cycleGroup,
    this.displayName,
    this.soundEvent,
    this.contactParticle,
    this.smokeParticle,
    this.defaultData,
    Map<BogeySize, String> sizes,
  ) : _sizes = sizes;

  /// `getCycleGroup()`: the styles of the group by id.
  Map<String, BogeyStyle> getCycleGroup() => AllBogeyStyles.getCycleGroup(cycleGroup);

  /// `validSizes()`.
  Set<BogeySize> validSizes() => _sizes.keys.toSet();

  /// `getBlockForSize(size)`: the bogey block of this style for [size]. Throws when there is none.
  AbstractBogeyBlock getBlockForSize(BogeySize size) {
    final key = _sizes[size];
    if (key == null) throw StateError('Bogey style $id has no block for size ${size.id}');
    return AbstractBogeyBlock.byKey(key)!;
  }

  /// `getNextBlock(currentSize)`: the block of the next larger size this style has, wrapping around
  /// (the same block when it only has one size).
  AbstractBogeyBlock getNextBlock(BogeySize currentSize) {
    var size = currentSize.nextBySize();
    // Stream.iterate(...).filter(sizes::containsKey).findFirst(): the sizes cycle, so after one full
    // round the current size itself is found (or nothing when the style has no sizes at all).
    for (var i = 0; i < BogeySizes.allSortedIncreasing().length; i++) {
      if (_sizes.containsKey(size)) return getBlockForSize(size);
      size = size.nextBySize();
    }
    return getBlockForSize(currentSize);
  }

  @override
  String toString() => 'BogeyStyle($id)';
}

/// `BogeyStyle.Builder`.
class BogeyStyleBuilder {
  final String id;
  final String cycleGroup;
  final Map<BogeySize, String> sizes = {};

  Txt displayName = Txt.translate('create.bogey.style.invalid');
  String soundEvent = 'create:train2';
  String contactParticle = 'minecraft:crit';
  String smokeParticle = 'minecraft:poof';
  CTag defaultData = CTag();

  BogeyStyleBuilder(this.id, this.cycleGroup);

  BogeyStyleBuilder setDisplayName(Txt value) {
    displayName = value;
    return this;
  }

  BogeyStyleBuilder setSoundEvent(String value) {
    soundEvent = value;
    return this;
  }

  BogeyStyleBuilder setContactParticle(String value) {
    contactParticle = value;
    return this;
  }

  BogeyStyleBuilder setSmokeParticle(String value) {
    smokeParticle = value;
    return this;
  }

  BogeyStyleBuilder setDefaultData(CTag value) {
    defaultData = value;
    return this;
  }

  /// `size(size, block, renderer)` without the renderer: [blockKey] is the bogey block of that size.
  BogeyStyleBuilder size(BogeySize size, String blockKey) {
    sizes[size] = blockKey;
    return this;
  }

  /// `build()`: registers the style in [AllBogeyStyles].
  BogeyStyle build() {
    final entry = BogeyStyle(id, cycleGroup, displayName, soundEvent, contactParticle, smokeParticle, defaultData, sizes);
    AllBogeyStyles.BOGEY_STYLES[id] = entry;
    AllBogeyStyles.CYCLE_GROUPS.putIfAbsent(cycleGroup, () => {})[id] = entry;
    return entry;
  }
}

/// `AllBogeyStyles`.
abstract final class AllBogeyStyles {
  /// `BOGEY_STYLES`.
  static final Map<String, BogeyStyle> BOGEY_STYLES = {};

  /// `CYCLE_GROUPS`.
  static final Map<String, Map<String, BogeyStyle>> CYCLE_GROUPS = {};

  /// `STANDARD_CYCLE_GROUP`.
  static const String STANDARD_CYCLE_GROUP = 'create:standard';

  /// `STANDARD`.
  static final BogeyStyle STANDARD = _buildStandard();

  /// [STANDARD] (lower camel case alias).
  static BogeyStyle get standard => STANDARD;

  static BogeyStyle _buildStandard() {
    final existing = BOGEY_STYLES['create:standard'];
    if (existing != null) return existing;
    return builder('standard', STANDARD_CYCLE_GROUP)
        .setDisplayName(Txt.translate('create.bogey.style.standard'))
        .size(BogeySizes.SMALL, 'create:small_bogey')
        .size(BogeySizes.LARGE, 'create:large_bogey')
        .build();
  }

  /// `getCycleGroup(cycleGroup)`.
  static Map<String, BogeyStyle> getCycleGroup(String cycleGroup) {
    STANDARD;
    return CYCLE_GROUPS[cycleGroup] ?? const {};
  }

  /// `builder(name, cycleGroup)`: a builder for `create:<name>`.
  static BogeyStyleBuilder builder(String name, String cycleGroup) => BogeyStyleBuilder('create:$name', cycleGroup);

  /// The style with [id] (`BOGEY_STYLES.get(id)`).
  static BogeyStyle? get(String id) {
    STANDARD;
    return BOGEY_STYLES[id];
  }

  /// The number of registered styles (`BOGEY_STYLES.size()`).
  static int get count {
    STANDARD;
    return BOGEY_STYLES.length;
  }

  /// `init()`.
  static void init() {
    STANDARD;
  }
}
