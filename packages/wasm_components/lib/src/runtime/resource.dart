/// Ownership tracking for component model resources (`own<T>`/`borrow<T>`
/// handles).
///
/// The host keeps the real resource in a table owned by the component instance
/// and hands out integer handles. Every `own` handle must be dropped exactly
/// once, otherwise the host keeps the resource alive forever. Dart has no
/// deterministic destructors (and standalone `dart2wasm` has no finalizers),
/// so handles are tracked by [ResourceScope]s instead: a scope is opened for
/// every call from the host into the component, and when it closes, everything
/// that was received during the call is released:
///
/// * `own` handles that the program still holds are dropped,
/// * `borrow` handles (only valid during the call) are invalidated, so that
///   using them later throws a [StateError] rather than corrupting the host
///   table.
///
/// Use [ResourceKeep.keep] to hold on to an owned resource beyond its scope
/// and [Resource.dispose] to release it.
library;

import 'package:meta/meta.dart';

/// Base class of the Dart wrappers generated for WIT resources.
base class Resource {
  static int _nextId = 0;

  /// The plugin the component belongs to, for lifetime errors. Set once by
  /// `runPlugin`.
  static String? pluginName;

  /// The callback the host is running right now (an event's name, when the API
  /// knows it), for lifetime errors: a resource that is used after its callback
  /// returned reports the callback it was received in and the one that used it,
  /// which is what tells a stored handle from a re-resolved one.
  ///
  /// Set around a dispatch by the API. Assigning it is a plain reference store:
  /// the value is a constant string, and nothing is formatted until a resource
  /// is actually misused.
  static String? receivingDuring;

  final int _id = _nextId++;
  final int _handle;
  final void Function(int handle)? _drop;
  ResourceScope? _scope;
  bool _valid = true;
  String _invalidatedBy = 'no reason recorded';
  final String? _receivedDuring = receivingDuring;
  final ResourceScope? _receivedIn = ResourceScope._current;

  /// Wraps an `own` handle that this program is now responsible for dropping.
  @protected
  Resource.owned(this._handle, void Function(int handle) drop) : _drop = drop {
    _scope = ResourceScope._current?.._register(this);
  }

  /// Wraps a `borrow` handle, which is only valid until the current scope ends.
  @protected
  Resource.borrowed(this._handle) : _drop = null {
    _scope = ResourceScope._current?.._register(this);
  }

  /// Whether this resource can still be used.
  bool get isValid => _valid;

  /// Whether this wrapper owns its handle (as opposed to borrowing it).
  bool get isOwned => _drop != null;

  /// The raw handle, to pass to the host as a `borrow`.
  @internal
  int get resourceHandle {
    if (!_valid) {
      throw StateError(
        'This $runtimeType is no longer valid ($_invalidatedBy). Resources are '
        'released when the callback that received them returns: store the '
        'id, not the handle, and look the object up again (for a world, '
        'Worlds.byId). keep() only preserves a resource a host call returned; '
        'it cannot preserve one an event carried, because the host takes the '
        "event's handles back when the dispatch returns. "
        '[received during: ${_describe(_receivedDuring)}, '
        'in: ${_receivedIn?._description ?? '<no scope>'}, used during: '
        '${_describe(receivingDuring)}]',
      );
    }
    return _handle;
  }

  /// Names a callback in a lifetime error. Only ever runs while the error is
  /// being built.
  static String _describe(String? callback) {
    final plugin = pluginName;
    final name = callback == null ? 'an unknown callback' : 'event handler $callback';
    return plugin == null ? name : '$name of $plugin';
  }

  /// Gives the handle away, to pass to the host as an `own`. The wrapper
  /// becomes invalid.
  @internal
  int takeHandle() {
    final handle = resourceHandle;
    if (_drop == null) {
      throw StateError('Cannot transfer ownership of a borrowed resource.');
    }
    _valid = false;
    _invalidatedBy = 'ownership was transferred to the host';
    _scope?._unregister(this);
    _scope = null;
    return handle;
  }

  /// Drops the handle, releasing the host resource. Does nothing if the
  /// resource is already invalid or only borrowed.
  void dispose() => _release('disposed by the plugin');

  /// Releases the handle on behalf of the [ResourceScope] it was received in,
  /// when that scope ends without the plugin keeping it.
  void _releaseByScope() => _release('released when the callback that received it returned');

  void _release(String reason) {
    final drop = _drop;
    if (!_valid || drop == null) return;
    _valid = false;
    _invalidatedBy = reason;
    _scope?._unregister(this);
    _scope = null;
    drop(_handle);
  }

  void _invalidateBorrowed() {
    _valid = false;
    _invalidatedBy = 'the call that lent it has returned';
    _scope = null;
  }
}

extension ResourceKeep<T extends Resource> on T {
  /// Keeps this owned resource alive beyond the scope it was received in, for
  /// instance to store it in a field. Call [Resource.dispose] when done with it.
  ///
  /// Borrowed resources (such as the `server` passed to callbacks) can't be
  /// kept.
  T keep() {
    if (!isValid) {
      throw StateError(
        'Cannot keep this $runtimeType: it is no longer valid '
        '($_invalidatedBy).',
      );
    }
    if (!isOwned) {
      throw StateError(
        'Cannot keep a borrowed resource: the host only lends it for the '
        'duration of the call.',
      );
    }
    _scope?._unregister(this);
    _scope = null;
    return this;
  }
}

/// The resources received during one call from the host into the component.
final class ResourceScope {
  static ResourceScope? _current;

  /// The scope new resources are registered with, if any.
  static ResourceScope? get current => _current;

  final ResourceScope? _parent;
  final Map<int, Resource> _resources = {};
  bool _held = false;
  bool _exited = false;

  /// What the scope belongs to (the export or task name), for lifetime errors.
  /// The API names a scope once it knows which callback the export is running
  /// (see [labelCurrent]); the export itself only knows the host function.
  String? label;

  ResourceScope._(this._parent, [this.label]);

  /// The scope in a lifetime error. Only read while the error is being built,
  /// so a label the API set after the resources were received is included.
  String get _description => label ?? '<unnamed scope>';

  /// Opens a scope that becomes the current one until it is [exit]ed. Scopes
  /// nest, as the host may call back into the component while a call is
  /// running.
  static ResourceScope enter() {
    final scope = ResourceScope._(_current);
    _current = scope;
    return scope;
  }

  /// Names the scope the host is currently in, so a lifetime error can say
  /// which callback received the resource. Called by the API, which knows the
  /// event's name; the export that opened the scope does not.
  static void labelCurrent(String label) => _current?.label = label;

  /// Creates a scope without making it the current one. Work is done in it with
  /// [run], which is how tasks that interleave with others use their scope.
  static ResourceScope detached([String? label]) => ResourceScope._(null, label);

  /// Runs [body] with this scope as the current one, for code that continues
  /// work started inside the scope after the original call returned.
  R run<R>(R Function() body) {
    final previous = _current;
    _current = this;
    try {
      return body();
    } finally {
      _current = previous;
    }
  }

  void _register(Resource resource) {
    _resources[resource._id] = resource;
  }

  void _unregister(Resource resource) {
    _resources.remove(resource._id);
  }

  /// Delays releasing owned resources until [release] is called. Borrowed
  /// resources are still invalidated when the call returns.
  void hold() {
    _held = true;
  }

  /// Ends the call that opened this scope.
  void exit() {
    if (_exited) return;
    _exited = true;
    if (identical(_current, this)) _current = _parent;

    for (final resource in _resources.values.toList()) {
      if (!resource.isOwned) {
        resource._invalidateBorrowed();
        _resources.remove(resource._id);
      }
    }
    if (!_held) release();
  }

  /// Drops all owned resources still tracked by this scope.
  void release() {
    for (final resource in _resources.values.toList()) {
      resource._releaseByScope();
    }
    _resources.clear();
  }
}
