// `dev.ryanhcode.sable.command.SableStorageCommands`:
//
//  * `/sable storage prune_holding_chunks`
//  * `/sable storage find_all_sub_levels`
//  * `/sable storage find <name>`
//
// Pure: no host imports beyond the model.
import 'package:pumpkin_api/pumpkin_api.dart' show ArgumentTypes, CommandBuilder, CommandContext;

import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../model/server_sub_level_container.dart';
import '../storage/holding/saved_pointer.dart';
import '../storage/holding/sub_level_holding_chunk.dart';
import '../storage/region/sub_level_storage_file.dart';
import '../storage/serialization/sub_level_data.dart';
import '../storage/serialization/sub_level_storage.dart';
import 'command_support.dart';

/// Registers the `storage` branch under [sable].
void registerStorageCommands(CommandBuilder sable, SableCommandState state) {
  sable.sub('storage', description: 'Inspects and prunes sub-level storage', build: (storage) {
    storage.sub(
      'prune_holding_chunks',
      description: 'Deletes the holding chunks that hold no sub-levels',
      runs: (ctx) => _prune(ctx, state),
    );
    storage.sub(
      'find_all_sub_levels',
      description: 'Lists every sub-level stored in this dimension',
      runs: (ctx) => _findAll(ctx, state),
    );
    storage.sub(
      'find',
      description: 'Lists the stored sub-levels with a given name',
      build: (find) => find.arg(
        'name',
        ArgumentTypes.string,
        runs: (ctx) => _find(ctx, state, ctx.string('name')),
      ),
    );
  });
}

/// The region files of [storage]'s folder: `r.<x>.<z>.slvlr`.
Iterable<(int, int)> _regionFiles(SubLevelStorage storage) sync* {
  for (final name in storage.store.list(storage.folder)) {
    if (!name.endsWith(SubLevelRegionFile.fileExtension)) continue;
    final withoutExtension = name.substring(
      0,
      name.length - SubLevelRegionFile.fileExtension.length,
    );
    final parts = withoutExtension.split('.');
    if (parts.length != 3) continue;
    final regionX = int.tryParse(parts[1]);
    final regionZ = int.tryParse(parts[2]);
    if (regionX == null || regionZ == null) continue;
    yield (regionX, regionZ);
  }
}

/// Every holding chunk of [storage], visiting each region's 32x32 chunks.
Iterable<SubLevelHoldingChunk> _holdingChunks(SubLevelStorage storage) sync* {
  for (final region in _regionFiles(storage)) {
    for (var localX = 0; localX < SubLevelRegionFile.sideLength; localX++) {
      for (var localZ = 0; localZ < SubLevelRegionFile.sideLength; localZ++) {
        final chunkX = region.$1 * SubLevelRegionFile.sideLength + localX;
        final chunkZ = region.$2 * SubLevelRegionFile.sideLength + localZ;
        final chunk = storage.attemptLoadHoldingChunk(chunkX, chunkZ);
        if (chunk == null) continue;
        yield chunk;
      }
    }
  }
}

int _prune(CommandContext ctx, SableCommandState state) {
  final storage = _storage(ctx, state);
  var pruned = 0;
  for (final chunk in _holdingChunks(storage).toList()) {
    if (!chunk.isEmpty()) continue;
    storage.attemptRemoveHoldingChunk(chunk.pos.$1, chunk.pos.$2);
    pruned++;
  }

  ctx.reply('Pruned $pruned empty holding chunk${pruned == 1 ? '' : 's'}.');
  return 1;
}

int _findAll(CommandContext ctx, SableCommandState state) {
  final storage = _storage(ctx, state);
  final container = containerOf(ctx, state);
  var count = 0;

  for (final chunk in _holdingChunks(storage)) {
    for (final pointer in chunk.getSubLevelPointers()) {
      final data = storage.attemptLoadSubLevel(chunk.pos.$1, chunk.pos.$2, pointer);
      if (data == null) continue;
      _logFound(ctx, container, chunk, pointer, data);
      count++;
    }
  }

  ctx.reply('Found $count stored sub-level${count == 1 ? '' : 's'}.');
  return 1;
}

int _find(CommandContext ctx, SableCommandState state, String name) {
  final storage = _storage(ctx, state);
  final container = containerOf(ctx, state);
  var count = 0;

  for (final chunk in _holdingChunks(storage)) {
    for (final pointer in chunk.getSubLevelPointers()) {
      final data = storage.attemptLoadSubLevel(chunk.pos.$1, chunk.pos.$2, pointer);
      if (data == null) continue;
      final displayName = _displayName(data);
      if (displayName != name) continue;
      _logFound(ctx, container, chunk, pointer, data);
      count++;
    }
  }

  if (count == 0) {
    ctx.reply('No stored sub-level is named "$name".');
    return 0;
  }
  return 1;
}

void _logFound(
  CommandContext ctx,
  ServerSubLevelContainer container,
  SubLevelHoldingChunk chunk,
  SavedSubLevelPointer pointer,
  SubLevelData data,
) {
  final global = GlobalSavedSubLevelPointer(
    chunk.pos.$1,
    chunk.pos.$2,
    pointer.storageIndex,
    pointer.subLevelIndex,
  );
  final position = data.pose.position();
  final size = data.bounds.size();

  ctx.reply('${_displayName(data)} (${data.uuid})');
  ctx.reply(
    '  at ${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, '
    '${position.z.toStringAsFixed(2)}  [$global]',
  );
  ctx.reply(
    '  size ${size.x.toStringAsFixed(2)} x ${size.y.toStringAsFixed(2)} x '
    '${size.z.toStringAsFixed(2)}',
  );
  ctx.reply(
    '  ${SableCommandHelper.teleportSuggestion(container.level.dimensionId, position.x, position.y, position.z)}',
  );
}

String _displayName(SubLevelData data) {
  final name = data.fullTag['display_name'];
  return name is String ? name : data.uuid;
}

SubLevelStorage _storage(CommandContext ctx, SableCommandState state) =>
    containerOf(ctx, state).getHoldingChunkMap().getStorage();
