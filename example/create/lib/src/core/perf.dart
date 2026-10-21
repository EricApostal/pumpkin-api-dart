// Timing instrumentation for profiling the plugin's hot paths.
//
// Enabled by an empty `perf` file in the plugin's data folder (next to
// config.json): create it, restart, read the `[perf]` lines, delete it. Its
// content may be a number: the tick interval of the per-tick report below
// (default [tickReportEvery]). A normal server pays one bool check per
// instrumented call.
//
// Two reports come out of one switch:
//
//  * `[perf] <label>: <n>x, total <ms>, max <ms>` — the aggregate of a label over
//    the whole run, logged every [reportEvery] samples (off when 0) and for any
//    single sample that took 5ms or more. Answers "what is slow".
//  * `[perf-tick]` — one line per [tickReportEvery] server ticks with the
//    *delta* of every label over that window, as `<per-tick count>` and
//    `<per-tick microseconds>`. That is the attribution report: a label with
//    0.00/tick did not run, and one with 1.00/tick runs once per tick no matter
//    whether anything is built. Answers "what does an idle tick cost".
//
// Labels are named after the direction and the source, so the two reports can be
// read together:
//
//  * `host.<call>` — a call the plugin made *into the host* (a host import),
//    recorded at the call site (perf instrumentation of the API wrappers).
//  * `event.<type>` — one host→guest event callback: installed as
//    `eventTimingSink` (pumpkin_api), so it covers every listener the plugin
//    registered, not just the ones instrumented by hand.
//  * `tick.<handler>` — one handler of the plugin's world tick, named after the
//    module that registered it (`CreateContext.onWorldTick`).
//  * `place.*`, `track.*` — one-off work (placement, scheduled ticks).

import 'dart:async';

/// A label, its number of samples and the total microseconds.
final class PerfSample {
  int count = 0;
  int totalMicros = 0;
  int maxMicros = 0;
}

/// Where the measurements go. The plugin installs its logger in `onLoad`; a plain VM
/// test or tool leaves it `null` and pays nothing.
typedef PerfSink = void Function(String message);

/// Wall clock measurements of the instrumented paths (`Perf.measure`).
abstract final class Perf {
  /// Set from the presence of the `perf` file in `CreatePlugin.onLoad`.
  static bool enabled = false;

  static PerfSink? log;

  static final Map<String, PerfSample> samples = {};

  /// When positive, [record] also logs the aggregate of a label every this many
  /// samples. For paths called thousands of times (host calls) a per-sample log
  /// would flood the console, but the total is what matters.
  ///
  /// A per-tick report that logs every [tickReportEvery] ticks already carries
  /// the same information (as a delta, which is what an idle tick needs), so
  /// `onLoad` sets this to 0 while the per-tick report is on and leaves it at the
  /// default for a plain aggregate run.
  static int reportEvery = 200;

  /// How many server ticks one `[perf-tick]` window covers, or 0 to turn the
  /// per-tick report off. Set from the content of the `perf` file.
  static int tickReportEvery = 100;

  // --- per-tick attribution ----------------------------------------------------------------

  /// The last server tick [onTick] saw: the world tick fires once per world, so
  /// several ticks of the same number are one window boundary.
  static int _lastTick = -1;

  /// Ticks in the window being filled.
  static int _windowTicks = 0;

  /// `samples` at the start of the window: the report is the difference.
  static final Map<String, ({int count, int totalMicros})> _windowStart = {};

  /// The slowest single sample seen in the window (the aggregate `maxMicros` is
  /// for the whole run, which hides a burst that has ended).
  static final Map<String, int> _windowMax = {};

  /// Closes the window when [tick] starts a new server tick, and logs the
  /// `[perf-tick]` breakdown every [tickReportEvery] ticks.
  ///
  /// Called from the plugin's `worldTick` listener with the tick the host
  /// reported. Cheap: the only cost when nothing is instrumented is a comparison.
  static void onTick(int tick) {
    if (!enabled || tickReportEvery <= 0) return;
    if (tick == _lastTick) return; // another world of the same server tick
    _lastTick = tick;
    _windowTicks++;
    if (_windowTicks < tickReportEvery) return;

    final ticks = _windowTicks;
    _windowTicks = 0;
    final lines = <String>[];
    for (final entry in samples.entries) {
      final start = _windowStart[entry.key];
      final count = entry.value.count - (start?.count ?? 0);
      if (count == 0) continue;
      final micros = entry.value.totalMicros - (start?.totalMicros ?? 0);
      lines.add(
        '${entry.key}=${(count / ticks).toStringAsFixed(2)}/tick,'
        '${(micros / ticks).toStringAsFixed(1)}us/tick,'
        '${(micros / 1000).toStringAsFixed(1)}ms window,'
        'max ${(_windowMax[entry.key] ?? 0) / 1000}ms',
      );
    }
    for (final entry in samples.entries) {
      _windowStart[entry.key] = (
        count: entry.value.count,
        totalMicros: entry.value.totalMicros,
      );
    }
    _windowMax.clear();
    log?.call('[perf-tick] ticks=$ticks ${lines.length} live labels; ${lines.join(' | ')}');
  }

  /// Times one host→guest event callback; installed as `eventTimingSink` in
  /// `onLoad` so every listener the plugin registered is attributed, whatever
  /// API registered it.
  static void eventTime(String type, int micros) => record('event.$type', micros);

  /// Times one world-tick handler under `tick.<label>`, sync or async.
  ///
  /// One [Stopwatch] runs for the whole life of the plugin and is only *read*
  /// here: in this runtime reading the clock is a host call of a few
  /// microseconds (see [selfTest]), so allocating a watch, resetting it and
  /// starting it per handler cost more than most handlers do. One read at the
  /// start and one at the end is the minimum, and the second read also gives
  /// the gap before the handler for free — see [gapMicros].
  ///
  /// Handlers never nest; every other measurement allocates its own watch and is
  /// unaffected by this one.
  static final Stopwatch _clock = Stopwatch()..start();

  /// Where the previous handler measurement ended, on [_clock].
  static int _lastEnd = 0;

  /// Gaps below this are the framework loop and are not recorded.
  static const int gapMicros = 1000;

  static FutureOr<T> handler<T>(String label, FutureOr<T> Function() body) {
    if (!enabled) return body();
    final start = _clock.elapsedMicroseconds;
    // Time between two handler measurements: the loop, the awaits, and any stall
    // of the whole guest (GC, descheduling) that lands outside a handler. A
    // stall inside a handler lands in that handler's row instead, which is why
    // both are recorded.
    if (_lastEnd != 0) {
      final gap = start - _lastEnd;
      if (gap >= gapMicros) record('tick.gap', gap);
    }
    final result = body();
    if (result is Future<T>) {
      return result.whenComplete(() {
        final end = _clock.elapsedMicroseconds;
        _lastEnd = end;
        record('tick.$label', end - start);
      });
    }
    final end = _clock.elapsedMicroseconds;
    _lastEnd = end;
    record('tick.$label', end - start);
    return result;
  }

  /// Measures the cost of the instrumentation itself, on the platform that runs
  /// it, and logs it: the floor every row of the report includes.
  ///
  /// Called once from `onLoad`, before the first measurement window, so it costs
  /// the run nothing but tells the reader what an empty handler costs here — a
  /// `tick.<label>` row that is not much above the floor did not do any work,
  /// and a report full of them is mostly the measurer.
  static void selfTest({int iterations = 500}) {
    if (!enabled) return;
    final probe = Stopwatch()..start();
    var sum = 0;
    for (var i = 0; i < iterations; i++) {
      sum += i;
    }
    final baseline = probe.elapsedMicroseconds;
    final reads = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      sum += _clock.elapsedMicroseconds;
    }
    final perRead = (reads.elapsedMicroseconds - baseline) / iterations;
    final handlerWatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      handler('selfTest', () {});
    }
    final perHandler = handlerWatch.elapsedMicroseconds / iterations;
    final recordWatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      record('selfTest.record', 1);
    }
    final perRecord = recordWatch.elapsedMicroseconds / iterations;
    // The test's own samples are not part of any attribution, and the gap it
    // produced would otherwise show up as a stall in the first window.
    samples.remove('tick.selfTest');
    samples.remove('selfTest.record');
    samples.remove('tick.gap');
    _lastEnd = 0;
    log?.call(
      '[perf] instrumentation floor: clock read ${perRead.toStringAsFixed(2)}us, '
      'handler() ${perHandler.toStringAsFixed(2)}us, '
      'record() ${perRecord.toStringAsFixed(2)}us '
      '(over $iterations; keep $sum busy)',
    );
  }

  // --- measurement ------------------------------------------------------------------------

  /// Runs [body], recording how long it took. Logs every sample.
  static T measure<T>(String label, T Function() body) {
    if (!enabled) return body();
    final watch = Stopwatch()..start();
    try {
      return body();
    } finally {
      record(label, watch.elapsedMicroseconds);
    }
  }

  /// [measure] for an async body.
  static Future<T> measureAsync<T>(
    String label,
    Future<T> Function() body,
  ) async {
    if (!enabled) return body();
    final watch = Stopwatch()..start();
    try {
      return await body();
    } finally {
      record(label, watch.elapsedMicroseconds);
    }
  }

  /// Adds a sample to [label]; logs it when it took 5ms or more.
  static void record(String label, int micros) {
    final sample = samples.putIfAbsent(label, PerfSample.new)
      ..count += 1
      ..totalMicros += micros;
    if (micros > sample.maxMicros) sample.maxMicros = micros;
    if (micros > (_windowMax[label] ?? 0)) _windowMax[label] = micros;
    if (micros >= 5000) {
      log?.call('[perf] $label: ${(micros / 1000).toStringAsFixed(1)}ms');
    }
    final every = reportEvery;
    if (every > 0 && sample.count % every == 0) {
      log?.call(
        '[perf] $label aggregate: ${sample.count}x, '
        'total ${(sample.totalMicros / 1000).toStringAsFixed(1)}ms, '
        'max ${(sample.maxMicros / 1000).toStringAsFixed(1)}ms',
      );
    }
  }

  /// Logs the aggregates of every label, slowest total first.
  static void report(String what) {
    if (!enabled) return;
    final entries = samples.entries.toList()
      ..sort((a, b) => b.value.totalMicros.compareTo(a.value.totalMicros));
    for (final e in entries) {
      log?.call(
        '[perf] $what ${e.key}: ${e.value.count}x, '
        'total ${(e.value.totalMicros / 1000).toStringAsFixed(1)}ms, '
        'max ${(e.value.maxMicros / 1000).toStringAsFixed(1)}ms',
      );
    }
  }

  /// Forgets the samples (between phases).
  static void reset() {
    samples.clear();
    _windowStart.clear();
    _windowMax.clear();
    _windowTicks = 0;
    _lastTick = -1;
    _lastEnd = 0;
  }
}