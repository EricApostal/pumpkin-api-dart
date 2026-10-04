import 'package:pumpkin_api/pumpkin_api.dart';

import 'storage.dart';

/// Stores documents in the plugin's data folder.
final class DataFolderBackend implements StorageBackend {
  final DataFolder _folder;

  DataFolderBackend(this._folder);

  @override
  String? read(String path) {
    try {
      return _folder.readAsString(path);
    } on FileException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  @override
  void write(String path, String content) {
    final slash = path.lastIndexOf('/');
    if (slash > 0) _folder.createDirectory(path.substring(0, slash));
    _folder.writeAsString(path, content);
  }
}
