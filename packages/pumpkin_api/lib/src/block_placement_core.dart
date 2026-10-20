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

  /// The face of the clicked block, but `up` gives `down` (hopper-like
  /// facing properties have no `up`).
  clickedFaceDown,

  /// The axis of the clicked face (`x`, `y`, `z`).
  clickedAxis,

  /// The horizontal axis of the player's look direction (`x` or `z`).
  horizontalAxis,

  /// `bottom` or `top` like stairs and slabs.
  clickedHalf,

  /// `up`, `down`, or `horizontal` from the player's pitch (see [PlacementRule.verticalLook]).
  verticalLook,

  /// `true` when the block replaces a water source (waterlogged).
  inWater,

  /// `true` when the player sneaks.
  sneaking,

  /// The direction of the neighbour whose shaft points into the placed block (see
  /// [ShaftNeighbour]); none when no neighbour has one or two lie on different
  /// axes.
  neighbourShaft,

  /// Always [PlacementRule.constant]'s value.
  constant,
}

/// How a [ShaftNeighbour]'s property says where its shaft points.
enum ShaftKind {
  /// The property lists a direction (`facing`): the shaft points into the placed
  /// block when the value is the direction from the placed block to the
  /// neighbour (`IRotate.hasShaftTowards` of a directional block).
  facing,

  /// The property lists an axis (`axis`): the shaft points into the placed block
  /// when the direction from the neighbour to it runs along that axis.
  axis,

  /// The property lists a direction (`facing`): the shaft points into the placed
  /// block when the value is the opposite of the direction from the placed block
  /// to the neighbour (Create's creative motor, `face == facing`).
  facingOpposite,
}

/// A neighbour that has a shaft pointing into the placed block, like Create's
/// `IRotate.hasShaftTowards`. Only plugin blocks are read, from their
/// registration properties; a vanilla neighbour never has a shaft.
final class ShaftNeighbour {
  /// Blocks that count, by tag (`create:shafts`).
  final String tag;

  /// The property that says where the shaft points (`axis`, `facing`).
  final String property;

  final ShaftKind kind;

  const ShaftNeighbour(this.tag, this.property, this.kind);

  @override
  bool operator ==(Object other) =>
      other is ShaftNeighbour &&
      other.tag == tag &&
      other.property == property &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(tag, property, kind);

  @override
  String toString() => '$tag.$property (${kind.name})';
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

  /// The neighbours that count for a [PlacementSourceKind.neighbourShaft].
  final List<ShaftNeighbour> shafts;

  /// Only apply the rule when the player sneaks (`true`) or does not sneak
  /// (`false`). A rule that does not apply leaves the property to the next rule.
  final bool? whenSneaking;

  const PlacementRule._(
    this.property,
    this.source,
    this.opposite, {
    this.pitch,
    this.constantValue,
    this.shafts = const [],
    this.whenSneaking,
  });

  const PlacementRule.horizontalFacing(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.horizontalFacing,
         opposite,
         whenSneaking: whenSneaking,
       );

  const PlacementRule.lookingDirection(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.lookingDirection,
         opposite,
         whenSneaking: whenSneaking,
       );

  const PlacementRule.clickedFace(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.clickedFace,
         opposite,
         whenSneaking: whenSneaking,
       );

  /// The clicked face, but `up` gives `down`: for hopper-like facing properties.
  const PlacementRule.clickedFaceDown(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.clickedFaceDown,
         opposite,
         whenSneaking: whenSneaking,
       );

  const PlacementRule.clickedAxis(String property, {bool? whenSneaking})
    : this._(
        property,
        PlacementSourceKind.clickedAxis,
        false,
        whenSneaking: whenSneaking,
      );

  /// The horizontal axis of the player's look direction: `x` or `z`.
  const PlacementRule.horizontalAxis(String property, {bool? whenSneaking})
    : this._(
        property,
        PlacementSourceKind.horizontalAxis,
        false,
        whenSneaking: whenSneaking,
      );

  const PlacementRule.clickedHalf(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.clickedHalf,
         opposite,
         whenSneaking: whenSneaking,
       );

  /// `up`/`down` from a pitch of [pitch] degrees or more (above 0, at most
  /// 90), `horizontal` in between.
  const PlacementRule.verticalLook(
    String property,
    double pitch, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.verticalLook,
         opposite,
         pitch: pitch,
         whenSneaking: whenSneaking,
       );

  const PlacementRule.inWater(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.inWater,
         opposite,
         whenSneaking: whenSneaking,
       );

  const PlacementRule.sneaking(
    String property, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.sneaking,
         opposite,
         whenSneaking: whenSneaking,
       );

  /// The direction of the neighbour whose shaft points into the placed block,
  /// read from [shafts] (like Create's `IRotate.hasShaftTowards`). Gives no
  /// value when no neighbour has one, or when two lie on different axes.
  const PlacementRule.neighbourShaft(
    String property,
    List<ShaftNeighbour> shafts, {
    bool opposite = false,
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.neighbourShaft,
         opposite,
         shafts: shafts,
         whenSneaking: whenSneaking,
       );

  const PlacementRule.constant(
    String property,
    String value, {
    bool? whenSneaking,
  }) : this._(
         property,
         PlacementSourceKind.constant,
         false,
         constantValue: value,
         whenSneaking: whenSneaking,
       );

  @override
  String toString() {
    final sneaking = switch (whenSneaking) {
      null => '',
      true => ' (sneaking)',
      false => ' (not sneaking)',
    };
    final neighbours = source == PlacementSourceKind.neighbourShaft
        ? ' [${shafts.join(', ')}]'
        : '';
    return '$property <- ${source.name}${opposite ? ' (opposite)' : ''}$sneaking$neighbours';
  }
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
