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

typedef _ErasedEventHandler = Event Function(Server server, Event event);

final eventHandlers = HandlerRegistry<_ErasedEventHandler>();

extension EventApi on Context {
  /// Calls [handler] when the server fires an [event] without waiting for it
  /// to finish. The handler can't change the event.
  ///
  /// ```dart
  /// context.listen(Events.playerJoin, (server, event) {
  ///   logger.info('Welcome ${event.player.getName()}!');
  /// });
  /// ```
  void listen<D>(
    EventKind<D> event,
    void Function(Server server, D data) handler, {
    EventPriority priority = EventPriority.normal,
  }) {
    final id = eventHandlers.add((server, raw) {
      handler(server, event.unwrap(raw));
      return raw;
    });
    registerEvent(
      handlerId: id,
      eventType: event.type,
      eventPriority: priority,
      blocking: false,
    );
  }

  /// Calls [handler] when the server fires an [event]. The server waits for
  /// the handler, and uses the data it returns. This is how events get
  /// cancelled or modified:
  ///
  /// ```dart
  /// context.intercept(Events.playerChat, (server, event) {
  ///   return event.copyWith(message: event.message.toUpperCase());
  /// });
  /// ```
  void intercept<D>(
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
  }
}
