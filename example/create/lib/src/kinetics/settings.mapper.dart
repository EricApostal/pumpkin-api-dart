// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'settings.dart';

class KineticsSettingsMapper extends ClassMapperBase<KineticsSettings> {
  KineticsSettingsMapper._();

  static KineticsSettingsMapper? _instance;
  static KineticsSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KineticsSettingsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'KineticsSettings';

  static bool _$disableStress(KineticsSettings v) => v.disableStress;
  static const Field<KineticsSettings, bool> _f$disableStress = Field(
    'disableStress',
    _$disableStress,
    key: r'disable_stress',
    opt: true,
    def: false,
  );
  static int _$maxRotationSpeed(KineticsSettings v) => v.maxRotationSpeed;
  static const Field<KineticsSettings, int> _f$maxRotationSpeed = Field(
    'maxRotationSpeed',
    _$maxRotationSpeed,
    key: r'max_rotation_speed',
    opt: true,
    def: maxRotationSpeedDefault,
  );
  static int _$kineticValidationFrequency(KineticsSettings v) =>
      v.kineticValidationFrequency;
  static const Field<KineticsSettings, int> _f$kineticValidationFrequency =
      Field(
        'kineticValidationFrequency',
        _$kineticValidationFrequency,
        key: r'kinetic_validation_frequency',
        opt: true,
        def: 60,
      );
  static double _$mediumSpeed(KineticsSettings v) => v.mediumSpeed;
  static const Field<KineticsSettings, double> _f$mediumSpeed = Field(
    'mediumSpeed',
    _$mediumSpeed,
    key: r'medium_speed',
    opt: true,
    def: kineticsMediumSpeed,
  );
  static double _$fastSpeed(KineticsSettings v) => v.fastSpeed;
  static const Field<KineticsSettings, double> _f$fastSpeed = Field(
    'fastSpeed',
    _$fastSpeed,
    key: r'fast_speed',
    opt: true,
    def: kineticsFastSpeed,
  );
  static double _$mediumStressImpact(KineticsSettings v) =>
      v.mediumStressImpact;
  static const Field<KineticsSettings, double> _f$mediumStressImpact = Field(
    'mediumStressImpact',
    _$mediumStressImpact,
    key: r'medium_stress_impact',
    opt: true,
    def: kineticsMediumStressImpact,
  );
  static double _$highStressImpact(KineticsSettings v) => v.highStressImpact;
  static const Field<KineticsSettings, double> _f$highStressImpact = Field(
    'highStressImpact',
    _$highStressImpact,
    key: r'high_stress_impact',
    opt: true,
    def: kineticsHighStressImpact,
  );
  static double _$mediumCapacity(KineticsSettings v) => v.mediumCapacity;
  static const Field<KineticsSettings, double> _f$mediumCapacity = Field(
    'mediumCapacity',
    _$mediumCapacity,
    key: r'medium_capacity',
    opt: true,
    def: kineticsMediumCapacity,
  );
  static double _$highCapacity(KineticsSettings v) => v.highCapacity;
  static const Field<KineticsSettings, double> _f$highCapacity = Field(
    'highCapacity',
    _$highCapacity,
    key: r'high_capacity',
    opt: true,
    def: kineticsHighCapacity,
  );
  static double _$crankHungerMultiplier(KineticsSettings v) =>
      v.crankHungerMultiplier;
  static const Field<KineticsSettings, double> _f$crankHungerMultiplier = Field(
    'crankHungerMultiplier',
    _$crankHungerMultiplier,
    key: r'crank_hunger_multiplier',
    opt: true,
    def: 0.009999999776482582,
  );
  static Map<String, double> _$stressImpacts(KineticsSettings v) =>
      v.stressImpacts;
  static const Field<KineticsSettings, Map<String, double>> _f$stressImpacts =
      Field(
        'stressImpacts',
        _$stressImpacts,
        key: r'stress_impacts',
        opt: true,
        def: const {},
      );
  static Map<String, double> _$stressCapacities(KineticsSettings v) =>
      v.stressCapacities;
  static const Field<KineticsSettings, Map<String, double>>
  _f$stressCapacities = Field(
    'stressCapacities',
    _$stressCapacities,
    key: r'stress_capacities',
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<KineticsSettings> fields = const {
    #disableStress: _f$disableStress,
    #maxRotationSpeed: _f$maxRotationSpeed,
    #kineticValidationFrequency: _f$kineticValidationFrequency,
    #mediumSpeed: _f$mediumSpeed,
    #fastSpeed: _f$fastSpeed,
    #mediumStressImpact: _f$mediumStressImpact,
    #highStressImpact: _f$highStressImpact,
    #mediumCapacity: _f$mediumCapacity,
    #highCapacity: _f$highCapacity,
    #crankHungerMultiplier: _f$crankHungerMultiplier,
    #stressImpacts: _f$stressImpacts,
    #stressCapacities: _f$stressCapacities,
  };

  static KineticsSettings _instantiate(DecodingData data) {
    return KineticsSettings(
      disableStress: data.dec(_f$disableStress),
      maxRotationSpeed: data.dec(_f$maxRotationSpeed),
      kineticValidationFrequency: data.dec(_f$kineticValidationFrequency),
      mediumSpeed: data.dec(_f$mediumSpeed),
      fastSpeed: data.dec(_f$fastSpeed),
      mediumStressImpact: data.dec(_f$mediumStressImpact),
      highStressImpact: data.dec(_f$highStressImpact),
      mediumCapacity: data.dec(_f$mediumCapacity),
      highCapacity: data.dec(_f$highCapacity),
      crankHungerMultiplier: data.dec(_f$crankHungerMultiplier),
      stressImpacts: data.dec(_f$stressImpacts),
      stressCapacities: data.dec(_f$stressCapacities),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static KineticsSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KineticsSettings>(map);
  }

  static KineticsSettings fromJson(String json) {
    return ensureInitialized().decodeJson<KineticsSettings>(json);
  }
}

mixin KineticsSettingsMappable {
  String toJson() {
    return KineticsSettingsMapper.ensureInitialized()
        .encodeJson<KineticsSettings>(this as KineticsSettings);
  }

  Map<String, dynamic> toMap() {
    return KineticsSettingsMapper.ensureInitialized()
        .encodeMap<KineticsSettings>(this as KineticsSettings);
  }

  KineticsSettingsCopyWith<KineticsSettings, KineticsSettings, KineticsSettings>
  get copyWith =>
      _KineticsSettingsCopyWithImpl<KineticsSettings, KineticsSettings>(
        this as KineticsSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return KineticsSettingsMapper.ensureInitialized().stringifyValue(
      this as KineticsSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return KineticsSettingsMapper.ensureInitialized().equalsValue(
      this as KineticsSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return KineticsSettingsMapper.ensureInitialized().hashValue(
      this as KineticsSettings,
    );
  }
}

extension KineticsSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, KineticsSettings, $Out> {
  KineticsSettingsCopyWith<$R, KineticsSettings, $Out>
  get $asKineticsSettings =>
      $base.as((v, t, t2) => _KineticsSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KineticsSettingsCopyWith<$R, $In extends KineticsSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, double, ObjectCopyWith<$R, double, double>>
  get stressImpacts;
  MapCopyWith<$R, String, double, ObjectCopyWith<$R, double, double>>
  get stressCapacities;
  $R call({
    bool? disableStress,
    int? maxRotationSpeed,
    int? kineticValidationFrequency,
    double? mediumSpeed,
    double? fastSpeed,
    double? mediumStressImpact,
    double? highStressImpact,
    double? mediumCapacity,
    double? highCapacity,
    double? crankHungerMultiplier,
    Map<String, double>? stressImpacts,
    Map<String, double>? stressCapacities,
  });
  KineticsSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _KineticsSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KineticsSettings, $Out>
    implements KineticsSettingsCopyWith<$R, KineticsSettings, $Out> {
  _KineticsSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KineticsSettings> $mapper =
      KineticsSettingsMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, double, ObjectCopyWith<$R, double, double>>
  get stressImpacts => MapCopyWith(
    $value.stressImpacts,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(stressImpacts: v),
  );
  @override
  MapCopyWith<$R, String, double, ObjectCopyWith<$R, double, double>>
  get stressCapacities => MapCopyWith(
    $value.stressCapacities,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(stressCapacities: v),
  );
  @override
  $R call({
    bool? disableStress,
    int? maxRotationSpeed,
    int? kineticValidationFrequency,
    double? mediumSpeed,
    double? fastSpeed,
    double? mediumStressImpact,
    double? highStressImpact,
    double? mediumCapacity,
    double? highCapacity,
    double? crankHungerMultiplier,
    Map<String, double>? stressImpacts,
    Map<String, double>? stressCapacities,
  }) => $apply(
    FieldCopyWithData({
      if (disableStress != null) #disableStress: disableStress,
      if (maxRotationSpeed != null) #maxRotationSpeed: maxRotationSpeed,
      if (kineticValidationFrequency != null)
        #kineticValidationFrequency: kineticValidationFrequency,
      if (mediumSpeed != null) #mediumSpeed: mediumSpeed,
      if (fastSpeed != null) #fastSpeed: fastSpeed,
      if (mediumStressImpact != null) #mediumStressImpact: mediumStressImpact,
      if (highStressImpact != null) #highStressImpact: highStressImpact,
      if (mediumCapacity != null) #mediumCapacity: mediumCapacity,
      if (highCapacity != null) #highCapacity: highCapacity,
      if (crankHungerMultiplier != null)
        #crankHungerMultiplier: crankHungerMultiplier,
      if (stressImpacts != null) #stressImpacts: stressImpacts,
      if (stressCapacities != null) #stressCapacities: stressCapacities,
    }),
  );
  @override
  KineticsSettings $make(CopyWithData data) => KineticsSettings(
    disableStress: data.get(#disableStress, or: $value.disableStress),
    maxRotationSpeed: data.get(#maxRotationSpeed, or: $value.maxRotationSpeed),
    kineticValidationFrequency: data.get(
      #kineticValidationFrequency,
      or: $value.kineticValidationFrequency,
    ),
    mediumSpeed: data.get(#mediumSpeed, or: $value.mediumSpeed),
    fastSpeed: data.get(#fastSpeed, or: $value.fastSpeed),
    mediumStressImpact: data.get(
      #mediumStressImpact,
      or: $value.mediumStressImpact,
    ),
    highStressImpact: data.get(#highStressImpact, or: $value.highStressImpact),
    mediumCapacity: data.get(#mediumCapacity, or: $value.mediumCapacity),
    highCapacity: data.get(#highCapacity, or: $value.highCapacity),
    crankHungerMultiplier: data.get(
      #crankHungerMultiplier,
      or: $value.crankHungerMultiplier,
    ),
    stressImpacts: data.get(#stressImpacts, or: $value.stressImpacts),
    stressCapacities: data.get(#stressCapacities, or: $value.stressCapacities),
  );

  @override
  KineticsSettingsCopyWith<$R2, KineticsSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _KineticsSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

