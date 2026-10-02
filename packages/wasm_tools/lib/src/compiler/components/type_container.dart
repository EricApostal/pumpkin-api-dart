import 'index_space.dart';
import 'type.dart';

final class TypesContainer {
  final Map<ModelType, ModelTypeReference> _typesToIndex = {};

  /// Allocates the next component-type index for [type], appending it wherever
  /// this container's types live (a plain list, or the enclosing component's
  /// interleaved top-level declaration stream). Returns the assigned index.
  final ComponentTypeIndex Function(ModelType type) _allocate;

  TypesContainer._(this._allocate);

  /// A container backed by a plain list -- indices are positions in [types].
  /// Used for self-contained (instance-local) type spaces.
  factory TypesContainer(List<ModelType> types) {
    return TypesContainer._((type) {
      final idx = ComponentTypeIndex(types.length);
      types.add(type);
      return idx;
    });
  }

  /// A container whose type indices are allocated by [allocate] -- used for
  /// the top-level component type space, which interleaves plain type
  /// definitions with instance imports and outer/export aliases.
  factory TypesContainer.allocated(
    ComponentTypeIndex Function(ModelType type) allocate,
  ) {
    return TypesContainer._(allocate);
  }

  R _addType<T extends ModelType, R extends ModelTypeReference<T>>(
    T type,
    R Function(TypesContainer, ComponentTypeIndex, T) create,
  ) {
    return _typesToIndex.putIfAbsent(type, () {
      final idx = _allocate(type);
      return create(this, idx, type);
    }) as R;
  }

  FunctionTypeReference addFunctionType(FunctionType type) {
    if (type case FunctionTypeReference ref
        when identical(ref.container, this)) {
      return type;
    }

    final result = switch (type.result) {
      null => null,
      final type => _fieldType(type),
    };
    final params = [
      for (final param in type.parameters)
        RecordOrVariantField(label: param.label, type: _fieldType(param.type)),
    ];

    return _addType(
      FunctionType(async: type.async, parameters: params, result: result),
      FunctionTypeReference.new,
    );
  }

  /// Normalizes a value type used in a "child" position (record field, variant
  /// case, tuple element, function parameter, etc.).
  ///
  /// Primitives and `string` are kept *inline* (encoded as
  /// `ComponentValType::Primitive`); everything else is defined and referenced
  /// by index. The component model requires this -- wrapping a primitive in a
  /// type-section entry and referencing it makes tools like `wit-component`
  /// reject the component ("expected id-based type").
  ValueType _fieldType(ValueType type) {
    final resolved = type is ValueTypeReference ? type.resolvedType : type;
    return switch (resolved) {
      PrimitiveType() || StringType() => resolved,
      _ => addValueType(type),
    };
  }

  InstanceTypeReference addInstanceType(InstanceType type) {
    if (type case InstanceTypeReference ref
        when identical(ref.container, this)) {
      return type;
    }

    // `type`'s own nested type list may directly contain `ResourceType`
    // definitions (from handles registered via `addResourceType` while the
    // interface's `InstanceTypeBuilder` was being built). A `resourcetype`
    // can only be *defined* (component model tag `0x3f`) within a concrete
    // top-level component, never inside an abstract instance/component type
    // declaration like this one -- so instead, mirror what real WIT tooling
    // does: turn each into a named `(export name (type (sub resource)))`
    // declaration, which *introduces* a fresh resource type and is legal
    // anywhere. `own`/`borrow` handles elsewhere in `type` reference these
    // entries by their (unchanged) position in `type.types`, so replacing in
    // place keeps them correct.
    for (var i = 0; i < type.types.length; i++) {
      if (type.types[i] case final ResourceType resource) {
        type.types[i] = InstanceResourceTypeExport(
          resource.name,
          ModelTypeReference<ResourceType>(
            this,
            ComponentTypeIndex(i),
            resource,
          ),
        );
      }
    }

    return _addType(type, InstanceTypeReference.new);

    // Don't normalize inner types, instance types have their own type index.
    // final exports = <InstanceExport>[
    //   for (final InstanceExport(:name, :kind, :innerType) in type.exports)
    //     switch (kind) {
    //       InstanceExportKind.type => .type(
    //         name,
    //         addValueType(innerType as ValueType),
    //       ),
    //       InstanceExportKind.function => .function(
    //         name,
    //         addFunctionType(innerType as FunctionType),
    //       ),
    //     },
    // ];

    // return _addType(InstanceType(exports), InstanceTypeReference.new);
  }

  ValueTypeReference addValueType(ValueType type) {
    ValueTypeReference addInner(ValueType type) =>
        _addType(type, ValueTypeReference.new);

    switch (type) {
      case ValueTypeReference():
        if (identical(type.container, this)) {
          return type;
        } else {
          // Referenced across containers, copy into this one.
          return addValueType(type.resolvedType);
        }
      case RecordType(:final fields):
        final normalizedFields = <RecordField>[
          for (final field in fields)
            RecordField(label: field.label, type: _fieldType(field.type)),
        ];
        return addInner(RecordType(normalizedFields));
      case VariantType(:final fields):
        final normalizedFields = <VariantField>[
          for (final field in fields)
            RecordOrVariantField(
              label: field.label,
              type: field.type != null ? _fieldType(field.type!) : null,
            ),
        ];
        return addInner(VariantType(normalizedFields));
      case VariableLengthListType(:final elementType):
        final normalizedElement = _fieldType(elementType);
        return addInner(VariableLengthListType(elementType: normalizedElement));
      case FixedLengthListType(:final elementType, :final length):
        final normalizedElement = _fieldType(elementType);
        return addInner(
          FixedLengthListType(elementType: normalizedElement, length: length),
        );
      case TupleType(:final elements):
        final normalizedElements = [
          for (final element in elements) _fieldType(element),
        ];
        return addInner(TupleType(normalizedElements));
      case OptionType(:final inner):
        return addInner(OptionType(_fieldType(inner)));
      case ResultType(:final ok, :final error):
        final normalizedOk = ok != null ? _fieldType(ok) : null;
        final normalizedError = error != null ? _fieldType(error) : null;
        return addInner(ResultType(ok: normalizedOk, error: normalizedError));
      case OwnType(:final resource):
        return addInner(OwnType(addResourceType(resource)));
      case BorrowType(:final resource):
        return addInner(BorrowType(addResourceType(resource)));
      case StreamType(:final element):
        return addInner(StreamType(addValueType(element)));
      case FutureType(:final element):
        return addInner(FutureType(addValueType(element)));
      case EnumType():
      case PrimitiveType():
      case StringType():
      case FlagsType():
        return addInner(type);
    }
  }

  /// Registers a resource type into this container, reusing the existing
  /// registration (by [ResourceType] object identity) if it was already
  /// added -- resources are referenced by every `own<T>`/`borrow<T>` handle
  /// to the same WIT resource, and the component model requires all of
  /// those handles to point at the exact same resource type index, so
  /// callers must pass the same [ResourceType] instance for the same WIT
  /// resource every time (see `ResolvedWitDefinitions._resourceTypeFor`).
  ModelTypeReference<ResourceType> registerResourceType(ResourceType type) {
    return _addType(type, ModelTypeReference<ResourceType>.new);
  }

  /// Copies a resource type reference from another container into this one,
  /// reusing the existing registration if the same [ResourceType] was
  /// already added here.
  ModelTypeReference<ResourceType> addResourceType(
    ModelTypeReference<ResourceType> resource,
  ) {
    if (identical(resource.container, this)) {
      return resource;
    }
    return registerResourceType(resource.resolvedType);
  }
}
