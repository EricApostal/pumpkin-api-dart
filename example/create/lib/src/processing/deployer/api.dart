/// The public API of the deployer part of the processing module (re-exported by
/// `lib/src/api/processing.dart`).
///
/// * [DeployerBlockEntity]: the fake player, the held item and the overflow.
/// * [DeployerMode], [DeployerState]: the mode and the animation state.
/// * [DeployerItemHandler]: the item handler the deployer exposes to hoppers.
/// * [DeployerMovementBehaviour], [DeployerMovingInteraction]: the contraption actor.
/// * [DeployerHandler]: what the fake player does when it activates.
library;

export 'belt_deployer_callbacks.dart';
export 'deployer_actor_player.dart';
export 'deployer_block.dart' show DeployerKineticDef;
export 'deployer_block_entity.dart' show DeployerBlockEntity;
export 'deployer_filter.dart' show DeployerFilterBehaviour, deployerFilterTest;
export 'deployer_handler.dart' show DeployerHandler;
export 'deployer_item_handler.dart';
export 'deployer_movement_behaviour.dart';
export 'deployer_moving_interaction.dart';
export 'deployer_types.dart';
