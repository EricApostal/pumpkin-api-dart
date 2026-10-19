// `DestinationInstruction` (pure): travel to a station whose name matches a glob.
import '../../graph/discovered_path.dart';
import '../../graph/edge_point_type.dart';
import '../../station/global_station.dart';
import '../glob_match.dart';
import '../schedule_level.dart';
import '../schedule_runtime.dart';
import 'text_schedule_instruction.dart';

class DestinationInstruction extends TextScheduleInstruction {
  @override
  bool supportsConditions() => true;

  @override
  String getId() => 'create:destination';

  /// `getFilter()`.
  String getFilter() => getLabelText();

  /// `getFilterForRegex()`: `Glob.toRegexPattern(getFilter(), "")`.
  String getFilterForRegex() => globToRegexOrEmpty(getFilter());

  @override
  DiscoveredPath? start(ScheduleRuntime runtime, ScheduleLevel level) {
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
      if (!_matches(regex, globalStation.name)) continue;
      anyMatch = true;
      validStations.add(globalStation);
    }

    final best = train.navigation.findPathTo(validStations, double.maxFinite);
    if (best == null) {
      if (anyMatch) {
        train.status.failedNavigation();
      } else {
        train.status.failedNavigationNoTarget(getFilter());
      }
      runtime.startCooldown();
      return null;
    }

    return best;
  }

  static bool _matches(String regex, String name) {
    try {
      return javaMatches(regex, name);
    } on FormatException {
      return false;
    }
  }
}
