import 'package:wasm_components/wasm_components.dart' show OkResult, ErrorResult;

import 'bindings.g.dart' show Ipc, ipc;
import 'infra_core.dart';

export 'infra_core.dart'
    show IpcException, IpcFailure, IpcHandler, RawIpcHandler, IpcHandlerRegistry;

/// The handlers for messages other plugins send to this one. Register typed
/// ones through [IpcChannel.handle].
final IpcHandlerRegistry ipcHandlers = IpcHandlerRegistry();

/// Handles an incoming message by dispatching to [ipcHandlers] and returns
/// the reply bytes. Throws [IpcException] if nobody can handle it. The plugin
/// dispatcher calls this from `Plugin.onMessage`'s default implementation.
List<int> handleIpc(String sender, List<int> bytes) =>
    ipcHandlers.handle(sender, bytes);

/// Nicer IPC calls than the raw `sendIpcMessage`, which returns nested
/// results. Failures throw [IpcException].
///
/// ```dart
/// final reply = ipc.requestJson('economy', {'op': 'balance', 'player': 'Eric'});
/// ```
extension IpcApi on Ipc {
  /// Sends raw [message] to [recipient] and returns its reply.
  ///
  /// Throws [IpcException] with [IpcFailure.pluginNotFound] if the plugin is
  /// not loaded, or [IpcFailure.rejected] if it threw. IPC is synchronous: the
  /// recipient runs before this returns.
  List<int> request(String recipient, List<int> message) {
    final outer = sendIpcMessage(recipient: recipient, message: message);
    switch (outer) {
      case ErrorResult():
        throw IpcException(
          IpcFailure.pluginNotFound,
          'Plugin "$recipient" is not available',
          recipient: recipient,
        );
      case OkResult(value: final inner):
        switch (inner) {
          case OkResult(value: final bytes):
            return bytes;
          case ErrorResult(value: final error):
            throw IpcException(
              IpcFailure.rejected,
              error,
              recipient: recipient,
            );
        }
    }
  }

  /// Sends [value] (anything `jsonEncode` accepts) to [recipient] as JSON and
  /// returns the decoded reply (null for an empty reply).
  Object? requestJson(String recipient, Object? value) =>
      decodeJsonPayload(request(recipient, encodeJsonPayload(value)));

  /// Like [requestJson], ignoring the reply. Still throws if the recipient is
  /// missing or fails.
  void sendJson(String recipient, Object? value) {
    request(recipient, encodeJsonPayload(value));
  }
}

/// A typed message kind plugins can send each other, carried in a
/// `{"type": name, "data": ...}` JSON envelope.
///
/// ```dart
/// final transfer = IpcChannel<Transfer>('economy.transfer',
///     (t) => {'to': t.to, 'amount': t.amount},
///     (json) => Transfer((json as Map)['to'] as String, (json)['amount'] as int));
///
/// // receiving plugin:
/// transfer.handle((sender, t) => {'ok': bank.move(t)});
/// // sending plugin:
/// final reply = transfer.request('economy', Transfer('Eric', 5));
/// ```
final class IpcChannel<T> {
  /// The message type name; must be unique per plugin.
  final String name;

  /// Converts a message to a JSON-encodable value.
  final Object? Function(T value) encode;

  /// Converts the decoded JSON back into a message.
  final T Function(Object? json) decode;

  const IpcChannel(this.name, this.encode, this.decode);

  /// A channel whose messages are plain JSON values.
  static IpcChannel<Object?> json(String name) =>
      IpcChannel<Object?>(name, (v) => v, (v) => v);

  /// Sends [message] to [recipient] and returns the raw decoded reply.
  /// Throws [IpcException].
  Object? request(String recipient, T message) {
    final bytes = ipc.request(recipient, encodeEnvelope(name, _encode(message)));
    return decodeJsonPayload(bytes);
  }

  /// Like [request] but converts the reply with [decodeReply].
  R requestAs<R>(
    String recipient,
    T message,
    R Function(Object? json) decodeReply,
  ) => decodeReply(request(recipient, message));

  /// Sends [message], ignoring the reply.
  void send(String recipient, T message) {
    request(recipient, message);
  }

  /// Handles incoming messages of this type. The returned value (JSON
  /// encodable, or null) is the reply. Throwing reports an error to the
  /// sender. Throws [StateError] if the type already has a handler. Handlers
  /// are synchronous.
  Subscription handle(Object? Function(String sender, T message) handler) =>
      ipcHandlers.register(name, (sender, data) {
        final T message;
        try {
          message = decode(data);
        } on Object catch (e) {
          throw IpcException(IpcFailure.badPayload, 'Bad "$name" payload: $e');
        }
        return handler(sender, message);
      });

  Object? _encode(T message) => encode(message);
}
