// How placing a custom block chooses its property values (`block-placement.wit`),
// without host imports: the rule values and the backend interface.
// `block_placement.dart` connects them to the generated bindings.
import 'plugin_registry_core.dart';

/// Where a [PlacementRule] takes the value of its property from.
enum PlacementSourceKind {
  /// The horizontal direction the player looks at (`north`, `south`, `east`, `west`).
  horizontalFacing,

  /// The dominant of all six directions the player looks at.
  lookingDirection,

  /// The face of the clicked block (`up` when its top was clicked).
  clickedFace,

  /// The axis of the clicked face (`x`, `y`, `z`).
  clickedAxis,

  /// `bottom` or `top` like stairs and slabs.
  clickedHalf,

  /// `up`, `down`, or `horizontal` from the player's pitch (see [PlacementRule.verticalLook]).
  verticalLook,

  /// `true` when the block replaces a water source (waterlogged).
  inWater,

  /// `true` when the player sneaks.
  sneaking,

  /// Always [PlacementRule.constant]'s value.
  constant,
}

/// Sets one property of a block when a player places it. Rules are tried in
/// order; for each property the first one that gives a value wins; a
/// property without a value keeps the default state's.
final class PlacementRule {
  final String property;
  final PlacementSourceKind source;

  /// Use the opposite of the source's value (`north` for `south`, `up` for
  /// `down`, `false` for `true`).
  final bool opposite;

  /// The pitch in degrees from which a [PlacementSourceKind.verticalLook]
  /// counts as vertical.
  final double? pitch;

  /// The value of a [PlacementSourceKind.constant].
  final String? constantValue;

  const PlacementRule._(this.property, this.source, this.opposite, {this.pitch, this.constantValue});

  const PlacementRule.horizontalFacing(String property, {bool opposite = false})
    : this._(property, PlacementSourceKind.horizontalFacing, opposite);

  const PlacementRule.lookingDirection(String property, {bool opposite = false})
    : this._(property, PlacementSourceKind.lookingDirection, opposite);

  const PlacementRule.clickedFace(String property, {bool opposite = false})
    : this._(property, PlacementSourceKind.clickedFace, opposite);

  const PlacementRule.clickedAxis(String property) : this._(property, PlacementSourceKind.clickedAxis, false);

  const PlacementRule.clickedHalf(String property, {bool opposite = false})
    : this._(property, PlacementSourceKind.clickedHalf, opposite);

  /// `up`/`down` from a pitch of [pitch] degrees or more (above 0, at most
  /// 90), `horizontal` in between.
  const PlacementRule.verticalLook(String property, double pitch, {bool opposite = false})
    : this._(property, PlacementSourceKind.verticalLook, opposite, pitch: pitch);

  const PlacementRule.inWater(String property, {bool opposite = false})
    : this._(property, PlacementSourceKind.inWater, opposite);

  const PlacementRule.sneaking(String property, {bool opposite = false})
    : this._(property, PlacementSourceKind.sneaking, opposite);

  const PlacementRule.constant(String property, String value)
    : this._(property, PlacementSourceKind.constant, false, constantValue: value);

  @override
  String toString() => '$property <- ${source.name}${opposite ? ' (opposite)' : ''}';
}

/// The host's block placement rules (`block-placement.wit`), permission
/// `registry.blocks`.
abstract interface class BlockPlacementBackend {
  /// Sets the rules of the registered block [blockKey]. Throws a
  /// [PluginRegistryException] for an unknown block or property, a property
  /// that lacks a value its source can give, other rules than the ones set
  /// before, or when registration is closed.
  void setRules(String blockKey, List<PlacementRule> rules);
}
