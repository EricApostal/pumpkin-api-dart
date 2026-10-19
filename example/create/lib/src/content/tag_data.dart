// The tags of the manifest as data (pure): which tags the host can register and with which entries.
import '../manifest/manifest.dart';

enum ManifestTagKind { block, item, fluid, entityType }

/// A tag to register.
final class ManifestTag {
  final ManifestTagKind kind;
  final String tag;
  final List<String> entries;

  const ManifestTag(this.kind, this.tag, this.entries);
}

const Map<String, ManifestTagKind> _tagKinds = {
  'block': ManifestTagKind.block,
  'item': ManifestTagKind.item,
  'fluid': ManifestTagKind.fluid,
  'entity_type': ManifestTagKind.entityType,
};

/// Namespaces whose entries exist in this environment. Optional entries from other mods are skipped.
const Set<String> _knownNamespaces = {'minecraft', 'create', 'c', 'neoforge'};

/// The block, item, fluid and entity type tags of `tagDefs` (damage type, enchantment and registry
/// tags are data pack content). Tags of other mods (`curios`, `quark`) and optional entries of
/// other mods are left out; duplicate entries are merged.
List<ManifestTag> manifestTags() {
  final result = <ManifestTag>[];
  for (final def in tagDefs) {
    final kind = _tagKinds[def.category];
    if (kind == null) continue;
    final ns = def.id.substring(0, def.id.indexOf(':'));
    if (!_knownNamespaces.contains(ns)) continue;
    final entries = <String>[];
    for (final e in def.entries) {
      final colon = e.id.indexOf(':');
      final eNs = colon < 0 ? 'minecraft' : e.id.substring(0, colon);
      if (!e.required && !_knownNamespaces.contains(eNs)) continue;
      final ref = e.isTag ? '#${e.id}' : e.id;
      if (!entries.contains(ref)) entries.add(ref);
    }
    result.add(ManifestTag(kind, def.id, entries));
  }
  return result;
}
