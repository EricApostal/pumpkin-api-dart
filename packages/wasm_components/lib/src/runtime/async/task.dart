import 'dart:async';
import 'dart:collection';
// ignore: import_internal_library
import 'dart:_wasm';

import '../resource.dart';
import 'waitable.dart';

@pragma('wasm:import', 'component.canon.context.set_i32_0')
external WasmVoid _contextSet(WasmI32 context);

@pragma('wasm:import', 'component.canon.context.get_i32_0')
external WasmI32 _contextGet();

// Subtask states, the low four bits of the status of a call to an async import.
const _subtaskStarting = 0;
const _subtaskStarted = 1;
const _subtaskReturned = 2;

// Events passed to the callback.
const _eventSubtask = 1;

// Return codes of the callback.
const _callbackExit = 0;
const _callbackYield = 1;
const _callbackWait = 2;

/// One call from the host into an async-lifted export.
///
/// The component model runs these concurrently: while one task waits for a host
/// call to finish, the host may start others. Dart has a single thread, so all
/// of them share one microtask queue. What belongs to a task is the list of host
/// calls it waits for (its subtasks), which decides when it may return, and the
/// resources it received.
final class AsyncTask {
  /// The task the Dart code that is running right now belongs to, if any.
  static AsyncTask? get current => _current;

  final int _id;

  /// For error messages.
  final String debugName;

  final Map<int, _Subtask<Object?>> _subtasks = {};
  final List<bool Function()> _idleHooks = [];
  WaitableSet? _set;
  ResourceScope? _scope;
  bool _bodyDone = false;
  void Function()? _completion;
  Object? _error;
  StackTrace? _stackTrace;

  AsyncTask._(this._id, this.debugName);

  /// Whether the export this task runs has produced its result.
  bool get isDone => _bodyDone;

  /// Called by the generated code with the call of `task.return`, once the
  /// result is lowered. The call is made when the task is over: all its host
  /// calls have finished and the handles it received are dropped. The server
  /// takes the handles it gave a task back when the call ends, so a handle
  /// dropped after `task.return` would not exist anymore.
  void complete(void Function() taskReturn) {
    _completion = taskReturn;
  }

  /// The number of host calls this task waits for.
  int get pendingHostCalls => _subtasks.length;

  /// Registers [hook] to be called when everything this task does is waiting for
  /// something other than a host call, such as a timer or a future that another
  /// task completes. A task can only finish while it is the one running, so the
  /// hook gets the chance to make the export return (by completing the future
  /// it awaits). It returns whether it did anything.
  ///
  /// Without a hook that does something, the task keeps yielding to the host.
  void onIdle(bool Function() hook) {
    _idleHooks.add(hook);
  }

  WaitableSet get _waitableSet => _set ??= WaitableSet();
}

final class _Subtask<T> {
  final int handle;
  final List<void Function()>? _cleanups;
  final T Function() _lift;
  final Completer<T> completer;
  bool _cleaned = false;

  _Subtask(this.handle, this._cleanups, this._lift, this.completer);

  /// Frees the buffers the arguments were lowered into, once the host has read
  /// them.
  void releaseArguments() {
    if (_cleaned) return;
    _cleaned = true;
    final cleanups = _cleanups;
    if (cleanups == null) return;
    for (final cleanup in cleanups) {
      cleanup();
    }
  }

  void complete() {
    releaseArguments();
    try {
      completer.complete(_lift());
    } catch (e, s) {
      completer.completeError(e, s);
    }
  }
}

AsyncTask? _current;
var _nextTaskId = 1;
final Map<int, AsyncTask> _tasks = {};

final Queue<_Microtask> _microtasks = Queue();

final class _Microtask {
  final Zone zone;
  final void Function() callback;

  _Microtask(this.zone, this.callback);
}

/// Runs queued microtasks until none is left. Also called by layers that add
/// their own work, see [onDrain].
void drainMicrotasks() {
  while (true) {
    while (_microtasks.isNotEmpty) {
      final entry = _microtasks.removeFirst();
      entry.zone.runGuarded(entry.callback);
    }
    // Hooks may queue more work.
    final hook = onDrain;
    if (hook == null || !hook()) return;
  }
}

/// Called whenever the microtask queue is empty. Returns whether it queued more
/// work, which is run before the task yields to the host.
bool Function()? onDrain;

/// The zone the async exports run in. Anything that needs to run later, like
/// the continuation of an `await`, is queued and run before the host call
/// returns or, for work that waits for the host, from the callback.
final Zone _taskZone = Zone.root.fork(
  specification: ZoneSpecification(
    scheduleMicrotask: (self, parent, zone, f) {
      _microtasks.add(_Microtask(zone, f));
    },
    handleUncaughtError: (self, parent, zone, error, stackTrace) {
      // Errors of an export's body are reported by the task itself.
      // ignore: avoid_print
      print('Uncaught error: $error\n$stackTrace');
    },
  ),
);

/// Starts the body of an async-lifted export, as a new task, and returns the
/// code its core function returns to the host.
///
/// [body] lifts the arguments, calls the plugin and lowers the result into
/// `task.return`. It runs until it has to wait. Awaiting a host call then makes
/// the host call the [callback] again once that has finished.
WasmI32 spawnAsyncExport(
  String debugName,
  Future<void> Function(AsyncTask task) body,
) {
  final task = AsyncTask._(_nextTaskId++, debugName);
  _tasks[task._id] = task;
  _contextSet(WasmI32.fromInt(task._id));
  // Tasks interleave, so the scope is only the current one while the task runs.
  task._scope = ResourceScope.detached();

  return _runIteration(task, () {
    _taskZone.run(() {
      body(task).then<void>(
        (_) {
          task._bodyDone = true;
        },
        onError: (Object error, StackTrace stackTrace) {
          task._bodyDone = true;
          task._error = error;
          task._stackTrace = stackTrace;
        },
      );
    });
  });
}

/// Called by the host with the event a task that returned `wait` was woken by.
WasmI32 resumeAsyncTask(WasmI32 eventCode, WasmI32 p1, WasmI32 p2) {
  final id = _contextGet().toIntUnsigned();
  final task = _tasks[id];
  if (task == null) {
    throw StateError('The host woke the unknown task $id.');
  }

  final event = eventCode.toIntUnsigned();
  return _runIteration(task, () {
    if (event == _eventSubtask) {
      _subtaskEvent(task, p1.toIntUnsigned(), p2.toIntUnsigned());
    }
    // Other events (_eventNone after a yield) only give the task a turn.
  });
}

void _subtaskEvent(AsyncTask task, int handle, int state) {
  final subtask = task._subtasks[handle];
  if (subtask == null) return;
  switch (state) {
    case _subtaskStarted:
      subtask.releaseArguments();
    case _subtaskReturned:
      task._subtasks.remove(handle);
      dropSubtask(handle);
      subtask.complete();
    default:
      // Cancelled states can't happen, plugins never cancel a call.
      task._subtasks.remove(handle);
      dropSubtask(handle);
      subtask.completer.completeError(
        StateError('The host call of ${task.debugName} was cancelled.'),
      );
  }
}

/// Runs [step] as part of [task], then everything it unblocks, and decides what
/// the task does next.
WasmI32 _runIteration(AsyncTask task, void Function() step) {
  final previousTask = _current;
  _current = task;
  final scope = task._scope!;
  try {
    scope.run(() {
      step();
      drainMicrotasks();

      // Nothing is left that can run, but the export may still be waiting for
      // something that is not a host call.
      while (!task._bodyDone && task._subtasks.isEmpty) {
        var progress = false;
        for (final hook in List.of(task._idleHooks)) {
          if (hook()) progress = true;
        }
        if (!progress) break;
        drainMicrotasks();
      }
    });
  } finally {
    _current = previousTask;
  }

  if (task._bodyDone && task._error != null) {
    // The export failed before it returned, nobody knows what to return to the
    // host. Trap, the host reports it and ends the task. Print the error first:
    // the trap only carries a wasm backtrace, which names no Dart frames.
    // ignore: avoid_print
    print(
      '${task.debugName} failed: ${task._error}\n${task._stackTrace}',
    );
    _finish(task);
    Error.throwWithStackTrace(task._error!, task._stackTrace!);
  }

  if (task._subtasks.isNotEmpty) {
    return WasmI32.fromInt(_callbackWait | (task._waitableSet.nativeId << 4));
  }
  if (task._bodyDone) {
    _finish(task);
    return WasmI32.fromInt(_callbackExit);
  }
  // Waiting for something this component can't tell the host about.
  return WasmI32.fromInt(_callbackYield);
}

void _finish(AsyncTask task) {
  _tasks.remove(task._id);
  task._set?.drop();
  task._set = null;
  // The handles go before the result: see [AsyncTask.complete].
  task._scope?.exit();
  task._scope = null;
  final completion = task._completion;
  task._completion = null;
  completion?.call();
}

/// Waits for the call to an async import whose status word is [status].
///
/// [cleanups] free what the arguments were lowered into. They run when the host
/// has read them, which may only be later. [lift] reads the results from where the
/// host stored them, once the call has returned.
Future<T> awaitSubtask<T>(
  int status,
  List<void Function()> cleanups,
  T Function() lift,
) {
  final state = status & 0xf;
  final handle = status >> 4;

  if (state == _subtaskReturned) {
    for (final cleanup in cleanups) {
      cleanup();
    }
    try {
      return Future<T>.value(lift());
    } catch (e, s) {
      return Future<T>.error(e, s);
    }
  }

  final task = _current;
  if (task == null) {
    throw StateError(
      'This host call does not finish right away, and can only be waited for '
      'from an async callback.',
    );
  }

  final subtask = _Subtask<T>(handle, cleanups, lift, Completer<T>());
  task._subtasks[handle] = subtask;
  task._waitableSet.join(handle);
  if (state != _subtaskStarting) subtask.releaseArguments();
  return subtask.completer.future;
}
