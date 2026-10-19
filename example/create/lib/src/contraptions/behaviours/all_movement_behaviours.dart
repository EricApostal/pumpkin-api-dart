// `AllMovementBehaviours` and `AllInteractionBehaviours`: the vanilla blocks that get an actor or a
// moving interaction. Create's own blocks are registered by their actor files
// (`actors_registration.dart`).
import '../core/movement.dart';
import 'bell_movement_behaviour.dart';
import 'campfire_movement_behaviour.dart';
import 'dispenser/dispenser_movement_behaviour.dart';
import 'dispenser/dropper_movement_behaviour.dart';
import 'door_moving_interaction.dart';
import 'lever_moving_interaction.dart';
import 'trapdoor_moving_interaction.dart';

/// `AllMovementBehaviours.registerDefaults`.
void registerAllMovementBehaviours() {
  MovementBehaviours.register('minecraft:bell', const BellMovementBehaviour());
  MovementBehaviours.register(
    'minecraft:campfire',
    const CampfireMovementBehaviour(),
  );
  MovementBehaviours.register(
    'minecraft:soul_campfire',
    const CampfireMovementBehaviour(),
  );
  MovementBehaviours.register(
    'minecraft:dispenser',
    const DispenserMovementBehaviour(),
  );
  MovementBehaviours.register(
    'minecraft:dropper',
    const DropperMovementBehaviour(),
  );
}

/// `AllInteractionBehaviours.registerDefaults`. Java's registry gives the fence gate tag the
/// trapdoor interaction; `FenceGateMovingInteraction` is ported but unused there.
void registerAllInteractionBehaviours() {
  MovingInteractions.register(
    'minecraft:lever',
    const LeverMovingInteraction(),
  );
  MovingInteractions.registerTag(
    'minecraft:wooden_doors',
    const DoorMovingInteraction(),
  );
  MovingInteractions.registerTag(
    'minecraft:wooden_trapdoors',
    const TrapdoorMovingInteraction(),
  );
  MovingInteractions.registerTag(
    'minecraft:fence_gates',
    const TrapdoorMovingInteraction(),
  );
}
