import 'components/index_space.dart';
import 'components/type.dart';
import 'components/type_container.dart';

/// Resolves the component-level type index for a type named [typeName] owned
/// by the interface with index [ownerInterface], creating an `alias export`
/// off that interface's (already-imported) instance if necessary.
typedef ForeignTypeAlias =
    ComponentTypeIndex Function(int ownerInterface, String typeName);

/// Encodes a single WIT interface as a component-model `InstanceType`,
/// following the same algorithm `wit-component` uses (`encode_valtype`).
///
/// Every named type owned by this interface is exported by name (records/
/// variants/enums/flags *must* be named; resources are exported as `(type
/// (sub resource))`). Types owned by *other* interfaces are brought in with
/// an `alias outer` to a component-level type projected out of that
/// interface's import ([ForeignTypeAlias]) -- this preserves identity, which
/// matters for resources and for same-named types from different interfaces.
/// Anonymous structural types (handles, options, lists, tuples, results) are
/// defined inline.
final class InterfaceEncoder {
  /// The raw `type_defs` array from the encoded ABI.
  final List<Map<String, Object?>> typeDefs;

  /// Index of the interface being encoded (matches `owner: {interface: N}`).
  final int thisInterface;

  final ForeignTypeAlias foreignTypeAlias;

  InterfaceEncoder(this.typeDefs, this.thisInterface, this.foreignTypeAlias);

  final List<ModelType> _types = [];
  final List<InstanceFunctionExport> _functionExports = [];

  final Map<int, ValueTypeReference> _values = {};
  final Map<int, ModelTypeReference<ResourceType>> _resources = {};

  /// Placeholder container required by [ModelTypeReference]; instance-type
  /// serialization only reads the reference's `.index`.
  late final TypesContainer _container = TypesContainer(<ModelType>[]);

  ComponentTypeIndex get _nextIndex => ComponentTypeIndex(_types.length);

  InstanceType build() => instanceTypeFromParts(_types, _functionExports);

  /// Ensures the interface's own named type at [typeDefIndex] is defined and
  /// exported (so other interfaces / the world's exports can alias it), even
  /// if none of this interface's own functions reference it.
  void encodeOwnedType(int typeDefIndex) {
    final def = typeDefs[typeDefIndex];
    if (def['kind'] == 'resource') {
      _encodeResourceDef(typeDefIndex);
    } else {
      _encodeValueDef(typeDefIndex);
    }
  }

  /// Adds a called function to the interface's exports.
  void addFunction(String name, Map<String, Object?> function) {
    final params = <RecordField>[
      for (final rawParam in function['params'] as List)
        RecordField(
          label: rawParam['name'] as String,
          type: _encodeRef(rawParam['type'] as Object),
        ),
    ];
    final result = switch (function['result']) {
      null => null,
      final type => _encodeRef(type),
    };
    final async = _kindTag(function['kind']).contains('async');
    final funcType = FunctionType(
      async: async,
      parameters: params,
      result: result,
    );

    final index = _nextIndex;
    _types.add(funcType);
    _functionExports.add(
      InstanceFunctionExport(
        name,
        FunctionTypeReference(_container, index, funcType),
      ),
    );
  }

  static String _kindTag(Object? kind) {
    return switch (kind) {
      final String s => s,
      final Map<String, Object?> m => m.keys.single,
      _ => 'freestanding',
    };
  }

  /// Follows a chain of plain type aliases (`kind: {type: N}`, e.g. from a
  /// `use other.{foo}`) down to the underlying definition's index.
  int _resolveAlias(int index) {
    var current = index;
    while (true) {
      final kind = typeDefs[current]['kind'];
      if (kind is Map && kind['type'] is int) {
        current = kind['type'] as int;
      } else {
        return current;
      }
    }
  }

  /// Returns the owning interface index of `type_defs[index]`, or `null` if it
  /// is world-owned or unowned (anonymous structural type).
  int? _ownerInterface(int index) {
    final owner = typeDefs[index]['owner'];
    if (owner is Map && owner['interface'] is int) {
      return owner['interface'] as int;
    }
    return null;
  }

  /// Encodes a type reference as it appears in a param/field/element position:
  /// a `String` primitive name, or an `int` index into [typeDefs].
  ValueType _encodeRef(Object type) {
    return switch (type) {
      final String primitive => _primitive(primitive),
      final int index => _encodeValueDef(index),
      _ => throw ArgumentError('Unsupported type reference: $type'),
    };
  }

  static ValueType _primitive(String name) {
    return switch (name) {
      'bool' => PrimitiveType.bool,
      'u8' => PrimitiveType.u8,
      'u16' => PrimitiveType.u16,
      'u32' => PrimitiveType.u32,
      'u64' => PrimitiveType.u64,
      's8' => PrimitiveType.s8,
      's16' => PrimitiveType.s16,
      's32' => PrimitiveType.s32,
      's64' => PrimitiveType.s64,
      'f32' => PrimitiveType.f32,
      'f64' => PrimitiveType.f64,
      'char' => PrimitiveType.char,
      'string' => const StringType(),
      _ => throw ArgumentError('Unknown primitive: $name'),
    };
  }

  ValueType _encodeValueDef(int index) {
    index = _resolveAlias(index);
    if (_values[index] case final existing?) return existing;

    final def = typeDefs[index];
    final name = def['name'] as String?;
    final owner = _ownerInterface(index);

    // A named type owned by another interface: alias it inward, preserving
    // identity, instead of re-declaring it (which would also clash when two
    // interfaces export a same-named type).
    if (name != null && owner != null && owner != thisInterface) {
      final componentIndex = foreignTypeAlias(owner, name);
      final localIndex = _nextIndex;
      _types.add(OuterTypeAlias(componentIndex.index));
      final ref = ValueTypeReference(
        _container,
        localIndex,
        RecordType(const []),
      );
      _values[index] = ref;
      return ref;
    }

    final ValueType raw;
    switch (def['kind']) {
      case {'type': final String primitive}:
        // An alias of a primitive, like `type plugin-id = string`. Aliases of
        // other definitions are resolved by [_resolveAlias].
        raw = _primitive(primitive);
      case {'record': final record}:
        final fields = (record as Map<String, Object?>)['fields'] as List;
        raw = RecordType([
          for (final field in fields.cast<Map<String, Object?>>())
            RecordField(
              label: field['name'] as String,
              type: _encodeRef(field['type'] as Object),
            ),
        ]);
      case {'variant': final variant}:
        final cases = (variant as Map<String, Object?>)['cases'] as List;
        raw = VariantType([
          for (final case_ in cases.cast<Map<String, Object?>>())
            RecordOrVariantField(
              label: case_['name'] as String,
              type: switch (case_['type']) {
                null => null,
                final type => _encodeRef(type),
              },
            ),
        ]);
      case {'enum': final enum_}:
        final cases = (enum_ as Map<String, Object?>)['cases'] as List;
        raw = EnumType([
          for (final case_ in cases.cast<Map<String, Object?>>())
            case_['name'] as String,
        ]);
      case {'flags': final flags}:
        final entries = (flags as Map<String, Object?>)['flags'] as List;
        raw = FlagsType([
          for (final flag in entries.cast<Map<String, Object?>>())
            flag['name'] as String,
        ]);
      case {'tuple': final tuple}:
        final elementTypes = (tuple as Map<String, Object?>)['types'] as List;
        raw = TupleType([
          for (final elementType in elementTypes)
            _encodeRef(elementType as Object),
        ]);
      case {'list': final elementType}:
        raw = VariableLengthListType(
          elementType: _encodeRef(elementType as Object),
        );
      case {'fixed-length-list': final fixed}:
        final list = fixed as List;
        raw = FixedLengthListType(
          elementType: _encodeRef(list[0] as Object),
          length: list[1] as int,
        );
      case {'option': final inner}:
        raw = OptionType(_encodeRef(inner as Object));
      case {'result': final result}:
        final map = result as Map<String, Object?>;
        raw = ResultType(
          ok: switch (map['ok']) {
            null => null,
            final type => _encodeRef(type),
          },
          error: switch (map['err']) {
            null => null,
            final type => _encodeRef(type),
          },
        );
      case {'handle': final handle}:
        final map = handle as Map<String, Object?>;
        if (map case {'own': final resource}) {
          raw = OwnType(_encodeResourceDef(resource as int));
        } else if (map case {'borrow': final resource}) {
          raw = BorrowType(_encodeResourceDef(resource as int));
        } else {
          throw ArgumentError('Unsupported handle: $handle');
        }
      case 'resource':
        throw StateError(
          'Resource type_def #$index used directly as a value type',
        );
      case final kind:
        throw ArgumentError('Unsupported type kind: $kind');
    }

    final rawIndex = _nextIndex;
    _types.add(raw);

    final ValueTypeReference reference;
    if (name != null) {
      final exportIndex = _nextIndex;
      _types.add(
        InstanceTypeExport(
          name,
          _container,
          exportIndex,
          ValueTypeReference(_container, rawIndex, raw),
        ),
      );
      reference = ValueTypeReference(_container, exportIndex, raw);
    } else {
      reference = ValueTypeReference(_container, rawIndex, raw);
    }

    _values[index] = reference;
    return reference;
  }

  ModelTypeReference<ResourceType> _encodeResourceDef(int index) {
    index = _resolveAlias(index);
    if (_resources[index] case final existing?) return existing;

    final name = typeDefs[index]['name'] as String;
    final owner = _ownerInterface(index);

    // Foreign resource: alias inward, preserving identity (essential -- a
    // re-declared resource would be a distinct nominal type the host can't
    // link).
    if (owner != null && owner != thisInterface) {
      final componentIndex = foreignTypeAlias(owner, name);
      final localIndex = _nextIndex;
      _types.add(OuterTypeAlias(componentIndex.index));
      final reference = ModelTypeReference<ResourceType>(
        _container,
        localIndex,
        ResourceType(name, false, null),
      );
      _resources[index] = reference;
      return reference;
    }

    final resourceType = ResourceType(name, false, null);
    final localIndex = _nextIndex;
    final reference = ModelTypeReference<ResourceType>(
      _container,
      localIndex,
      resourceType,
    );
    _types.add(InstanceResourceTypeExport(name, reference));
    _resources[index] = reference;
    return reference;
  }
}
