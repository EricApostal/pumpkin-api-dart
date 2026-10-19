// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'stack.dart';

class LStackMapper extends ClassMapperBase<LStack> {
  LStackMapper._();

  static LStackMapper? _instance;
  static LStackMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LStackMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LStack';

  static String _$key(LStack v) => v.key;
  static const Field<LStack, String> _f$key = Field('key', _$key);
  static int _$count(LStack v) => v.count;
  static const Field<LStack, int> _f$count = Field('count', _$count);
  static int _$maxStack(LStack v) => v.maxStack;
  static const Field<LStack, int> _f$maxStack = Field(
    'maxStack',
    _$maxStack,
    key: r'max_stack',
    opt: true,
    def: 64,
  );
  static bool _$damageable(LStack v) => v.damageable;
  static const Field<LStack, bool> _f$damageable = Field(
    'damageable',
    _$damageable,
    opt: true,
    def: false,
  );
  static Map<String, String> _$comps(LStack v) => v.comps;
  static const Field<LStack, Map<String, String>> _f$comps = Field(
    'comps',
    _$comps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<LStack> fields = const {
    #key: _f$key,
    #count: _f$count,
    #maxStack: _f$maxStack,
    #damageable: _f$damageable,
    #comps: _f$comps,
  };

  static LStack _instantiate(DecodingData data) {
    return LStack(
      data.dec(_f$key),
      data.dec(_f$count),
      maxStack: data.dec(_f$maxStack),
      damageable: data.dec(_f$damageable),
      comps: data.dec(_f$comps),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LStack fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LStack>(map);
  }

  static LStack fromJson(String json) {
    return ensureInitialized().decodeJson<LStack>(json);
  }
}

mixin LStackMappable {
  String toJson() {
    return LStackMapper.ensureInitialized().encodeJson<LStack>(this as LStack);
  }

  Map<String, dynamic> toMap() {
    return LStackMapper.ensureInitialized().encodeMap<LStack>(this as LStack);
  }

  LStackCopyWith<LStack, LStack, LStack> get copyWith =>
      _LStackCopyWithImpl<LStack, LStack>(this as LStack, $identity, $identity);
  @override
  String toString() {
    return LStackMapper.ensureInitialized().stringifyValue(this as LStack);
  }

  @override
  bool operator ==(Object other) {
    return LStackMapper.ensureInitialized().equalsValue(this as LStack, other);
  }

  @override
  int get hashCode {
    return LStackMapper.ensureInitialized().hashValue(this as LStack);
  }
}

extension LStackValueCopy<$R, $Out> on ObjectCopyWith<$R, LStack, $Out> {
  LStackCopyWith<$R, LStack, $Out> get $asLStack =>
      $base.as((v, t, t2) => _LStackCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LStackCopyWith<$R, $In extends LStack, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>> get comps;
  $R call({
    String? key,
    int? count,
    int? maxStack,
    bool? damageable,
    Map<String, String>? comps,
  });
  LStackCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LStackCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, LStack, $Out>
    implements LStackCopyWith<$R, LStack, $Out> {
  _LStackCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LStack> $mapper = LStackMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get comps => MapCopyWith(
    $value.comps,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(comps: v),
  );
  @override
  $R call({
    String? key,
    int? count,
    int? maxStack,
    bool? damageable,
    Map<String, String>? comps,
  }) => $apply(
    FieldCopyWithData({
      if (key != null) #key: key,
      if (count != null) #count: count,
      if (maxStack != null) #maxStack: maxStack,
      if (damageable != null) #damageable: damageable,
      if (comps != null) #comps: comps,
    }),
  );
  @override
  LStack $make(CopyWithData data) => LStack(
    data.get(#key, or: $value.key),
    data.get(#count, or: $value.count),
    maxStack: data.get(#maxStack, or: $value.maxStack),
    damageable: data.get(#damageable, or: $value.damageable),
    comps: data.get(#comps, or: $value.comps),
  );

  @override
  LStackCopyWith<$R2, LStack, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LStackCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BigStackMapper extends ClassMapperBase<BigStack> {
  BigStackMapper._();

  static BigStackMapper? _instance;
  static BigStackMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BigStackMapper._());
      LStackMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'BigStack';

  static LStack _$itemStack(BigStack v) => v.itemStack;
  static const Field<BigStack, LStack> _f$itemStack = Field(
    'itemStack',
    _$itemStack,
    key: r'item_stack',
  );
  static int _$count(BigStack v) => v.count;
  static const Field<BigStack, int> _f$count = Field(
    'count',
    _$count,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<BigStack> fields = const {
    #itemStack: _f$itemStack,
    #count: _f$count,
  };

  static BigStack _instantiate(DecodingData data) {
    return BigStack(data.dec(_f$itemStack), data.dec(_f$count));
  }

  @override
  final Function instantiate = _instantiate;

  static BigStack fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BigStack>(map);
  }

  static BigStack fromJson(String json) {
    return ensureInitialized().decodeJson<BigStack>(json);
  }
}

mixin BigStackMappable {
  String toJson() {
    return BigStackMapper.ensureInitialized().encodeJson<BigStack>(
      this as BigStack,
    );
  }

  Map<String, dynamic> toMap() {
    return BigStackMapper.ensureInitialized().encodeMap<BigStack>(
      this as BigStack,
    );
  }

  BigStackCopyWith<BigStack, BigStack, BigStack> get copyWith =>
      _BigStackCopyWithImpl<BigStack, BigStack>(
        this as BigStack,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BigStackMapper.ensureInitialized().stringifyValue(this as BigStack);
  }

  @override
  bool operator ==(Object other) {
    return BigStackMapper.ensureInitialized().equalsValue(
      this as BigStack,
      other,
    );
  }

  @override
  int get hashCode {
    return BigStackMapper.ensureInitialized().hashValue(this as BigStack);
  }
}

extension BigStackValueCopy<$R, $Out> on ObjectCopyWith<$R, BigStack, $Out> {
  BigStackCopyWith<$R, BigStack, $Out> get $asBigStack =>
      $base.as((v, t, t2) => _BigStackCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BigStackCopyWith<$R, $In extends BigStack, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  LStackCopyWith<$R, LStack, LStack> get itemStack;
  $R call({LStack? itemStack, int? count});
  BigStackCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _BigStackCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BigStack, $Out>
    implements BigStackCopyWith<$R, BigStack, $Out> {
  _BigStackCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BigStack> $mapper =
      BigStackMapper.ensureInitialized();
  @override
  LStackCopyWith<$R, LStack, LStack> get itemStack =>
      $value.itemStack.copyWith.$chain((v) => call(itemStack: v));
  @override
  $R call({LStack? itemStack, int? count}) => $apply(
    FieldCopyWithData({
      if (itemStack != null) #itemStack: itemStack,
      if (count != null) #count: count,
    }),
  );
  @override
  BigStack $make(CopyWithData data) => BigStack(
    data.get(#itemStack, or: $value.itemStack),
    data.get(#count, or: $value.count),
  );

  @override
  BigStackCopyWith<$R2, BigStack, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BigStackCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

