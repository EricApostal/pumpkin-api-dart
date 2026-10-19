/// The public API of the arm part of the processing module (re-exported by
/// `lib/src/api/processing.dart`).
///
/// * [ArmBlockEntity]: the interaction points, the held item and the selection state.
/// * [ArmInteractionPoint], [ArmInteractionPointType]: a point and its kind.
/// * [armInteractionPointTypes], [primaryArmPointType]: the built-in point types, in registry
///   order.
/// * [ArmPointMode], [ArmPhase], [ArmSelectionMode]: the pure model.
library;

export 'arm_block.dart' show ArmKineticDef;
export 'arm_block_entity.dart' show ArmBlockEntity;
export 'arm_interaction_point.dart';
export 'arm_model.dart';
export 'arm_point_types.dart';
