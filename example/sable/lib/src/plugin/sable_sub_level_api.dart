// The sub-level operations other plugin **components** call.
//
// A Pumpkin server runs every plugin in its own wasm instance, and each plugin
// compiles its own copy of `package:sable`, so `SubLevelContainer`'s static map
// is per component: the container this plugin creates is invisible to the
// Simulated / Aeronautics / Offroad components, even though they link the same
// source. See `docs/sable-core-port.md`, "Cross-plugin ownership".
//
// So the model is not shared, it is *asked*: this channel is the operation
// surface. Sable keeps ownership (it creates, ticks and closes the containers)
// and the other components send operations here, over the host's plugin IPC
// (`IpcChannel`, addressed by the plugin name `sable`). Only data crosses the
// boundary — ids, positions, bounds — never objects.
//
// The handler is synchronous by construction (`IpcChannel.handle`), so an
// operation runs to completion inside Sable's component before the reply is
// sent. The *caller* awaits the reply, which is why `assemble` is only safe from
// an entry point that can await (`simulated:assemble` is dispatched from an
// async payload handler); a block-entity tick has to queue its request.
//
// Host: this file uses `pumpkin_api` (IPC + commands only).
// create's positions are not exported from its public barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../sublevel/api/sub_level_assembly_helper.dart';
import '../sublevel/math/bounding_box.dart';
import '../sublevel/model/server_sub_level.dart';
import '../sublevel/model/server_sub_level_container.dart';
import '../sublevel/model/sub_level_container.dart';

/// The IPC channel every sub-level operation travels on.
///
/// The envelope is `{"type": "sable.sublevels", "data": {"op": ...}}` (see
/// `IpcChannel`); `op` is one of [SableSubLevelOps].
const IpcChannel<Map<String, Object?>> sableSubLevelChannel = IpcChannel<
  Map<String, Object?>
>(
  sableSubLevelChannelName,
  _encodeMessage,
  _decodeMessage,
);

/// The channel name (`IpcChannel` requires one per message type).
const String sableSubLevelChannelName = 'sable.sublevels';

/// The plugin name other components address the operations to.
const String sablePluginName = 'sable';

Object? _encodeMessage(Map<String, Object?> message) => message;

Map<String, Object?> _decodeMessage(Object? json) =>
    json is Map ? {for (final entry in json.entries) '${entry.key}': entry.value} : const {};

/// The operations of [sableSubLevelChannel].
abstract final class SableSubLevelOps {
  /// `{"op": "list", "world": ...}`: every sub-level of the level.
  static const String list = 'list';

  /// `{"op": "get", "world": ..., "id": ...}`: one sub-level, or `null`.
  static const String get = 'get';

  /// `{"op": "containing", "world": ..., "pos": [x, y, z]}`: the sub-level whose
  /// plot contains a block position, or `null`.
  static const String containing = 'containing';

  /// `{"op": "areaLoaded", "world": ..., "center": [x, y, z], "range": n}`.
  static const String areaLoaded = 'areaLoaded';

  /// `{"op": "assemble", "world": ..., "anchor": [x,y,z], "blocks": [...],
  /// "bounds": [minX,minY,minZ,maxX,maxY,maxZ]}`.
  static const String assemble = 'assemble';

  /// `{"op": "subscribe"}`: push `changed` messages to the sender from now on.
  static const String subscribe = 'subscribe';

  /// The push: `{"op": "changed", "world": ..., "subLevels": [...]}`.
  static const String changed = 'changed';
}

/// The reply shape: `{"ok": true, ...}` or `{"ok": false, "error": "..."}`.
Map<String, Object?> _ok([Map<String, Object?> fields = const {}]) => {'ok': true, ...fields};

Map<String, Object?> _error(Object error) => {'ok': false, 'error': '$error'};

/// What the API needs from the plugin: the level containers, by dimension.
typedef SableLevelLookup = SubLevelContainer? Function(String world);

/// The sub-level operations of the Sable plugin.
final class SableSubLevelApi {
  SableSubLevelApi(this._containerOf, {required this.log});

  /// Resolves the world named by a request (dimension key or world id).
  final SableLevelLookup _containerOf;

  final Logger log;

  /// The components that asked for `changed` pushes.
  final Set<String> _subscribers = {};

  /// Registers the handler. Call once, from `onLoad`.
  void install() {
    sableSubLevelChannel.handle(_handle);
  }

  /// Announces the current sub-levels of [level] to the subscribers.
  ///
  /// Called when a sub-level is added or removed, so a component that keeps a
  /// mirror (it needs synchronous answers, see the class comment) can refresh
  /// it without polling.
  void announce(SubLevelContainer container) {
    if (_subscribers.isEmpty) return;
    final message = _ok({
      'op': SableSubLevelOps.changed,
      'world': container.level.dimensionId,
      'subLevels': _describeAll(container),
    });
    for (final subscriber in _subscribers.toList()) {
      sableSubLevelChannel.send(subscriber, message).then(
        (_) {},
        // A component that unloaded cannot answer; stop pushing to it.
        onError: (Object _) {
          _subscribers.remove(subscriber);
        },
      );
    }
  }

  Object? _handle(String sender, Map<String, Object?> message) {
    final op = message['op'];
    if (op == SableSubLevelOps.subscribe) {
      _subscribers.add(sender);
      return _ok({'subscribed': true});
    }

    final world = message['world'];
    if (world is! String) return _error('"world" must be a string');
    final resolved = _containerOf(world);
    if (resolved is! ServerSubLevelContainer) {
      return _error('No server sub-level container for $world (level not loaded)');
    }
    final container = resolved;

    try {
      return switch (op) {
        SableSubLevelOps.list => _ok({'subLevels': _describeAll(container)}),
        SableSubLevelOps.get => _ok({'subLevel': _describeOne(container, message['id'])}),
        SableSubLevelOps.containing => _ok({'subLevel': _containing(container, message['pos'])}),
        SableSubLevelOps.areaLoaded => _ok({'loaded': _areaLoaded(container, message)}),
        SableSubLevelOps.assemble => _assemble(container, message),
        _ => _error('Unknown sub-level operation "$op"'),
      };
    } on Object catch (error) {
      log.warn('sable.sublevels "$op" from $sender failed: $error');
      return _error(error);
    }
  }

  // --------------------------------------------------------------- operations

  Map<String, Object?> _assemble(ServerSubLevelContainer container, Map<String, Object?> message) {
    final anchor = _posOf(message['anchor']);
    final bounds = _boundsOf(message['bounds']);
    final blocks = message['blocks'];
    if (anchor == null || bounds == null || blocks is! List) {
      return _error('"anchor", "bounds" and "blocks" are required');
    }

    final positions = <Pos>[];
    for (final entry in blocks) {
      final pos = _posOf(entry);
      if (pos == null) return _error('bad block position "$entry"');
      positions.add(pos);
    }

    final subLevel = SubLevelAssemblyHelper.assembleBlocks(
      container.level,
      anchor,
      positions,
      bounds,
    );
    return _ok({
      'subLevel': _describeOne(container, subLevel.uniqueIdOrNull),
      'assembledBlocks': positions.length,
    });
  }

  Map<String, Object?>? _containing(ServerSubLevelContainer container, Object? rawPos) {
    final pos = _posOf(rawPos);
    if (pos == null) return null;
    final plot = container.getPlot(pos.$1 >> 4, pos.$3 >> 4);
    final subLevel = plot?.getSubLevel();
    if (subLevel is! ServerSubLevel) return null;
    return _describeOne(container, subLevel.uniqueIdOrNull);
  }

  bool _areaLoaded(ServerSubLevelContainer container, Map<String, Object?> message) {
    final center = _posOf(message['center']);
    final range = message['range'];
    if (center == null || range is! num) return false;

    final level = container.level;
    final r = range.toInt();
    if (center.$2 + r < level.minY || center.$2 - r >= level.maxY) return false;

    final host = container.chunkHost;
    for (var chunkX = (center.$1 - r) >> 4; chunkX <= (center.$1 + r) >> 4; chunkX++) {
      for (var chunkZ = (center.$3 - r) >> 4; chunkZ <= (center.$3 + r) >> 4; chunkZ++) {
        if (host.getLoadedChunk(chunkX, chunkZ) == null) return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------- describing

  List<Map<String, Object?>> _describeAll(SubLevelContainer container) => [
    for (final subLevel in container.getAllSubLevels())
      if (subLevel is ServerSubLevel) _describe(subLevel),
  ];

  Map<String, Object?>? _describeOne(SubLevelContainer container, Object? id) {
    if (id is! String) return null;
    final subLevel = container.getSubLevelById(id);
    if (subLevel is! ServerSubLevel) return null;
    return _describe(subLevel);
  }

  /// The data a caller can act on: identity, pose, bounds and mass.
  ///
  /// Deliberately no object graph: the receiving component can only use these
  /// values, never the sub-level itself.
  Map<String, Object?> _describe(ServerSubLevel subLevel) {
    final pose = subLevel.logicalPose;
    final position = pose.position();
    final orientation = pose.orientation();
    final bounds = subLevel.boundingBox;
    final tracker = subLevel.massTracker;
    final mass = tracker == null || tracker.isInvalid() ? null : tracker.getMass();
    final plot = subLevel.getPlot();
    final center = plot.getCenterBlock();

    return {
      'id': subLevel.uniqueIdOrNull,
      'removed': subLevel.isRemoved(),
      'position': [position.x, position.y, position.z],
      'orientation': [orientation.x, orientation.y, orientation.z, orientation.w],
      'bounds': [bounds.minX, bounds.minY, bounds.minZ, bounds.maxX, bounds.maxY, bounds.maxZ],
      'mass': mass,
      'plot': [plot.plotPos.$1, plot.plotPos.$2],
      // The plot's centre block, which is what `assembleBlocks` measures its
      // offset from (`SimAssemblyResult.offset`).
      'centerBlock': [center.$1, center.$2, center.$3],
    };
  }

  // ------------------------------------------------------------------- parsing

  static Pos? _posOf(Object? value) {
    if (value is! List || value.length != 3) return null;
    final x = _intOf(value[0]);
    final y = _intOf(value[1]);
    final z = _intOf(value[2]);
    if (x == null || y == null || z == null) return null;
    return (x, y, z);
  }

  static BoundingBox3i? _boundsOf(Object? value) {
    if (value is! List || value.length != 6) return null;
    final values = [for (final entry in value) _intOf(entry)];
    if (values.any((v) => v == null)) return null;
    return BoundingBox3i.values(
      values[0]!,
      values[1]!,
      values[2]!,
      values[3]!,
      values[4]!,
      values[5]!,
    );
  }

  static int? _intOf(Object? value) => switch (value) {
    final int v => v,
    final double v when v == v.roundToDouble() => v.toInt(),
    _ => null,
  };
}
