// Ships Create's data pack (recipes, loot tables, advancements, tags, ...) with the
// plugin. The files are embedded in `data/datapack.g.dart` (see
// tool/package_datapack.dart) because a wasm plugin has no file system apart from
// its data folder.
//
// Load time behaviour:
//  * onLoad: the pack is written to `<plugin data folder>/datapacks/create/` when
//    the embedded version/categories differ from `.stamp` there (no host server
//    is needed for that).
//  * onServerLoaded: the host datapack manager exists now. If the host knows a pack
//    called `create` (see below) and it is disabled, it is enabled (the host
//    reloads on enable); if it is already enabled but the files were rewritten
//    in this run, the datapacks are reloaded.
//
// The host only discovers packs in `<world>/datapacks/<name>` (its level info lists
// them as `file/<name>`); it does not scan plugin data folders. The operator must
// therefore link `<world>/datapacks/create` to `plugins/data/create/datapacks/create`
// (a symlink, or point the plugin data at it). When the pack is not visible the
// module logs this instruction once and does nothing else.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';
import '../core/registry.dart';
import '../data/datapack.g.dart';
import '../data/datapack_install.dart';
import '../data/datapack_settings.dart';

/// Directory of the pack inside the plugin data folder.
const String datapackDir = 'datapacks/create';

/// The pack name the host knows it by (`file/create`).
const String datapackName = 'create';

final class _FolderSink implements PackSink {
  final DataFolder folder;

  _FolderSink(this.folder);

  @override
  bool exists(String path) => folder.exists(path);

  @override
  String readString(String path) => folder.readAsString(path);

  @override
  void writeBytes(String path, List<int> bytes) => folder.writeAsBytes(path, bytes);

  @override
  void writeString(String path, String text) => folder.writeAsString(path, text);

  @override
  void createDirectory(String path) => folder.createDirectory(path);

  @override
  void deleteRecursive(String path) => folder.delete(path, recursive: true);
}

final class DatapackModule extends CreateModule {
  @override
  String get name => 'datapack';

  DatapackSettings _settings = const DatapackSettings();
  bool _wrote = false;
  bool _active = false;

  @override
  void register(CreateRegistry registry) {}

  @override
  void onLoad(CreateContext ctx) {
    _settings = ctx.config.section('datapack', DatapackSettingsMapper.fromMap, (v) => v.toMap(), const DatapackSettings());
    if (!_settings.enabled) {
      ctx.log.info('Data pack disabled by config');
      return;
    }
    try {
      final result = installDatapack(
        sink: _FolderSink(ctx.host.files),
        root: datapackDir,
        version: datapackVersion,
        mcmeta: datapackMcmeta,
        blobs: datapackBlobs,
        categories: _settings.categories,
      );
      _wrote = result.wrote;
      _active = true;
      if (result.wrote) {
        ctx.log.info('Wrote data pack $datapackVersion: ${result.files} files, ${result.bytes} bytes (${_settings.categories.toList()..sort()})');
      } else {
        ctx.log.debug('Data pack $datapackVersion is up to date');
      }
    } on FileException catch (e) {
      ctx.log.error('Could not write the data pack: $e');
    } on FormatException catch (e) {
      ctx.log.error('The embedded data pack is corrupt: ${e.message}');
    }
  }

  @override
  Future<void> onServerLoaded(CreateRuntime runtime) async {
    if (!_active || !_settings.autoEnable) return;
    final packs = runtime.server.datapacks;
    try {
      final info = packs[datapackName];
      if (info == null) {
        runtime.log.warn(
          'The host does not list a data pack called "$datapackName". It only scans <world>/datapacks: link '
          '<world>/datapacks/$datapackName to plugins/data/create/$datapackDir (ln -s) and restart.',
        );
        return;
      }
      if (!packs.isPackEnabled(datapackName)) {
        await packs.enable(datapackName); // the host reloads the datapacks itself
        runtime.log.info('Enabled data pack "$datapackName"');
      } else if (_wrote) {
        await packs.reloadPacks();
        runtime.log.info('Reloaded datapacks after updating "$datapackName"');
      }
    } on DatapackException catch (e) {
      runtime.log.warn('Data pack "$datapackName": ${e.message}');
    }
  }
}
