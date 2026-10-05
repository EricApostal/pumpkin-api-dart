// The `file_transfer` event of CC: Tweaked (`TransferredFiles`,
// `TransferredFile` in core/apis/transfer): the files a player dropped onto the
// terminal, as objects the program reads.
import 'dart:typed_data';

import '../lua/lua.dart';
import 'api/fs_api.dart' show buildBinaryReadHandle;
import 'filesystem.dart' show OpenFile;

/// One transferred file: a name and its content.
final class TransferredFileData {
  final String name;
  final Uint8List bytes;

  const TransferredFileData(this.name, this.bytes);
}

/// The first argument of the `file_transfer` event: a table whose `getFiles()`
/// returns the files, each a binary read handle (`read`, `readAll`, `readLine`,
/// `seek`, `close`) with an extra `getName()`. [onConsumed] runs the first
/// time `getFiles` is called (CC tells the client the upload was consumed).
///
/// Differences from CC: the handle is the plugin's own binary read handle (the
/// same one `fs.open(path, "rb")` returns), not `ReadHandle`'s class, so the
/// methods `ReadHandle` has beyond those (none that `rom/programs/import.lua`
/// uses) are absent.
LuaTable buildTransferredFiles(List<TransferredFileData> files, void Function() onConsumed) {
  var consumed = false;
  final table = LuaTable();
  table.setString(
    'getFiles',
    NativeFunction('getFiles', (_) {
      if (!consumed) {
        consumed = true;
        onConsumed();
      }
      final list = LuaTable();
      var index = 1;
      for (final file in files) {
        final handle = buildBinaryReadHandle(OpenFile.memory(file.bytes));
        handle.setString('getName', NativeFunction('getName', (_) => one(file.name)));
        list.setInt(index++, handle);
      }
      return one(list);
    }),
  );
  return table;
}
