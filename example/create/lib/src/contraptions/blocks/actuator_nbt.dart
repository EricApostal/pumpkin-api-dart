// The assembly-exception NBT of the actuator block entities, written into the host compound the
// client reads (`LastException {Component, Position}`).
//
// `AssemblyException` is a pure class over `NbtMap`; the block entities hold a host `NbtCompound`,
// so these two helpers bridge it without converting whole tags.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/nbt_map.dart';
import '../core/structure_info.dart';

/// `AssemblyException.write(compound, exception)`.
void writeAssemblyException(NbtCompound tag, AssemblyException? exception) {
  if (exception == null) return;
  final nbt = NbtCompound()
    ..putString('Component', exception.toComponentJson());
  final p = exception.position;
  if (p != null) nbt.putLong('Position', packBlockPos(p));
  tag.putCompound('LastException', nbt);
}

/// `AssemblyException.read(compound)`.
AssemblyException? readAssemblyException(NbtCompound tag) {
  final source = tag.getCompound('LastException');
  if (source == null) return null;
  final map = NbtMap()
    ..putString('Component', source.getString('Component') ?? '');
  final position = source.getInt('Position');
  if (position != null) map.putLong('Position', position);
  return AssemblyException.read(map);
}
