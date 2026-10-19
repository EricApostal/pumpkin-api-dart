// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'processing_settings.dart';

class ProcessingSettingsMapper extends ClassMapperBase<ProcessingSettings> {
  ProcessingSettingsMapper._();

  static ProcessingSettingsMapper? _instance;
  static ProcessingSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProcessingSettingsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProcessingSettings';

  static bool _$loadEmbeddedRecipes(ProcessingSettings v) =>
      v.loadEmbeddedRecipes;
  static const Field<ProcessingSettings, bool> _f$loadEmbeddedRecipes = Field(
    'loadEmbeddedRecipes',
    _$loadEmbeddedRecipes,
    key: r'load_embedded_recipes',
    opt: true,
    def: true,
  );
  static bool _$loadFolderRecipes(ProcessingSettings v) => v.loadFolderRecipes;
  static const Field<ProcessingSettings, bool> _f$loadFolderRecipes = Field(
    'loadFolderRecipes',
    _$loadFolderRecipes,
    key: r'load_folder_recipes',
    opt: true,
    def: true,
  );
  static String _$recipeFolder(ProcessingSettings v) => v.recipeFolder;
  static const Field<ProcessingSettings, String> _f$recipeFolder = Field(
    'recipeFolder',
    _$recipeFolder,
    key: r'recipe_folder',
    opt: true,
    def: 'recipes',
  );
  static bool _$syncRecipes(ProcessingSettings v) => v.syncRecipes;
  static const Field<ProcessingSettings, bool> _f$syncRecipes = Field(
    'syncRecipes',
    _$syncRecipes,
    key: r'sync_recipes',
    opt: true,
    def: true,
  );
  static int _$vanillaRecipeSerializerCount(ProcessingSettings v) =>
      v.vanillaRecipeSerializerCount;
  static const Field<ProcessingSettings, int> _f$vanillaRecipeSerializerCount =
      Field(
        'vanillaRecipeSerializerCount',
        _$vanillaRecipeSerializerCount,
        key: r'vanilla_recipe_serializer_count',
        opt: true,
        def: 22,
      );
  static int _$vanillaFluidCount(ProcessingSettings v) => v.vanillaFluidCount;
  static const Field<ProcessingSettings, int> _f$vanillaFluidCount = Field(
    'vanillaFluidCount',
    _$vanillaFluidCount,
    key: r'vanilla_fluid_count',
    opt: true,
    def: 5,
  );
  static bool _$logInvalidRecipes(ProcessingSettings v) => v.logInvalidRecipes;
  static const Field<ProcessingSettings, bool> _f$logInvalidRecipes = Field(
    'logInvalidRecipes',
    _$logInvalidRecipes,
    key: r'log_invalid_recipes',
    opt: true,
    def: true,
  );

  @override
  final MappableFields<ProcessingSettings> fields = const {
    #loadEmbeddedRecipes: _f$loadEmbeddedRecipes,
    #loadFolderRecipes: _f$loadFolderRecipes,
    #recipeFolder: _f$recipeFolder,
    #syncRecipes: _f$syncRecipes,
    #vanillaRecipeSerializerCount: _f$vanillaRecipeSerializerCount,
    #vanillaFluidCount: _f$vanillaFluidCount,
    #logInvalidRecipes: _f$logInvalidRecipes,
  };

  static ProcessingSettings _instantiate(DecodingData data) {
    return ProcessingSettings(
      loadEmbeddedRecipes: data.dec(_f$loadEmbeddedRecipes),
      loadFolderRecipes: data.dec(_f$loadFolderRecipes),
      recipeFolder: data.dec(_f$recipeFolder),
      syncRecipes: data.dec(_f$syncRecipes),
      vanillaRecipeSerializerCount: data.dec(_f$vanillaRecipeSerializerCount),
      vanillaFluidCount: data.dec(_f$vanillaFluidCount),
      logInvalidRecipes: data.dec(_f$logInvalidRecipes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProcessingSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProcessingSettings>(map);
  }

  static ProcessingSettings fromJson(String json) {
    return ensureInitialized().decodeJson<ProcessingSettings>(json);
  }
}

mixin ProcessingSettingsMappable {
  String toJson() {
    return ProcessingSettingsMapper.ensureInitialized()
        .encodeJson<ProcessingSettings>(this as ProcessingSettings);
  }

  Map<String, dynamic> toMap() {
    return ProcessingSettingsMapper.ensureInitialized()
        .encodeMap<ProcessingSettings>(this as ProcessingSettings);
  }

  ProcessingSettingsCopyWith<
    ProcessingSettings,
    ProcessingSettings,
    ProcessingSettings
  >
  get copyWith =>
      _ProcessingSettingsCopyWithImpl<ProcessingSettings, ProcessingSettings>(
        this as ProcessingSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProcessingSettingsMapper.ensureInitialized().stringifyValue(
      this as ProcessingSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProcessingSettingsMapper.ensureInitialized().equalsValue(
      this as ProcessingSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return ProcessingSettingsMapper.ensureInitialized().hashValue(
      this as ProcessingSettings,
    );
  }
}

extension ProcessingSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProcessingSettings, $Out> {
  ProcessingSettingsCopyWith<$R, ProcessingSettings, $Out>
  get $asProcessingSettings => $base.as(
    (v, t, t2) => _ProcessingSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ProcessingSettingsCopyWith<
  $R,
  $In extends ProcessingSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? loadEmbeddedRecipes,
    bool? loadFolderRecipes,
    String? recipeFolder,
    bool? syncRecipes,
    int? vanillaRecipeSerializerCount,
    int? vanillaFluidCount,
    bool? logInvalidRecipes,
  });
  ProcessingSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ProcessingSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProcessingSettings, $Out>
    implements ProcessingSettingsCopyWith<$R, ProcessingSettings, $Out> {
  _ProcessingSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProcessingSettings> $mapper =
      ProcessingSettingsMapper.ensureInitialized();
  @override
  $R call({
    bool? loadEmbeddedRecipes,
    bool? loadFolderRecipes,
    String? recipeFolder,
    bool? syncRecipes,
    int? vanillaRecipeSerializerCount,
    int? vanillaFluidCount,
    bool? logInvalidRecipes,
  }) => $apply(
    FieldCopyWithData({
      if (loadEmbeddedRecipes != null)
        #loadEmbeddedRecipes: loadEmbeddedRecipes,
      if (loadFolderRecipes != null) #loadFolderRecipes: loadFolderRecipes,
      if (recipeFolder != null) #recipeFolder: recipeFolder,
      if (syncRecipes != null) #syncRecipes: syncRecipes,
      if (vanillaRecipeSerializerCount != null)
        #vanillaRecipeSerializerCount: vanillaRecipeSerializerCount,
      if (vanillaFluidCount != null) #vanillaFluidCount: vanillaFluidCount,
      if (logInvalidRecipes != null) #logInvalidRecipes: logInvalidRecipes,
    }),
  );
  @override
  ProcessingSettings $make(CopyWithData data) => ProcessingSettings(
    loadEmbeddedRecipes: data.get(
      #loadEmbeddedRecipes,
      or: $value.loadEmbeddedRecipes,
    ),
    loadFolderRecipes: data.get(
      #loadFolderRecipes,
      or: $value.loadFolderRecipes,
    ),
    recipeFolder: data.get(#recipeFolder, or: $value.recipeFolder),
    syncRecipes: data.get(#syncRecipes, or: $value.syncRecipes),
    vanillaRecipeSerializerCount: data.get(
      #vanillaRecipeSerializerCount,
      or: $value.vanillaRecipeSerializerCount,
    ),
    vanillaFluidCount: data.get(
      #vanillaFluidCount,
      or: $value.vanillaFluidCount,
    ),
    logInvalidRecipes: data.get(
      #logInvalidRecipes,
      or: $value.logInvalidRecipes,
    ),
  );

  @override
  ProcessingSettingsCopyWith<$R2, ProcessingSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProcessingSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

