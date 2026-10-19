// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'potion_data.dart';

class BottleTypeMapper extends EnumMapper<BottleType> {
  BottleTypeMapper._();

  static BottleTypeMapper? _instance;
  static BottleTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BottleTypeMapper._());
    }
    return _instance!;
  }

  static BottleType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  BottleType decode(dynamic value) {
    switch (value) {
      case r'regular':
        return BottleType.regular;
      case r'splash':
        return BottleType.splash;
      case r'lingering':
        return BottleType.lingering;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(BottleType self) {
    switch (self) {
      case BottleType.regular:
        return r'regular';
      case BottleType.splash:
        return r'splash';
      case BottleType.lingering:
        return r'lingering';
    }
  }
}

extension BottleTypeMapperExtension on BottleType {
  String toValue() {
    BottleTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<BottleType>(this) as String;
  }
}

class PotionEffectDataMapper extends ClassMapperBase<PotionEffectData> {
  PotionEffectDataMapper._();

  static PotionEffectDataMapper? _instance;
  static PotionEffectDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PotionEffectDataMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PotionEffectData';

  static String _$effect(PotionEffectData v) => v.effect;
  static const Field<PotionEffectData, String> _f$effect = Field(
    'effect',
    _$effect,
  );
  static int _$duration(PotionEffectData v) => v.duration;
  static const Field<PotionEffectData, int> _f$duration = Field(
    'duration',
    _$duration,
    opt: true,
    def: 0,
  );
  static int _$amplifier(PotionEffectData v) => v.amplifier;
  static const Field<PotionEffectData, int> _f$amplifier = Field(
    'amplifier',
    _$amplifier,
    opt: true,
    def: 0,
  );
  static bool _$ambient(PotionEffectData v) => v.ambient;
  static const Field<PotionEffectData, bool> _f$ambient = Field(
    'ambient',
    _$ambient,
    opt: true,
    def: false,
  );
  static bool _$visible(PotionEffectData v) => v.visible;
  static const Field<PotionEffectData, bool> _f$visible = Field(
    'visible',
    _$visible,
    opt: true,
    def: true,
  );

  @override
  final MappableFields<PotionEffectData> fields = const {
    #effect: _f$effect,
    #duration: _f$duration,
    #amplifier: _f$amplifier,
    #ambient: _f$ambient,
    #visible: _f$visible,
  };

  static PotionEffectData _instantiate(DecodingData data) {
    return PotionEffectData(
      data.dec(_f$effect),
      duration: data.dec(_f$duration),
      amplifier: data.dec(_f$amplifier),
      ambient: data.dec(_f$ambient),
      visible: data.dec(_f$visible),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PotionEffectData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PotionEffectData>(map);
  }

  static PotionEffectData fromJson(String json) {
    return ensureInitialized().decodeJson<PotionEffectData>(json);
  }
}

mixin PotionEffectDataMappable {
  String toJson() {
    return PotionEffectDataMapper.ensureInitialized()
        .encodeJson<PotionEffectData>(this as PotionEffectData);
  }

  Map<String, dynamic> toMap() {
    return PotionEffectDataMapper.ensureInitialized()
        .encodeMap<PotionEffectData>(this as PotionEffectData);
  }

  PotionEffectDataCopyWith<PotionEffectData, PotionEffectData, PotionEffectData>
  get copyWith =>
      _PotionEffectDataCopyWithImpl<PotionEffectData, PotionEffectData>(
        this as PotionEffectData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PotionEffectDataMapper.ensureInitialized().stringifyValue(
      this as PotionEffectData,
    );
  }

  @override
  bool operator ==(Object other) {
    return PotionEffectDataMapper.ensureInitialized().equalsValue(
      this as PotionEffectData,
      other,
    );
  }

  @override
  int get hashCode {
    return PotionEffectDataMapper.ensureInitialized().hashValue(
      this as PotionEffectData,
    );
  }
}

extension PotionEffectDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PotionEffectData, $Out> {
  PotionEffectDataCopyWith<$R, PotionEffectData, $Out>
  get $asPotionEffectData =>
      $base.as((v, t, t2) => _PotionEffectDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PotionEffectDataCopyWith<$R, $In extends PotionEffectData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? effect,
    int? duration,
    int? amplifier,
    bool? ambient,
    bool? visible,
  });
  PotionEffectDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PotionEffectDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PotionEffectData, $Out>
    implements PotionEffectDataCopyWith<$R, PotionEffectData, $Out> {
  _PotionEffectDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PotionEffectData> $mapper =
      PotionEffectDataMapper.ensureInitialized();
  @override
  $R call({
    String? effect,
    int? duration,
    int? amplifier,
    bool? ambient,
    bool? visible,
  }) => $apply(
    FieldCopyWithData({
      if (effect != null) #effect: effect,
      if (duration != null) #duration: duration,
      if (amplifier != null) #amplifier: amplifier,
      if (ambient != null) #ambient: ambient,
      if (visible != null) #visible: visible,
    }),
  );
  @override
  PotionEffectData $make(CopyWithData data) => PotionEffectData(
    data.get(#effect, or: $value.effect),
    duration: data.get(#duration, or: $value.duration),
    amplifier: data.get(#amplifier, or: $value.amplifier),
    ambient: data.get(#ambient, or: $value.ambient),
    visible: data.get(#visible, or: $value.visible),
  );

  @override
  PotionEffectDataCopyWith<$R2, PotionEffectData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PotionEffectDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PotionFluidDataMapper extends ClassMapperBase<PotionFluidData> {
  PotionFluidDataMapper._();

  static PotionFluidDataMapper? _instance;
  static PotionFluidDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PotionFluidDataMapper._());
      BottleTypeMapper.ensureInitialized();
      PotionEffectDataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PotionFluidData';

  static String _$potion(PotionFluidData v) => v.potion;
  static const Field<PotionFluidData, String> _f$potion = Field(
    'potion',
    _$potion,
  );
  static BottleType _$bottle(PotionFluidData v) => v.bottle;
  static const Field<PotionFluidData, BottleType> _f$bottle = Field(
    'bottle',
    _$bottle,
    opt: true,
    def: BottleType.regular,
  );
  static List<PotionEffectData> _$customEffects(PotionFluidData v) =>
      v.customEffects;
  static const Field<PotionFluidData, List<PotionEffectData>> _f$customEffects =
      Field(
        'customEffects',
        _$customEffects,
        key: r'custom_effects',
        opt: true,
        def: const [],
      );

  @override
  final MappableFields<PotionFluidData> fields = const {
    #potion: _f$potion,
    #bottle: _f$bottle,
    #customEffects: _f$customEffects,
  };

  static PotionFluidData _instantiate(DecodingData data) {
    return PotionFluidData(
      data.dec(_f$potion),
      bottle: data.dec(_f$bottle),
      customEffects: data.dec(_f$customEffects),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PotionFluidData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PotionFluidData>(map);
  }

  static PotionFluidData fromJson(String json) {
    return ensureInitialized().decodeJson<PotionFluidData>(json);
  }
}

mixin PotionFluidDataMappable {
  String toJson() {
    return PotionFluidDataMapper.ensureInitialized()
        .encodeJson<PotionFluidData>(this as PotionFluidData);
  }

  Map<String, dynamic> toMap() {
    return PotionFluidDataMapper.ensureInitialized().encodeMap<PotionFluidData>(
      this as PotionFluidData,
    );
  }

  PotionFluidDataCopyWith<PotionFluidData, PotionFluidData, PotionFluidData>
  get copyWith =>
      _PotionFluidDataCopyWithImpl<PotionFluidData, PotionFluidData>(
        this as PotionFluidData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PotionFluidDataMapper.ensureInitialized().stringifyValue(
      this as PotionFluidData,
    );
  }

  @override
  bool operator ==(Object other) {
    return PotionFluidDataMapper.ensureInitialized().equalsValue(
      this as PotionFluidData,
      other,
    );
  }

  @override
  int get hashCode {
    return PotionFluidDataMapper.ensureInitialized().hashValue(
      this as PotionFluidData,
    );
  }
}

extension PotionFluidDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PotionFluidData, $Out> {
  PotionFluidDataCopyWith<$R, PotionFluidData, $Out> get $asPotionFluidData =>
      $base.as((v, t, t2) => _PotionFluidDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PotionFluidDataCopyWith<$R, $In extends PotionFluidData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    PotionEffectData,
    PotionEffectDataCopyWith<$R, PotionEffectData, PotionEffectData>
  >
  get customEffects;
  $R call({
    String? potion,
    BottleType? bottle,
    List<PotionEffectData>? customEffects,
  });
  PotionFluidDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PotionFluidDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PotionFluidData, $Out>
    implements PotionFluidDataCopyWith<$R, PotionFluidData, $Out> {
  _PotionFluidDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PotionFluidData> $mapper =
      PotionFluidDataMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    PotionEffectData,
    PotionEffectDataCopyWith<$R, PotionEffectData, PotionEffectData>
  >
  get customEffects => ListCopyWith(
    $value.customEffects,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(customEffects: v),
  );
  @override
  $R call({
    String? potion,
    BottleType? bottle,
    List<PotionEffectData>? customEffects,
  }) => $apply(
    FieldCopyWithData({
      if (potion != null) #potion: potion,
      if (bottle != null) #bottle: bottle,
      if (customEffects != null) #customEffects: customEffects,
    }),
  );
  @override
  PotionFluidData $make(CopyWithData data) => PotionFluidData(
    data.get(#potion, or: $value.potion),
    bottle: data.get(#bottle, or: $value.bottle),
    customEffects: data.get(#customEffects, or: $value.customEffects),
  );

  @override
  PotionFluidDataCopyWith<$R2, PotionFluidData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PotionFluidDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

