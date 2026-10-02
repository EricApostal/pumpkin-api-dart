import 'bindings.g.dart' as wit;

/// Writes to the server's log, prefixed with the plugin's name.
final class Logger {
  const Logger._();

  void trace(Object? message) => _log(wit.Level.trace, message);
  void debug(Object? message) => _log(wit.Level.debug, message);
  void info(Object? message) => _log(wit.Level.info, message);
  void warn(Object? message) => _log(wit.Level.warn, message);
  void error(Object? message) => _log(wit.Level.error, message);

  void _log(wit.Level level, Object? message) {
    wit.logging.log(level: level, message: '$message');
  }
}

/// The plugin's logger.
const logger = Logger._();
