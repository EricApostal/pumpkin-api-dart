// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'smoke_module.dart';

class SmokeStateMapper extends ClassMapperBase<SmokeState> {
  SmokeStateMapper._();

  static SmokeStateMapper? _instance;
  static SmokeStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SmokeStateMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SmokeState';

  static int _$count(SmokeState v) => v.count;
  static const Field<SmokeState, int> _f$count = Field(
    'count',
    _$count,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<SmokeState> fields = const {#count: _f$count};

  static SmokeState _instantiate(DecodingData data) {
    return SmokeState(count: data.dec(_f$count));
  }

  @override
  final Function instantiate = _instantiate;

  static SmokeState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SmokeState>(map);
  }

  static SmokeState fromJson(String json) {
    return ensureInitialized().decodeJson<SmokeState>(json);
  }
}

mixin SmokeStateMappable {
  String toJson() {
    return SmokeStateMapper.ensureInitialized().encodeJson<SmokeState>(
      this as SmokeState,
    );
  }

  Map<String, dynamic> toMap() {
    return SmokeStateMapper.ensureInitialized().encodeMap<SmokeState>(
      this as SmokeState,
    );
  }

  SmokeStateCopyWith<SmokeState, SmokeState, SmokeState> get copyWith =>
      _SmokeStateCopyWithImpl<SmokeState, SmokeState>(
        this as SmokeState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SmokeStateMapper.ensureInitialized().stringifyValue(
      this as SmokeState,
    );
  }

  @override
  bool operator ==(Object other) {
    return SmokeStateMapper.ensureInitialized().equalsValue(
      this as SmokeState,
      other,
    );
  }

  @override
  int get hashCode {
    return SmokeStateMapper.ensureInitialized().hashValue(this as SmokeState);
  }
}

extension SmokeStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SmokeState, $Out> {
  SmokeStateCopyWith<$R, SmokeState, $Out> get $asSmokeState =>
      $base.as((v, t, t2) => _SmokeStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SmokeStateCopyWith<$R, $In extends SmokeState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? count});
  SmokeStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SmokeStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SmokeState, $Out>
    implements SmokeStateCopyWith<$R, SmokeState, $Out> {
  _SmokeStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SmokeState> $mapper =
      SmokeStateMapper.ensureInitialized();
  @override
  $R call({int? count}) =>
      $apply(FieldCopyWithData({if (count != null) #count: count}));
  @override
  SmokeState $make(CopyWithData data) =>
      SmokeState(count: data.get(#count, or: $value.count));

  @override
  SmokeStateCopyWith<$R2, SmokeState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SmokeStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

