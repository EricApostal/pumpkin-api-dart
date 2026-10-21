import 'dart:io';
import '../test/support/pumpkin_trace.dart';

void main(List<String> args) {
  final origin = TracePos(int.parse(args[1]), int.parse(args[2]), int.parse(args[3]));
  final trace = PumpkinTrace.read(File(args[0]));
  final seen = <String>{};
  for (final p in trace.blockEntityData) {
    final pos = p.pos;
    if (pos == null) continue;
    final dx = pos.x - origin.x, dy = pos.y - origin.y, dz = pos.z - origin.z;
    if (dx < -1 || dx > 1 || dy < -2 || dy > 2 || dz < -2 || dz > 4) continue;
    final rel = '$dx,$dy,$dz';
    if (!seen.add(rel)) continue;
    print('== $rel ${p.nbt}');
  }
}
