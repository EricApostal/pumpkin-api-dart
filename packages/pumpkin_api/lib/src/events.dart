import 'dart:async';

import 'bindings.g.dart';
import 'registry.dart';

/// Identifies one kind of server event and the data it carries. The available
/// kinds are listed in [Events].
final class EventKind<D> {
  final EventType type;
  final D Function(Event event) _unwrap;
  final Event Function(D data) _wrap;

  EventKind(this.type, this._unwrap, this._wrap);

  D unwrap(Event event) => _unwrap(event);

  Event wrap(D data) => _wrap(data);
}

typedef _ErasedEventHandler = FutureOr<Event> Function(Server server, Event event);

final eventHandlers = HandlerRegistry<_ErasedEventHandler>();

/// A registered event handler. The server has no way to unregister handlers,
/// so [cancel] makes the handler inert: it stays registered but is ignored.
final class EventSubscription {
  final int _id;
  bool _active = true;

  EventSubscription._(this._id);

  /// Whether the handler is still called.
  bool get isActive => _active;

  /// Stops calling the handler. Does nothing if it was already cancelled.
  void cancel() {
    if (!_active) return;
    _active = false;
    eventHandlers.remove(_id);
  }
}

extension EventApi on Context {
  /// Calls [handler] when the server fires an [event] without waiting for it
  /// to finish. The handler can't change the event, and may be `async`.
  ///
  /// ```dart
  /// context.listen(Events.playerJoin, (server, event) {
  ///   logger.info('Welcome ${event.player.getName()}!');
  /// });
  /// ```
  ///
  /// Returns a subscription to stop listening.
  EventSubscription listen<D>(
    EventKind<D> event,
    FutureOr<void> Function(Server server, D data) handler, {
    EventPriority priority = EventPriority.normal,
  }) {
    final id = eventHandlers.add((server, raw) {
      final result = handler(server, event.unwrap(raw));
      if (result is Future) return result.then((_) => raw);
      return raw;
    });
    registerEvent(
      handlerId: id,
      eventType: event.type,
      eventPriority: priority,
      blocking: false,
    );
    return EventSubscription._(id);
  }

  /// Calls [handler] when the server fires an [event]. The server waits for
  /// the handler, and uses the data it returns. This is how events get
  /// cancelled or modified:
  ///
  /// ```dart
  /// context.intercept(Events.playerChat, (server, event) {
  ///   return event.copyWith(message: event.message.toUpperCase());
  /// });
  /// context.intercept(Events.blockBreak, (server, event) => event.cancel());
  /// ```
  ///
  /// Events with a `cancelled` field have a `cancel()` method.
  EventSubscription intercept<D>(
    EventKind<D> event,
    D Function(Server server, D data) handler, {
    EventPriority priority = EventPriority.normal,
  }) {
    final id = eventHandlers.add((server, raw) {
      return event.wrap(handler(server, event.unwrap(raw)));
    });
    registerEvent(
      handlerId: id,
      eventType: event.type,
      eventPriority: priority,
      blocking: true,
    );
    return EventSubscription._(id);
  }

  /// Like [listen], but only for the first event (that satisfies [where]).
  EventSubscription once<D>(
    EventKind<D> event,
    FutureOr<void> Function(Server server, D data) handler, {
    bool Function(D data)? where,
    EventPriority priority = EventPriority.normal,
  }) {
    late final EventSubscription subscription;
    subscription = listen(event, (server, data) {
      if (!subscription.isActive) return null;
      if (where != null && !where(data)) return null;
      subscription.cancel();
      return handler(server, data);
    }, priority: priority);
    return subscription;
  }

  /// Waits for the next [event] (that satisfies [where]):
  ///
  /// ```dart
  /// sender.reply('Type your answer in chat...');
  /// final chat = await context.next(
  ///   Events.playerChat,
  ///   where: (chat) => chat.player.getName() == name,
  ///   timeout: const Duration(seconds: 30),
  /// );
  /// ```
  ///
  /// Fails with a [TimeoutException] if [timeout] passes first. The event's
  /// resources (like its `player`) are only valid until your code first
  /// `await`s again, so read what you need right away.
  Future<D> next<D>(
    EventKind<D> event, {
    bool Function(D data)? where,
    Duration? timeout,
    EventPriority priority = EventPriority.normal,
  }) {
    final completer = Completer<D>();
    Timer? timer;
    late final EventSubscription subscription;
    subscription = listen(event, (server, data) {
      if (completer.isCompleted) return;
      if (where != null && !where(data)) return;
      timer?.cancel();
      subscription.cancel();
      completer.complete(data);
    }, priority: priority);

    if (timeout != null) {
      timer = Timer(timeout, () {
        if (completer.isCompleted) return;
        subscription.cancel();
        completer.completeError(
          TimeoutException('Timed out waiting for ${event.type.name}', timeout),
        );
      });
    }
    return completer.future;
  }
}
