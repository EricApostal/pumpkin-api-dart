// `ElevatorPulleyBlock` and `ElevatorContactBlock`: the pulley that drives an elevator and the
// floor contacts. A contact calls the elevator to its floor, pulses redstone when the elevator
// arrives and turns back into a redstone contact when wrenched out of a column.
//
// Java: `content/contraptions/elevator/{ElevatorPulleyBlock,ElevatorContactBlock}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/wrenchable.dart';
import '../../common/common.dart';
import '../../core/blocks.dart';
import '../blocks/actuator_runtime.dart';
import 'elevator_column.dart';
import 'elevator_contact_block_entity.dart';
import 'elevator_pulley_block_entity.dart';

const String elevatorPulleyKey = 'create:elevator_pulley';
const String elevatorContactKey = 'create:elevator_contact';
const String redstoneContactKey = 'create:redstone_contact';

/// The elevator block definitions.
List<CreateBlock> buildElevatorBlocks() => [
  manifestBlock(
    'elevator_pulley',
    blockEntityType: elevatorPulleyKey,
    // `ElevatorPulleyBlock extends HorizontalKineticBlock`: opposite of the look direction.
    placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
    behavior: BlockBehavior(
      // `useItemOn` with a non-empty stack returns TRY_WITH_EMPTY_HAND, so any click toggles the
      // elevator (a sneaking click is refused).
      onUse: (server, e) async {
        if (e.sneaking) return BlockUseResult.fail;
        final be = ActuatorRuntime.maybe?.store.at(
          e.targetWorld.getId(),
          e.pos,
        );
        if (be is ElevatorPulleyBlockEntity) {
          be.clicked();
          return BlockUseResult.success;
        }
        return BlockUseResult.pass;
      },
    ),
  ),
  manifestBlock(
    'elevator_contact',
    blockEntityType: elevatorContactKey,
    // `ElevatorContactBlock extends WrenchableDirectionalBlock`: `getNearestLookingDirection()`.
    placement: const [PlacementRule.lookingDirection('facing')],
    behavior: elevatorContactBehavior(),
  ),
];

/// `ElevatorContactBlock` behaviour.
BlockBehavior elevatorContactBehavior() => BlockBehavior(
  onNeighborUpdate: (server, e) async {
    final world = e.targetWorld;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    if (state.key != elevatorContactKey) return;

    final wasPowered = state.flag('powered');
    final isPowered = await world.hasNeighborSignal(pos: e.pos);
    if (wasPowered == isPowered) return;
    await _setFlag(world, pos, state, 'powered', isPowered);

    if (wasPowered) return;
    if (state.flag('calling')) return;

    final coords = ElevatorColumn.contactColumnCoords(state, pos);
    if (coords == null) return;
    await callToContactAndUpdate(world.getId(), world, state, pos, true);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    if (state.key != elevatorContactKey) return;

    final wasPowering = state.flag('powering');
    var shouldPower = false;
    final be = ActuatorRuntime.maybe?.store.at(e.targetWorld.getId(), e.pos);
    if (be is ElevatorContactBlockEntity) {
      shouldPower = be.activateBlock;
      be.activateBlock = false;
      be.markDirty();
    }
    final facing = state.dir('facing') ?? Direction.south;
    shouldPower |= _hasValidContact(world, pos.relative(facing), facing);

    if (wasPowering || shouldPower) {
      await _setFlag(world, pos, state, 'powering', shouldPower);
    }
  },
  // `getSignal`: no strong power (the block has no `getDirectSignal`), and a contact
  // directly behind the reading side does not power it.
  onWeakPower: (server, e) {
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final behind = HostBlockGetter(e.targetWorld)
        .stateAt(pos.relative(toDirection(e.face)));
    if (behind.key == elevatorContactKey) return 0;
    return state.flag('powering') ? 15 : 0;
  },
  canConnectRedstone: (server, e) {
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    final facing = state.dir('facing') ?? Direction.south;
    return e.direction == null || toDirection(e.direction!) != facing.opposite;
  },
  // `updateShape`: the contact in front changed, recheck whether it still powers.
  onUpdateShape: (server, e) {
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    if (state.key != elevatorContactKey) return null;
    final facing = state.dir('facing') ?? Direction.south;
    if (toDirection(e.direction) != facing) return null;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final valid = _hasValidContact(e.targetWorld, pos.relative(facing), facing);
    if (state.flag('powering') != valid) {
      e.targetWorld.scheduleBlockTick(
        pos: e.pos,
        delayTicks: 1,
        priority: TickPriority.normal,
      );
    }
    return null;
  },
  // `useItemOn`: a wrench click goes to the empty-hand path (which has no action); anything else
  // opens the contact screen client-side.
  onUseWithItem: (server, e) async {
    try {
      if (await e.item.getRegistryKey() == 'create:wrench') {
        return BlockUseResult.pass;
      }
    } on Object {
      // an empty or unreadable stack behaves like any other item
    }
    return BlockUseResult.success;
  },
  // `getCloneItemStack`: middle-click gives the redstone contact.
  onCloneItem: (server, e) =>
      ItemStack.create(registryKey: redstoneContactKey, count: 1),
);

/// `ElevatorContactBlock.onWrenched`: after the rotation, a contact that is not part of a live
/// column turns back into a redstone contact.
Wrenchable elevatorContactWrenchable() => CallbackWrenchable(
  onWrenchedOverride: (c) async {
    final result = await c.registry.defaultRotate(c);
    if (result != WrenchResult.success) return result;

    final world = c.world;
    final pos = (c.pos.x, c.pos.y, c.pos.z);
    final state = HostBlockGetter(world).stateAt(pos);
    final facing = state.dir('facing') ?? Direction.south;
    if (facing.axis != Axis.y &&
        ElevatorColumn.get(
              world.getId(),
              ColumnCoords(c.pos.x, c.pos.z, facing),
            ) !=
            null) {
      return result;
    }

    // `BlockHelper.copyProperties(state, REDSTONE_CONTACT.getDefaultState())`: only the
    // properties both blocks have survive.
    final props = {
      for (final name in const ['facing', 'powered'])
        if (state.props.containsKey(name)) name: state.props[name]!,
    };
    await setBlockState(world, pos, BState(redstoneContactKey, props));
    return result;
  },
);

/// `ElevatorContactBlock.callToContactAndUpdate`: this contact becomes the called one, the others
/// stop calling, and the column targets its y level.
Future<void> callToContactAndUpdate(
  String worldId,
  World world,
  BState state,
  Pos pos,
  bool powered,
) async {
  var current = await _setFlag(
    world,
    pos,
    state,
    'calling',
    !state.flag('calling'),
  );

  final coords = ElevatorColumn.contactColumnCoords(state, pos);
  final column = ElevatorColumn.getOrCreate(
    worldId,
    coords ?? ColumnCoords(pos.$1, pos.$3, Direction.south),
  );
  for (final otherPos in column.getContacts()) {
    if (otherPos == pos) continue;
    final otherState = HostBlockGetter(world).stateAt(otherPos);
    if (otherState.key != elevatorContactKey) continue;
    if (otherState.flag('calling')) {
      await _setFlag(world, otherPos, otherState, 'calling', false);
    }
    // The other contacts re-check their redstone contact after the target changed.
    await scheduleActivation(world, otherPos);
  }

  if (powered) current = current.setFlag('powered', true);
  await _setFlag(world, pos, current, 'calling', true);

  column.target(pos.$2);
  column.markDirty();
}

/// `ElevatorContactBlock.scheduleActivation`.
Future<void> scheduleActivation(World world, Pos pos) async {
  world.scheduleBlockTick(
    pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    delayTicks: 1,
    priority: TickPriority.normal,
  );
}

/// `RedstoneContactBlock.hasValidContact`: the block at [pos] is a contact facing back at the
/// elevator contact.
bool _hasValidContact(World world, Pos pos, Direction direction) {
  final other = HostBlockGetter(world).stateAt(pos);
  if (other.key != redstoneContactKey && other.key != elevatorContactKey)
    return false;
  return other.dir('facing') == direction.opposite;
}

/// Sets one boolean property of the block at [pos] and returns the new state.
Future<BState> _setFlag(
  World world,
  Pos pos,
  BState state,
  String property,
  bool value,
) async {
  final next = state.setFlag(property, value);
  if (next == state) return state;
  final id = BlockRegistry.resolveState(next.key, next.props);
  if (id == null) return state;
  await world.setBlockState(
    pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    state: id,
    updateFlags: {BlockFlagsFlag.notifyListeners},
  );
  return next;
}
