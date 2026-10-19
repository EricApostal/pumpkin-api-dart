// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'train_hat_info.dart';

class TrainHatInfoMapper extends ClassMapperBase<TrainHatInfo> {
  TrainHatInfoMapper._();

  static TrainHatInfoMapper? _instance;
  static TrainHatInfoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TrainHatInfoMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TrainHatInfo';

  static String _$part(TrainHatInfo v) => v.part;
  static const Field<TrainHatInfo, String> _f$part = Field('part', _$part);
  static int _$cubeIndex(TrainHatInfo v) => v.cubeIndex;
  static const Field<TrainHatInfo, int> _f$cubeIndex = Field(
    'cubeIndex',
    _$cubeIndex,
    key: r'cube_index',
  );
  static List<double> _$offsetList(TrainHatInfo v) => v.offsetList;
  static const Field<TrainHatInfo, List<double>> _f$offsetList = Field(
    'offsetList',
    _$offsetList,
    key: r'offset_list',
  );
  static double _$scale(TrainHatInfo v) => v.scale;
  static const Field<TrainHatInfo, double> _f$scale = Field('scale', _$scale);

  @override
  final MappableFields<TrainHatInfo> fields = const {
    #part: _f$part,
    #cubeIndex: _f$cubeIndex,
    #offsetList: _f$offsetList,
    #scale: _f$scale,
  };

  static TrainHatInfo _instantiate(DecodingData data) {
    return TrainHatInfo(
      data.dec(_f$part),
      data.dec(_f$cubeIndex),
      data.dec(_f$offsetList),
      data.dec(_f$scale),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TrainHatInfo fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TrainHatInfo>(map);
  }

  static TrainHatInfo fromJson(String json) {
    return ensureInitialized().decodeJson<TrainHatInfo>(json);
  }
}

mixin TrainHatInfoMappable {
  String toJson() {
    return TrainHatInfoMapper.ensureInitialized().encodeJson<TrainHatInfo>(
      this as TrainHatInfo,
    );
  }

  Map<String, dynamic> toMap() {
    return TrainHatInfoMapper.ensureInitialized().encodeMap<TrainHatInfo>(
      this as TrainHatInfo,
    );
  }

  TrainHatInfoCopyWith<TrainHatInfo, TrainHatInfo, TrainHatInfo> get copyWith =>
      _TrainHatInfoCopyWithImpl<TrainHatInfo, TrainHatInfo>(
        this as TrainHatInfo,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TrainHatInfoMapper.ensureInitialized().stringifyValue(
      this as TrainHatInfo,
    );
  }

  @override
  bool operator ==(Object other) {
    return TrainHatInfoMapper.ensureInitialized().equalsValue(
      this as TrainHatInfo,
      other,
    );
  }

  @override
  int get hashCode {
    return TrainHatInfoMapper.ensureInitialized().hashValue(
      this as TrainHatInfo,
    );
  }
}

extension TrainHatInfoValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TrainHatInfo, $Out> {
  TrainHatInfoCopyWith<$R, TrainHatInfo, $Out> get $asTrainHatInfo =>
      $base.as((v, t, t2) => _TrainHatInfoCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TrainHatInfoCopyWith<$R, $In extends TrainHatInfo, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, double, ObjectCopyWith<$R, double, double>> get offsetList;
  $R call({
    String? part,
    int? cubeIndex,
    List<double>? offsetList,
    double? scale,
  });
  TrainHatInfoCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _TrainHatInfoCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TrainHatInfo, $Out>
    implements TrainHatInfoCopyWith<$R, TrainHatInfo, $Out> {
  _TrainHatInfoCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TrainHatInfo> $mapper =
      TrainHatInfoMapper.ensureInitialized();
  @override
  ListCopyWith<$R, double, ObjectCopyWith<$R, double, double>> get offsetList =>
      ListCopyWith(
        $value.offsetList,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(offsetList: v),
      );
  @override
  $R call({
    String? part,
    int? cubeIndex,
    List<double>? offsetList,
    double? scale,
  }) => $apply(
    FieldCopyWithData({
      if (part != null) #part: part,
      if (cubeIndex != null) #cubeIndex: cubeIndex,
      if (offsetList != null) #offsetList: offsetList,
      if (scale != null) #scale: scale,
    }),
  );
  @override
  TrainHatInfo $make(CopyWithData data) => TrainHatInfo(
    data.get(#part, or: $value.part),
    data.get(#cubeIndex, or: $value.cubeIndex),
    data.get(#offsetList, or: $value.offsetList),
    data.get(#scale, or: $value.scale),
  );

  @override
  TrainHatInfoCopyWith<$R2, TrainHatInfo, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TrainHatInfoCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

