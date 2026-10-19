// `GlobalTrainDisplayData` (pure): the departure predictions of all scheduled trains, grouped by
// destination station name and refreshed every 100 ticks. Display links and the station summary
// read them.
import '../../redstone/support/text.dart' show Txt;
import '../entity/train.dart';
import '../schedule/glob_match.dart' show globToRegexOrEmpty, javaMatches;
import 'create.dart';

class GlobalTrainDisplayData {
  // ignore: non_constant_identifier_names
  static final Map<String, List<TrainDeparturePrediction>> statusByDestination = {};
  static bool updateTick = false;

  static void refresh() {
    statusByDestination.clear();
    for (final train in Create.RAILWAYS.trains.values) {
      if (train.runtime.paused || train.runtime.getSchedule() == null) continue;
      if (train.derailed || train.graph == null) continue;
      for (final prediction in train.runtime.submitPredictions()) {
        statusByDestination.putIfAbsent(prediction.destination, () => []).add(prediction);
      }
    }
  }

  static List<TrainDeparturePrediction> prepare(String filter, int maxLines) {
    final regex = globToRegexOrEmpty(filter);
    final all = <TrainDeparturePrediction>[];
    for (final e in statusByDestination.entries) {
      if (!javaMatches(regex, e.key)) continue;
      all.addAll(e.value);
    }
    // a stable sort, like `Stream.sorted()`
    final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
    indexed.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final p in indexed.take(maxLines)) p.$2];
  }
}

class TrainDeparturePrediction implements Comparable<TrainDeparturePrediction> {
  Train train;
  int ticks;
  Txt scheduleTitle;
  String destination;

  TrainDeparturePrediction(this.train, this.ticks, this.scheduleTitle, this.destination);

  int _getCompareTicks() {
    if (ticks == -1) return 0x7FFFFFFF;
    if (ticks < 200) return 0;
    return ticks;
  }

  @override
  int compareTo(TrainDeparturePrediction other) {
    final compare = _getCompareTicks().compareTo(other._getCompareTicks());
    if (compare == 0) return train.name.plain.compareTo(other.train.name.plain);
    return compare;
  }
}
