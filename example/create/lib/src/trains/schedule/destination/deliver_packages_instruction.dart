// `DeliverPackagesInstruction` (pure): travel to a station with a package port the train's
// packages are addressed to.
import '../../graph/discovered_path.dart';
import '../../graph/edge_point_type.dart';
import '../../station/global_station.dart';
import '../schedule_level.dart';
import '../schedule_runtime.dart';
import 'schedule_instruction.dart';

class DeliverPackagesInstruction extends ScheduleInstruction {
  @override
  String getId() => 'create:package_delivery';

  @override
  bool supportsConditions() => true;

  @override
  DiscoveredPath? start(ScheduleRuntime runtime, ScheduleLevel level) {
    var anyMatch = false;
    String? firstPackage;
    final validStations = <GlobalStation>[];
    final train = runtime.train;

    if (!train.hasForwardConductor() && !train.hasBackwardConductor()) {
      train.status.missingConductor();
      runtime.startCooldown();
      return null;
    }

    for (final carriage in train.carriages) {
      final cargo = carriage.storage;

      // Export to station
      for (final stack in cargo.getAllItems()) {
        if (!stack.isPackage) continue;
        firstPackage ??= stack.packageAddress;
        for (final globalStation in train.graph!.getPoints(EdgePointType.STATION)) {
          for (final port in globalStation.connectedPorts.entries) {
            if (!matchPackageAddress(stack.packageAddress, port.value.address)) continue;
            anyMatch = true;
            validStations.add(globalStation);
            break;
          }
        }
      }
    }

    if (validStations.isEmpty) {
      if (firstPackage != null) {
        train.status.failedPackageNoTarget(firstPackage);
        runtime.startCooldown();
      } else {
        runtime.state = State.PRE_TRANSIT;
        runtime.currentEntry++;
      }
      return null;
    }

    final best = train.navigation.findPathTo(validStations, double.maxFinite);
    if (best == null) {
      if (anyMatch) train.status.failedNavigation();
      runtime.startCooldown();
      return null;
    }

    return best;
  }
}
