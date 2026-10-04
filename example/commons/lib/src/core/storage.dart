import 'clock.dart';

/// Where documents are stored. The plugin uses the server's data folder
/// (`storage_pumpkin.dart`), tests use [MemoryBackend].
abstract interface class StorageBackend {
  /// The content of [path], or `null` if it doesn't exist.
  String? read(String path);

  /// Replaces the content of [path], creating it (and its folders) if needed.
  void write(String path, String content);
}

final class MemoryBackend implements StorageBackend {
  final Map<String, String> files = {};

  @override
  String? read(String path) => files[path];

  @override
  void write(String path, String content) => files[path] = content;
}

typedef LogSink = void Function(String message);

/// One JSON file holding one immutable value `T` (normally a dart_mappable
/// class), with change tracking.
///
/// ```dart
/// final doc = docs.open('economy/accounts.json',
///     decode: AccountsMapper.fromJson, encode: (v) => v.toJson(), create: Accounts.new);
/// doc.value = doc.value.copyWith(...);   // marks the document dirty
/// ```
///
/// Dirty documents are written by [Documents.saveDirty], which the plugin runs
/// periodically and when it unloads. A file that can't be decoded is copied to
/// `<path>.corrupt-<time>` and replaced by a fresh value, so one bad edit never
/// takes a module down or silently destroys data.
final class JsonDocument<T extends Object> {
  final String path;
  final StorageBackend _backend;
  final String Function(T value) _encode;
  final LogSink _warn;

  T _value;
  bool _dirty = false;

  JsonDocument._(
    this.path,
    this._backend,
    this._encode,
    this._warn,
    this._value,
  );

  T get value => _value;

  set value(T next) {
    _value = next;
    _dirty = true;
  }

  /// Replaces the value with `change(value)`.
  void modify(T Function(T current) change) => value = change(_value);

  bool get isDirty => _dirty;

  /// Writes the document now, if it changed.
  void save() {
    if (!_dirty) return;
    try {
      _backend.write(path, _encode(_value));
      _dirty = false;
    } catch (e) {
      _warn('Could not save $path: $e');
    }
  }
}

/// Opens and tracks every [JsonDocument] of the plugin.
final class Documents {
  final StorageBackend backend;
  final Clock clock;
  final LogSink warn;
  final List<JsonDocument<Object>> _open = [];

  Documents(this.backend, {this.clock = const SystemClock(), LogSink? warn})
    : warn = warn ?? ((_) {});

  /// Opens [path]. If the file doesn't exist, `create()` is used and the file
  /// is written on the next save.
  JsonDocument<T> open<T extends Object>(
    String path, {
    required T Function(String json) decode,
    required String Function(T value) encode,
    required T Function() create,
  }) {
    final text = backend.read(path);
    T value;
    var dirty = false;
    if (text == null) {
      value = create();
      dirty = true;
    } else {
      try {
        value = decode(text);
      } catch (e) {
        final stamp = clock.now().millisecondsSinceEpoch;
        warn('$path is not valid ($e), keeping a copy as $path.corrupt-$stamp');
        backend.write('$path.corrupt-$stamp', text);
        value = create();
        dirty = true;
      }
    }
    final document = JsonDocument<T>._(path, backend, encode, warn, value)
      .._dirty = dirty;
    _open.add(document as JsonDocument<Object>);
    return document;
  }

  /// Writes every document that changed.
  void saveDirty() {
    for (final document in _open) {
      document.save();
    }
  }

  int get dirtyCount => _open.where((d) => d.isDirty).length;
}
