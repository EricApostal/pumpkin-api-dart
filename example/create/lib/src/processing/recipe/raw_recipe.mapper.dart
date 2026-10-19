// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'raw_recipe.dart';

class RawRecipeMapper extends ClassMapperBase<RawRecipe> {
  RawRecipeMapper._();

  static RawRecipeMapper? _instance;
  static RawRecipeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RawRecipeMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RawRecipe';

  static String _$type(RawRecipe v) => v.type;
  static const Field<RawRecipe, String> _f$type = Field('type', _$type);
  static List<Object?>? _$ingredients(RawRecipe v) => v.ingredients;
  static const Field<RawRecipe, List<Object?>> _f$ingredients = Field(
    'ingredients',
    _$ingredients,
    opt: true,
  );
  static Object? _$ingredient(RawRecipe v) => v.ingredient;
  static const Field<RawRecipe, Object> _f$ingredient = Field(
    'ingredient',
    _$ingredient,
    opt: true,
  );
  static List<Object?>? _$results(RawRecipe v) => v.results;
  static const Field<RawRecipe, List<Object?>> _f$results = Field(
    'results',
    _$results,
    opt: true,
  );
  static Object? _$result(RawRecipe v) => v.result;
  static const Field<RawRecipe, Object> _f$result = Field(
    'result',
    _$result,
    opt: true,
  );
  static int? _$processingTime(RawRecipe v) => v.processingTime;
  static const Field<RawRecipe, int> _f$processingTime = Field(
    'processingTime',
    _$processingTime,
    key: r'processing_time',
    opt: true,
  );
  static String? _$heatRequirement(RawRecipe v) => v.heatRequirement;
  static const Field<RawRecipe, String> _f$heatRequirement = Field(
    'heatRequirement',
    _$heatRequirement,
    key: r'heat_requirement',
    opt: true,
  );
  static bool? _$keepHeldItem(RawRecipe v) => v.keepHeldItem;
  static const Field<RawRecipe, bool> _f$keepHeldItem = Field(
    'keepHeldItem',
    _$keepHeldItem,
    key: r'keep_held_item',
    opt: true,
  );
  static bool? _$acceptMirrored(RawRecipe v) => v.acceptMirrored;
  static const Field<RawRecipe, bool> _f$acceptMirrored = Field(
    'acceptMirrored',
    _$acceptMirrored,
    key: r'accept_mirrored',
    opt: true,
  );
  static List<String>? _$pattern(RawRecipe v) => v.pattern;
  static const Field<RawRecipe, List<String>> _f$pattern = Field(
    'pattern',
    _$pattern,
    opt: true,
  );
  static Map<String, Object?>? _$key(RawRecipe v) => v.key;
  static const Field<RawRecipe, Map<String, Object?>> _f$key = Field(
    'key',
    _$key,
    opt: true,
  );
  static String? _$category(RawRecipe v) => v.category;
  static const Field<RawRecipe, String> _f$category = Field(
    'category',
    _$category,
    opt: true,
  );
  static String? _$group(RawRecipe v) => v.group;
  static const Field<RawRecipe, String> _f$group = Field(
    'group',
    _$group,
    opt: true,
  );
  static bool? _$showNotification(RawRecipe v) => v.showNotification;
  static const Field<RawRecipe, bool> _f$showNotification = Field(
    'showNotification',
    _$showNotification,
    key: r'show_notification',
    opt: true,
  );
  static List<Object?>? _$sequence(RawRecipe v) => v.sequence;
  static const Field<RawRecipe, List<Object?>> _f$sequence = Field(
    'sequence',
    _$sequence,
    opt: true,
  );
  static Object? _$transitionalItem(RawRecipe v) => v.transitionalItem;
  static const Field<RawRecipe, Object> _f$transitionalItem = Field(
    'transitionalItem',
    _$transitionalItem,
    key: r'transitional_item',
    opt: true,
  );
  static int? _$loops(RawRecipe v) => v.loops;
  static const Field<RawRecipe, int> _f$loops = Field(
    'loops',
    _$loops,
    opt: true,
  );
  static List<Object?>? _$conditions(RawRecipe v) => v.conditions;
  static const Field<RawRecipe, List<Object?>> _f$conditions = Field(
    'conditions',
    _$conditions,
    key: r'neoforge:conditions',
    opt: true,
  );

  @override
  final MappableFields<RawRecipe> fields = const {
    #type: _f$type,
    #ingredients: _f$ingredients,
    #ingredient: _f$ingredient,
    #results: _f$results,
    #result: _f$result,
    #processingTime: _f$processingTime,
    #heatRequirement: _f$heatRequirement,
    #keepHeldItem: _f$keepHeldItem,
    #acceptMirrored: _f$acceptMirrored,
    #pattern: _f$pattern,
    #key: _f$key,
    #category: _f$category,
    #group: _f$group,
    #showNotification: _f$showNotification,
    #sequence: _f$sequence,
    #transitionalItem: _f$transitionalItem,
    #loops: _f$loops,
    #conditions: _f$conditions,
  };

  static RawRecipe _instantiate(DecodingData data) {
    return RawRecipe(
      type: data.dec(_f$type),
      ingredients: data.dec(_f$ingredients),
      ingredient: data.dec(_f$ingredient),
      results: data.dec(_f$results),
      result: data.dec(_f$result),
      processingTime: data.dec(_f$processingTime),
      heatRequirement: data.dec(_f$heatRequirement),
      keepHeldItem: data.dec(_f$keepHeldItem),
      acceptMirrored: data.dec(_f$acceptMirrored),
      pattern: data.dec(_f$pattern),
      key: data.dec(_f$key),
      category: data.dec(_f$category),
      group: data.dec(_f$group),
      showNotification: data.dec(_f$showNotification),
      sequence: data.dec(_f$sequence),
      transitionalItem: data.dec(_f$transitionalItem),
      loops: data.dec(_f$loops),
      conditions: data.dec(_f$conditions),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RawRecipe fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RawRecipe>(map);
  }

  static RawRecipe fromJson(String json) {
    return ensureInitialized().decodeJson<RawRecipe>(json);
  }
}

mixin RawRecipeMappable {
  String toJson() {
    return RawRecipeMapper.ensureInitialized().encodeJson<RawRecipe>(
      this as RawRecipe,
    );
  }

  Map<String, dynamic> toMap() {
    return RawRecipeMapper.ensureInitialized().encodeMap<RawRecipe>(
      this as RawRecipe,
    );
  }

  RawRecipeCopyWith<RawRecipe, RawRecipe, RawRecipe> get copyWith =>
      _RawRecipeCopyWithImpl<RawRecipe, RawRecipe>(
        this as RawRecipe,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RawRecipeMapper.ensureInitialized().stringifyValue(
      this as RawRecipe,
    );
  }

  @override
  bool operator ==(Object other) {
    return RawRecipeMapper.ensureInitialized().equalsValue(
      this as RawRecipe,
      other,
    );
  }

  @override
  int get hashCode {
    return RawRecipeMapper.ensureInitialized().hashValue(this as RawRecipe);
  }
}

extension RawRecipeValueCopy<$R, $Out> on ObjectCopyWith<$R, RawRecipe, $Out> {
  RawRecipeCopyWith<$R, RawRecipe, $Out> get $asRawRecipe =>
      $base.as((v, t, t2) => _RawRecipeCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RawRecipeCopyWith<$R, $In extends RawRecipe, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get ingredients;
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>? get results;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get pattern;
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get key;
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get sequence;
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get conditions;
  $R call({
    String? type,
    List<Object?>? ingredients,
    Object? ingredient,
    List<Object?>? results,
    Object? result,
    int? processingTime,
    String? heatRequirement,
    bool? keepHeldItem,
    bool? acceptMirrored,
    List<String>? pattern,
    Map<String, Object?>? key,
    String? category,
    String? group,
    bool? showNotification,
    List<Object?>? sequence,
    Object? transitionalItem,
    int? loops,
    List<Object?>? conditions,
  });
  RawRecipeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RawRecipeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RawRecipe, $Out>
    implements RawRecipeCopyWith<$R, RawRecipe, $Out> {
  _RawRecipeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RawRecipe> $mapper =
      RawRecipeMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get ingredients => $value.ingredients != null
      ? ListCopyWith(
          $value.ingredients!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(ingredients: v),
        )
      : null;
  @override
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get results => $value.results != null
      ? ListCopyWith(
          $value.results!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(results: v),
        )
      : null;
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get pattern =>
      $value.pattern != null
      ? ListCopyWith(
          $value.pattern!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(pattern: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get key => $value.key != null
      ? MapCopyWith(
          $value.key!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(key: v),
        )
      : null;
  @override
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get sequence => $value.sequence != null
      ? ListCopyWith(
          $value.sequence!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(sequence: v),
        )
      : null;
  @override
  ListCopyWith<$R, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get conditions => $value.conditions != null
      ? ListCopyWith(
          $value.conditions!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(conditions: v),
        )
      : null;
  @override
  $R call({
    String? type,
    Object? ingredients = $none,
    Object? ingredient = $none,
    Object? results = $none,
    Object? result = $none,
    Object? processingTime = $none,
    Object? heatRequirement = $none,
    Object? keepHeldItem = $none,
    Object? acceptMirrored = $none,
    Object? pattern = $none,
    Object? key = $none,
    Object? category = $none,
    Object? group = $none,
    Object? showNotification = $none,
    Object? sequence = $none,
    Object? transitionalItem = $none,
    Object? loops = $none,
    Object? conditions = $none,
  }) => $apply(
    FieldCopyWithData({
      if (type != null) #type: type,
      if (ingredients != $none) #ingredients: ingredients,
      if (ingredient != $none) #ingredient: ingredient,
      if (results != $none) #results: results,
      if (result != $none) #result: result,
      if (processingTime != $none) #processingTime: processingTime,
      if (heatRequirement != $none) #heatRequirement: heatRequirement,
      if (keepHeldItem != $none) #keepHeldItem: keepHeldItem,
      if (acceptMirrored != $none) #acceptMirrored: acceptMirrored,
      if (pattern != $none) #pattern: pattern,
      if (key != $none) #key: key,
      if (category != $none) #category: category,
      if (group != $none) #group: group,
      if (showNotification != $none) #showNotification: showNotification,
      if (sequence != $none) #sequence: sequence,
      if (transitionalItem != $none) #transitionalItem: transitionalItem,
      if (loops != $none) #loops: loops,
      if (conditions != $none) #conditions: conditions,
    }),
  );
  @override
  RawRecipe $make(CopyWithData data) => RawRecipe(
    type: data.get(#type, or: $value.type),
    ingredients: data.get(#ingredients, or: $value.ingredients),
    ingredient: data.get(#ingredient, or: $value.ingredient),
    results: data.get(#results, or: $value.results),
    result: data.get(#result, or: $value.result),
    processingTime: data.get(#processingTime, or: $value.processingTime),
    heatRequirement: data.get(#heatRequirement, or: $value.heatRequirement),
    keepHeldItem: data.get(#keepHeldItem, or: $value.keepHeldItem),
    acceptMirrored: data.get(#acceptMirrored, or: $value.acceptMirrored),
    pattern: data.get(#pattern, or: $value.pattern),
    key: data.get(#key, or: $value.key),
    category: data.get(#category, or: $value.category),
    group: data.get(#group, or: $value.group),
    showNotification: data.get(#showNotification, or: $value.showNotification),
    sequence: data.get(#sequence, or: $value.sequence),
    transitionalItem: data.get(#transitionalItem, or: $value.transitionalItem),
    loops: data.get(#loops, or: $value.loops),
    conditions: data.get(#conditions, or: $value.conditions),
  );

  @override
  RawRecipeCopyWith<$R2, RawRecipe, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RawRecipeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

