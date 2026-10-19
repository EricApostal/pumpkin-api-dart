// The elevator payload handlers: `create:configure_elevator_contact`,
// `create:request_floor_list`, `create:elevator_set_floor`.
//
// Java: `content/contraptions/elevator/{ElevatorContactEditPacket,ElevatorFloorListPacket,
// ElevatorTargetFloorPacket}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/decoration.dart' show DoorControl;
import '../../api/payloads.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import 'elevator_blocks.dart';
import 'elevator_column.dart';
import 'elevator_contact_block_entity.dart';
import 'elevator_contraption.dart';

/// Binds the three elevator channels to the payload bus.
void bindElevatorPackets(PayloadBus bus) {
  bus.onServerbound('create:configure_elevator_contact', (player, fields) {
    final pos = fields['pos'] as (int, int, int);
    final shortName = fields['shortName'] as String;
    final longName = fields['longName'] as String;
    final doorControl = fields['doorControl'] as int;
    handleContactEdit(player, pos, shortName, longName, doorControl);
  });

  bus.onServerbound('create:request_floor_list', (player, fields) {
    handleFloorListRequest(player, fields['entityId'] as int);
  });

  bus.onServerbound('create:elevator_set_floor', (player, fields) {
    handleSetFloor(player, fields['entityId'] as int, fields['targetY'] as int);
  });
}

/// `ElevatorContactEditPacket.applySettings`, with the checks of
/// `BlockEntityConfigurationPacket.handle` (not a spectator or in adventure, loaded, within 20
/// blocks of the block).
void handleContactEdit(
  Player player,
  Pos pos,
  String shortName,
  String longName,
  int doorControl,
) {
  final mode = player.getGamemode();
  if (mode == GameMode.spectator || mode == GameMode.adventure) return;

  final world = player.getWorld();
  final blockPos = BlockPos(x: pos.$1, y: pos.$2, z: pos.$3);
  if (!world.isLoaded(pos: blockPos)) return;
  final playerPos = player.asEntity().getPosition();
  final dx = playerPos.$1 - (pos.$1 + .5);
  final dy = playerPos.$2 - (pos.$2 + .5);
  final dz = playerPos.$3 - (pos.$3 + .5);
  if (dx * dx + dy * dy + dz * dz > 20 * 20) return;

  final be = ActuatorRuntime.maybe?.store.at(world.getId(), blockPos);
  if (be is! ElevatorContactBlockEntity) return;
  be.updateName(shortName, longName);
  be.doorControls?.set(
    doorControl >= 0 && doorControl < DoorControl.values.length
        ? DoorControl.values[doorControl]
        : DoorControl.all,
  );
}

/// `ElevatorFloorListPacket.RequestFloorList.handle`: send the floor list of the elevator to the
/// player that asked for it.
void handleFloorListRequest(Player player, int entityId) {
  final worldId = player.getWorld().getId();
  final entity = ActuatorHosts.entities?.entityById(worldId, entityId);
  final contraption = entity?.contraption;
  if (contraption is! ElevatorContraption) return;

  ActuatorHosts.payloadBus?.sendClientbound(
    'create:update_elevator_floors',
    player,
    {
      'entityId': entityId,
      'floors': [
        for (final (y, names) in contraption.namesList)
          {
            'first': y,
            'second': {'first': names.$1, 'second': names.$2},
          },
      ],
    },
  );
}

/// `ElevatorTargetFloorPacket.handle`: the controls selected a floor; the contact calls the
/// elevator there.
Future<void> handleSetFloor(Player player, int entityId, int targetY) async {
  final world = player.getWorld();
  final worldId = world.getId();
  final entity = ActuatorHosts.entities?.entityById(worldId, entityId);
  final contraption = entity?.contraption;
  if (contraption is! ElevatorContraption) return;
  final playerPos = player.asEntity().getPosition();
  if (entity != null && (entity.position - playerPos).lengthSquared > 50 * 50)
    return;

  final coords = contraption.getGlobalColumn();
  if (coords == null) return;
  final column = ElevatorColumn.get(worldId, coords);
  if (column == null) return;
  if (!column.contacts.contains(targetY)) return;
  if (contraption.isTargetUnreachable(targetY)) return;

  final pos = column.contactAt(targetY);
  final state = HostBlockGetter.stateOfId(
    world.getBlockStateId(pos: pos.toBlockPos()),
  );
  if (state.key != elevatorContactKey) return;

  await callToContactAndUpdate(worldId, world, state, pos, false);
}
