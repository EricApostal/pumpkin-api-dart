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

/// The event type each handler id was registered for, for diagnostics: the plugin's timing
/// instrumentation (`Perf`) reads it to name the handler an event dispatch ran.
final eventHandlerLabels = <int, String>{};

/// Optional hook a plugin can install to attribute the time an event handler spends inside the
/// guest: called with the event type of the handler that ran, and the microseconds it took.
///
/// `null` (the default) costs one null check per event dispatch. Create's `Perf` sets it when its
/// `perf` file is present, which is what gives the per-event breakdown of a tick.
void Function(String type, int micros)? eventTimingSink;

/// A registered event handler. The server has no way to unregister handlers,
/// so [cancel] makes the handler inert: it stays registered but is ignored.
final class EventSubscription {
  final int _id;

  /// What [cancel] does besides forgetting the handler id, for a subscription that is one member
  /// of a [ListenGroup] or [InterceptGroup] rather than a host handler of its own.
  final void Function()? _onCancel;
  bool _active = true;

  EventSubscription._(this._id) : _onCancel = null;

  /// A subscription for one member of an event group. The group is registered with the host as
  /// **one** handler for all its members, so a member has no handler id of its own: [cancel]
  /// takes the member out of the group and leaves the other members listening.
  EventSubscription.detached(this._onCancel) : _id = -1;

  /// Whether the handler is still called.
  bool get isActive => _active;

  /// Stops calling the handler. Does nothing if it was already cancelled.
  void cancel() {
    if (!_active) return;
    _active = false;
    if (_id >= 0) eventHandlers.remove(_id);
    _onCancel?.call();
  }
}

/// One handler of a [ListenGroup] or [InterceptGroup].
final class EventGroupMember {
  EventGroupMember(this.wants, this.handler);

  /// Whether this member wants the event, checked before the member is run: a group is one host
  /// call for every member it holds, so a member that does not want an event must not cost a
  /// callback scope.
  final bool Function(Event event) wants;

  /// The member's handler, built exactly like the [EventApi.listen] or [EventApi.intercept]
  /// registration it replaces.
  final FutureOr<Event> Function(Server server, Event event) handler;

  /// Cleared by [EventSubscription.cancel].
  ///
  /// A cancelled member stays in its group's list - removing it would shift the members the
  /// dispatch in flight is walking, and the host dispatches a snapshot of its own handler list
  /// anyway - so a cancel during a dispatch silences the member for the rest of that event too,
  /// which is what removing the handler from the registry did before members shared a group.
  bool active = true;
}

/// The members of each group, by the id of the one host handler that dispatches them.
///
/// `handleEvent` runs them itself instead of the host dispatching one call per member.
final eventGroups = <int, List<EventGroupMember>>{};

/// Registers the one host handler a group is dispatched by and remembers its members.
int _registerGroup<D>(
  Context context,
  EventKind<D> kind,
  EventPriority priority, {
  required bool blocking,
  required List<EventGroupMember> members,
}) {
  final id = eventHandlers.reserve();
  eventHandlerLabels[id] = kind.type.name;
  context.registerEvent(
    handlerId: id,
    eventType: kind.type,
    eventPriority: priority,
    blocking: blocking,
  );
  eventGroups[id] = members;
  return id;
}

/// A set of handlers the server dispatches as **one** host call, for hooks that have a handler per
/// block, item or position.
///
/// [EventApi.listen] and [EventApi.intercept] register one host handler per call, and the host
/// crosses into the plugin once per registered handler for *every* event. A plugin that registers
/// a handler per block therefore pays one host→guest round trip per block and per event: for the
/// `placed` event of a bulk write that was 397 crossings (about 80 ms) per block, against a write
/// that takes microseconds.
///
/// A group registers **one** handler with the host for its event kind and runs the members itself
/// ([Plugin.handleEvent]). The members see the same events, in registration order, and each runs
/// in its own callback scope exactly as a registration of its own would have, so one member's
/// failure does not stop the others and a member that waits for a timer does not hold the server.
///
/// Created by [EventApi.listenGroup]; [InterceptGroup] by [EventApi.interceptGroup].
final class ListenGroup<D> {
  ListenGroup._(Context context, EventKind<D> kind, EventPriority priority) : _kind = kind {
    _registerGroup(context, kind, priority, blocking: false, members: _members);
  }

  final EventKind<D> _kind;
  final List<EventGroupMember> _members = [];

  /// Adds [handler] to the group, after the members already added. [where] decides which events
  /// the member gets; without it the member is asked for every event of the group's kind.
  EventSubscription add(
    FutureOr<void> Function(Server server, D data) handler, {
    bool Function(D data)? where,
  }) {
    final member = EventGroupMember(
      where == null ? (Event _) => true : (Event e) => where(_kind.unwrap(e)),
      (server, event) {
        final result = handler(server, _kind.unwrap(event));
        if (result is Future) return result.then((_) => event);
        return event;
      },
    );
    _members.add(member);
    return EventSubscription.detached(() => member.active = false);
  }
}

/// A [ListenGroup] whose members are called like [EventApi.intercept]'s: the server waits for
/// them, and the event a member returns is the one the next member and the server see.
final class InterceptGroup<D> {
  InterceptGroup._(Context context, EventKind<D> kind, EventPriority priority) : _kind = kind {
    _registerGroup(context, kind, priority, blocking: true, members: _members);
  }

  final EventKind<D> _kind;
  final List<EventGroupMember> _members = [];

  /// Adds [handler] to the group, after the members already added. [where] decides which events
  /// the member gets; without it the member is asked for every event of the group's kind.
  EventSubscription add(
    FutureOr<D> Function(Server server, D data) handler, {
    bool Function(D data)? where,
  }) {
    final member = EventGroupMember(
      where == null ? (Event _) => true : (Event e) => where(_kind.unwrap(e)),
      (server, event) {
        final result = handler(server, _kind.unwrap(event));
        if (result is Future<D>) return result.then(_kind.wrap);
        return _kind.wrap(result);
      },
    );
    _members.add(member);
    return EventSubscription.detached(() => member.active = false);
  }
}

extension EventApi on Context {
  /// Like [listen], but the handler is added to a group the server dispatches as **one** call
  /// (see [ListenGroup]) instead of registering a host handler of its own.
  ///
  /// Use it when one event kind has a handler per block, item or position: the host crosses into
  /// the plugin once per registered handler for every event, so a handler per block makes every
  /// such event cost hundreds of round trips.
  ///
  /// Returns the group to add the handlers to.
  ListenGroup<D> listenGroup<D>(
    EventKind<D> event, {
    EventPriority priority = EventPriority.normal,
  }) => ListenGroup._(this, event, priority);

  /// Like [intercept], but the handler is added to a group the server dispatches as **one** call
  /// (see [ListenGroup]) instead of registering a host handler of its own.
  ///
  /// Use it when one event kind has a handler per block, item or position, for the same reason as
  /// [listenGroup]: an intercept handler registered for every block makes every such event cost
  /// one host→guest round trip per block, and each member of the group sees the event the members
  /// before it returned.
  ///
  /// Returns the group to add the handlers to.
  InterceptGroup<D> interceptGroup<D>(
    EventKind<D> event, {
    EventPriority priority = EventPriority.normal,
  }) => InterceptGroup._(this, event, priority);

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
    eventHandlerLabels[id] = event.type.name;
    registerEvent(
      handlerId: id,
      eventType: event.type,
      eventPriority: priority,
      blocking: false,
    );
    return EventSubscription._(id);
  }

  /// Calls [handler] when the server fires an [event]. The server waits for
  /// the handler, and uses the data it returns. The handler may be `async`; the
  /// server waits for the host calls it awaits, but not for timers. This is
  /// how events get cancelled or modified:
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
    FutureOr<D> Function(Server server, D data) handler, {
    EventPriority priority = EventPriority.normal,
  }) {
    final id = eventHandlers.add((server, raw) {
      final result = handler(server, event.unwrap(raw));
      if (result is Future<D>) return result.then(event.wrap);
      return event.wrap(result);
    });
    eventHandlerLabels[id] = event.type.name;
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
  /// resources (like its `player`) are only valid until the handler that
  /// received it has returned, so read what you need right away.
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
