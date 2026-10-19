/// The trains module's public contract for the other modules (contraptions, logistics,
/// infrastructure).
///
/// ```dart
/// // The contraptions module implements the carriage contraption assembly:
/// ctx.services.provide<CarriageContraptionAssembly>(MyAssembly());
///
/// // The logistics module implements the station's schedule slot:
/// ctx.services.provide<StationDepotFactory>(MyDepotFactory());
/// ```
///
/// Everything here is either a pure model of the trains module or an interface another module
/// provides. The host glue of the trains module (`trains_module.dart`) consumes them.
library;

import 'package:pumpkin_api/pumpkin_api.dart' show ItemStack;

import '../common/pos.dart';
import '../core/block_entity.dart';
import '../trains/entity/carriage_contraption.dart';
import '../trains/entity/train_level.dart';
import '../trains/station/global_station.dart';

export 'contraption/train/train_hat_info_provider.dart';
export '../trains/entity/carriage.dart';
export '../trains/entity/carriage_bogey.dart';
export '../trains/entity/carriage_contraption.dart';
export '../trains/entity/carriage_contraption_entity.dart';
export '../trains/entity/carriage_entity_host.dart';
export '../trains/entity/carriage_storage.dart';
export '../trains/entity/carriage_sync_data.dart';
export '../trains/entity/contraption_data.dart';
export '../trains/entity/train.dart';
export '../trains/entity/train_icon_type.dart';
export '../trains/entity/train_level.dart';
export '../trains/entity/train_relocator.dart';
export '../trains/entity/train_status.dart';
export '../trains/entity/travelling_point.dart';
export '../trains/schedule/schedule_services.dart'
    show ConductorSeatLookup, ScheduleCarriagePassenger;
export '../trains/station/global_station.dart';
export '../trains/station/station_assembly.dart' show StationAssembly;
export '../trains/station/station_marker.dart';
export '../trains/support/ctag_host.dart';
export '../trains/track/bezier_track_point_location.dart';
export '../trains/track/i_track_block.dart';
export '../trains/track/track_host.dart'
    show FakeTrackBlockEntityHost, HostTrackLevel, TrackBlockEntityHost;
export '../trains/track/track_level.dart';
export '../trains/track/track_targeting_behaviour.dart';
export '../trains/util/ctag.dart';

/// Provided by the contraptions module: builds the contraption of a carriage the station
/// assembles (`new CarriageContraption(direction)` + `contraption.assemble(level, anchor)`).
///
/// The returned contraption has its [CarriageContraption.data] set by the provider; the station
/// only reads the train specific parts (`hasForwardControls`, `getSecondBogeyPos`, ...).
abstract interface class CarriageContraptionAssembly {
  /// `contraption.assemble(level, anchor)`: `null` when no structure is attached at [anchor].
  CarriageContraption? assemble(String worldId, TrainLevel level, Pos anchor);
}

/// Provided by the logistics module: the single schedule slot of a station (`DepotBehaviour` with
/// `onlyAccepts(AllItems.SCHEDULE)`). The station adds the behaviour to its block entity.
abstract class StationDepot extends BlockEntityBehaviour {
  /// `getHeldItemStack()`: the held stack, `null` when the slot is empty.
  ItemStack? get heldItem;

  /// `removeHeldItem()`.
  void removeHeldItem();
}

/// Creates the station's schedule slot. Provided by the logistics module.
abstract interface class StationDepotFactory {
  /// `new DepotBehaviour(station).onlyAccepts(AllItems.SCHEDULE).withCallback(onChanged)`.
  StationDepot create(
    CreateBlockEntity station, {
    required void Function() onChanged,
  });
}

/// Provided by the logistics module: attaches and removes the package ports of a station
/// (`StationBlockEntity.attachPackagePort` / `removePackagePort`).
abstract interface class StationPackagePorts {
  /// `attachPackagePort(ppbe)`: the port joins [station]'s [GlobalStation.connectedPorts].
  void attach(GlobalStation station, Object portBlockEntity);

  /// `removePackagePort(ppbe)`.
  void remove(GlobalStation station, Object portBlockEntity);
}
