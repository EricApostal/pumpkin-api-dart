import 'components/component.dart';
import 'components/index_space.dart';
import 'components/type.dart';
import 'components/wit.dart';
import 'interface_encoder.dart';
import 'program_abi.dart';

/// Assembles the component's imports: it encodes each interface referenced by
/// the plugin as an instance type (naming its own types, aliasing types it
/// `use`s from other interfaces), and imports them in dependency order so that
/// cross-interface `alias outer` references resolve to already-imported
/// instances.
final class ComponentAssembler {
  final ComponentBuilder builder;
  final DartProgramAbi abi;

  ComponentAssembler(this.builder, this.abi);

  List<Map<String, Object?>> get _typeDefs => abi.rawTypeDefs;

  /// The component instance each imported interface was imported as.
  final Map<ResolvedInterface, ComponentInstanceIndex> instances = {};

  /// Live named types owned by each interface index (the ones some signature
  /// actually references, so they must be exported for aliasing).
  final Map<int, Set<int>> _liveOwnedTypes = {};

  /// Resolves a chain of `kind: {type: N}` aliases to the underlying def.
  int _resolveAlias(int index) {
    var current = index;
    while (true) {
      final kind = _typeDefs[current]['kind'];
      if (kind is Map && kind['type'] is int) {
        current = kind['type'] as int;
      } else {
        return current;
      }
    }
  }

  int? _ownerInterface(int index) {
    final owner = _typeDefs[index]['owner'];
    if (owner is Map && owner['interface'] is int) {
      return owner['interface'] as int;
    }
    return null;
  }

  String? _name(int index) => _typeDefs[index]['name'] as String?;

  /// Direct type references (as `type_defs` indices) out of `type_defs[index]`.
  Iterable<int> _directRefs(int index) sync* {
    final kind = _typeDefs[index]['kind'];
    if (kind is! Map) return;
    void ref(Object? r) {}
    for (final entry in kind.entries) {
      switch (entry.key) {
        case 'record':
          for (final f
              in (entry.value as Map)['fields'] as List) {
            if (f['type'] is int) yield f['type'] as int;
          }
        case 'variant':
          for (final c in (entry.value as Map)['cases'] as List) {
            if (c['type'] is int) yield c['type'] as int;
          }
        case 'tuple':
          for (final t in (entry.value as Map)['types'] as List) {
            if (t is int) yield t;
          }
        case 'list' || 'option' || 'type':
          if (entry.value is int) yield entry.value as int;
        case 'result':
          final m = entry.value as Map;
          if (m['ok'] is int) yield m['ok'] as int;
          if (m['err'] is int) yield m['err'] as int;
        case 'handle':
          for (final v in (entry.value as Map).values) {
            if (v is int) yield v;
          }
        case 'fixed-length-list':
          final l = entry.value as List;
          if (l[0] is int) yield l[0] as int;
      }
    }
    ref(null);
  }

  /// Marks [index] (and everything it references) live, recording named types
  /// against their owning interface.
  void _markLive(int index, Set<int> visited) {
    final resolved = _resolveAlias(index);
    if (!visited.add(resolved)) return;
    final owner = _ownerInterface(resolved);
    if (owner != null && _name(resolved) != null) {
      (_liveOwnedTypes[owner] ??= {}).add(resolved);
    }
    for (final ref in _directRefs(resolved)) {
      _markLive(ref, visited);
    }
    // Also follow the pre-resolution ref so alias targets are covered.
    if (resolved != index) {
      for (final ref in _directRefs(index)) {
        _markLive(ref, visited);
      }
    }
  }

  void _markSignatureLive(Map<String, Object?> function, Set<int> visited) {
    for (final param in function['params'] as List) {
      if (param['type'] is int) _markLive(param['type'] as int, visited);
    }
    if (function['result'] is int) {
      _markLive(function['result'] as int, visited);
    }
  }

  /// Computes the live type set from every called import function and every
  /// export/hook signature.
  void _computeLiveness() {
    final visited = <int>{};
    for (final interface in abi.interfaces) {
      if (interface.isSynthetic) continue;
      for (final called in interface.importedFunctions) {
        final sig =
            interface.rawExportedFunctions[called.interfaceMethod]
                as Map<String, Object?>?;
        if (sig != null) _markSignatureLive(sig, visited);
      }
    }
    for (final export in [...abi.bareExports, ...abi.functionExports.values]) {
      _markSignatureLive(export.rawJson, visited);
    }
  }

  /// Interfaces that must be imported: those with called functions, plus those
  /// owning a live named type.
  Set<ResolvedInterface> _liveInterfaces() {
    final result = <ResolvedInterface>{};
    for (final interface in abi.interfaces) {
      if (interface.isSynthetic) {
        result.add(interface);
      } else if (interface.importedFunctions.isNotEmpty ||
          (_liveOwnedTypes[interface.index]?.isNotEmpty ?? false)) {
        result.add(interface);
      }
    }
    return result;
  }

  /// Topologically orders [live] so that an interface is imported after every
  /// interface it references types from.
  List<ResolvedInterface> _topoOrder(Set<ResolvedInterface> live) {
    final byIndex = {
      for (final i in live)
        if (!i.isSynthetic) i.index: i,
    };
    final ordered = <ResolvedInterface>[];
    final state = <int, int>{}; // 0=unvisited, 1=visiting, 2=done

    void visit(ResolvedInterface interface) {
      if (state[interface.index] == 2) return;
      state[interface.index] = 1;
      // Dependencies: interfaces owning any type referenced by this
      // interface's live owned types.
      final deps = <int>{};
      for (final owned in _liveOwnedTypes[interface.index] ?? const <int>{}) {
        for (final ref in _directRefs(owned)) {
          final owner = _ownerInterface(_resolveAlias(ref));
          if (owner != null && owner != interface.index) deps.add(owner);
        }
      }
      for (final dep in deps) {
        final depInterface = byIndex[dep];
        if (depInterface != null) visit(depInterface);
      }
      state[interface.index] = 2;
      ordered.add(interface);
    }

    // Synthetic interfaces have no ABI type dependencies; import them first.
    for (final i in live) {
      if (i.isSynthetic) ordered.add(i);
    }
    for (final i in byIndex.values) {
      visit(i);
    }
    return ordered;
  }

  ComponentTypeIndex _foreignTypeAlias(int ownerInterface, String typeName) {
    final owner = abi.interfacesByIndex[ownerInterface];
    final instance = instances[owner];
    if (instance == null) {
      throw StateError(
        'Interface ${owner.fullName} not imported before a type of it '
        '($typeName) was referenced',
      );
    }
    return builder.aliasInstanceTypeExport(instance, typeName);
  }

  /// Encodes and imports all live interfaces in dependency order.
  void buildImports() {
    _computeLiveness();
    final order = _topoOrder(_liveInterfaces());

    for (final interface in order) {
      final InstanceType instanceType;
      if (interface.isSynthetic) {
        instanceType = interface.type!;
      } else {
        final encoder = InterfaceEncoder(
          _typeDefs,
          interface.index,
          _foreignTypeAlias,
        );
        // Export every live type this interface owns (so dependents can alias
        // them), then its called functions.
        for (final owned in _liveOwnedTypes[interface.index] ?? const <int>{}) {
          encoder.encodeOwnedType(owned);
        }
        for (final called in interface.importedFunctions) {
          final sig =
              interface.rawExportedFunctions[called.interfaceMethod]
                  as Map<String, Object?>;
          encoder.addFunction(called.interfaceMethod, sig);
        }
        instanceType = encoder.build();
        interface.type = instanceType;
      }

      final typeIndex = builder.defineType(instanceType);
      instances[interface] = builder.importInstanceByType(
        interface.fullName,
        typeIndex,
      );
    }
  }

  ResolvedWitDefinitions? _definitions;

  /// Resolves the [FunctionType] of every export (interface and world-level)
  /// from its raw signature.
  ///
  /// TODO: these are currently decoded structurally (types re-declared at the
  /// concrete-component level). To link against the host, resource handles in
  /// these signatures must instead alias the imported interfaces' resources.
  void resolveExportTypes() {
    final definitions = _definitions = ResolvedWitDefinitions()
      ..readTypes(abi.rawTypeDefs);
    for (final export in abi.functionExports.values) {
      export.type = _readFunctionType(definitions, export.rawJson);
    }
  }

  /// The named value types (`record`/`variant`/`enum`/`flags`) owned by the
  /// exported interface [interface], each defined at the component level and
  /// paired with the component type index to export from the interface's
  /// instance (so its functions' signatures reference named types).
  List<(String, ComponentTypeIndex)> namedTypeExportsFor(
    ResolvedInterface interface,
  ) {
    final definitions = _definitions!;
    final result = <(String, ComponentTypeIndex)>[];
    for (final (index, def) in _typeDefs.indexed) {
      final name = def['name'] as String?;
      if (name == null) continue;
      if (_ownerInterface(index) != interface.index) continue;
      final kind = def['kind'];
      if (kind is! Map) continue;
      if (!(kind.containsKey('record') ||
          kind.containsKey('variant') ||
          kind.containsKey('enum') ||
          kind.containsKey('flags'))) {
        continue;
      }
      final ref = builder.types.addValueType(definitions.readType(def));
      result.add((name, ref.index));
    }
    return result;
  }

  static FunctionType _readFunctionType(
    ResolvedWitDefinitions definitions,
    Map<String, Object?> value,
  ) {
    final params = <RecordField>[
      for (final rawParam in value['params'] as List)
        RecordField(
          label: rawParam['name'] as String,
          type: definitions.readType(rawParam['type'] as Object),
        ),
    ];
    final result = definitions.readOptionalType(value['result']);
    final kindTag = switch (value['kind']) {
      final String s => s,
      final Map<String, Object?> m => m.keys.single,
      final other => throw ArgumentError('Unsupported function kind: $other'),
    };
    return FunctionType(
      async: kindTag.contains('async'),
      parameters: params,
      result: result,
    );
  }

  // ---------------------------------------------------------------------------
  // Root-level (world) export type encoding.
  //
  // Bare world exports (the lifecycle hooks) reference types owned by imported
  // interfaces (resources like `context`/`server`, records like
  // `command-error`) and world-owned types (the `event` variant). For a
  // root-level function export these must be *named*: interface-owned types are
  // aliased out of their imports (preserving identity), and world-owned named
  // types are defined once and exported from the component root.
  // ---------------------------------------------------------------------------

  final Map<int, ValueTypeReference> _rootValues = {};
  final Map<int, ModelTypeReference<ResourceType>> _rootResources = {};

  /// World-owned named types that must be exported from the component root so
  /// they are named where the hooks reference them (`(name, type index)`).
  final List<(String, ComponentTypeIndex)> rootTypeExports = [];

  /// Placeholder container for root-level references; only `.index` is read.
  late final _rootContainer = builder.types;

  bool _isWorldOwned(int index) {
    final owner = _typeDefs[index]['owner'];
    return owner is Map && owner.containsKey('world');
  }

  /// Builds the component-level [FunctionType] for a world-level export,
  /// naming/aliasing referenced types as required.
  FunctionType buildBareExportType(Map<String, Object?> json) {
    final params = <RecordField>[
      for (final rawParam in json['params'] as List)
        RecordField(
          label: rawParam['name'] as String,
          type: _encodeRootRef(rawParam['type'] as Object),
        ),
    ];
    final result = switch (json['result']) {
      null => null,
      final type => _encodeRootRef(type),
    };
    final kindTag = switch (json['kind']) {
      final String s => s,
      final Map<String, Object?> m => m.keys.single,
      _ => 'freestanding',
    };
    return FunctionType(
      async: kindTag.contains('async'),
      parameters: params,
      result: result,
    );
  }

  /// Builds the component function type for a world-level export and returns a
  /// reference to it, for use in `canon lift`.
  FunctionTypeReference bareExportFunctionType(Map<String, Object?> json) {
    final functionType = buildBareExportType(json);
    final index = builder.defineType(functionType);
    return FunctionTypeReference(builder.types, index, functionType);
  }

  ValueType _encodeRootRef(Object type) {
    return switch (type) {
      final String primitive => _rootPrimitive(primitive),
      final int index => _encodeRootValueDef(index),
      _ => throw ArgumentError('Unsupported type reference: $type'),
    };
  }

  static ValueType _rootPrimitive(String name) {
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

  ValueType _encodeRootValueDef(int index) {
    index = _resolveAlias(index);
    if (_rootValues[index] case final existing?) return existing;

    final def = _typeDefs[index];
    final name = def['name'] as String?;
    final owner = _ownerInterface(index);

    // Interface-owned named type: alias it in from the interface's import.
    if (name != null && owner != null) {
      final componentIndex = _foreignTypeAlias(owner, name);
      final ref = ValueTypeReference(
        _rootContainer,
        componentIndex,
        RecordType(const []),
      );
      _rootValues[index] = ref;
      return ref;
    }

    final ValueType built;
    switch (def['kind']) {
      case {'record': final record}:
        built = RecordType([
          for (final field
              in ((record as Map)['fields'] as List)
                  .cast<Map<String, Object?>>())
            RecordField(
              label: field['name'] as String,
              type: _encodeRootRef(field['type'] as Object),
            ),
        ]);
      case {'variant': final variant}:
        built = VariantType([
          for (final case_
              in ((variant as Map)['cases'] as List)
                  .cast<Map<String, Object?>>())
            RecordOrVariantField(
              label: case_['name'] as String,
              type: switch (case_['type']) {
                null => null,
                final type => _encodeRootRef(type),
              },
            ),
        ]);
      case {'enum': final enum_}:
        built = EnumType([
          for (final case_
              in ((enum_ as Map)['cases'] as List)
                  .cast<Map<String, Object?>>())
            case_['name'] as String,
        ]);
      case {'flags': final flags}:
        built = FlagsType([
          for (final flag
              in ((flags as Map)['flags'] as List)
                  .cast<Map<String, Object?>>())
            flag['name'] as String,
        ]);
      case {'tuple': final tuple}:
        built = TupleType([
          for (final t in (tuple as Map)['types'] as List)
            _encodeRootRef(t as Object),
        ]);
      case {'list': final el}:
        built = VariableLengthListType(elementType: _encodeRootRef(el as Object));
      case {'fixed-length-list': final fixed}:
        final l = fixed as List;
        built = FixedLengthListType(
          elementType: _encodeRootRef(l[0] as Object),
          length: l[1] as int,
        );
      case {'option': final inner}:
        built = OptionType(_encodeRootRef(inner as Object));
      case {'result': final result}:
        final m = result as Map;
        built = ResultType(
          ok: switch (m['ok']) {
            null => null,
            final Object t => _encodeRootRef(t),
          },
          error: switch (m['err']) {
            null => null,
            final Object t => _encodeRootRef(t),
          },
        );
      case {'handle': final handle}:
        final m = handle as Map;
        if (m case {'own': final r}) {
          built = OwnType(_encodeRootResourceDef(r as int));
        } else if (m case {'borrow': final r}) {
          built = BorrowType(_encodeRootResourceDef(r as int));
        } else {
          throw ArgumentError('Unsupported handle: $handle');
        }
      case final kind:
        throw ArgumentError('Unsupported root type kind: $kind');
    }

    final ref = _rootContainer.addValueType(built);
    if (name != null && _isWorldOwned(index)) {
      // World-owned named types are exported from the component root so they
      // are named where the hooks reference them.
      rootTypeExports.add((name, ref.index));
    }
    _rootValues[index] = ref;
    return ref;
  }

  ModelTypeReference<ResourceType> _encodeRootResourceDef(int index) {
    index = _resolveAlias(index);
    if (_rootResources[index] case final existing?) return existing;

    final owner = _ownerInterface(index);
    final name = _name(index)!;
    if (owner == null) {
      throw StateError('Resource $name has no owning interface to alias from');
    }
    final componentIndex = _foreignTypeAlias(owner, name);
    final reference = ModelTypeReference<ResourceType>(
      _rootContainer,
      componentIndex,
      ResourceType(name, false, null),
    );
    _rootResources[index] = reference;
    return reference;
  }
}
