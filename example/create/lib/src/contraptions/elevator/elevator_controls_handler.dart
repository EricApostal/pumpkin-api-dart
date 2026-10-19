// `ElevatorControlsHandler` (server-relevant parts): the floor selection state of the contraption
// controls actor and the helper that resolves it against an elevator contraption.
//
// The Java `ElevatorControlsHandler.onScroll` is client-only (it raycasts the local player's view
// and scrolls the controls); the scroll arrives at the server as `create:elevator_set_floor`, which
// is handled here through [selectFloor].
//
// Java: `content/contraptions/elevator/ElevatorControlsHandler` and
// `ContraptionControlsMovement.{ElevatorFloorSelection,tickFloorSelection}`.
import 'elevator_contraption.dart';

/// `ContraptionControlsMovement.ElevatorFloorSelection`: the temporary data of the controls actor.
final class ElevatorFloorSelection {
  int currentIndex = 0;
  int currentTargetY = 0;
  bool targetYEqualsSelection = true;
  String currentShortName = '';
  String currentLongName = '';
}

/// `ContraptionControlsMovement.tickFloorSelection`.
void tickFloorSelection(
  ElevatorFloorSelection selection,
  ElevatorContraption contraption,
) {
  if (contraption.namesList.isEmpty) {
    selection
      ..currentShortName = 'X'
      ..currentLongName = 'No Floors'
      ..currentIndex = 0
      ..targetYEqualsSelection = true;
    return;
  }

  selection.currentIndex = selection.currentIndex.clamp(
    0,
    contraption.namesList.length - 1,
  );
  final (y, names) = contraption.namesList[selection.currentIndex];
  selection
    ..currentTargetY = y
    ..currentShortName = names.$1
    ..currentLongName = names.$2
    ..targetYEqualsSelection = y == contraption.clientYTarget;

  if (contraption.isTargetUnreachable(y)) {
    selection.currentLongName = 'contraption.controls.floor_unreachable';
  }
}

/// The floor list entry of [targetY], `null` when the column has no such floor.
int? floorIndexAt(ElevatorContraption contraption, int targetY) {
  for (var i = 0; i < contraption.namesList.length; i++) {
    if (contraption.namesList[i].$1 == targetY) return i;
  }
  return null;
}
