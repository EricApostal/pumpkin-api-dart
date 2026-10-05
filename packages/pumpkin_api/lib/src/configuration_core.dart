// Binding-free core of the connection-phase API (login and configuration):
// the connection state machines (hold, awaiting replies, timeouts, closing)
// and the per-registration bookkeeping. Kept free of host imports so it can be
// unit-tested on the Dart VM; configuration.dart connects it to the server
// events and functions.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'packet_buffer.dart';

/// A connection-phase call failed: the server refused it (the connection is
/// gone or in another phase) or it was misused.
class ConfigurationException implements Exception {
  final String message;

  const ConfigurationException(this.message);

  @override
  String toString() => 'ConfigurationException: $message';
}

/// The connection left the phase: the client finished it, disconnected, or
/// the plugin disconnected or released it. Pending `next`/`query` futures fail
/// with this.
final class ConnectionClosedException extends ConfigurationException {
  /// The id of the connection.
  final int connectionId;

  const ConnectionClosedException(this.connectionId, String message)
    : super(message);

  @override
  String toString() => 'ConnectionClosedException: $message';
}

/// How the play phase of a connection encodes its packets (the host's
/// `connection-flavour`). `vanilla` is the default. A connection that a mod
/// loader classified as a NeoForge one (it received the `neoforge:register`
/// query before the brand) expects a few packets with extra fields: marking the
/// connection `neoforge` makes the host write them. Set it with
/// [ConfigurationConnection.setFlavour], only for clients that really got and
/// answered the query.
enum ConnectionFlavour {
  vanilla,
  neoforge;

  /// The name of this case in the WIT.
  String get wireName => name;
}

/// The point of the configuration phase a [ConfigurationConnection] is at.
/// The server can hold the connection at each of them (see
/// [ConfigurationConnection.stage]).
enum ConfigurationStage {
  /// Right after login was acknowledged, **before** the server's
  /// `minecraft:brand`. Only reached when the registration has a pre-brand
  /// handler. A release here lets the server send the brand and move on to
  /// [start].
  preBrand,

  /// After the brand, before the resource pack, registries and tags. A
  /// release continues the configuration.
  start,

  /// After the registries and tags, right before "finish configuration". A
  /// release sends "finish configuration".
  finish,
}

/// What a [ConfigurationConnection] needs from the server. The real
/// implementation calls the `server` resource; tests use a fake.
abstract interface class ConfigurationTransport {
  /// Sends a custom payload. Throws a [ConfigurationException] if the server
  /// refuses.
  void sendPayload(int connectionId, String channel, Uint8List data);

  /// Sends a raw clientbound configuration packet (body without id/length).
  void sendPacket(int connectionId, int packetId, Uint8List payload);

  /// Continues a held configuration (whichever hold is active).
  void release(int connectionId);

  /// Marks the connection with the encoding flavour of its play phase.
  void setFlavour(int connectionId, ConnectionFlavour flavour);

  /// Disconnects the client.
  void disconnect(int connectionId, String reason);
}

/// What a [LoginConnection] needs from the server.
abstract interface class LoginTransport {
  /// Sends a login query. Throws a [ConfigurationException] if the server
  /// refuses (for instance when the query id is in use).
  void sendQuery(int connectionId, int queryId, String channel, Uint8List data);

  /// Continues a held login.
  void release(int connectionId);

  /// Disconnects the client.
  void disconnect(int connectionId, String reason);
}

/// The default time the server waits for a held phase to be released.
const Duration defaultHoldTimeout = Duration(seconds: 30);

/// The default time `next` and `query` wait for the client.
const Duration defaultNextTimeout = Duration(seconds: 10);

/// How many messages that nobody waits for yet are kept per key (channel or
/// packet id).
const int maxQueuedPayloadsPerChannel = 32;

/// Login query ids are allocated from here up, far away from the small ids
/// proxies and loaders use (Velocity's modern forwarding uses 0, loaders count
/// up from 0 as well).
const int loginQueryIdBase = 0x40000000;

const int _loginQueryIdEnd = 0x7FFFFFFF;
int _nextLoginQueryId = loginQueryIdBase;

/// Allocates a query id for the login phase, unique within this plugin.
int allocateLoginQueryId() {
  final id = _nextLoginQueryId;
  _nextLoginQueryId = id >= _loginQueryIdEnd ? loginQueryIdBase : id + 1;
  return id;
}

final class _Waiter {
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
  Timer? timer;

  _Waiter() {
    // Closing the connection fails the future; nobody has to await it for
    // that to be fine.
    completer.future.ignore();
  }
}

/// Messages from the client by key (a channel, a packet id, a query id), with
/// waiters in order. Messages nobody waits for are queued when
/// [queueUnclaimed] is set.
final class _Mailbox<K> {
  final bool queueUnclaimed;
  final Map<K, Queue<Uint8List>> _queued = {};
  final Map<K, Queue<_Waiter>> _waiters = {};
  int dropped = 0;

  _Mailbox({required this.queueUnclaimed});

  /// Hands [data] (null: the client has no answer) to the first waiter for
  /// [key], or queues it. Returns whether it was consumed or queued.
  bool deliver(K key, Uint8List? data) {
    final waiting = _waiters[key];
    while (waiting != null && waiting.isNotEmpty) {
      final waiter = waiting.removeFirst();
      if (waiter.completer.isCompleted) continue;
      waiter.timer?.cancel();
      waiter.completer.complete(data);
      return true;
    }
    if (!queueUnclaimed || data == null) return false;
    final queue = _queued.putIfAbsent(key, Queue.new);
    if (queue.length >= maxQueuedPayloadsPerChannel) {
      dropped++;
      return false;
    }
    queue.add(data);
    return true;
  }

  Future<Uint8List?> next(K key, Duration? timeout) {
    final queue = _queued[key];
    if (queue != null && queue.isNotEmpty) {
      return Future.value(queue.removeFirst());
    }
    if (timeout != null && timeout <= Duration.zero) return Future.value(null);

    final waiter = _Waiter();
    final waiting = _waiters.putIfAbsent(key, Queue.new);
    waiting.add(waiter);
    if (timeout != null) {
      waiter.timer = Timer(timeout, () {
        waiting.remove(waiter);
        if (!waiter.completer.isCompleted) waiter.completer.complete(null);
      });
    }
    return waiter.completer.future;
  }

  /// Gives up on a waiter that was just added with [next] (the send failed).
  void abandon(K key, Future<Uint8List?> future) {
    final waiting = _waiters[key];
    if (waiting == null) return;
    for (final waiter in waiting.toList()) {
      if (identical(waiter.completer.future, future)) {
        waiter.timer?.cancel();
        waiting.remove(waiter);
      }
    }
  }

  /// Fails every waiter with [error] and forgets queued messages.
  void fail(Object error) {
    _queued.clear();
    for (final waiting in _waiters.values) {
      for (final waiter in waiting) {
        waiter.timer?.cancel();
        if (!waiter.completer.isCompleted) {
          waiter.completer.completeError(error);
        }
      }
    }
    _waiters.clear();
  }
}

/// A client in a phase of the connection before it joins the world, as seen
/// by a handler registered with `onLogin` or `onConfiguration`: its identity,
/// the hold the server keeps while the handler works, and closing.
///
/// It is plain Dart data plus methods, so it can be kept and used for as long
/// as the handler runs, across `await`s.
abstract base class PhaseConnection {
  /// The server's id of this connection.
  final int id;

  /// The authenticated profile's UUID in canonical form.
  final String uuid;

  final String username;

  /// The Minecraft protocol version the client connected with.
  final int protocolVersion;

  bool _window = false;
  bool _holdPending = false;
  int _holdSeconds = 0;
  bool _holding = false;
  bool _released = false;
  int _epoch = 0;
  bool _ended = false;
  bool _completed = false;
  String _closeReason = 'The connection is closed';
  final Completer<bool> _done = Completer<bool>();

  PhaseConnection._(this.id, this.uuid, this.username, this.protocolVersion);

  /// Whether the server is holding this phase for this registration: a hold
  /// was requested and [release] was not called yet.
  bool get isHeld => _holding && !_ended;

  /// Whether a hold of this connection was released with [release].
  bool get isReleased => _released;

  /// Whether the connection left the phase for any reason.
  bool get isClosed => _ended;

  /// Whether the phase ended successfully (the client finished it, or the
  /// plugin released it where that ends it). Only known once [isClosed].
  bool get completed => _completed;

  /// Completes with [completed] when the connection ends. Never fails.
  Future<bool> get done => _done.future;

  /// How many holds this connection had so far (each hold point is one).
  /// Handlers use it to tell which hold they are responsible for.
  int get holdEpoch => _epoch;

  /// Asks the server to hold this phase after the event that is being
  /// handled, until [release] is called or [timeout] passes (then the client
  /// is disconnected). Rounded up to whole seconds, at least one.
  ///
  /// This only works while that event is being handled, which for
  /// `onLogin`/`onConfiguration` is the `where` callback (or use their
  /// `holdTimeout` parameter). Later it throws a [StateError].
  void hold({Duration timeout = defaultHoldTimeout}) {
    if (!_window) {
      throw StateError(
        'A hold can only be requested while the event is handled (use the '
        'holdTimeout parameter)',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    _holdPending = true;
    _holdSeconds = ((timeout.inMilliseconds + 999) ~/ 1000).clamp(
      1,
      0xFFFFFFFF,
    );
  }

  /// Whether [hold] was requested for the event handled last.
  bool get holdRequested => _holdPending;

  /// The requested hold timeout of the event handled last, in whole seconds
  /// (0 without a hold).
  int get holdTimeoutSeconds => _holdSeconds;

  /// Lets the client continue after a hold. Does nothing if the phase is not
  /// held for this registration. Throws [ConnectionClosedException] if the
  /// connection ended.
  ///
  /// It releases the hold that is active *now*: in the configuration that is
  /// the pre-brand, the start or the finish hold (see
  /// [ConfigurationConnection.stage]), and what the server does next depends
  /// on which one it was.
  void release() {
    _checkOpen();
    if (!_holding) return;
    _sendRelease();
    _holding = false;
    _released = true;
    _afterRelease();
  }

  /// Disconnects the client with [reason], which it shows to the player. Does
  /// nothing if the connection ended already. Pending waits fail.
  void disconnect(String reason) {
    if (_ended) return;
    try {
      _sendDisconnect(reason);
    } finally {
      _finish(completed: false, reason: 'Disconnected by the plugin: $reason');
    }
  }

  // Overridden per phase. ---------------------------------------------------

  void _sendRelease();

  void _sendDisconnect(String reason);

  void _afterRelease() {}

  void _failWaiters(Object error);

  // Called by the sessions. -------------------------------------------------

  void _openHoldWindow() {
    _window = true;
    _holdPending = false;
    _holdSeconds = 0;
  }

  void _closeHoldWindow() {
    _window = false;
    if (_holdPending) {
      _holding = true;
      _released = false;
      _epoch++;
    }
  }

  void _finish({required bool completed, required String reason}) {
    if (_ended) return;
    _ended = true;
    _completed = completed;
    _closeReason = reason;
    _failWaiters(ConnectionClosedException(id, reason));
    _done.complete(completed);
  }

  void _checkOpen() {
    if (_ended) throw ConnectionClosedException(id, _closeReason);
  }
}

/// A client in the configuration phase (after login, before the world is
/// sent), as seen by a handler registered with `Context.onConfiguration`.
///
/// Payloads and packets the client sends are queued from the moment the
/// connection starts, so a reply that arrives before you call [next] is not
/// lost.
final class ConfigurationConnection extends PhaseConnection {
  final ConfigurationTransport _transport;
  final _Mailbox<String> _channels = _Mailbox(queueUnclaimed: true);
  final _Mailbox<int> _packets = _Mailbox(queueUnclaimed: true);
  String? _brand;
  ConfigurationStage _stage = ConfigurationStage.start;
  ConnectionFlavour _flavour = ConnectionFlavour.vanilla;

  ConfigurationConnection({
    required int id,
    required String uuid,
    required String username,
    required int protocolVersion,
    required ConfigurationTransport transport,
  }) : _transport = transport,
       super._(id, uuid, username, protocolVersion);

  /// The client's brand (`vanilla`, `fabric`, `neoforge`, ...) once the
  /// server has received it, otherwise null.
  String? get brand => _brand;

  /// The stage of the configuration this connection is at: [ConfigurationStage.preBrand]
  /// from the pre-brand event until the server sent the brand,
  /// [ConfigurationStage.start] after that, [ConfigurationStage.finish] from
  /// the finish event on. One connection object carries over all stages.
  ConfigurationStage get stage => _stage;

  /// The flavour this plugin gave the connection with [setFlavour]
  /// ([ConnectionFlavour.vanilla] until then).
  ConnectionFlavour get flavour => _flavour;

  /// Marks the connection with the encoding flavour of its play phase: with
  /// [ConnectionFlavour.neoforge] the host writes the few play packets whose
  /// encoding differs on a NeoForge connection (block particles).
  ///
  /// Only call it for a client that was told to be a NeoForge connection, which
  /// is to say that it received the `neoforge:register` query before the brand
  /// (a vanilla client would get bytes it cannot read). It takes effect at
  /// once and can be called until the configuration ended; call it before
  /// [release]ing the pre-brand hold. Throws [ConnectionClosedException] if the
  /// connection ended and a [ConfigurationException] if the server refuses
  /// (the connection is gone or past the configuration).
  void setFlavour(ConnectionFlavour flavour) {
    _checkOpen();
    _transport.setFlavour(id, flavour);
    _flavour = flavour;
  }

  /// How many payloads and packets were dropped because too many arrived
  /// before anybody waited for them.
  int get droppedPayloads => _channels.dropped + _packets.dropped;

  /// Sends [data] to the client on [channel] (`namespace:path`) as a custom
  /// payload. The client must understand the channel, or ignore it.
  ///
  /// Throws [ConnectionClosedException] if the connection ended and a
  /// [ConfigurationException] if the server refuses.
  void send(String channel, List<int> data) {
    _checkChannel(channel);
    _checkOpen();
    _transport.sendPayload(id, channel, _bytes(data));
  }

  /// Tells the client which channels the server receives (a
  /// `minecraft:register` payload). Mod loaders only let the client send
  /// channels announced here, so call it before the client has to answer.
  void announceChannels(Iterable<String> channels) =>
      send(registerChannel, encodeChannelList(channels));

  /// Sends [text] as UTF-8.
  void sendString(String channel, String text) =>
      send(channel, PayloadCodecs.utf8Text.encode(text));

  /// Sends [value] encoded with [codec].
  void sendTyped<T>(String channel, PayloadCodec<T> codec, T value) =>
      send(channel, codec.encode(value));

  /// Sends a raw clientbound configuration packet: [payload] is the body
  /// without the packet id and length prefix. This is how a loader's own
  /// configuration packets are sent.
  void sendPacket(int packetId, List<int> payload) {
    _checkOpen();
    _transport.sendPacket(id, packetId, _bytes(payload));
  }

  /// Waits for the next payload the client sends on [channel], including one
  /// that arrived earlier and was not consumed yet.
  ///
  /// Completes with null after [timeout] (waits until the connection ends if
  /// it is null). Fails with a [ConnectionClosedException] if the connection
  /// ends first. Payloads are handed to waiters in order.
  Future<Uint8List?> next(
    String channel, {
    Duration? timeout = defaultNextTimeout,
  }) {
    _checkChannel(channel);
    if (_ended) {
      return Future.error(ConnectionClosedException(id, _closeReason));
    }
    return _channels.next(channel, timeout);
  }

  /// Like [next], decoded with [codec]. A payload that does not decode throws
  /// the codec's exception (a [PacketException] for [PayloadCodec.buffer]).
  Future<T?> nextTyped<T>(
    String channel,
    PayloadCodec<T> codec, {
    Duration? timeout = defaultNextTimeout,
  }) async {
    final data = await next(channel, timeout: timeout);
    return data == null ? null : codec.decode(data);
  }

  /// Waits for the next raw packet with [packetId] the client sends (the
  /// body without id and length). Needs `capturePackets: true` (or an
  /// `onPacket` handler) in `onConfiguration`, which makes the server report
  /// every packet. Otherwise like [next].
  Future<Uint8List?> nextPacket(
    int packetId, {
    Duration? timeout = defaultNextTimeout,
  }) {
    if (_ended) {
      return Future.error(ConnectionClosedException(id, _closeReason));
    }
    return _packets.next(packetId, timeout);
  }

  @override
  void _sendRelease() => _transport.release(id);

  @override
  void _sendDisconnect(String reason) => _transport.disconnect(id, reason);

  @override
  void _failWaiters(Object error) {
    _channels.fail(error);
    _packets.fail(error);
  }

  void _deliver(String channel, Uint8List data, String? brand) {
    if (brand != null) _brand = brand;
    if (_ended) return;
    _channels.deliver(channel, data);
  }

  @override
  String toString() => 'ConfigurationConnection($id, $username)';
}

/// A client in the login phase (authenticated, but before "login finished"),
/// as seen by a handler registered with `Context.onLogin`. The login phase has
/// no custom payloads; it has *queries*: the server asks, the client answers.
///
/// The phase is always held while the handler runs; [release] lets the login
/// finish, which ends this connection (the client continues into the
/// configuration phase, see `onConfiguration`).
final class LoginConnection extends PhaseConnection {
  final LoginTransport _transport;
  final _Mailbox<int> _answers = _Mailbox(queueUnclaimed: false);

  LoginConnection({
    required int id,
    required String uuid,
    required String username,
    required int protocolVersion,
    required LoginTransport transport,
  }) : _transport = transport,
       super._(id, uuid, username, protocolVersion);

  /// Asks the client on [channel] (`namespace:path`) and waits for its
  /// answer.
  ///
  /// Completes with null if the client does not understand the query (what
  /// vanilla does) or does not answer within [timeout] (never times out if it
  /// is null). Fails with a [ConnectionClosedException] if the connection
  /// ends first, and with a [ConfigurationException] if the server refuses the
  /// query.
  ///
  /// [queryId] is allocated from a high range (see [loginQueryIdBase]) unless
  /// you give one, for a protocol that fixes it.
  Future<Uint8List?> query(
    String channel,
    List<int> data, {
    Duration? timeout = defaultNextTimeout,
    int? queryId,
  }) async {
    _checkChannel(channel);
    _checkOpen();
    final key = queryId ?? allocateLoginQueryId();
    final future = _answers.next(key, timeout);
    try {
      _transport.sendQuery(id, key, channel, _bytes(data));
    } catch (_) {
      _answers.abandon(key, future);
      rethrow;
    }
    return future;
  }

  @override
  void _sendRelease() => _transport.release(id);

  @override
  void _sendDisconnect(String reason) => _transport.disconnect(id, reason);

  @override
  void _afterRelease() =>
      _finish(completed: true, reason: 'The login was released');

  @override
  void _failWaiters(Object error) => _answers.fail(error);

  bool _answer(int queryId, Uint8List? data) {
    if (_ended) return false;
    return _answers.deliver(queryId, data);
  }

  @override
  String toString() => 'LoginConnection($id, $username)';
}

Uint8List _bytes(List<int> data) =>
    data is Uint8List ? data : Uint8List.fromList(data);

void _checkChannel(String channel) {
  final parts = channel.split(':');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    throw ArgumentError.value(channel, 'channel', 'must be "namespace:path"');
  }
}

/// Starts connections for one registration: creates them, applies the hold
/// policy, tracks them and feeds them the plain data of the events.
base class _Sessions<C extends PhaseConnection> {
  final Map<int, C> _connections = {};

  /// How many connections are being tracked.
  int get length => _connections.length;

  /// The tracked connection with [id], if any.
  C? operator [](int id) => _connections[id];

  C? _begin(
    C connection, {
    bool Function(C connection)? where,
    Duration? holdTimeout,
  }) {
    connection._openHoldWindow();
    try {
      if (where != null && !where(connection)) return null;
      if (holdTimeout != null && !connection.holdRequested) {
        connection.hold(timeout: holdTimeout);
      }
    } finally {
      connection._closeHoldWindow();
    }
    // A connection id is only reused after the old one ended; make sure a
    // missed end event cannot leave a stale connection behind.
    _connections
        .remove(connection.id)
        ?._finish(completed: false, reason: 'Replaced by a new connection');
    _connections[connection.id] = connection;
    return connection;
  }

  /// Forgets [id] (and returns its connection) without finishing it.
  C? _forget(int id) => _connections.remove(id);

  /// Gives up on all connections. Connections that are held and not released
  /// are disconnected with [reason] (fail closed: they never finished the
  /// handshake); the others just stop being tracked.
  void closeAll(String reason) {
    final connections = _connections.values.toList();
    _connections.clear();
    for (final connection in connections) {
      if (connection.isHeld) {
        try {
          connection.disconnect(reason);
        } on ConfigurationException {
          // The connection is gone already.
        }
      }
      connection._finish(completed: false, reason: reason);
    }
  }
}

/// The configuration connections one `onConfiguration` registration handles.
final class ConfigurationSessions extends _Sessions<ConfigurationConnection> {
  final ConfigurationTransport transport;

  /// Connections [where] declined at the pre-brand event; the start event
  /// must not ask again.
  final Set<int> _declined = {};

  ConfigurationSessions(this.transport);

  @override
  void closeAll(String reason) {
    _declined.clear();
    super.closeAll(reason);
  }

  /// A client entered the configuration phase, before the server's brand
  /// (the pre-brand event; only used by registrations with a pre-brand
  /// handler). Returns the connection to hand to the handler, or null if
  /// [where] declined it (it is then not handled at the start either). If
  /// [holdTimeout] is set and [where] did not already call `hold`, the
  /// connection is held.
  ///
  /// Read `holdRequested` and `holdTimeoutSeconds` of the result to answer the
  /// event. Exceptions from [where] propagate and nothing is tracked.
  ConfigurationConnection? preBrand({
    required int id,
    required String uuid,
    required String username,
    required int protocolVersion,
    bool Function(ConfigurationConnection connection)? where,
    Duration? holdTimeout,
  }) {
    _declined.remove(id);
    final connection = _begin(
      ConfigurationConnection(
        id: id,
        uuid: uuid,
        username: username,
        protocolVersion: protocolVersion,
        transport: transport,
      ).._stage = ConfigurationStage.preBrand,
      where: where,
      holdTimeout: holdTimeout,
    );
    if (connection == null) _declined.add(id);
    return connection;
  }

  /// A client entered the configuration phase after the server's brand (the
  /// start event). Returns the connection to hand to the handler, or null if
  /// [where] declined it. If [holdTimeout] is set and [where] did not already
  /// call `hold`, the connection is held.
  ///
  /// If the connection came through [preBrand] it is the same object (and
  /// [where] is not asked again; the hold of the start stage is [holdTimeout]).
  ///
  /// Read `holdRequested` and `holdTimeoutSeconds` of the result to answer the
  /// start event. Exceptions from [where] propagate and nothing is tracked.
  ConfigurationConnection? start({
    required int id,
    required String uuid,
    required String username,
    required int protocolVersion,
    bool Function(ConfigurationConnection connection)? where,
    Duration? holdTimeout,
  }) {
    if (_declined.contains(id)) return null;
    final existing = _connections[id];
    if (existing != null &&
        !existing.isClosed &&
        existing._stage == ConfigurationStage.preBrand) {
      existing._stage = ConfigurationStage.start;
      existing._openHoldWindow();
      try {
        if (holdTimeout != null) existing.hold(timeout: holdTimeout);
      } finally {
        existing._closeHoldWindow();
      }
      return existing;
    }
    return _begin(
      ConfigurationConnection(
        id: id,
        uuid: uuid,
        username: username,
        protocolVersion: protocolVersion,
        transport: transport,
      ),
      where: where,
      holdTimeout: holdTimeout,
    );
  }

  /// The server is about to finish the configuration (second hold point).
  /// Returns the tracked connection with the hold applied, or null if it is
  /// not tracked or already closed. Read `holdRequested` and
  /// `holdTimeoutSeconds` of the result to answer the event.
  ConfigurationConnection? finish({required int id, Duration? holdTimeout}) {
    final connection = _connections[id];
    if (connection == null || connection.isClosed) return null;
    connection._stage = ConfigurationStage.finish;
    connection._openHoldWindow();
    try {
      if (holdTimeout != null) connection.hold(timeout: holdTimeout);
    } finally {
      connection._closeHoldWindow();
    }
    return connection;
  }

  /// The client sent a payload. Returns the connection, or null if this
  /// registration does not handle it.
  ConfigurationConnection? payload({
    required int id,
    required String channel,
    required List<int> data,
    String? brand,
  }) {
    final connection = _connections[id];
    connection?._deliver(channel, _bytes(data), brand);
    return connection;
  }

  /// The client sent a raw packet. Queues it for `nextPacket` if [capture],
  /// then asks [onPacket] whether to cancel it (the server then ignores the
  /// packet). Returns true to cancel. Exceptions from [onPacket] propagate.
  bool packet({
    required int id,
    required int packetId,
    required List<int> payload,
    bool capture = false,
    bool Function(
      ConfigurationConnection connection,
      int packetId,
      Uint8List payload,
    )?
    onPacket,
  }) {
    final connection = _connections[id];
    if (connection == null || connection.isClosed) return false;
    final bytes = _bytes(payload);
    if (capture) connection._packets.deliver(packetId, bytes);
    return onPacket != null && onPacket(connection, packetId, bytes);
  }

  /// The configuration phase ended. Returns the connection that was tracked.
  ConfigurationConnection? end({required int id, required bool completed}) {
    _declined.remove(id);
    final connection = _forget(id);
    connection?._finish(
      completed: completed,
      reason: completed
          ? 'The configuration is finished'
          : 'The client disconnected during the configuration',
    );
    return connection;
  }
}

/// The login connections one `onLogin` registration handles.
final class LoginSessions extends _Sessions<LoginConnection> {
  final LoginTransport transport;

  LoginSessions(this.transport);

  /// A client finished authenticating. Like [ConfigurationSessions.start];
  /// [holdTimeout] is required, since queries only work while the login is
  /// held.
  LoginConnection? start({
    required int id,
    required String uuid,
    required String username,
    required int protocolVersion,
    required Duration holdTimeout,
    bool Function(LoginConnection connection)? where,
  }) => _begin(
    LoginConnection(
      id: id,
      uuid: uuid,
      username: username,
      protocolVersion: protocolVersion,
      transport: transport,
    ),
    where: where,
    holdTimeout: holdTimeout,
  );

  /// The client answered query [queryId] ([data] is null if it did not
  /// understand it). Returns whether a pending query took the answer.
  bool answer({required int id, required int queryId, List<int>? data}) =>
      _connections[id]?._answer(queryId, data == null ? null : _bytes(data)) ??
      false;

  /// Stops tracking [connection] and fails its pending queries, if it is
  /// still the tracked one. For logins that never reported an end (the client
  /// vanished): the plugin calls this when the hold timeout has passed.
  void expire(LoginConnection connection) {
    if (!identical(_connections[connection.id], connection)) return;
    _forget(connection.id);
    connection._finish(
      completed: false,
      reason: 'The login timed out or the client disconnected',
    );
  }

  /// Stops tracking a connection that moved on to the next phase.
  LoginConnection? end({required int id, required bool completed}) {
    final connection = _forget(id);
    connection?._finish(
      completed: completed,
      reason: completed
          ? 'The login is finished'
          : 'The client disconnected during the login',
    );
    return connection;
  }
}

/// A handler for a [ConfigurationConnection]. It may be `async`.
typedef ConfigurationHandler = FutureOr<void> Function(
  ConfigurationConnection connection,
);

/// A handler for a [LoginConnection]. It may be `async`.
typedef LoginHandler = FutureOr<void> Function(LoginConnection connection);

/// Runs [handler] for [connection] and deals with the outcome. The returned
/// future never fails.
///
/// * Errors are reported to [onError], except a [ConnectionClosedException]
///   (the client leaving is not a bug in the handler).
/// * The handler is responsible for the hold that is active when it starts.
///   If it throws or returns while that hold is still on (not released), the
///   connection is disconnected with [failureMessage] (fail closed), or
///   released when it returned normally and [releaseOnReturn] is true. A
///   later hold point (like the finish of the configuration) is not touched.
Future<void> runConnectionHandler<C extends PhaseConnection>(
  C connection,
  FutureOr<void> Function(C connection) handler, {
  required void Function(String message) onError,
  bool releaseOnReturn = false,
  String failureMessage = 'Failed to complete the server handshake.',
}) async {
  final epoch = connection.holdEpoch;
  bool stillHeld() => connection.isHeld && connection.holdEpoch == epoch;

  var failed = false;
  try {
    await handler(connection);
  } on ConnectionClosedException {
    return;
  } catch (e, s) {
    failed = true;
    onError('Handler for ${connection.username} failed: $e\n$s');
  }

  if (!stillHeld()) return;
  try {
    if (!failed && releaseOnReturn) {
      connection.release();
      return;
    }
    if (!failed) {
      onError(
        'Handler for ${connection.username} returned without releasing or '
        'disconnecting the held connection; disconnecting it',
      );
    }
    connection.disconnect(failureMessage);
  } on ConfigurationException catch (e) {
    onError(
      'Could not finish the handshake of ${connection.username}: ${e.message}',
    );
  }
}
