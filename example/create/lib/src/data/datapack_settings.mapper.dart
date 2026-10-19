// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'datapack_settings.dart';

class DatapackSettingsMapper extends ClassMapperBase<DatapackSettings> {
  DatapackSettingsMapper._();

  static DatapackSettingsMapper? _instance;
  static DatapackSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DatapackSettingsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'DatapackSettings';

  static bool _$enabled(DatapackSettings v) => v.enabled;
  static const Field<DatapackSettings, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static bool _$autoEnable(DatapackSettings v) => v.autoEnable;
  static const Field<DatapackSettings, bool> _f$autoEnable = Field(
    'autoEnable',
    _$autoEnable,
    key: r'auto_enable',
    opt: true,
    def: true,
  );
  static bool _$recipes(DatapackSettings v) => v.recipes;
  static const Field<DatapackSettings, bool> _f$recipes = Field(
    'recipes',
    _$recipes,
    opt: true,
    def: true,
  );
  static bool _$lootTables(DatapackSettings v) => v.lootTables;
  static const Field<DatapackSettings, bool> _f$lootTables = Field(
    'lootTables',
    _$lootTables,
    key: r'loot_tables',
    opt: true,
    def: true,
  );
  static bool _$advancements(DatapackSettings v) => v.advancements;
  static const Field<DatapackSettings, bool> _f$advancements = Field(
    'advancements',
    _$advancements,
    opt: true,
    def: true,
  );
  static bool _$recipeAdvancements(DatapackSettings v) => v.recipeAdvancements;
  static const Field<DatapackSettings, bool> _f$recipeAdvancements = Field(
    'recipeAdvancements',
    _$recipeAdvancements,
    key: r'recipe_advancements',
    opt: true,
    def: false,
  );
  static bool _$tags(DatapackSettings v) => v.tags;
  static const Field<DatapackSettings, bool> _f$tags = Field(
    'tags',
    _$tags,
    opt: true,
    def: true,
  );
  static bool _$structures(DatapackSettings v) => v.structures;
  static const Field<DatapackSettings, bool> _f$structures = Field(
    'structures',
    _$structures,
    opt: true,
    def: true,
  );
  static bool _$registries(DatapackSettings v) => v.registries;
  static const Field<DatapackSettings, bool> _f$registries = Field(
    'registries',
    _$registries,
    opt: true,
    def: false,
  );
  static bool _$other(DatapackSettings v) => v.other;
  static const Field<DatapackSettings, bool> _f$other = Field(
    'other',
    _$other,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<DatapackSettings> fields = const {
    #enabled: _f$enabled,
    #autoEnable: _f$autoEnable,
    #recipes: _f$recipes,
    #lootTables: _f$lootTables,
    #advancements: _f$advancements,
    #recipeAdvancements: _f$recipeAdvancements,
    #tags: _f$tags,
    #structures: _f$structures,
    #registries: _f$registries,
    #other: _f$other,
  };

  static DatapackSettings _instantiate(DecodingData data) {
    return DatapackSettings(
      enabled: data.dec(_f$enabled),
      autoEnable: data.dec(_f$autoEnable),
      recipes: data.dec(_f$recipes),
      lootTables: data.dec(_f$lootTables),
      advancements: data.dec(_f$advancements),
      recipeAdvancements: data.dec(_f$recipeAdvancements),
      tags: data.dec(_f$tags),
      structures: data.dec(_f$structures),
      registries: data.dec(_f$registries),
      other: data.dec(_f$other),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DatapackSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DatapackSettings>(map);
  }

  static DatapackSettings fromJson(String json) {
    return ensureInitialized().decodeJson<DatapackSettings>(json);
  }
}

mixin DatapackSettingsMappable {
  String toJson() {
    return DatapackSettingsMapper.ensureInitialized()
        .encodeJson<DatapackSettings>(this as DatapackSettings);
  }

  Map<String, dynamic> toMap() {
    return DatapackSettingsMapper.ensureInitialized()
        .encodeMap<DatapackSettings>(this as DatapackSettings);
  }

  DatapackSettingsCopyWith<DatapackSettings, DatapackSettings, DatapackSettings>
  get copyWith =>
      _DatapackSettingsCopyWithImpl<DatapackSettings, DatapackSettings>(
        this as DatapackSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DatapackSettingsMapper.ensureInitialized().stringifyValue(
      this as DatapackSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return DatapackSettingsMapper.ensureInitialized().equalsValue(
      this as DatapackSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return DatapackSettingsMapper.ensureInitialized().hashValue(
      this as DatapackSettings,
    );
  }
}

extension DatapackSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DatapackSettings, $Out> {
  DatapackSettingsCopyWith<$R, DatapackSettings, $Out>
  get $asDatapackSettings =>
      $base.as((v, t, t2) => _DatapackSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DatapackSettingsCopyWith<$R, $In extends DatapackSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? enabled,
    bool? autoEnable,
    bool? recipes,
    bool? lootTables,
    bool? advancements,
    bool? recipeAdvancements,
    bool? tags,
    bool? structures,
    bool? registries,
    bool? other,
  });
  DatapackSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DatapackSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DatapackSettings, $Out>
    implements DatapackSettingsCopyWith<$R, DatapackSettings, $Out> {
  _DatapackSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DatapackSettings> $mapper =
      DatapackSettingsMapper.ensureInitialized();
  @override
  $R call({
    bool? enabled,
    bool? autoEnable,
    bool? recipes,
    bool? lootTables,
    bool? advancements,
    bool? recipeAdvancements,
    bool? tags,
    bool? structures,
    bool? registries,
    bool? other,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (autoEnable != null) #autoEnable: autoEnable,
      if (recipes != null) #recipes: recipes,
      if (lootTables != null) #lootTables: lootTables,
      if (advancements != null) #advancements: advancements,
      if (recipeAdvancements != null) #recipeAdvancements: recipeAdvancements,
      if (tags != null) #tags: tags,
      if (structures != null) #structures: structures,
      if (registries != null) #registries: registries,
      if (other != null) #other: other,
    }),
  );
  @override
  DatapackSettings $make(CopyWithData data) => DatapackSettings(
    enabled: data.get(#enabled, or: $value.enabled),
    autoEnable: data.get(#autoEnable, or: $value.autoEnable),
    recipes: data.get(#recipes, or: $value.recipes),
    lootTables: data.get(#lootTables, or: $value.lootTables),
    advancements: data.get(#advancements, or: $value.advancements),
    recipeAdvancements: data.get(
      #recipeAdvancements,
      or: $value.recipeAdvancements,
    ),
    tags: data.get(#tags, or: $value.tags),
    structures: data.get(#structures, or: $value.structures),
    registries: data.get(#registries, or: $value.registries),
    other: data.get(#other, or: $value.other),
  );

  @override
  DatapackSettingsCopyWith<$R2, DatapackSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DatapackSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

