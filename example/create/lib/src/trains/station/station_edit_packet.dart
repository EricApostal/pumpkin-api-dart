// `StationEditPacket` (serverbound `create:configure_station`): the station screen's actions -
// drop the auto schedule, set the door control / name, assemble or disassemble, enter or leave the
// assembly mode.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/decoration.dart' show DoorControl;
import '../../api/payloads.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../core/module.dart';
import '../support/runtime.dart';
import '../track/track_host.dart';
import 'station_block.dart';
import 'station_block_entity.dart';

/// `BlockEntityConfigurationPacket.maxRange()` of the station screen.
const double stationEditMaxRange = 64;

/// Installs the handler on the payload bus.
void installStationEditPacket(CreateContext ctx) {
  ctx.services.find<PayloadBus>()?.onServerbound('create:configure_station', (
    player,
    fields,
  ) {
    final pos = fields['pos'];
    if (pos is! Pos) return;
    final world = player.getWorld();
    final be = Tr.i.store.typed<StationBlockEntity>(
      world.getId(),
      pos.toBlockPos(),
    );
    if (be == null) return;

    final (px, py, pz) = player.getPosition();
    final dx = px - pos.x, dy = py - pos.y, dz = pz - pos.z;
    if (dx * dx + dy * dy + dz * dz >
        stationEditMaxRange * stationEditMaxRange) {
      Tr.i.log.warn('A station edit packet came from too far away');
      return;
    }

    final dropSchedule = fields['dropSchedule'] == true;
    final assemblyMode = fields['assemblyMode'] == true;
    final tryAssemble = fields['tryAssemble'] as bool?;
    final doorControl = fields['doorControl'] as int?;
    final name = fields['name'] as String?;
    _apply(
      player,
      be,
      dropSchedule,
      assemblyMode,
      tryAssemble,
      doorControl,
      name,
    );
  });
}

Future<void> _apply(
  Player player,
  StationBlockEntity be,
  bool dropSchedule,
  bool assemblyMode,
  bool? tryAssemble,
  int? doorControl,
  String? name,
) async {
  final uuid = player.getId().asString;
  final station = be.getStation();

  if (dropSchedule) {
    if (station == null) return;
    await be.dropSchedule(uuid, station.getPresentTrain());
    return;
  }

  if (doorControl != null &&
      doorControl >= 0 &&
      doorControl < DoorControl.values.length) {
    be.doorControls.set(DoorControl.values[doorControl]);
  }

  if (name != null && name.trim().isNotEmpty) be.updateName(name);

  final level = HostTrackLevel(player.getWorld(), Tr.i.store);
  final state = level.stateAt(be.pos.toPos());
  if (state.key != stationBlockKey) return;

  final isAssemblyMode = state.flag(stationAssemblingProperty);
  var assemblyComplete = false;

  if (tryAssemble != null) {
    if (!isAssemblyMode) return;
    if (tryAssemble) {
      be.assemble(uuid);
      assemblyComplete = station != null && station.getPresentTrain() != null;
    } else {
      if (be.tryDisassembleTrain(uuid) && be.tryEnterAssemblyMode()) {
        be.refreshAssemblyInfo();
      }
    }
    if (!assemblyComplete) return;
  }

  if (assemblyMode) {
    be.enterAssemblyMode(uuid);
  } else {
    be.exitAssemblyMode();
  }
}
