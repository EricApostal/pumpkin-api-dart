// Binding-free building blocks of the plugin infrastructure (lifecycle, IPC).
// Kept free of host imports so they can be unit-tested on the Dart VM; the
// public wrappers live in lifecycle.dart, ipc.dart and channels.dart.
import 'dart:async';
import 'dart:convert';

/// Where infrastructure errors go when no logger is given. `print` ends up in
/// the server log.
void defaultErrorSink(String message) => print(message);

/// Something that can release resources.
abstract interface class Disposable {
  /// Releases the resource. Calling it again does nothing.
  void dispose();
}

/// A handle to something that can be cancelled: a listener, a timer, a
/// registered handler. Also a [Disposable], so it can be added to a
/// [DisposableBag].
final class Subscription implements Disposable {
  void Function()? _onCancel;

  /// Creates a handle that runs [onCancel] once when cancelled.
  Subscription(void Function() onCancel) : _onCancel = onCancel;

  /// Whether [cancel] was called.
  bool get isCancelled => _onCancel == null;

  /// Cancels this subscription. Does nothing if it was cancelled already.
  void cancel() {
    final fn = _onCancel;
    if (fn == null) return;
    _onCancel = null;
    fn();
  }

  @override
  void dispose() => cancel();
}

/// Collects cleanups and runs them together, in reverse order of adding.
///
/// ```dart
/// final bag = DisposableBag();
/// bag.addTimer(Timer.periodic(Duration(seconds: 5), (_) => save()));
/// bag.addCallback(() => logger.info('bye'));
/// bag.dispose(); // runs the callback, then cancels the timer
/// ```
final class DisposableBag implements Disposable {
  /// Receives a description of each cleanup that threw.
  final void Function(String message) onError;

  final List<void Function()> _items = [];

  DisposableBag({this.onError = defaultErrorSink});

  /// How many cleanups are waiting.
  int get length => _items.length;

  /// Whether nothing is waiting.
  bool get isEmpty => _items.isEmpty;

  /// Adds [fn]. The returned [Subscription] removes it again without running
  /// it when cancelled.
  Subscription addCallback(void Function() fn) {
    _items.add(fn);
    return Subscription(() => _items.remove(fn));
  }

  /// Adds [disposable] and returns it.
  T add<T extends Disposable>(T disposable) {
    _items.add(disposable.dispose);
    return disposable;
  }

  /// Cancels [timer] on dispose.
  Timer addTimer(Timer timer) {
    _items.add(timer.cancel);
    return timer;
  }

  /// Cancels [subscription] on dispose.
  StreamSubscription<T> addStreamSubscription<T>(
    StreamSubscription<T> subscription,
  ) {
    _items.add(() {
      subscription.cancel();
    });
    return subscription;
  }

  /// Runs every cleanup, newest first, and empties the bag. A cleanup that
  /// throws is reported to [onError] and does not stop the others. The bag can
  /// be used again afterwards.
  @override
  void dispose() {
    final items = _items.reversed.toList();
    _items.clear();
    for (final fn in items) {
      try {
        fn();
      } catch (e, s) {
        onError('Error while disposing: $e\n$s');
      }
    }
  }
}

/// Cleanup callbacks that run when the plugin unloads.
final class UnloadHooks {
  final List<FutureOr<void> Function()> _hooks = [];

  /// Registers [hook]. The returned [Subscription] removes it.
  Subscription add(FutureOr<void> Function() hook) {
    _hooks.add(hook);
    return Subscription(() => _hooks.remove(hook));
  }

  /// How many hooks are registered.
  int get length => _hooks.length;

  /// Runs all hooks, newest first. Each is guarded: a failure is passed to
  /// [onError] and the rest still run. Async hooks are awaited one after the
  /// other. Returns a future only if some hook was asynchronous. Hooks are
  /// consumed: running twice does nothing the second time.
  FutureOr<void> run(void Function(String message) onError) {
    final hooks = _hooks.reversed.toList();
    _hooks.clear();
    return _runFrom(hooks, 0, onError);
  }

  static FutureOr<void> _runFrom(
    List<FutureOr<void> Function()> hooks,
    int start,
    void Function(String) onError,
  ) {
    for (var i = start; i < hooks.length; i++) {
      try {
        final result = hooks[i]();
        if (result is Future<void>) {
          return result
              .catchError((Object e, StackTrace s) {
                onError('Error in unload hook: $e\n$s');
              })
              .then((_) => _runFrom(hooks, i + 1, onError));
        }
      } catch (e, s) {
        onError('Error in unload hook: $e\n$s');
      }
    }
  }
}

/// Why an IPC call failed.
enum IpcFailure {
  /// The recipient plugin is not loaded.
  pluginNotFound,

  /// The recipient plugin received the message and refused or failed it.
  rejected,

  /// The message or the reply could not be encoded or decoded.
  badPayload,
}

/// An IPC call failed. See [reason].
final class IpcException implements Exception {
  final IpcFailure reason;
  final String message;

  /// The plugin that was addressed, if known.
  final String? recipient;

  const IpcException(this.reason, this.message, {this.recipient});

  @override
  String toString() => 'IpcException(${reason.name}): $message';
}

/// Encodes [value] as UTF-8 JSON, throwing [IpcException] if impossible.
List<int> encodeJsonPayload(Object? value) {
  try {
    return utf8.encode(jsonEncode(value));
  } on Object catch (e) {
    throw IpcException(IpcFailure.badPayload, 'Cannot encode payload: $e');
  }
}

/// Decodes UTF-8 JSON. An empty payload is `null`.
Object? decodeJsonPayload(List<int> bytes) {
  if (bytes.isEmpty) return null;
  try {
    return jsonDecode(utf8.decode(bytes));
  } on Object catch (e) {
    throw IpcException(IpcFailure.badPayload, 'Payload is not valid JSON: $e');
  }
}

/// Builds the `{"type": ..., "data": ...}` envelope used by typed channels.
List<int> encodeEnvelope(String type, Object? data) =>
    encodeJsonPayload({'type': type, 'data': data});

/// Handles one message type. Returns the reply (JSON-encodable, or null).
typedef IpcHandler = Object? Function(String sender, Object? data);

/// Handles messages that are not typed envelopes.
typedef RawIpcHandler = List<int> Function(String sender, List<int> bytes);

/// Handlers for incoming IPC messages, by message type.
final class IpcHandlerRegistry {
  final Map<String, IpcHandler> _handlers = {};

  /// Called for messages that are not envelopes, or whose type has no
  /// handler. Without it those messages are rejected.
  RawIpcHandler? fallback;

  /// Whether anything can handle a message.
  bool get hasHandlers => _handlers.isNotEmpty || fallback != null;

  /// The registered type names.
  Iterable<String> get types => _handlers.keys;

  /// Registers [handler] for [type]. Throws [StateError] if taken. The
  /// returned [Subscription] unregisters it.
  Subscription register(String type, IpcHandler handler) {
    if (_handlers.containsKey(type)) {
      throw StateError('An IPC handler for "$type" is already registered');
    }
    _handlers[type] = handler;
    return Subscription(() {
      if (identical(_handlers[type], handler)) _handlers.remove(type);
    });
  }

  /// Dispatches an incoming message and returns the reply bytes. Throws
  /// [IpcException] for payloads nobody can handle; exceptions thrown by a
  /// handler propagate (the host reports them to the sender).
  List<int> handle(String sender, List<int> bytes) {
    Object? decoded;
    var isJson = true;
    try {
      decoded = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } on Object {
      isJson = false;
    }
    if (isJson && decoded is Map && decoded['type'] is String) {
      final type = decoded['type'] as String;
      final handler = _handlers[type];
      if (handler != null) {
        return encodeJsonPayload(handler(sender, decoded['data']));
      }
      final raw = fallback;
      if (raw != null) return raw(sender, bytes);
      throw IpcException(
        IpcFailure.rejected,
        'No handler for message type "$type"',
      );
    }
    final raw = fallback;
    if (raw != null) return raw(sender, bytes);
    throw const IpcException(
      IpcFailure.badPayload,
      'Message is not a {"type", "data"} envelope',
    );
  }
}
