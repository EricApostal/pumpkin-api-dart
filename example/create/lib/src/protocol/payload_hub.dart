// The host independent core of the payload bus (pure): handler table, size and
// decode checks, rate-limited logging, exception containment. The host glue
// (`payload_bus.dart`) adds players, worlds and the transport.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../core/payload.dart';
import '../manifest/types_network.dart';
import 'codec_compiler.dart';

/// Marks an incoming payload that was dropped (the reason is already logged).
final class BadPayload {
  final String reason;

  const BadPayload(this.reason);

  @override
  String toString() => 'BadPayload($reason)';
}

/// Log levels used by the protocol layer.
enum ProtocolLogLevel { debug, warn, error }

typedef ProtocolLogSink = void Function(ProtocolLogLevel level, String message);

/// Logs at most [maxPerWindow] messages per key and window, then counts the rest
/// and reports "N suppressed" with the next message after the window.
final class RateLimitedLog {
  final ProtocolLogSink sink;
  final int maxPerWindow;
  final int windowMillis;
  final int Function() _nowMillis;
  final Map<String, _Bucket> _buckets = {};

  RateLimitedLog(this.sink, {this.maxPerWindow = 3, this.windowMillis = 10000, int Function()? nowMillis})
    : _nowMillis = nowMillis ?? _wallClock;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _wallClock() => _clock.elapsedMilliseconds;

  void log(ProtocolLogLevel level, String key, String message) {
    final now = _nowMillis();
    final b = _buckets.putIfAbsent(key, () => _Bucket(now));
    if (now - b.start >= windowMillis) {
      if (b.suppressed > 0) sink(level, '$key: ${b.suppressed} similar message(s) suppressed');
      b
        ..start = now
        ..count = 0
        ..suppressed = 0;
    }
    if (b.count < maxPerWindow) {
      b.count++;
      sink(level, message);
    } else {
      b.suppressed++;
    }
    if (_buckets.length > 512) _buckets.removeWhere((_, v) => now - v.start >= windowMillis * 6);
  }

  void warn(String key, String message) => log(ProtocolLogLevel.warn, key, message);
  void error(String key, String message) => log(ProtocolLogLevel.error, key, message);
  void debug(String key, String message) => log(ProtocolLogLevel.debug, key, message);
}

final class _Bucket {
  int start;
  int count = 0;
  int suppressed = 0;

  _Bucket(this.start);
}

/// The vanilla limit of a clientbound custom payload.
const int maxClientboundPayloadBytes = 1048576;

/// Create's biggest serverbound payload is a schematic chunk; vanilla itself caps
/// serverbound custom payloads at 32767 bytes, this bound is a safety net.
const int defaultMaxServerboundPayloadBytes = 1 << 20;

/// Registers all manifest payloads as channels of [payloads] in manifest order
/// (`required`, version `1`, play phase), wiring the serverbound ones to [hub].
void registerPayloadChannels<C extends Object>(PayloadRegistry<C> payloads, PayloadHub<C> hub) {
  for (final schema in hub.schemas.all) {
    final id = schema.id;
    final codec = PayloadCodec<Object?>.of(
      encode: (v) => schema.encode(v as Map<String, Object?>),
      decode: (bytes) => hub.decodeIncoming(id, bytes),
    );
    if (schema.direction == NetDirection.serverbound) {
      payloads.serverbound<Object?>(id, codec, (player, value) => hub.dispatch(id, player, value));
    } else {
      payloads.clientbound<Object?>(id, codec);
    }
  }
}

/// Handlers, decoding and containment for serverbound payloads; encoding with
/// validation for clientbound ones. [P] is the player type.
final class PayloadHub<P extends Object> {
  final PayloadSchemas schemas;
  final RateLimitedLog log;
  final String Function(P player) describePlayer;
  final int maxServerboundBytes;
  final Map<String, List<void Function(P player, Map<String, Object?> fields)>> _handlers = {};

  PayloadHub({
    required this.schemas,
    required ProtocolLogSink sink,
    required this.describePlayer,
    this.maxServerboundBytes = defaultMaxServerboundPayloadBytes,
    RateLimitedLog? rateLimitedLog,
  }) : log = rateLimitedLog ?? RateLimitedLog(sink);

  /// Adds a handler for the serverbound payload [id]. Several handlers per id run in
  /// registration order; each is isolated from the others' exceptions.
  void onServerbound(String id, void Function(P player, Map<String, Object?> fields) handler) {
    final schema = schemas.byId[id] ?? (throw ArgumentError.value(id, 'id', 'is not a Create payload'));
    if (schema.direction != NetDirection.serverbound) {
      throw ArgumentError.value(id, 'id', 'is a clientbound payload');
    }
    (_handlers[id] ??= []).add(handler);
  }

  /// Decode used by the channel codec: never throws, returns a [BadPayload] instead
  /// (oversized, malformed, trailing bytes) and logs it rate-limited.
  Object decodeIncoming(String id, List<int> data) {
    if (data.length > maxServerboundBytes) {
      return BadPayload('payload of ${data.length} bytes is larger than $maxServerboundBytes');
    }
    final schema = schemas.byId[id];
    if (schema == null) return const BadPayload('unknown payload');
    try {
      return schema.decode(data);
    } on PacketException catch (e) {
      return BadPayload(e.message);
    } on Object catch (e) {
      return BadPayload('$e');
    }
  }

  /// Runs the handlers for a value from [decodeIncoming]. Never throws.
  FutureOr<void> dispatch(String id, P player, Object? value) {
    if (value is BadPayload) {
      log.warn('bad:$id', 'Dropped a payload on $id from ${_who(player)}: ${value.reason}');
      return null;
    }
    final handlers = _handlers[id];
    if (handlers == null || handlers.isEmpty) {
      log.debug('unhandled:$id', 'No handler for $id');
      return null;
    }
    final fields = value as Map<String, Object?>;
    for (final handler in List.of(handlers)) {
      try {
        final result = (handler as dynamic)(player, fields);
        if (result is Future) {
          unawaited(result.then<void>((_) {}, onError: (Object e, StackTrace s) => _handlerFailed(id, player, e)));
        }
      } on Object catch (e) {
        _handlerFailed(id, player, e);
      }
    }
    return null;
  }

  void _handlerFailed(String id, P player, Object error) =>
      log.error('handler:$id', 'Handler of $id failed for ${_who(player)}: $error');

  String _who(P player) {
    try {
      return describePlayer(player);
    } on Object {
      return '<unknown player>';
    }
  }

  /// Decodes [bytes] of payload [id] (any direction), throwing on bad data.
  Map<String, Object?> decode(String id, Uint8List bytes) => schemas[id].decode(bytes);

  /// Encodes [fields] of payload [id], throwing on bad data.
  Uint8List encode(String id, Map<String, Object?> fields) => schemas[id].encode(fields);

  /// The bytes to send for clientbound [id], or null (logged) when the payload is
  /// invalid, serverbound, or larger than the vanilla limit.
  Uint8List? encodeClientbound(String id, Map<String, Object?> fields) {
    final schema = schemas.byId[id];
    if (schema == null || schema.direction != NetDirection.clientbound) {
      log.error('send:$id', '$id is not a clientbound Create payload');
      return null;
    }
    try {
      final bytes = schema.encode(fields);
      if (bytes.length > maxClientboundPayloadBytes) {
        log.error('send:$id', 'Payload $id of ${bytes.length} bytes exceeds the limit of $maxClientboundPayloadBytes, not sent');
        return null;
      }
      return bytes;
    } on Object catch (e) {
      log.error('send:$id', 'Could not encode $id: $e');
      return null;
    }
  }
}
