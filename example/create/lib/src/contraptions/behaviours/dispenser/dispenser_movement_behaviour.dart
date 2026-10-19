// `DispenserMovementBehaviour`: a dispenser uses the item specific mounted dispense behaviour when
// one is registered, and the default one otherwise.
import '../../../common/common.dart';
import '../../core/movement.dart';
import '../../storage/stacks.dart';
import 'dropper_movement_behaviour.dart';
import 'mounted_dispense_behaviour.dart';

/// `DispenserMovementBehaviour`.
final class DispenserMovementBehaviour extends DropperMovementBehaviour {
  const DispenserMovementBehaviour();

  @override
  MountedDispenseBehaviour getDispenseBehaviour(
    MovementContext context,
    Pos pos,
    StoredStack stack,
  ) =>
      MountedDispenseBehaviour.of(stack.item) ??
      DefaultMountedDispenseBehaviour.instance;
}
