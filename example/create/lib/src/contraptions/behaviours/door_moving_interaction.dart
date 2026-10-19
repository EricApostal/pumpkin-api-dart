// `DoorMovingInteraction`: clicking a door (vanilla or Create's sliding doors) on a contraption
// toggles both halves and, for a double sliding door, the other door as well.
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/movement.dart';
import '../core/structure_info.dart';

final math.Random _random = math.Random();

/// `SlidingDoorBlock` of the decoration module: the doors whose state carries `hinge`/`facing` and
/// whose `open` toggles like a vanilla door.
const Set<String> _slidingDoorKeys = {
  'create:andesite_door',
  'create:brass_door',
  'create:copper_door',
  'create:train_door',
  'create:framed_glass_door',
};

/// `SlidingDoorBlock.isDoubleDoor`.
bool _isDoubleDoor(
  BState state,
  String hinge,
  Direction facing,
  BState otherDoor,
) =>
    otherDoor.key == state.key &&
    otherDoor['hinge'] != hinge &&
    otherDoor.dir('facing') == facing &&
    otherDoor.flag('open') != state.flag('open') &&
    otherDoor['half'] == state['half'];

/// `DoorMovingInteraction`.
final class DoorMovingInteraction extends SimpleBlockMovingInteraction {
  const DoorMovingInteraction();

  @override
  bool get updateColliders => true;

  @override
  BState handle(
    InteractingPlayer? player,
    Contraption contraption,
    Pos pos,
    BState currentState,
  ) {
    if (!currentState.has('open') || !currentState.has('half'))
      return currentState;

    final trainDoor = _slidingDoorKeys.contains(currentState.key);
    final opening = !currentState.flag('open');
    // `DoorBlock` sound: a sliding door only makes a sound when it opens.
    final String? sound = opening
        ? (trainDoor
              ? 'minecraft:block.iron_door.open'
              : 'minecraft:block.wooden_door.open')
        : (trainDoor ? null : 'minecraft:block.wooden_door.close');

    final otherPos = currentState['half'] == 'lower' ? pos.above : pos.below;
    final other = contraption.blocks[otherPos];
    if (other != null && other.state.has('open')) {
      final newOther = other.state.cycleFlag('open');
      setContraptionBlockData(
        contraption,
        otherPos,
        StructureBlockInfo(other.pos, newOther, other.nbt),
      );
    }

    currentState = currentState.cycleFlag('open');

    if (player != null) {
      if (trainDoor) {
        final hinge = currentState['hinge'] ?? 'left';
        final facing = currentState.dir('facing');
        if (facing != null) {
          final doublePos = pos.relative(
            hinge == 'left' ? facing.clockWise : facing.counterClockWise,
          );
          final doubleInfo = contraption.blocks[doublePos];
          if (doubleInfo != null &&
              _isDoubleDoor(currentState, hinge, facing, doubleInfo.state)) {
            // Java recurses with a null player so the second door makes no sound.
            final newDouble = handle(
              null,
              contraption,
              doublePos,
              doubleInfo.state,
            );
            if (newDouble != doubleInfo.state) {
              setContraptionBlockData(
                contraption,
                doublePos,
                StructureBlockInfo(doubleInfo.pos, newDouble, doubleInfo.nbt),
              );
              contraption.invalidateColliders();
            }
          }
        }
      }
      if (sound != null)
        playSound(player, sound, _random.nextDouble() * 0.1 + 0.9);
    }

    return currentState;
  }
}
