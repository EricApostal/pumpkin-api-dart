import 'dart:async';

/// Runs async actions one after another per key. Host calls finish later, so
/// without it two callers could both pass a check before either has made the
/// change that the check is about.
final class KeyedLock {
  final Map<Object, Completer<void>> _tails = {};

  /// Runs [action] once every earlier action for [key] is done.
  Future<T> run<T>(Object key, Future<T> Function() action) async {
    final previous = _tails[key];
    final done = Completer<void>();
    _tails[key] = done;
    try {
      if (previous != null) await previous.future;
      return await action();
    } finally {
      done.complete();
      if (identical(_tails[key], done)) _tails.remove(key);
    }
  }
}
