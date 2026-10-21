// Network payload extraction (AllPackets + Catnip + Ponder).
import 'dart:io';

import '../../lib/src/manifest/types_network.dart';
import 'java.dart';
import 'net_codec.dart';

class NetResult {
  NetResult(this.payloads, this.log);
  final List<NetPayload> payloads;
  final List<String> log;
}

/// Sources of catnip / ponder are only available as -sources.jar in ~/.m2.
Directory? _unzipSources(String name, String module) {
  final home = Platform.environment['HOME'] ?? '';
  final base = Directory('$home/.m2/repository/net/createmod/$name/$module');
  if (!base.existsSync()) return null;
  File? jar;
  for (final e in base.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('-sources.jar')) jar = e;
  }
  if (jar == null) return null;
  final out = Directory('${Directory.systemTemp.path}/create_extract_$name')..createSync(recursive: true);
  final r = Process.runSync('unzip', ['-qo', jar.path, '-d', out.path]);
  if (r.exitCode != 0) {
    stderr.writeln('unzip failed for ${jar.path}: ${r.stderr}');
    return null;
  }
  return out;
}

String _rel(String path, String createRoot, Map<String, String> jarRoots) {
  if (createRoot.isNotEmpty && path.startsWith(createRoot)) return path.substring(createRoot.length + 1);
  for (final e in jarRoots.entries) {
    if (path.startsWith(e.value)) return '${e.key}:${path.substring(e.value.length + 1)}';
  }
  return path;
}

NetDirection? _direction(SourceIndex idx, JavaClass cls) {
  JavaClass? c = cls;
  final seen = <String>{};
  while (c != null && seen.add(c.qualifiedName)) {
    final h = c.header;
    if (h.contains('ClientboundPacketPayload')) return NetDirection.clientbound;
    if (h.contains('ServerboundPacketPayload')) return NetDirection.serverbound;
    final sn = c.superName;
    c = sn == null ? null : idx.resolveClass(sn, c.file, context: c);
  }
  return null;
}

NetPayload _build(SourceIndex idx, Decoder dec, String createRoot, Map<String, String> jarRoots, String id,
    String constant, String clsExpr, JavaClass owner, JavaFile ownerFile, NetDirection? forced) {
  final cls = idx.resolveClass(clsExpr, ownerFile, context: owner);
  if (cls == null) {
    return NetPayload(
        id: id,
        direction: forced ?? NetDirection.serverbound,
        javaClass: clsExpr,
        javaSource: '?',
        fields: const [],
        verified: false,
        constant: constant,
        note: 'class not found');
  }
  final dir = forced ?? _direction(idx, cls);
  final f = cls.field('STREAM_CODEC') ?? cls.field('CODEC');
  final src = _rel(cls.file.path, createRoot, jarRoots);
  if (f == null || f.init.isEmpty) {
    return NetPayload(
        id: id,
        direction: dir ?? NetDirection.serverbound,
        javaClass: cls.qualifiedName,
        javaSource: src,
        fields: const [],
        verified: false,
        constant: constant,
        note: 'no STREAM_CODEC field');
  }
  dec.issues.clear();
  final t = dec.decode(f.init, CodecCtx(cls.file, cls));
  List<NetField> fields;
  if (t.kind == NetKind.custom && t.className == null && t.fields != null) {
    fields = t.fields!;
  } else {
    var name = 'value';
    final segs = parseSegs(f.init);
    if (segs != null && segs.isNotEmpty && segs.last.name == 'map' && segs.last.args != null) {
      final a = splitArgs(segs.last.args!);
      if (a.length == 2) name = getterName(a[1], 0);
    }
    fields = [NetField(name, t)];
  }
  var note = dec.issues.isEmpty ? null : dec.issues.toSet().join('; ');
  var verified = dec.issues.isEmpty;
  if (dir == null) {
    verified = false;
    note = '${note ?? ''} direction not determinable'.trim();
  }
  return NetPayload(
    id: id,
    direction: dir ?? NetDirection.serverbound,
    javaClass: cls.qualifiedName,
    javaSource: src,
    fields: fields,
    verified: verified,
    constant: constant,
    note: note,
  );
}

NetResult extractNetwork(String createRoot) {
  final log = <String>[];
  final catnip = _unzipSources('catnip', 'catnip-neoforge');
  final ponder = _unzipSources('ponder', 'ponder-neoforge');
  final roots = <Directory>[Directory('$createRoot/src/main/java')];
  final jarRoots = <String, String>{};
  if (catnip != null) {
    roots.add(catnip);
    jarRoots['catnip-sources'] = catnip.path;
  } else {
    log.add('catnip sources jar not found');
  }
  if (ponder != null) {
    roots.add(ponder);
    jarRoots['ponder-sources'] = ponder.path;
  } else {
    log.add('ponder sources jar not found');
  }
  final idx = SourceIndex(roots)..build();
  final dec = Decoder(idx);

  final apFile = idx.fileAt('$createRoot/src/main/java/com/simibubi/create/AllPackets.java')!;
  final ap = apFile.classes.firstWhere((c) => c.name == 'AllPackets');
  final payloads = <NetPayload>[];
  for (final ec in ap.enumConstants) {
    final m = RegExp(r'^([\w.]+)\.class\s*,').firstMatch(ec.args);
    if (m == null) {
      log.add('cannot parse AllPackets entry ${ec.name}');
      continue;
    }
    final p = _build(idx, dec, createRoot, jarRoots, 'create:${ec.name.toLowerCase()}', ec.name, m.group(1)!, ap, apFile, null);
    payloads.add(applyOverride(p, idx, dec, ap, apFile));
  }
  payloads.addAll(catnipPonderPayloads(idx, dec, jarRoots, log));
  return NetResult(payloads, log);
}

// -------------------------------------------------------------- overrides

const _uuid = NetType(NetKind.uuid);
const _int = NetType(NetKind.int);
const _varint = NetType(NetKind.varint);
const _bool = NetType(NetKind.bool);
const _double = NetType(NetKind.double);
const _vec3 = NetType(NetKind.vec3);
const _string = NetType(NetKind.string, maxLength: 32767);
const _blockPos = NetType(NetKind.blockPos);

NetPayload _with(NetPayload p, {List<NetField>? fields, bool? verified, String? note}) => NetPayload(
      id: p.id,
      direction: p.direction,
      javaClass: p.javaClass,
      javaSource: p.javaSource,
      fields: fields ?? p.fields,
      verified: verified ?? p.verified,
      constant: p.constant,
      note: note ?? p.note,
    );

/// Hand verified wire formats for codecs written with `StreamCodec.of(...)`
/// or registry dispatch codecs (read from the Java `write`/`read` methods).
NetPayload applyOverride(NetPayload p, SourceIndex idx, Decoder dec, JavaClass ap, JavaFile apFile) {
  switch (p.id) {
    case 'create:place_package_port':
      {
        dec.issues.clear();
        dec.issues.clear();
        final cls = idx.resolveClass('PackagePortPlacementPacket', apFile, context: ap)!;
        final ctx = CodecCtx(cls.file, cls);
        final chain2 = dec.decode('PackagePortTarget.ChainConveyorFrogportTarget.STREAM_CODEC', ctx);
        final station2 = dec.decode('PackagePortTarget.TrainStationFrogportTarget.STREAM_CODEC', ctx);
        final ok = dec.issues.isEmpty;
        return _with(p,
            fields: [
              NetField(
                  'target',
                  NetType(NetKind.dispatch, className: 'PackagePortTargetType (registry id, varint)', fields: [
                    NetField('create:chain_conveyor', chain2),
                    NetField('create:train_station', station2),
                  ])),
              const NetField('pos', _blockPos),
            ],
            verified: ok,
            note: 'PackagePortTarget.STREAM_CODEC = registry(PACKAGE_PORT_TARGET_TYPE).dispatch(...): varint registry id '
                '(registration order: chain_conveyor=0, train_station=1) then the type codec.');
      }
    case 'create:sync_rail_graph':
      {
        const nodeLoc = NetType(NetKind.custom, className: 'TrackNodeLocation', fields: [
          NetField('x', _varint),
          NetField('y', NetType(NetKind.short)),
          NetField('z', _varint),
          NetField('yOffsetPixels', _varint),
          NetField('dimensionIndex', _varint),
        ]);
        const bezier = NetType(NetKind.custom, className: 'BezierConnection', fields: [
          NetField('bePosition0', _blockPos),
          NetField('bePosition1', _blockPos),
          NetField('start0', _vec3),
          NetField('start1', _vec3),
          NetField('axis0', _vec3),
          NetField('axis1', _vec3),
          NetField('normal0', _vec3),
          NetField('normal1', _vec3),
          NetField('primary', _bool),
          NetField('hasGirder', _bool),
          NetField('material', _string),
          NetField(
              'smoothing',
              NetType(NetKind.optional,
                  element: NetType(NetKind.custom, fields: [NetField('first', _varint), NetField('second', _varint)]))),
        ]);
        const edgePoint = NetType(NetKind.custom, className: 'TrackEdgePoint', fields: [
          NetField('type', NetType(NetKind.resourceLocation)),
          NetField('id', _uuid),
          NetField('edgeLocation0', nodeLoc),
          NetField('edgeLocation1', nodeLoc),
          NetField('position', _double),
          NetField(
              'subclassData',
              NetType(NetKind.custom,
                  className: 'TrackEdgePoint subclass data (type create:signal: 2x [bool present, uuid group]; type create:station: name, bool assembling, [bool present, blockPos]; other types write nothing)',
                  fields: [])),
        ]);
        return _with(p,
            fields: [
              const NetField('graphId', _uuid),
              const NetField('netId', _int),
              const NetField('packetDeletesGraph', _bool),
              const NetField('fullWipe', _bool),
              NetField(
                  'dimensionPalette',
                  NetType(NetKind.list,
                      element: NetType(NetKind.resourceLocation), className: 'DimensionPalette (int count prefix)')),
              const NetField('removedNodes', NetType(NetKind.list, element: _varint)),
              const NetField(
                  'addedNodes',
                  NetType(NetKind.map,
                      key: _varint,
                      value: NetType(NetKind.custom, fields: [NetField('location', nodeLoc), NetField('position', _vec3)]))),
              const NetField(
                  'addedEdges',
                  NetType(NetKind.list,
                      element: NetType(NetKind.custom, fields: [
                        NetField('node0', _varint),
                        NetField('node1', _varint),
                        NetField('trackMaterial', _string),
                        NetField('bezier', NetType(NetKind.optional, element: bezier, nullable: true)),
                      ]))),
              const NetField('addedEdgePoints', NetType(NetKind.list, element: edgePoint)),
              const NetField('removedEdgePoints', NetType(NetKind.list, element: _uuid)),
              const NetField(
                  'updatedEdgeData',
                  NetType(NetKind.list,
                      element: NetType(NetKind.custom, fields: [
                        NetField('node0', _int),
                        NetField('node1', _int),
                        NetField('groupType', _varint),
                        NetField('ids', NetType(NetKind.list, element: _uuid)),
                      ]))),
              const NetField(
                  'splitSubGraphs',
                  NetType(NetKind.map,
                      key: _varint,
                      value: NetType(NetKind.custom, fields: [NetField('netId', _int), NetField('graphId', _uuid)]))),
            ],
            verified: true,
            note: 'Hand decoded from TrackGraphSyncPacket.write(): every field after fullWipe is absent when '
                'packetDeletesGraph is true. The dimension palette is written first (int count, then identifiers), '
                'followed by the lists in the order shown. SignalBoundary and GlobalStation edge points append subclass data (see the subclassData field).');
      }
  }
  return p;
}

List<NetPayload> catnipPonderPayloads(SourceIndex idx, Decoder dec, Map<String, String> jarRoots, List<String> log) {
  final out = <NetPayload>[];
  NetPayload make(String id, String fqn, NetDirection dir, {List<NetField>? fields, String? note}) {
    final f = idx.fileForFqn(fqn);
    if (f == null) {
      log.add('missing source for $fqn');
      return NetPayload(
          id: id, direction: dir, javaClass: fqn, javaSource: '?', fields: const [], verified: false, note: 'source not found');
    }
    final cls = f.classes.firstWhere((c) => c.name == fqn.split('.').last);
    final owner = cls;
    final built = _build(idx, dec, '', jarRoots, id, '', cls.name, owner, f, dir);
    final src = _rel(f.path, '', jarRoots);
    return NetPayload(
      id: id,
      direction: dir,
      javaClass: fqn,
      javaSource: src,
      fields: fields ?? built.fields,
      verified: fields != null ? true : built.verified,
      note: note ?? built.note,
    );
  }

  out.add(make('catnip:open_config_screen', 'net.createmod.catnip.impl.config.packet.OpenConfigScreenPacket',
      NetDirection.clientbound,
      note: 'Either<String modId, Either<ConfigId, ConfigValueId>>: bool(isLeft) then the left/right value.'));
  out.add(make('catnip:set_config_value', 'net.createmod.catnip.impl.config.packet.ClientboundSetConfigValuePacket',
      NetDirection.clientbound));
  {
    final f = idx.fileForFqn('net.createmod.catnip.impl.config.packet.ServerboundSetConfigValuesPacket')!;
    final cls = f.classes.first;
    dec.issues.clear();
    final path = dec.decode('ConfigPath.STREAM_CODEC', CodecCtx(f, cls));
    final wrapped = NetType(NetKind.dispatch, className: 'WrappedConfigValue.Type', fields: const [
      NetField('BOOL', _bool),
      NetField('INT', _varint),
      NetField('FLOAT', NetType(NetKind.float)),
      NetField('DOUBLE', _double),
      NetField('STRING', _string),
      NetField('ENUM', _varint),
    ]);
    out.add(NetPayload(
      id: 'catnip:set_config_values',
      direction: NetDirection.serverbound,
      javaClass: 'net.createmod.catnip.impl.config.packet.ServerboundSetConfigValuesPacket',
      javaSource: _rel(f.path, '', jarRoots),
      verified: dec.issues.isEmpty,
      note: 'changes: varint count, then (ConfigPath, WrappedConfigValue) pairs; WrappedConfigValue is a tagged union: '
          'varint ordinal of WrappedConfigValue.Type then the variant value (ENUM = varint ordinal).',
      fields: [
        const NetField('modId', _string),
        NetField('changes', NetType(NetKind.map, key: path, value: wrapped)),
      ],
    ));
  }
  out.add(make('ponder:reload_ponder', 'net.createmod.ponder.impl.packet.ReloadPonderPacket', NetDirection.clientbound));
  {
    final f = idx.fileForFqn('net.createmod.ponder.impl.packet.OpenPonderPacket')!;
    out.add(NetPayload(
      id: 'ponder:open_ponder',
      direction: NetDirection.clientbound,
      javaClass: 'net.createmod.ponder.impl.packet.OpenPonderPacket',
      javaSource: _rel(f.path, '', jarRoots),
      verified: true,
      note: 'Target is a tagged union: varint ordinal of OpenPonderPacket.Target.Type then the variant payload.',
      fields: const [
        NetField(
            'target',
            NetType(NetKind.dispatch, className: 'OpenPonderPacket.Target.Type', fields: [
              NetField('INDEX', NetType(NetKind.custom, fields: [])),
              NetField('TAGS', NetType(NetKind.custom, fields: [])),
              NetField('SCENE', NetType(NetKind.resourceLocation)),
            ])),
      ],
    ));
  }
  return out;
}
