// Fire-and-forget host calls: a write that nobody awaits, with the failure
// logged instead of crashing the tick.
//
// Pure: no host imports.
import 'dart:async';

/// Runs [future] without awaiting it; a failure is dropped.
///
/// Use it for host writes that the tick cannot wait for (redstone outputs,
/// particles, sounds). The alternative, an unawaited future with no handler,
/// reports the error as an unhandled asynchronous error and ends the tick.
void ignoredCall(Future<void> future) {
  unawaited(future.catchError((Object _) {}));
}
