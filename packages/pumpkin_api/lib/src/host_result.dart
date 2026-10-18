import 'dart:async';

import 'package:wasm_components/wasm_components.dart'
    show ErrorResult, OkResult, Result;

/// Thrown when a host call that returns `result<_, string>` fails (a refused
/// registration, an action that is out of reach, a missing block entity, ...).
/// [message] is the host's reason.
final class HostException implements Exception {
  /// What was attempted and why the host refused.
  final String message;

  const HostException(this.message);

  @override
  String toString() => 'HostException: $message';
}

/// The value of [result], or a [HostException] that names [what] failed.
T unwrapHost<T>(Result<T, String> result, String what) => switch (result) {
  OkResult(:final value) => value,
  ErrorResult(:final value) => throw HostException('$what failed: $value'),
};

/// Like [unwrapHost] for the `Future` of an async host call.
Future<T> unwrapHostAsync<T>(Future<Result<T, String>> result, String what) =>
    result.then((r) => unwrapHost(r, what));

/// Applies [f] to [value] now or when it completes.
FutureOr<R> thenOr<T, R>(FutureOr<T> value, R Function(T value) f) =>
    value is Future<T> ? value.then(f) : f(value);
