// Loading schematic files into [TemplateData] and [SchematicWorld], with the 5 minute cache of
// `SchematicInstances`.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart' show BlockPosToPos;
import '../schematic_world.dart';
import '../upload_receiver.dart';

/// Converts a host template to plain data.
TemplateData templateDataOf(StructureTemplate template) {
  final palette = [
    for (final e in template.palette) BState(e.name.contains(':') ? e.name : 'minecraft:${e.name}', {for (final (k, v) in e.properties) k: v}),
  ];
  final blocks = <TemplateBlock>[];
  for (final b in template.blocks) {
    if (b.paletteIndex < 0 || b.paletteIndex >= palette.length) continue;
    blocks.add(TemplateBlock(b.pos.toPos(), palette[b.paletteIndex], b.nbt));
  }
  final entities = [
    for (final e in template.entities) TemplateEntity(e.pos, e.blockPos.toPos(), e.nbt),
  ];
  return TemplateData(template.size.toPos(), blocks, entities);
}

/// A cached schematic world.
class _Cached {
  final SchematicWorld world;
  int lastAccess;

  _Cached(this.world, this.lastAccess);
}

/// Reads schematic files from the store.
final class SchematicLoader {
  final SchematicFileStore store;
  final Logger log;
  final int Function() nowMs;

  SchematicLoader(this.store, this.log, {int Function()? nowMs}) : nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Map<String, _Cached> _cache = {};
  static const int cacheLifetimeMs = 5 * 60 * 1000;

  /// The path of an uploaded schematic or `null` when the name is unsafe.
  static String? pathFor(String owner, String file) {
    if (!SchematicUploadReceiver.isSafeName(owner) || !SchematicUploadReceiver.isSafeName(file) || !file.endsWith('.nbt')) {
      return null;
    }
    return SchematicUploadReceiver.pathOf(owner, file);
  }

  /// `SchematicItem.loadSchematic`: the template of the file, `null` (with a log) when it cannot be read.
  TemplateData? loadTemplate(String owner, String file) {
    final path = pathFor(owner, file);
    if (path == null || !store.exists(path)) return null;
    try {
      final bytes = store.read(path);
      return templateDataOf(StructureTemplates.load(bytes));
    } on Object catch (e) {
      log.warn('Failed to read schematic $owner/$file: $e');
      return null;
    }
  }

  /// The raw host template (for the creative placement through the host).
  StructureTemplate? loadHostTemplate(String owner, String file) {
    final path = pathFor(owner, file);
    if (path == null || !store.exists(path)) return null;
    try {
      return StructureTemplates.load(store.read(path));
    } on Object catch (e) {
      log.warn('Failed to read schematic $owner/$file: $e');
      return null;
    }
  }

  /// `SchematicItem.writeSize`: the template size of a file, `null` when unreadable.
  Pos? sizeOf(String owner, String file) {
    final t = loadTemplate(owner, file);
    return t?.size;
  }

  /// `SchematicInstances.get`: the world of a deployed schematic, cached for five minutes.
  /// `null` when the file is missing or empty.
  SchematicWorld? world(String owner, String file, Pos anchor, BlockRotation rotation, BlockMirror mirror) {
    final now = nowMs();
    _cache.removeWhere((_, c) => now - c.lastAccess > cacheLifetimeMs);
    final key = '$owner/$file/${anchor.$1},${anchor.$2},${anchor.$3}/${rotation.index}/${mirror.index}';
    final hit = _cache[key];
    if (hit != null) {
      hit.lastAccess = now;
      return hit.world;
    }
    final template = loadTemplate(owner, file);
    if (template == null || template.isEmpty) return null;
    final w = SchematicWorld.fromTemplate(template, anchor: anchor, rotation: rotation, mirror: mirror);
    _cache[key] = _Cached(w, now);
    return w;
  }

  void clearCache() => _cache.clear();

  /// The bytes of a stored schematic (for tools), or `null`.
  Uint8List? bytes(String owner, String file) {
    final path = pathFor(owner, file);
    if (path == null || !store.exists(path)) return null;
    return store.read(path);
  }
}

/// The schematic store on the plugin data folder.
final class DataFolderSchematicStore implements SchematicFileStore {
  final DataFolder folder;

  DataFolderSchematicStore(this.folder);

  @override
  bool exists(String path) => folder.stat(path)?.isFile ?? false;

  @override
  void write(String path, List<int> bytes, {bool append = false}) => folder.writeAsBytes(path, bytes, append: append);

  @override
  void delete(String path) {
    if (folder.stat(path) != null) folder.delete(path);
  }

  @override
  void createDirectory(String path) => folder.createDirectory(path);

  @override
  List<StoredSchematic> list(String dir) {
    if (folder.stat(dir) == null) return const [];
    return [
      for (final e in folder.list(dir))
        StoredSchematic(e.name, e.isDirectory, folder.stat('$dir/${e.name}')?.modified?.millisecondsSinceEpoch ?? 0),
    ];
  }

  @override
  Uint8List read(String path) => Uint8List.fromList(folder.readAsBytes(path));
}
