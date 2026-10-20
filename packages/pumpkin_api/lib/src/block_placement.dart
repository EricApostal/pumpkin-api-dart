import 'package:wasm_components/wasm_components.dart' show ErrorResult, OkResult;

import 'bindings.g.dart' as generated;
import 'block_placement_core.dart';
import 'plugin_registry_core.dart';

/// The host's block placement rules (`block-placement.wit`): how placing a
/// plugin block chooses `facing`, `orientation`, `waterlogged` and similar
/// properties, like vanilla's `getStateForPlacement`.
///
/// ```dart
/// BlockPlacements.host.setRules('my_plugin:furnace', const [
///   PlacementRule.horizontalFacing('facing', opposite: true),
/// ]);
/// ```
abstract final class BlockPlacements {
  /// The server's placement rules.
  static final BlockPlacementBackend host = const HostBlockPlacement();
}

/// [BlockPlacementBackend] over the generated host bindings.
final class HostBlockPlacement implements BlockPlacementBackend {
  const HostBlockPlacement();

  @override
  void setRules(String blockKey, List<PlacementRule> rules) {
    final result = generated.blockPlacement.setBlockPlacementRules(
      blockKey: blockKey,
      rules: [for (final r in rules) _toWire(r)],
    );
    if (result case ErrorResult(:final value)) {
      throw PluginRegistryException('Setting the placement rules of $blockKey failed: $value');
    }
    if (result is! OkResult) throw StateError('Unexpected result $result');
  }

  static generated.PlacementRule _toWire(PlacementRule rule) => generated.PlacementRule(
    property: rule.property,
    opposite: rule.opposite,
    whenSneaking: rule.whenSneaking,
    source: switch (rule.source) {
      PlacementSourceKind.horizontalFacing => const generated.PlacementSourceHorizontalFacing(),
      PlacementSourceKind.lookingDirection => const generated.PlacementSourceLookingDirection(),
      PlacementSourceKind.clickedFace => const generated.PlacementSourceClickedFace(),
      PlacementSourceKind.clickedFaceDown => const generated.PlacementSourceClickedFaceDown(),
      PlacementSourceKind.clickedAxis => const generated.PlacementSourceClickedAxis(),
      PlacementSourceKind.horizontalAxis => const generated.PlacementSourceHorizontalAxis(),
      PlacementSourceKind.clickedHalf => const generated.PlacementSourceClickedHalf(),
      PlacementSourceKind.verticalLook => generated.PlacementSourceVerticalLook(rule.pitch ?? 90),
      PlacementSourceKind.inWater => const generated.PlacementSourceInWater(),
      PlacementSourceKind.sneaking => const generated.PlacementSourceSneaking(),
      PlacementSourceKind.neighbourShaft => generated.PlacementSourceNeighbourShaft([
        for (final shaft in rule.shafts)
          generated.ShaftNeighbour(
            tag: shaft.tag,
            property: shaft.property,
            kind: switch (shaft.kind) {
              ShaftKind.facing => generated.ShaftKind.facing,
              ShaftKind.axis => generated.ShaftKind.axis,
              ShaftKind.facingOpposite => generated.ShaftKind.facingOpposite,
            },
          ),
      ]),
      PlacementSourceKind.constant => generated.PlacementSourceConstant(rule.constantValue ?? ''),
    },
  );
}
