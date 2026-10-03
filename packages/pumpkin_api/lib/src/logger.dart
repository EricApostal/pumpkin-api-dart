import 'bindings.g.dart' as wit;

/// A message, or a closure producing one that only runs if the level is
/// enabled: `logger.debug(() => 'state: ${expensive()}')`.
typedef LogMessage = Object?;

/// Writes to the server's log, which prefixes lines with the plugin's name.
///
/// The global [logger] logs plain messages. Named loggers add a prefix:
///
/// ```dart
/// final log = Logger('teleport');
/// log.info('saved 3 homes');            // [teleport] saved 3 homes
/// log.debug(() => 'homes: ${dump()}');  // closure only runs if debug is on
/// log.error('save failed', error: e, stackTrace: s);
/// final n = log.time('load', () => loadAll()); // debug: "load took 12ms"
/// ```
final class Logger {
  /// The logger's name, or null for the global [logger].
  final String? name;

  final Logger? _parent;
  wit.Level? _minLevel;

  Logger._root() : name = null, _parent = null, _minLevel = wit.Level.trace;

  /// A logger that prefixes messages with `[name] `. Inherits its level from
  /// the global [logger] until [minLevel] is set.
  Logger(String this.name) : _parent = logger;

  Logger._child(String this.name, Logger this._parent);

  /// A logger named [name] below this one: `[parent.name]`-style prefixes are
  /// joined with a dot.
  Logger child(String name) => Logger._child(name, this);

  /// Messages below this level are dropped. Setting it on a named logger
  /// overrides what it inherits; set it to null to inherit again (not
  /// possible on the global [logger], where null means everything).
  wit.Level get minLevel => _minLevel ?? _parent?.minLevel ?? wit.Level.trace;
  set minLevel(wit.Level? value) => _minLevel = value;

  /// Whether a message at [level] would be written.
  bool isEnabled(wit.Level level) => level.index >= minLevel.index;

  String get _prefix {
    final path = _path;
    return path.isEmpty ? '' : '[$path] ';
  }

  String get _path {
    final parentPath = _parent?._path ?? '';
    final n = name;
    if (n == null) return parentPath;
    return parentPath.isEmpty ? n : '$parentPath.$n';
  }

  void trace(LogMessage message, {Object? error, StackTrace? stackTrace}) =>
      _log(wit.Level.trace, message, error, stackTrace);
  void debug(LogMessage message, {Object? error, StackTrace? stackTrace}) =>
      _log(wit.Level.debug, message, error, stackTrace);
  void info(LogMessage message, {Object? error, StackTrace? stackTrace}) =>
      _log(wit.Level.info, message, error, stackTrace);
  void warn(LogMessage message, {Object? error, StackTrace? stackTrace}) =>
      _log(wit.Level.warn, message, error, stackTrace);

  /// Logs at error level. [error] and [stackTrace] are appended.
  void error(LogMessage message, {Object? error, StackTrace? stackTrace}) =>
      _log(wit.Level.error, message, error, stackTrace);

  /// Runs [work] and logs how long it took at debug level. Futures are
  /// awaited: the time covers the future's completion. Failures are logged
  /// and rethrown.
  T time<T>(String label, T Function() work) {
    final watch = Stopwatch()..start();
    void done(String suffix) =>
        _log(wit.Level.debug, '$label took ${watch.elapsedMilliseconds}ms$suffix', null, null);
    final T result;
    try {
      result = work();
    } catch (_) {
      done(' (failed)');
      rethrow;
    }
    if (result is Future) {
      result.then<void>((_) => done(''), onError: (Object _) => done(' (failed)'));
    } else {
      done('');
    }
    return result;
  }

  void _log(
    wit.Level level,
    LogMessage message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!isEnabled(level)) return;
    final resolved = message is Object? Function() ? message() : message;
    final buffer = StringBuffer(_prefix)..write(resolved);
    if (error != null) buffer.write(': $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    wit.logging.log(level: level, message: buffer.toString());
  }
}

/// The plugin's logger.
final logger = Logger._root();
