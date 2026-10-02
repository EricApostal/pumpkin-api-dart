import 'type.dart';
import 'type_container.dart';

final class ResolvedWitDefinitions {
  final List<ValueType> types = [];

  /// One [ResourceType] per WIT resource `TypeDef`, keyed by its index in
  /// the `type_defs` array (matching how `types` itself is indexed). Every
  /// `own<T>`/`borrow<T>` handle referencing the same WIT resource must
  /// resolve to the exact same [ResourceType] instance -- the component
  /// model identifies a resource type by its type index, so two separate
  /// `ResourceType()` allocations for the same WIT resource would be
  /// treated as two unrelated resource types. `TypesContainer` dedupes by
  /// object identity, so the raw instances are kept here and registered
  /// into `_resourceContainer` (a standalone container -- no
  /// `ComponentBuilder` exists yet at the point `readTypes` runs) through
  /// its normal registration path, rather than constructing
  /// `ModelTypeReference`s by hand.
  final Map<int, ResourceType> _rawResourceTypes = {};
  final Map<int, String> _resourceNames = {};

  /// Maps a plain type-alias `TypeDef` (`kind: {"type": N}`, e.g. from a
  /// `use other.{some-resource}` import) to the `TypeDef` index it points
  /// at. A `handle` can reference the *alias*'s index rather than the
  /// resource's own -- [_resourceTypeFor] follows this chain so that both
  /// resolve to the same [ResourceType] (component-model resource identity
  /// is per-definition, not per-alias).
  final Map<int, int> _typeAliases = {};

  final List<ModelType> _resourceTypeStorage = [];
  late final TypesContainer _resourceContainer = TypesContainer(
    _resourceTypeStorage,
  );

  void readTypes(List<Object?> types) {
    final entries = types.cast<Map<String, Object?>>();

    // Resource names (and alias chains) must all be known before resolving
    // any type below, since a `handle` can reference a resource `TypeDef`
    // (or an alias of one) occurring later in `types` than the handle
    // itself (types aren't necessarily in dependency order across
    // interfaces).
    for (final (index, entry) in entries.indexed) {
      if (entry['kind'] == 'resource') {
        _resourceNames[index] = entry['name'] as String;
      } else if (entry['kind'] case {'type': final int aliased}) {
        _typeAliases[index] = aliased;
      }
    }

    for (final entry in entries) {
      this.types.add(readType(entry));
    }
  }

  int _resolveResourceAlias(int index) {
    while (_typeAliases.containsKey(index)) {
      index = _typeAliases[index]!;
    }
    return index;
  }

  /// Looks up (or lazily creates) the [ResourceType] for the resource whose
  /// `TypeDef` is at `type_defs[index]`, or that a chain of `type_defs[index]`
  /// aliases ultimately resolves to. Called whenever a `handle` `TypeDef`
  /// references it; which resource TypeDef index it is doesn't otherwise
  /// matter here (`hasInt64Representation`/`destructor` are for guest-owned
  /// exported resources, which Pumpkin's plugin API doesn't use -- every
  /// resource it exposes, e.g. `context`, is host-owned and only ever
  /// imported).
  ModelTypeReference<ResourceType> _resourceTypeFor(int index) {
    index = _resolveResourceAlias(index);
    final raw = _rawResourceTypes.putIfAbsent(
      index,
      () => ResourceType(_resourceNames[index]!, false, null),
    );
    return _resourceContainer.registerResourceType(raw);
  }

  /// Public entry point for [_resourceTypeFor], for callers (e.g.
  /// `program_abi.dart`, exporting a resource's own type from the interface
  /// that declares it) that need the [ResourceType] for a resource
  /// `TypeDef` directly, rather than via a `handle` referencing it.
  ModelTypeReference<ResourceType> resourceTypeFor(int index) =>
      _resourceTypeFor(index);

  ValueType readType(Object type) {
    switch (type) {
      case final int index:
        return types[index];
      case 'string':
        return StringType();
      case 'bool':
        return PrimitiveType.bool;
      case 'u8':
        return PrimitiveType.u8;
      case 'u16':
        return PrimitiveType.u8;
      case 'u32':
        return PrimitiveType.u32;
      case 'u64':
        return PrimitiveType.u64;
      case 's8':
        return PrimitiveType.s8;
      case 's16':
        return PrimitiveType.s8;
      case 's32':
        return PrimitiveType.s32;
      case 's64':
        return PrimitiveType.s64;
      case 'f32':
        return PrimitiveType.f32;
      case 'f64':
        return PrimitiveType.f64;
      case 'char':
        return PrimitiveType.char;
      case 'resource':
        // A bare `resource` `TypeDef` on its own (as opposed to a `handle`
        // referencing one) never shows up as a value type directly -- only
        // `own<T>`/`borrow<T>` handles are used in signatures, and those are
        // resolved separately via `_resourceTypeFor`. But `readTypes` walks
        // `type_defs` positionally regardless of each entry's kind, so this
        // slot still needs *some* placeholder `ValueType` to keep `types`
        // aligned with `type_defs`'s indices; it's never meant to be read
        // back out directly.
        return RecordType(const []);
      case {'kind': final kind}:
        switch (kind) {
          case 'string':
            return StringType();
          case 'resource':
            return RecordType(const []);
          case {'record': final record}:
            final fields = (record as Map<String, Object?>)['fields'] as List;
            return RecordType([
              for (final field in fields.cast<Map<String, Object?>>())
                RecordField(
                  label: field['name'] as String,
                  type: readType(field['type'] as Object),
                ),
            ]);
          case {'variant': final variant}:
            final cases = (variant as Map<String, Object?>)['cases'] as List;
            return VariantType([
              for (final case_ in cases.cast<Map<String, Object?>>())
                RecordOrVariantField(
                  label: case_['name'] as String,
                  type: readOptionalType(case_['type']),
                ),
            ]);
          case {'enum': final enum_}:
            final cases = (enum_ as Map<String, Object?>)['cases'] as List;
            return EnumType([
              for (final case_ in cases.cast<Map<String, Object?>>())
                case_['name'] as String,
            ]);
          case {'flags': final flags}:
            final entries = (flags as Map<String, Object?>)['flags'] as List;
            return FlagsType([
              for (final flag in entries.cast<Map<String, Object?>>())
                flag['name'] as String,
            ]);
          case {'tuple': final tuple}:
            final elementTypes =
                (tuple as Map<String, Object?>)['types'] as List;
            return TupleType([
              for (final elementType in elementTypes)
                readType(elementType as Object),
            ]);
          case {'list': final elementType}:
            return VariableLengthListType(
              elementType: readType(elementType as Object),
            );
          case {'fixed-length-list': final fixed}:
            final [elementType, length] = fixed as List;
            return FixedLengthListType(
              elementType: readType(elementType as Object),
              length: length as int,
            );
          case {'option': final inner}:
            return OptionType(readType(inner as Object));
          case {'result': final result}:
            final ok = readOptionalType((result as Map<String, Object?>)['ok']);
            final err = readOptionalType(result['err']);

            return ResultType(ok: ok, error: err);
          case {'type': final aliased}:
            // A plain type alias (`use other.{some-type}` or `type foo =
            // bar`), not a distinct value type of its own -- just read
            // through to whatever it points at.
            return readType(aliased as Object);
          case {'handle': final handle}:
            final handleMap = handle as Map<String, Object?>;
            if (handleMap case {'own': final resourceIndex}) {
              return OwnType(_resourceTypeFor(resourceIndex as int));
            }
            if (handleMap case {'borrow': final resourceIndex}) {
              return BorrowType(_resourceTypeFor(resourceIndex as int));
            }
            throw ArgumentError('Unsupported handle: $handle');
          case {'future': final inner}:
            return FutureType(readType(inner as Object));
          case {'stream': final inner}:
            return StreamType(readType(inner as Object));
        }
    }

    throw ArgumentError('Unsupported type: $type');
  }

  ValueType? readOptionalType(Object? type) {
    return switch (type) {
      null => null,
      final type => readType(type),
    };
  }
}
