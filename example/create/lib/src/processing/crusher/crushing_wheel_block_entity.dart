// `CrushingWheelBlockEntity`: a kinetic block entity that carries its controllers. The wheel
// itself does not process anything; it keeps the invisible `CrushingWheelControllerBlock`
// between two wheels up to date (direction and validity) and lets the controller do the work.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/kinetics.dart';
import '../../core/block_entity.dart';
import '../../core/block_entity.dart' show BlockEntityStore;
import 'crushing_keys.dart';
import 'crushing_logic.dart';
import 'crushing_wheel_controller_block_entity.dart';

/// `CrushingWheelBlockEntity`.
class CrushingWheelBlockEntity extends KineticBlockEntity {
  CrushingWheelBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 20;
  }

  bool _fixing = false;
  bool _fixQueued = false;

  /// `fixControllers()`: called when the speed changed and every lazy tick. Coalesced, because
  /// the block writes of the controller are asynchronous here.
  void fixControllers() {
    if (removed) return;
    if (_fixing) {
      _fixQueued = true;
      return;
    }
    unawaited(
      _fixLoop().catchError((Object e, StackTrace s) {
        KineticsRuntime.instance.log.error(
          'Updating the crushing wheel controllers of $this failed',
          error: e,
          stackTrace: s,
        );
      }),
    );
  }

  Future<void> _fixLoop() async {
    _fixing = true;
    try {
      do {
        _fixQueued = false;
        final state = blockState;
        if (!state.isCreate('crushing_wheel')) return;
        for (final side in Dir.values) {
          await updateControllerForSide(store, worldId, pos, state, side);
        }
      } while (_fixQueued && !removed);
    } finally {
      _fixing = false;
    }
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    fixControllers();
  }

  @override
  void lazyTick() {
    super.lazyTick();
    fixControllers();
  }
}

/// `CrushingWheelBlock.updateControllers` for one side: creates, updates or removes the
/// controller between this wheel and the wheel two blocks away.
Future<void> updateControllerForSide(
  BlockEntityStore store,
  String worldId,
  BlockPos pos,
  KState state,
  Dir side,
) async {
  final wheelAxis = state.axisOf('axis') ?? KAxis.y;
  if (side.axis == wheelAxis) return;
  final world = store.worlds.byId(worldId);
  if (world == null) return;

  final runtime = KineticsRuntime.instance;
  final level = runtime.level(worldId);
  final kpos = toKPos(pos);
  final controllerPos = kpos.relative(side);
  final otherWheelPos = kpos.relative(side, 2);

  final controllerState = level.stateAt(controllerPos);
  final controllerExists = controllerState.block == crushingWheelControllerKey;
  final controllerIsValid = controllerExists && controllerState.flag('valid');
  final controllerOldDirection = controllerExists
      ? controllerState.dirOf('facing')
      : null;

  var controllerShouldExist = false;
  var controllerShouldBeValid = false;
  var controllerNewDirection = Dir.down;

  final otherState = level.stateAt(otherWheelPos);
  if (otherState.block == crushingWheelKey) {
    controllerShouldExist = true;
    final be = store.typed<CrushingWheelBlockEntity>(worldId, pos);
    final otherBE = store.typed<CrushingWheelBlockEntity>(
      worldId,
      toBlockPos(otherWheelPos),
    );
    if (be != null &&
        otherBE != null &&
        (be.speed > 0) != (otherBE.speed > 0) &&
        be.speed != 0 &&
        otherBE.speed != 0) {
      controllerNewDirection = controllerDirection(wheelAxis, side, be.speed);
      controllerShouldBeValid = true;
    }
    // Two wheels only form a crusher when they share their axis.
    if (otherState.axisOf('axis') != wheelAxis) controllerShouldExist = false;
  }

  if (!controllerShouldExist) {
    if (controllerExists) {
      final air = runtime.states.idOf(KState.air);
      if (air != null) {
        await world.setBlockState(
          pos: toBlockPos(controllerPos),
          state: air,
          updateFlags: BlockUpdateFlags.normal,
        );
      }
    }
    return;
  }

  final target = KState(crushingWheelControllerKey, {
    'facing': controllerNewDirection.name,
    'valid': '$controllerShouldBeValid',
  });

  if (!controllerExists) {
    if (!HostBlockGetter(world)
        .canBeReplaced((controllerPos.x, controllerPos.y, controllerPos.z))) {
      return;
    }
    final id = runtime.states.idOf(target);
    if (id == null) return;
    await world.setBlockState(
      pos: toBlockPos(controllerPos),
      state: id,
      updateFlags: BlockUpdateFlags.normal,
    );
    // The host fires `placed` for the new block; creating the entity here guarantees it exists
    // before the speed is handed over (`createAt` is idempotent).
    store.createAt(
      world,
      toBlockPos(controllerPos),
      crushingWheelControllerKey,
    );
  } else if (controllerIsValid != controllerShouldBeValid ||
      controllerOldDirection != controllerNewDirection) {
    final id = runtime.states.idOf(target);
    if (id == null) return;
    await world.setBlockState(
      pos: toBlockPos(controllerPos),
      state: id,
      updateFlags: BlockUpdateFlags.normal,
    );
  }

  final controller = store.typed<CrushingWheelControllerBlockEntity>(
    worldId,
    toBlockPos(controllerPos),
  );
  controller?.updateSpeed(target);
}
