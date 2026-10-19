// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'config_models.dart';

class CoreSettingsMapper extends ClassMapperBase<CoreSettings> {
  CoreSettingsMapper._();

  static CoreSettingsMapper? _instance;
  static CoreSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CoreSettingsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'CoreSettings';

  static bool _$neoforge(CoreSettings v) => v.neoforge;
  static const Field<CoreSettings, bool> _f$neoforge = Field(
    'neoforge',
    _$neoforge,
    opt: true,
    def: true,
  );
  static String _$modVersion(CoreSettings v) => v.modVersion;
  static const Field<CoreSettings, String> _f$modVersion = Field(
    'modVersion',
    _$modVersion,
    key: r'mod_version',
    opt: true,
    def: createModVersion,
  );
  static bool _$debugSmokeTest(CoreSettings v) => v.debugSmokeTest;
  static const Field<CoreSettings, bool> _f$debugSmokeTest = Field(
    'debugSmokeTest',
    _$debugSmokeTest,
    key: r'debug_smoke_test',
    opt: true,
    def: false,
  );
  static int _$saveIntervalTicks(CoreSettings v) => v.saveIntervalTicks;
  static const Field<CoreSettings, int> _f$saveIntervalTicks = Field(
    'saveIntervalTicks',
    _$saveIntervalTicks,
    key: r'save_interval_ticks',
    opt: true,
    def: 20,
  );
  static bool _$logRegistryIds(CoreSettings v) => v.logRegistryIds;
  static const Field<CoreSettings, bool> _f$logRegistryIds = Field(
    'logRegistryIds',
    _$logRegistryIds,
    key: r'log_registry_ids',
    opt: true,
    def: false,
  );
  static Map<String, bool> _$modules(CoreSettings v) => v.modules;
  static const Field<CoreSettings, Map<String, bool>> _f$modules = Field(
    'modules',
    _$modules,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<CoreSettings> fields = const {
    #neoforge: _f$neoforge,
    #modVersion: _f$modVersion,
    #debugSmokeTest: _f$debugSmokeTest,
    #saveIntervalTicks: _f$saveIntervalTicks,
    #logRegistryIds: _f$logRegistryIds,
    #modules: _f$modules,
  };

  static CoreSettings _instantiate(DecodingData data) {
    return CoreSettings(
      neoforge: data.dec(_f$neoforge),
      modVersion: data.dec(_f$modVersion),
      debugSmokeTest: data.dec(_f$debugSmokeTest),
      saveIntervalTicks: data.dec(_f$saveIntervalTicks),
      logRegistryIds: data.dec(_f$logRegistryIds),
      modules: data.dec(_f$modules),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static CoreSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<CoreSettings>(map);
  }

  static CoreSettings fromJson(String json) {
    return ensureInitialized().decodeJson<CoreSettings>(json);
  }
}

mixin CoreSettingsMappable {
  String toJson() {
    return CoreSettingsMapper.ensureInitialized().encodeJson<CoreSettings>(
      this as CoreSettings,
    );
  }

  Map<String, dynamic> toMap() {
    return CoreSettingsMapper.ensureInitialized().encodeMap<CoreSettings>(
      this as CoreSettings,
    );
  }

  CoreSettingsCopyWith<CoreSettings, CoreSettings, CoreSettings> get copyWith =>
      _CoreSettingsCopyWithImpl<CoreSettings, CoreSettings>(
        this as CoreSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return CoreSettingsMapper.ensureInitialized().stringifyValue(
      this as CoreSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return CoreSettingsMapper.ensureInitialized().equalsValue(
      this as CoreSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return CoreSettingsMapper.ensureInitialized().hashValue(
      this as CoreSettings,
    );
  }
}

extension CoreSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, CoreSettings, $Out> {
  CoreSettingsCopyWith<$R, CoreSettings, $Out> get $asCoreSettings =>
      $base.as((v, t, t2) => _CoreSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class CoreSettingsCopyWith<$R, $In extends CoreSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, bool, ObjectCopyWith<$R, bool, bool>> get modules;
  $R call({
    bool? neoforge,
    String? modVersion,
    bool? debugSmokeTest,
    int? saveIntervalTicks,
    bool? logRegistryIds,
    Map<String, bool>? modules,
  });
  CoreSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _CoreSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, CoreSettings, $Out>
    implements CoreSettingsCopyWith<$R, CoreSettings, $Out> {
  _CoreSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<CoreSettings> $mapper =
      CoreSettingsMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, bool, ObjectCopyWith<$R, bool, bool>> get modules =>
      MapCopyWith(
        $value.modules,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(modules: v),
      );
  @override
  $R call({
    bool? neoforge,
    String? modVersion,
    bool? debugSmokeTest,
    int? saveIntervalTicks,
    bool? logRegistryIds,
    Map<String, bool>? modules,
  }) => $apply(
    FieldCopyWithData({
      if (neoforge != null) #neoforge: neoforge,
      if (modVersion != null) #modVersion: modVersion,
      if (debugSmokeTest != null) #debugSmokeTest: debugSmokeTest,
      if (saveIntervalTicks != null) #saveIntervalTicks: saveIntervalTicks,
      if (logRegistryIds != null) #logRegistryIds: logRegistryIds,
      if (modules != null) #modules: modules,
    }),
  );
  @override
  CoreSettings $make(CopyWithData data) => CoreSettings(
    neoforge: data.get(#neoforge, or: $value.neoforge),
    modVersion: data.get(#modVersion, or: $value.modVersion),
    debugSmokeTest: data.get(#debugSmokeTest, or: $value.debugSmokeTest),
    saveIntervalTicks: data.get(
      #saveIntervalTicks,
      or: $value.saveIntervalTicks,
    ),
    logRegistryIds: data.get(#logRegistryIds, or: $value.logRegistryIds),
    modules: data.get(#modules, or: $value.modules),
  );

  @override
  CoreSettingsCopyWith<$R2, CoreSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _CoreSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

