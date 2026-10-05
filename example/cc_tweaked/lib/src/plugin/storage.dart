// Where a computer's files and the plugin's records live: the plugin's data
// folder (`plugins/data/cc_tweaked/` on the server).
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../machine/mounts.dart';

/// A [FileStore] for one directory of the data folder.
final class DataFolderStore implements FileStore {
  final DataFolder _folder;
  final String _root;

  DataFolderStore(this._folder, this._root) {
    _ensureRoot();
  }

  void _ensureRoot() {
    var prefix = '';
    for (final part in _root.split('/')) {
      prefix = prefix.isEmpty ? part : '$prefix/$part';
      if (_folder.stat(prefix) == null) _folder.createDirectory(prefix);
    }
  }

  String _path(String path) => path.isEmpty ? _root : '$_root/$path';

  @override
  StoredKind? kind(String path) {
    final info = _folder.stat(_path(path));
    if (info == null) return null;
    return info.isDirectory ? StoredKind.directory : StoredKind.file;
  }

  @override
  List<String> list(String path) => [
    for (final entry in _folder.list(_path(path))) entry.name,
  ];

  @override
  int size(String path) => _folder.stat(_path(path))?.size ?? 0;

  @override
  Uint8List read(String path) => Uint8List.fromList(_folder.readAsBytes(_path(path)));

  @override
  void write(String path, Uint8List data) => _folder.writeAsBytes(_path(path), data);

  @override
  void makeDirectory(String path) => _folder.createDirectory(_path(path), recursive: false);

  @override
  void delete(String path) => _folder.delete(_path(path), recursive: true);

  @override
  DateTime? modified(String path) => _folder.stat(_path(path))?.modified;
}
