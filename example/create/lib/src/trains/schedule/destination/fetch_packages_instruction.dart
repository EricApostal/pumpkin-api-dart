// `FetchPackagesInstruction` (pure): travel to a station that has packages to pick up for an
// address matching the filter.
import '../../graph/discovered_path.dart';
import '../../graph/edge_point_type.dart';
import '../../station/global_station.dart';
import '../glob_match.dart';
import '../schedule_level.dart';
import '../schedule_runtime.dart';
import 'text_schedule_instruction.dart';

class FetchPackagesInstruction extends TextScheduleInstruction {
  /// `getFilter()`.
  String getFilter() => getLabelText();

  /// `getFilterForRegex()`: a blank filter is `*`.
  String getFilterForRegex() {
    if (getFilter().trim().isEmpty) return globToRegexOrEmpty('*');
    return globToRegexOrEmpty(getFilter());
  }

  @override
  String getId() => 'create:package_retrieval';

  @override
  bool supportsConditions() => true;

  @override
  DiscoveredPath? start(ScheduleRuntime runtime, ScheduleLevel level) {
    if (!level.hasServer) return null;

    final regex = getFilterForRegex();
    var anyMatch = false;
    final validStations = <GlobalStation>[];
    final train = runtime.train;

    if (!train.hasForwardConductor() && !train.hasBackwardConductor()) {
      train.status.missingConductor();
      runtime.startCooldown();
      return null;
    }

    for (final globalStation in train.graph!.getPoints(EdgePointType.STATION)) {
      final dimension = globalStation.blockEntityDimension;
      if (!level.hasDimension(dimension)) continue;

      for (final entry in globalStation.connectedPorts.entries) {
        final port = entry.value;
        final pos = entry.key;

        final addresses = level.ports.packageAddresses(dimension, pos, port);
        if (addresses == null) continue;
        for (final address in addresses) {
          if (matchPackageAddress(address, port.address)) continue;
          try {
            if (!javaMatches(regex, address)) continue;
            anyMatch = true;
            validStations.add(globalStation);
          } on FormatException {
            // PatternSyntaxException: ignored
          }
        }
      }
    }

    if (validStations.isEmpty) {
      runtime.startCooldown();
      runtime.state = State.PRE_TRANSIT;
      runtime.currentEntry++;
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
