import 'dart:async';
import 'dart:typed_data';

import 'package:wasm_components/wasm_components.dart' show ErrorResult, Result;

import 'async_runtime.dart' show runCallback;
import 'bindings.g.dart' as raw show ConnectionFlavour;
import 'bindings.g.dart' show Context, EventPriority, Server;
import 'configuration_core.dart';
import 'events.dart';
import 'events.g.dart';
import 'lifecycle.dart';
import 'logger.dart';

final Logger _log = Logger('connection');

const String _unloadReason = 'The server is reloading plugins.';

/// How long after the hold timeout an abandoned login is forgotten.
const Duration _loginExpirySlack = Duration(seconds: 5);

/// Custom handshakes while a client connects, before a player joins.
///
/// Mods with their own client side negotiate with the server after login and
/// before the world is sent. `onConfiguration` runs a handler for every client
/// that enters that phase:
///
/// ```dart
/// const hello = 'mymod:hello';
/// const ack = 'mymod:ack';
///
/// context.onConfiguration((connection) async {
///   connection.send(hello, PayloadCodecs.string.encode('Welcome!'));
///   final reply = await connection.next(ack, timeout: const Duration(seconds: 5));
///   if (reply == null) {
///     connection.disconnect('This server needs the My Mod client mod.');
///     return;
///   }
///   connection.release();   // let the client continue
/// });
/// ```
///
/// See `docs/configuration.md` for what holds, when handlers run and what is
/// not covered.
extension ConfigurationApi on Context {
  /// Calls [handler] for every client that enters the configuration phase,
  /// each in its own async task. Handlers may `await`, so a handshake reads
  /// top to bottom. The handler runs a moment (one server tick) after the
  /// client entered the phase, so everything on the connection is usable
  /// from its first line.
  ///
  /// * [holdTimeout]: the server pauses the configuration of every client
  ///   for at most this long, until the handler calls
  ///   `connection.release()` (or disconnects the client). Pass null to not
  ///   hold; the configuration then continues right away and the handler can
  ///   only exchange payloads with the client while it is still in progress.
  ///   This is the *start* hold, which comes after the server's brand.
  /// * [onPreBrand]: an earlier hold point, before the server sends its
  ///   `minecraft:brand` (see "The pre-brand stage" below). Optional; without
  ///   it nothing changes: the server sends the brand right away and this
  ///   registration only has the start (and finish) hold. [preBrandHoldTimeout]
  ///   is its hold (null: no hold, the brand follows at once).
  /// * [where]: decides synchronously whether this registration handles a
  ///   client (by name, protocol version, ...); `connection.hold` may be
  ///   called here for a per-client timeout. If it throws, the error is
  ///   logged and the client is not handled. It is asked once per client, at
  ///   the first stage the registration has: the pre-brand event when
  ///   [onPreBrand] is given (a hold requested there is the pre-brand hold; the
  ///   start hold is then [holdTimeout]), otherwise the start event.
  /// * [onFinish]: a second hold point. The server runs it when the registries
  ///   and tags were sent, right before "finish configuration" (the place mod
  ///   loaders run their own configuration tasks). It gets the same
  ///   connection, and the server holds for [finishHoldTimeout] until
  ///   `connection.release()`, with the same fail-closed rules as [handler].
  ///   The two hold points are independent: each handler is only
  ///   responsible for the hold that was active when it started, so the
  ///   first handler returning does not disconnect a client that the finish
  ///   handler holds. Call `release()` once per hold point, in the handler
  ///   of that point.
  /// * [onPacket]: sees every raw packet the client sends during the
  ///   configuration (with its id and body, without id/length), before the
  ///   server handles it, and returns true to cancel it (the server then
  ///   ignores it). It runs synchronously in the server's packet loop, so
  ///   keep it short, and use `connection.nextPacket` from the handler to wait
  ///   for packets. If it throws, the error is logged and the packet is not
  ///   cancelled. Custom payloads arrive here too; they are also queued for
  ///   `connection.next`, whether or not they are cancelled.
  /// * [capturePackets]: also queue every packet for `connection.nextPacket`
  ///   (implied by [onPacket]). Off by default, because it makes the server
  ///   ask the plugin about every packet.
  /// * Errors thrown by a handler are logged and never crash the plugin. If
  ///   the connection is still held then, or the handler returns without
  ///   releasing or disconnecting it, the client is disconnected with
  ///   [failureMessage] (fail closed); with [releaseOnReturn] a normal return
  ///   releases it instead.
  /// * When the plugin unloads (or the returned subscription is cancelled)
  ///   clients that are still held are disconnected.
  ///
  /// Several registrations can coexist; each sees every client and keeps its
  /// own payload queues. How the server combines their holds and releases is
  /// up to the server.
  ///
  /// ### The pre-brand stage
  ///
  /// Some mod loaders classify a connection by what the server sends *before*
  /// its brand (NeoForge: the `neoforge:register` query). [onPreBrand] runs for
  /// every client right after login was acknowledged, before the server sent
  /// anything of the configuration, with the same [ConfigurationConnection]
  /// that [handler] and [onFinish] get later (`connection.stage` tells which
  /// stage it is at, `connection.id` is the same):
  ///
  /// ```dart
  /// context.onConfiguration(
  ///   onPreBrand: (connection) async {
  ///     connection.send('mymod:probe', const []);
  ///     final answer = await connection.next('mymod:probe', timeout: const Duration(seconds: 3));
  ///     if (answer != null) connection.setFlavour(ConnectionFlavour.neoforge);
  ///     connection.release();   // the server sends its brand and moves on
  ///   },
  ///   (connection) async { /* start hold, after the brand, as before */ },
  /// );
  /// ```
  ///
  /// * The server holds the connection until `release()`, at most
  ///   [preBrandHoldTimeout]; the same fail-closed rules as for the other
  ///   holds apply (a handler that throws, or returns without releasing or
  ///   disconnecting, disconnects the client; [releaseOnReturn] releases it
  ///   instead).
  /// * `release()` at this stage lets the host send the brand, fire the start
  ///   event and go on: [handler] runs next, with its own hold
  ///   ([holdTimeout]), and so on. It does not finish anything.
  /// * Each handler is only responsible for the hold that was active when it
  ///   started. Call `release()` once per stage, in that stage's handler; a
  ///   pre-brand handler that is still running after it released must not call
  ///   `release()` again, since it would release the start hold.
  /// * While held, `send`, `sendPacket`, `next`, `nextPacket` and
  ///   `announceChannels` work, and `connection.setFlavour` can mark the
  ///   connection (it fails once the configuration ended). `connection.brand`
  ///   is usually known after the client's first payload.
  /// * Packets: pass [capturePackets] (or [onPacket]) to use `nextPacket` here
  ///   (a ping/pong, for instance).
  /// * With no [onPreBrand] the registration behaves exactly as without the
  ///   stage: the server is not even told to hold before the brand.
  ///
  /// Needs the plugin's kept context (the one `onLoad` receives, or
  /// `Plugin.context`): the connection talks to the server through it.
  Subscription onConfiguration(
    ConfigurationHandler handler, {
    ConfigurationHandler? onPreBrand,
    Duration? preBrandHoldTimeout = defaultHoldTimeout,
    Duration? holdTimeout = defaultHoldTimeout,
    bool Function(ConfigurationConnection connection)? where,
    ConfigurationHandler? onFinish,
    Duration? finishHoldTimeout = defaultHoldTimeout,
    bool Function(
      ConfigurationConnection connection,
      int packetId,
      Uint8List payload,
    )?
    onPacket,
    bool capturePackets = false,
    bool releaseOnReturn = false,
    String failureMessage = 'Failed to complete the server handshake.',
    EventPriority priority = EventPriority.normal,
  }) {
    final sessions = ConfigurationSessions(_ConfigurationTransport(this));

    void run(ConfigurationConnection c, ConfigurationHandler h) =>
        _startHandler(c, h, releaseOnReturn, failureMessage);

    final subscriptions = <EventSubscription>[
      if (onPreBrand != null)
        intercept(Events.configurationPreBrand, (server, event) {
          try {
            final connection = sessions.preBrand(
              id: event.connectionId,
              uuid: event.uuid,
              username: event.username,
              protocolVersion: event.protocolVersion,
              where: where,
              holdTimeout: preBrandHoldTimeout,
            );
            if (connection == null) return event;
            run(connection, onPreBrand);
            return connection.holdRequested
                ? event.copyWith(
                    hold: true,
                    holdTimeoutSeconds: _holdSeconds(
                      connection,
                      event.hold,
                      event.holdTimeoutSeconds,
                    ),
                  )
                : event;
          } catch (e, s) {
            _log.error('Configuration pre-brand failed: $e\n$s');
            return event;
          }
        }, priority: priority),
      intercept(Events.configurationStart, (server, event) {
        try {
          final connection = sessions.start(
            id: event.connectionId,
            uuid: event.uuid,
            username: event.username,
            protocolVersion: event.protocolVersion,
            where: where,
            holdTimeout: holdTimeout,
          );
          if (connection == null) return event;
          run(connection, handler);
          return connection.holdRequested
              ? event.copyWith(
                  hold: true,
                  holdTimeoutSeconds: _holdSeconds(
                    connection,
                    event.hold,
                    event.holdTimeoutSeconds,
                  ),
                )
              : event;
        } catch (e, s) {
          _log.error('Configuration start failed: $e\n$s');
          return event;
        }
      }, priority: priority),
      listen(Events.configurationPayload, (server, event) {
        sessions.payload(
          id: event.connectionId,
          channel: event.channel,
          data: event.data,
          brand: event.brand,
        );
      }, priority: priority),
      listen(Events.configurationEnd, (server, event) {
        sessions.end(id: event.connectionId, completed: event.completed);
      }, priority: priority),
      if (onFinish != null)
        intercept(Events.configurationFinish, (server, event) {
          try {
            final connection = sessions.finish(
              id: event.connectionId,
              holdTimeout: finishHoldTimeout,
            );
            if (connection == null) return event;
            run(connection, onFinish);
            return connection.holdRequested
                ? event.copyWith(
                    hold: true,
                    holdTimeoutSeconds: _holdSeconds(
                      connection,
                      event.hold,
                      event.holdTimeoutSeconds,
                    ),
                  )
                : event;
          } catch (e, s) {
            _log.error('Configuration finish failed: $e\n$s');
            return event;
          }
        }, priority: priority),
      if (onPacket != null || capturePackets)
        intercept(Events.configurationPacketReceived, (server, event) {
          try {
            final cancel = sessions.packet(
              id: event.connectionId,
              packetId: event.packetId,
              payload: event.payload,
              capture: true,
              onPacket: onPacket,
            );
            return cancel ? event.cancel() : event;
          } catch (e, s) {
            _log.error('Configuration packet handler failed: $e\n$s');
            return event;
          }
        }, priority: priority),
    ];

    final unloadHook = onUnload(() => sessions.closeAll(_unloadReason));
    return Subscription(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      unloadHook.cancel();
      sessions.closeAll(_unloadReason);
    });
  }

  /// Calls [handler] for every client that finished authenticating, in the
  /// login phase (before "login finished" is sent and the configuration
  /// phase starts), each in its own async task. This is where loaders that
  /// negotiate with login queries (Forge before 1.20.2, for instance) talk to
  /// the client:
  ///
  /// ```dart
  /// context.onLogin((login) async {
  ///   final answer = await login.query('mymod:handshake', hello, timeout: const Duration(seconds: 5));
  ///   if (answer == null) {
  ///     login.disconnect('This server needs the My Mod client mod.');
  ///     return;
  ///   }
  ///   login.release();   // the login finishes
  /// });
  /// ```
  ///
  /// The login is held for every handled client, for at most [holdTimeout]
  /// (then the server disconnects the client). The handler, [where],
  /// fail-closed behavior and unload behavior work as in [onConfiguration]:
  /// a handler that throws or returns without releasing or disconnecting
  /// disconnects the client with [failureMessage], and held logins are
  /// disconnected when the plugin unloads or the subscription is cancelled.
  ///
  /// The server reports no end of the login phase, so a client that vanishes
  /// mid-login is noticed when [holdTimeout] (plus a few seconds) has passed:
  /// pending queries then fail with a `ConnectionClosedException`.
  Subscription onLogin(
    LoginHandler handler, {
    Duration holdTimeout = defaultHoldTimeout,
    bool Function(LoginConnection connection)? where,
    bool releaseOnReturn = false,
    String failureMessage = 'Failed to complete the server handshake.',
    EventPriority priority = EventPriority.normal,
  }) {
    final sessions = LoginSessions(_LoginTransport(this));

    final subscriptions = <EventSubscription>[
      intercept(Events.loginStart, (server, event) {
        try {
          final connection = sessions.start(
            id: event.connectionId,
            uuid: event.uuid,
            username: event.username,
            protocolVersion: event.protocolVersion,
            holdTimeout: holdTimeout,
            where: where,
          );
          if (connection == null) return event;

          // Nothing reports the end of a login: forget it after the hold.
          final expiry = Timer(holdTimeout + _loginExpirySlack, () {
            sessions.expire(connection);
          });
          unawaited(
            connection.done.then((_) {
              expiry.cancel();
              sessions.expire(connection);
            }),
          );

          _startHandler(connection, handler, releaseOnReturn, failureMessage);
          return event.copyWith(
            hold: true,
            holdTimeoutSeconds: _holdSeconds(
              connection,
              event.hold,
              event.holdTimeoutSeconds,
            ),
          );
        } catch (e, s) {
          _log.error('Login start failed: $e\n$s');
          return event;
        }
      }, priority: priority),
      listen(Events.loginQueryAnswer, (server, event) {
        sessions.answer(
          id: event.connectionId,
          queryId: event.queryId,
          data: event.data,
        );
      }, priority: priority),
    ];

    final unloadHook = onUnload(() => sessions.closeAll(_unloadReason));
    return Subscription(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      unloadHook.cancel();
      sessions.closeAll(_unloadReason);
    });
  }
}

/// Another plugin may have asked for a hold already: keep the longer one.
int _holdSeconds(
  PhaseConnection connection,
  bool eventHold,
  int eventSeconds,
) => eventHold && eventSeconds > connection.holdTimeoutSeconds
    ? eventSeconds
    : connection.holdTimeoutSeconds;

/// Runs [handler] for [connection] after the event that is being handled
/// returned: the server only holds once the event has returned, so the
/// handler's first `send` must not happen inside it. One tick later it runs
/// as a callback of its own (own zone and resource scope).
void _startHandler<C extends PhaseConnection>(
  C connection,
  FutureOr<void> Function(C connection) handler,
  bool releaseOnReturn,
  String failureMessage,
) {
  Timer(const Duration(milliseconds: 1), () {
    if (connection.isClosed) return;
    try {
      runCallback<void>(
        'connection handler',
        () => runConnectionHandler<C>(
          connection,
          handler,
          onError: _log.error,
          releaseOnReturn: releaseOnReturn,
          failureMessage: failureMessage,
        ),
      );
    } catch (e, s) {
      _log.error('Connection handler failed: $e\n$s');
    }
  });
}

/// Talks to the server through the plugin's context: the `server` of an event
/// handler is only valid during that callback, but a handler of a connection
/// lives longer. A fresh server handle is requested per call and dropped
/// right away.
void _callServer(
  Context context,
  Result<void, String> Function(Server server) call,
) {
  if (!context.isValid) {
    throw const ConfigurationException(
      'The plugin context is no longer valid (is the plugin unloading?)',
    );
  }
  final server = context.getServer();
  try {
    if (call(server) case ErrorResult(value: final message)) {
      throw ConfigurationException(message);
    }
  } finally {
    server.dispose();
  }
}

final class _ConfigurationTransport implements ConfigurationTransport {
  final Context _context;

  _ConfigurationTransport(this._context);

  @override
  void sendPayload(int connectionId, String channel, Uint8List data) =>
      _callServer(
        _context,
        (server) => server.sendConfigurationPayload(
          connectionId: connectionId,
          channel: channel,
          data: data,
        ),
      );

  @override
  void sendPacket(int connectionId, int packetId, Uint8List payload) =>
      _callServer(
        _context,
        (server) => server.sendConfigurationPacket(
          connectionId: connectionId,
          packetId: packetId,
          payload: payload,
        ),
      );

  @override
  void release(int connectionId) => _callServer(
    _context,
    (server) => server.releaseConfiguration(connectionId: connectionId),
  );

  @override
  void setFlavour(int connectionId, ConnectionFlavour flavour) => _callServer(
    _context,
    (server) => server.setConnectionFlavour(
      connectionId: connectionId,
      flavour: switch (flavour) {
        ConnectionFlavour.vanilla => raw.ConnectionFlavour.vanilla,
        ConnectionFlavour.neoforge => raw.ConnectionFlavour.neoforge,
      },
    ),
  );

  @override
  void disconnect(int connectionId, String reason) => _callServer(
    _context,
    (server) => server.disconnectConfiguration(
      connectionId: connectionId,
      reason: reason,
    ),
  );
}

final class _LoginTransport implements LoginTransport {
  final Context _context;

  _LoginTransport(this._context);

  @override
  void sendQuery(
    int connectionId,
    int queryId,
    String channel,
    Uint8List data,
  ) => _callServer(
    _context,
    (server) => server.sendLoginQuery(
      connectionId: connectionId,
      queryId: queryId,
      channel: channel,
      data: data,
    ),
  );

  @override
  void release(int connectionId) => _callServer(
    _context,
    (server) => server.releaseLogin(connectionId: connectionId),
  );

  @override
  void disconnect(int connectionId, String reason) => _callServer(
    _context,
    (server) =>
        server.disconnectLogin(connectionId: connectionId, reason: reason),
  );
}
