// `ScheduleRuntime` (pure): the state machine that works a train through its schedule. A train
// is PRE_TRANSIT (about to start the current entry's instruction), IN_TRANSIT (navigating to its
// destination) or POST_TRANSIT (at the station, waiting for the conditions of the entry).
// ignore_for_file: constant_identifier_names
import '../../redstone/support/text.dart' show Txt;
import '../entity/train.dart';
import '../graph/discovered_path.dart';
import '../manager/global_train_display_data.dart' show TrainDeparturePrediction;
import '../station/global_station.dart';
import '../util/ctag.dart';
import 'condition/schedule_wait_condition.dart';
import 'condition/scheduled_delay.dart';
import 'destination/change_title_instruction.dart';
import 'destination/destination_instruction.dart';
import 'schedule.dart';
import 'schedule_level.dart';
import 'schedule_math.dart';

/// `ScheduleRuntime.State`.
enum State { PRE_TRANSIT, IN_TRANSIT, POST_TRANSIT }

class ScheduleRuntime {
  static const int _tbd = -1;
  static const int _invalid = -2;

  Train train;
  Schedule? schedule;

  bool isAutoSchedule = false;
  bool paused = true;
  bool completed = false;
  int currentEntry = 0;
  State state = State.PRE_TRANSIT;

  List<int> conditionProgress = [];
  List<CTag> conditionContext = [];
  String currentTitle = '';

  int ticksInTransit = 0;
  List<int> predictionTicks = [];

  bool displayLinkUpdateRequested = false;

  static const int _interval = 40;
  int _cooldown = 0;

  ScheduleRuntime(this.train) {
    reset();
  }

  /// `startCooldown()`.
  void startCooldown() {
    _cooldown = _interval;
  }

  /// `destinationReached()`.
  void destinationReached() {
    if (state != State.IN_TRANSIT) return;
    state = State.POST_TRANSIT;
    conditionProgress.clear();
    conditionContext.clear();
    displayLinkUpdateRequested = true;
    for (final carriage in train.carriages) {
      carriage.storage.resetIdleCargoTracker();
    }

    if (ticksInTransit > 0) {
      final current = predictionTicks[currentEntry];
      if (current > 0) ticksInTransit = (current + ticksInTransit) ~/ 2;
      predictionTicks[currentEntry] = ticksInTransit;
    }

    final schedule = this.schedule!;
    if (currentEntry >= schedule.entries.length) return;
    final conditions = schedule.entries[currentEntry].conditions;
    for (var i = 0; i < conditions.length; i++) {
      conditionProgress.add(0);
      conditionContext.add(CTag());
    }
  }

  /// `transitInterrupted()`.
  void transitInterrupted() {
    if (schedule == null || state != State.IN_TRANSIT) return;
    state = State.PRE_TRANSIT;
    _cooldown = 0;
  }

  /// `tick(level)`.
  void tick(ScheduleLevel level) {
    if (schedule == null) return;
    if (paused) return;
    if (train.derailed) return;
    if (train.navigation.destination != null) {
      ticksInTransit++;
      return;
    }

    if (_checkEndOfScheduleReached()) return;
    if (_cooldown-- > 0) return;
    if (state == State.IN_TRANSIT) return;
    if (state == State.POST_TRANSIT) {
      tickConditions(level);
      return;
    }

    final nextPath = startCurrentInstruction(level);
    if (nextPath == null) return;

    train.status.successfulNavigation();
    if (identical(nextPath.destination, train.getCurrentStation())) {
      state = State.IN_TRANSIT;
      destinationReached();
      return;
    }
    if (train.navigation.startNavigation(nextPath) != _tbd) {
      state = State.IN_TRANSIT;
      ticksInTransit = 0;
    }
  }

  bool _checkEndOfScheduleReached() {
    if (currentEntry < schedule!.entries.length) return false;

    currentEntry = 0;
    if (!schedule!.cyclic) {
      paused = true;
      completed = true;
    }
    return true;
  }

  /// `tickConditions(level)`.
  void tickConditions(ScheduleLevel level) {
    final entry = schedule!.entries[currentEntry];
    final conditions = entry.conditions;

    if (!entry.instruction.supportsConditions()) {
      state = State.PRE_TRANSIT;
      currentEntry++;
      return;
    }

    for (var i = 0; i < conditions.length; i++) {
      final list = conditions[i];
      final progress = conditionProgress[i];

      if (progress >= list.length) {
        state = State.PRE_TRANSIT;
        currentEntry++;
        return;
      }

      final tag = conditionContext[i];
      final condition = list[progress];
      final prevVersion = tag.getInt('StatusVersion');

      if (condition.tickCompletion(level, train, tag)) {
        conditionContext[i] = CTag();
        conditionProgress[i] = progress + 1;
        displayLinkUpdateRequested |= i == 0;
      }

      displayLinkUpdateRequested |= i == 0 && prevVersion != tag.getInt('StatusVersion');
    }

    for (final carriage in train.carriages) {
      carriage.storage.tickIdleCargoTracker();
    }
  }

  /// `startCurrentInstruction(level)`.
  DiscoveredPath? startCurrentInstruction(ScheduleLevel level) {
    if (_checkEndOfScheduleReached()) return null;

    final entry = schedule!.entries[currentEntry];
    final instruction = entry.instruction;
    return instruction.start(this, level);
  }

  /// `setSchedule(schedule, auto)`.
  void setSchedule(Schedule schedule, bool auto) {
    reset();
    this.schedule = schedule;
    currentEntry = clampInt(schedule.savedProgress, 0, schedule.entries.length - 1);
    paused = false;
    isAutoSchedule = auto;
    train.status.newSchedule();
    predictionTicks = [];
    for (var i = 0; i < schedule.entries.length; i++) {
      predictionTicks.add(_tbd);
    }
    displayLinkUpdateRequested = true;
  }

  /// `getSchedule()`.
  Schedule? getSchedule() => schedule;

  /// `discardSchedule()`.
  void discardSchedule() {
    train.navigation.cancelNavigation();
    reset();
  }

  /// `reset()`.
  void reset() {
    paused = true;
    completed = false;
    isAutoSchedule = false;
    currentEntry = 0;
    currentTitle = '';
    schedule = null;
    state = State.PRE_TRANSIT;
    conditionProgress = [];
    conditionContext = [];
    predictionTicks = [];
  }

  /// `submitPredictions()`.
  List<TrainDeparturePrediction> submitPredictions() {
    final predictions = <TrainDeparturePrediction?>[];
    final schedule = this.schedule!;
    final entryCount = schedule.entries.length;
    var accumulatedTime = 0;
    final current = currentEntry;

    // Current
    if (state == State.POST_TRANSIT || current >= entryCount) {
      final currentStation = train.getCurrentStation();
      if (currentStation != null) {
        predictions.add(_createPrediction(current, currentStation.name, currentTitle, 0));
      }
      final departureTime = _estimateStayDuration(current);
      if (departureTime == _invalid) {
        accumulatedTime = _invalid;
      } else {
        accumulatedTime += departureTime;
      }
    } else {
      final GlobalStation? destination = train.navigation.destination;
      if (destination != null) {
        final speed = _min(train.throttle * train.maxSpeed(), (train.maxSpeed() + train.maxTurnSpeed()) / 2);
        var timeRemaining = (javaInt(train.navigation.distanceToDestination / speed) * 2).toSigned(32);

        if (predictionTicks.length > current && train.navigation.distanceStartedAt != 0) {
          var predictedTime = toFloat32(predictionTicks[current].toDouble());
          if (predictedTime > 0) {
            predictedTime = toFloat32(
              predictedTime *
                  clampDouble(train.navigation.distanceToDestination / train.navigation.distanceStartedAt, 0, 1),
            );
            timeRemaining = ((timeRemaining + javaInt(predictedTime)) ~/ 2);
          }
        }

        accumulatedTime += timeRemaining;
        predictions.add(_createPrediction(current, destination.name, currentTitle, accumulatedTime));

        final departureTime = _estimateStayDuration(current);
        if (departureTime != _invalid) {
          accumulatedTime += departureTime;
        } else {
          accumulatedTime = _invalid;
        }
      } else {
        // (the Java call ignores the returned time)
        _predictForEntry(current, currentTitle, accumulatedTime, predictions);
      }
    }

    // Upcoming
    var title = currentTitle;
    for (var i = 1; i < entryCount; i++) {
      final index = (i + current) % entryCount;
      if (index == 0 && !schedule.cyclic) break;

      final instruction = schedule.entries[index].instruction;
      if (instruction is ChangeTitleInstruction) {
        title = instruction.getScheduleTitle();
        continue;
      }

      accumulatedTime = _predictForEntry(index, title, accumulatedTime, predictions);
    }

    return [for (final p in predictions) ?p];
  }

  static double _min(double a, double b) => a < b ? a : b;

  int _predictForEntry(
    int index,
    String currentTitle,
    int accumulatedTime,
    List<TrainDeparturePrediction?> predictions,
  ) {
    final entry = schedule!.entries[index];
    final filter = entry.instruction;
    if (filter is! DestinationInstruction) return accumulatedTime;
    if (predictionTicks.length <= currentEntry) return accumulatedTime;

    final departureTime = _estimateStayDuration(index);

    if (accumulatedTime < 0) {
      predictions.add(_createPrediction(index, filter.getFilter(), currentTitle, accumulatedTime));
      return accumulatedTime < departureTime ? accumulatedTime : departureTime;
    }

    final predictedTime = predictionTicks[index];
    accumulatedTime += predictedTime;

    if (predictedTime == _tbd) accumulatedTime = _tbd;

    predictions.add(_createPrediction(index, filter.getFilter(), currentTitle, accumulatedTime));

    if (accumulatedTime != _tbd) accumulatedTime += departureTime;

    if (departureTime == _invalid) accumulatedTime = _invalid;

    return accumulatedTime;
  }

  int _estimateStayDuration(int index) {
    final schedule = this.schedule!;
    if (index >= schedule.entries.length) {
      if (!schedule.cyclic) return _invalid;
      index = 0;
    }

    final scheduleEntry = schedule.entries[index];
    columns:
    for (final list in scheduleEntry.conditions) {
      var total = 0;
      for (final condition in list) {
        if (condition is! ScheduledDelay) continue columns;
        total += condition.totalWaitTicks();
      }
      return total;
    }

    return _invalid;
  }

  TrainDeparturePrediction? _createPrediction(int index, String destination, String currentTitle, int time) {
    if (time == _invalid) return null;

    final schedule = this.schedule!;
    final size = schedule.entries.length;
    if (index >= size) {
      if (!schedule.cyclic) {
        return TrainDeparturePrediction(train, time, Txt.space(), destination);
      }
      index %= size;
    }

    var text = currentTitle;
    if (text.trim().isEmpty) {
      for (var i = 1; i < size; i++) {
        final j = (index + i) % size;
        final scheduleEntry = schedule.entries[j];
        final instruction = scheduleEntry.instruction;
        if (instruction is! DestinationInstruction) continue;
        text = instruction.getFilter().replaceAll('*', '').trim();
        break;
      }
    }

    return TrainDeparturePrediction(train, time, Txt.literal(text), destination);
  }

  /// `write(registries)`.
  CTag write() {
    final tag = CTag();
    tag.putInt('CurrentEntry', currentEntry);
    tag.putBoolean('AutoSchedule', isAutoSchedule);
    tag.putBoolean('Paused', paused);
    tag.putBoolean('Completed', completed);
    final current = schedule;
    if (current != null) tag.putCompound('Schedule', current.write());
    tag.putString('State', state.name);
    tag.putIntArray('ConditionProgress', conditionProgress);
    tag.putCompoundList('ConditionContext', [for (final c in conditionContext) c.copy()]);
    tag.putIntArray('TransitTimes', predictionTicks);
    return tag;
  }

  /// `read(registries, tag)`.
  void read(CTag tag) {
    reset();
    paused = tag.getBooleanOr('Paused', false);
    completed = tag.getBooleanOr('Completed', false);
    isAutoSchedule = tag.getBooleanOr('AutoSchedule', false);
    currentEntry = tag.getInt('CurrentEntry') < 0 ? 0 : tag.getInt('CurrentEntry');
    if (tag.contains('Schedule')) schedule = Schedule.fromTag(tag.getCompound('Schedule'));
    state = _readEnum(tag, 'State');
    for (final i in tag.getIntArray('ConditionProgress')) {
      conditionProgress.add(i);
    }
    for (final c in tag.getCompoundList('ConditionContext')) {
      conditionContext.add(c);
    }

    final readTransits = tag.getIntArray('TransitTimes');
    final loaded = schedule;
    if (loaded != null) {
      for (var i = 0; i < loaded.entries.length; i++) {
        predictionTicks.add(_tbd);
      }
      if (readTransits.length == loaded.entries.length) {
        for (var i = 0; i < readTransits.length; i++) {
          predictionTicks[i] = readTransits[i];
        }
      }
    }
  }

  /// `returnSchedule(registries)`: takes the schedule off the train. Returns the schedule tag for a
  /// new schedule item (`stack.set(TRAIN_SCHEDULE, ...)`), or `null` when there was no schedule or
  /// it was an automatic one (no item comes back).
  CTag? returnSchedule() {
    final current = schedule;
    if (current == null) return null;
    current.savedProgress = currentEntry;
    final stack = current.write();
    final result = isAutoSchedule ? null : stack;
    discardSchedule();
    return result;
  }

  /// `getWaitingStatus(level)`.
  Txt getWaitingStatus(ScheduleLevel level) {
    final conditions = schedule!.entries[currentEntry].conditions;
    if (conditions.isEmpty || conditionProgress.isEmpty || conditionContext.isEmpty) return Txt.empty();

    final list = conditions[0];
    final progress = conditionProgress[0];
    if (progress >= list.length) return Txt.empty();

    final tag = conditionContext[0];
    final ScheduleWaitCondition condition = list[progress];
    return condition.getWaitingStatus(level, train, tag);
  }

  static State _readEnum(CTag tag, String key) {
    final name = tag.getString(key);
    for (final e in State.values) {
      if (e.name == name) return e;
    }
    return State.values.first;
  }
}
