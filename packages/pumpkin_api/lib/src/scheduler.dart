import 'bindings.g.dart' as wit;
import 'bindings.g.dart' show Context, Server;
import 'registry.dart';

/// Code that runs on the server's tick loop.
typedef TaskHandler = void Function(Server server);

final taskHandlers = HandlerRegistry<TaskHandler>();

/// A task scheduled with [SchedulerApi.runLater] or
/// [SchedulerApi.runRepeating].
final class ScheduledTask {
  final int _taskId;
  final int _handlerId;

  ScheduledTask._(this._taskId, this._handlerId);

  /// Stops the task. Does nothing if it already ran or was cancelled.
  void cancel() {
    wit.scheduler.cancelTask(taskId: _taskId);
    taskHandlers.remove(_handlerId);
  }
}

/// Schedules closures to run on the server's tick loop (20 ticks per second).
extension SchedulerApi on Server {
  /// Runs [task] once, after [delayTicks] ticks.
  ScheduledTask runLater(int delayTicks, TaskHandler task) =>
      _runLater(delayTicks, task);

  /// Runs [task] every [periodTicks] ticks, starting after [delayTicks].
  ScheduledTask runRepeating(
    int periodTicks,
    TaskHandler task, {
    int delayTicks = 0,
  }) => _runRepeating(delayTicks, periodTicks, task);
}

/// Same as [SchedulerApi], available while the plugin is loading.
extension ContextSchedulerApi on Context {
  ScheduledTask runLater(int delayTicks, TaskHandler task) =>
      _runLater(delayTicks, task);

  ScheduledTask runRepeating(
    int periodTicks,
    TaskHandler task, {
    int delayTicks = 0,
  }) => _runRepeating(delayTicks, periodTicks, task);
}

ScheduledTask _runLater(int delayTicks, TaskHandler task) {
  final handlerId = taskHandlers.add(task);
  final taskId = wit.scheduler.scheduleDelayedTask(
    handlerId: handlerId,
    delayTicks: delayTicks,
  );
  return ScheduledTask._(taskId, handlerId);
}

ScheduledTask _runRepeating(int delayTicks, int periodTicks, TaskHandler task) {
  final handlerId = taskHandlers.add(task);
  final taskId = wit.scheduler.scheduleRepeatingTask(
    handlerId: handlerId,
    delayTicks: delayTicks,
    periodTicks: periodTicks,
  );
  return ScheduledTask._(taskId, handlerId);
}
