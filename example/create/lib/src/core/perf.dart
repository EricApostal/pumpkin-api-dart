// Timing instrumentation for profiling the plugin's hot paths.
//
// Enabled by an empty `perf` file in the plugin's data folder (next to
// config.json): create it, restart, read the `[perf]` lines, delete it. A normal
// server pays one bool check per instrumented call. Each measurement logs the
// elapsed time at info level when it took 5ms or more; [report] logs the
// aggregates.

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
  /// Set from `core.debug_timings` in `CreatePlugin.onLoad`.
  static bool enabled = false;

  static PerfSink? log;

  static final Map<String, PerfSample> samples = {};

  /// When positive, [record] also logs the aggregate of a label every this many
  /// samples. For paths called thousands of times (host calls) a per-sample log
  /// would flood the console, but the total is what matters.
  static int reportEvery = 200;

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
  static void reset() => samples.clear();
}
