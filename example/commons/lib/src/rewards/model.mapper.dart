// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class ItemRewardMapper extends ClassMapperBase<ItemReward> {
  ItemRewardMapper._();

  static ItemRewardMapper? _instance;
  static ItemRewardMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ItemRewardMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ItemReward';

  static String _$item(ItemReward v) => v.item;
  static const Field<ItemReward, String> _f$item = Field('item', _$item);
  static int _$count(ItemReward v) => v.count;
  static const Field<ItemReward, int> _f$count = Field(
    'count',
    _$count,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<ItemReward> fields = const {
    #item: _f$item,
    #count: _f$count,
  };

  static ItemReward _instantiate(DecodingData data) {
    return ItemReward(data.dec(_f$item), count: data.dec(_f$count));
  }

  @override
  final Function instantiate = _instantiate;

  static ItemReward fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ItemReward>(map);
  }

  static ItemReward fromJson(String json) {
    return ensureInitialized().decodeJson<ItemReward>(json);
  }
}

mixin ItemRewardMappable {
  String toJson() {
    return ItemRewardMapper.ensureInitialized().encodeJson<ItemReward>(
      this as ItemReward,
    );
  }

  Map<String, dynamic> toMap() {
    return ItemRewardMapper.ensureInitialized().encodeMap<ItemReward>(
      this as ItemReward,
    );
  }

  ItemRewardCopyWith<ItemReward, ItemReward, ItemReward> get copyWith =>
      _ItemRewardCopyWithImpl<ItemReward, ItemReward>(
        this as ItemReward,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ItemRewardMapper.ensureInitialized().stringifyValue(
      this as ItemReward,
    );
  }

  @override
  bool operator ==(Object other) {
    return ItemRewardMapper.ensureInitialized().equalsValue(
      this as ItemReward,
      other,
    );
  }

  @override
  int get hashCode {
    return ItemRewardMapper.ensureInitialized().hashValue(this as ItemReward);
  }
}

extension ItemRewardValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ItemReward, $Out> {
  ItemRewardCopyWith<$R, ItemReward, $Out> get $asItemReward =>
      $base.as((v, t, t2) => _ItemRewardCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ItemRewardCopyWith<$R, $In extends ItemReward, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? item, int? count});
  ItemRewardCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ItemRewardCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ItemReward, $Out>
    implements ItemRewardCopyWith<$R, ItemReward, $Out> {
  _ItemRewardCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ItemReward> $mapper =
      ItemRewardMapper.ensureInitialized();
  @override
  $R call({String? item, int? count}) => $apply(
    FieldCopyWithData({
      if (item != null) #item: item,
      if (count != null) #count: count,
    }),
  );
  @override
  ItemReward $make(CopyWithData data) => ItemReward(
    data.get(#item, or: $value.item),
    count: data.get(#count, or: $value.count),
  );

  @override
  ItemRewardCopyWith<$R2, ItemReward, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ItemRewardCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class StreakMilestoneMapper extends ClassMapperBase<StreakMilestone> {
  StreakMilestoneMapper._();

  static StreakMilestoneMapper? _instance;
  static StreakMilestoneMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = StreakMilestoneMapper._());
      ItemRewardMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'StreakMilestone';

  static int _$day(StreakMilestone v) => v.day;
  static const Field<StreakMilestone, int> _f$day = Field('day', _$day);
  static int _$currency(StreakMilestone v) => v.currency;
  static const Field<StreakMilestone, int> _f$currency = Field(
    'currency',
    _$currency,
    opt: true,
    def: 0,
  );
  static List<ItemReward> _$items(StreakMilestone v) => v.items;
  static const Field<StreakMilestone, List<ItemReward>> _f$items = Field(
    'items',
    _$items,
    opt: true,
    def: const [],
  );
  static String _$label(StreakMilestone v) => v.label;
  static const Field<StreakMilestone, String> _f$label = Field(
    'label',
    _$label,
    opt: true,
    def: 'Milestone',
  );

  @override
  final MappableFields<StreakMilestone> fields = const {
    #day: _f$day,
    #currency: _f$currency,
    #items: _f$items,
    #label: _f$label,
  };

  static StreakMilestone _instantiate(DecodingData data) {
    return StreakMilestone(
      day: data.dec(_f$day),
      currency: data.dec(_f$currency),
      items: data.dec(_f$items),
      label: data.dec(_f$label),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static StreakMilestone fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<StreakMilestone>(map);
  }

  static StreakMilestone fromJson(String json) {
    return ensureInitialized().decodeJson<StreakMilestone>(json);
  }
}

mixin StreakMilestoneMappable {
  String toJson() {
    return StreakMilestoneMapper.ensureInitialized()
        .encodeJson<StreakMilestone>(this as StreakMilestone);
  }

  Map<String, dynamic> toMap() {
    return StreakMilestoneMapper.ensureInitialized().encodeMap<StreakMilestone>(
      this as StreakMilestone,
    );
  }

  StreakMilestoneCopyWith<StreakMilestone, StreakMilestone, StreakMilestone>
  get copyWith =>
      _StreakMilestoneCopyWithImpl<StreakMilestone, StreakMilestone>(
        this as StreakMilestone,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return StreakMilestoneMapper.ensureInitialized().stringifyValue(
      this as StreakMilestone,
    );
  }

  @override
  bool operator ==(Object other) {
    return StreakMilestoneMapper.ensureInitialized().equalsValue(
      this as StreakMilestone,
      other,
    );
  }

  @override
  int get hashCode {
    return StreakMilestoneMapper.ensureInitialized().hashValue(
      this as StreakMilestone,
    );
  }
}

extension StreakMilestoneValueCopy<$R, $Out>
    on ObjectCopyWith<$R, StreakMilestone, $Out> {
  StreakMilestoneCopyWith<$R, StreakMilestone, $Out> get $asStreakMilestone =>
      $base.as((v, t, t2) => _StreakMilestoneCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class StreakMilestoneCopyWith<$R, $In extends StreakMilestone, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, ItemReward, ItemRewardCopyWith<$R, ItemReward, ItemReward>>
  get items;
  $R call({int? day, int? currency, List<ItemReward>? items, String? label});
  StreakMilestoneCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _StreakMilestoneCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, StreakMilestone, $Out>
    implements StreakMilestoneCopyWith<$R, StreakMilestone, $Out> {
  _StreakMilestoneCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<StreakMilestone> $mapper =
      StreakMilestoneMapper.ensureInitialized();
  @override
  ListCopyWith<$R, ItemReward, ItemRewardCopyWith<$R, ItemReward, ItemReward>>
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({int? day, int? currency, List<ItemReward>? items, String? label}) =>
      $apply(
        FieldCopyWithData({
          if (day != null) #day: day,
          if (currency != null) #currency: currency,
          if (items != null) #items: items,
          if (label != null) #label: label,
        }),
      );
  @override
  StreakMilestone $make(CopyWithData data) => StreakMilestone(
    day: data.get(#day, or: $value.day),
    currency: data.get(#currency, or: $value.currency),
    items: data.get(#items, or: $value.items),
    label: data.get(#label, or: $value.label),
  );

  @override
  StreakMilestoneCopyWith<$R2, StreakMilestone, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _StreakMilestoneCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DailyConfigMapper extends ClassMapperBase<DailyConfig> {
  DailyConfigMapper._();

  static DailyConfigMapper? _instance;
  static DailyConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DailyConfigMapper._());
      StreakMilestoneMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DailyConfig';

  static bool _$enabled(DailyConfig v) => v.enabled;
  static const Field<DailyConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int _$baseAmount(DailyConfig v) => v.baseAmount;
  static const Field<DailyConfig, int> _f$baseAmount = Field(
    'baseAmount',
    _$baseAmount,
    opt: true,
    def: 100,
  );
  static int _$incrementPerDay(DailyConfig v) => v.incrementPerDay;
  static const Field<DailyConfig, int> _f$incrementPerDay = Field(
    'incrementPerDay',
    _$incrementPerDay,
    opt: true,
    def: 25,
  );
  static int _$maxGrowthDays(DailyConfig v) => v.maxGrowthDays;
  static const Field<DailyConfig, int> _f$maxGrowthDays = Field(
    'maxGrowthDays',
    _$maxGrowthDays,
    opt: true,
    def: 7,
  );
  static int _$resetHourUtc(DailyConfig v) => v.resetHourUtc;
  static const Field<DailyConfig, int> _f$resetHourUtc = Field(
    'resetHourUtc',
    _$resetHourUtc,
    opt: true,
    def: 0,
  );
  static int _$graceDays(DailyConfig v) => v.graceDays;
  static const Field<DailyConfig, int> _f$graceDays = Field(
    'graceDays',
    _$graceDays,
    opt: true,
    def: 1,
  );
  static bool _$joinReminder(DailyConfig v) => v.joinReminder;
  static const Field<DailyConfig, bool> _f$joinReminder = Field(
    'joinReminder',
    _$joinReminder,
    opt: true,
    def: true,
  );
  static List<StreakMilestone> _$milestones(DailyConfig v) => v.milestones;
  static const Field<DailyConfig, List<StreakMilestone>> _f$milestones = Field(
    'milestones',
    _$milestones,
    opt: true,
    def: const [
      StreakMilestone(
        day: 7,
        currency: 500,
        items: [ItemReward('diamond', count: 3)],
        label: 'Weekly bonus',
      ),
      StreakMilestone(
        day: 14,
        currency: 1000,
        items: [ItemReward('diamond', count: 8)],
        label: 'Two week bonus',
      ),
      StreakMilestone(
        day: 30,
        currency: 3000,
        items: [ItemReward('netherite_ingot', count: 1)],
        label: 'Monthly bonus',
      ),
    ],
  );

  @override
  final MappableFields<DailyConfig> fields = const {
    #enabled: _f$enabled,
    #baseAmount: _f$baseAmount,
    #incrementPerDay: _f$incrementPerDay,
    #maxGrowthDays: _f$maxGrowthDays,
    #resetHourUtc: _f$resetHourUtc,
    #graceDays: _f$graceDays,
    #joinReminder: _f$joinReminder,
    #milestones: _f$milestones,
  };

  static DailyConfig _instantiate(DecodingData data) {
    return DailyConfig(
      enabled: data.dec(_f$enabled),
      baseAmount: data.dec(_f$baseAmount),
      incrementPerDay: data.dec(_f$incrementPerDay),
      maxGrowthDays: data.dec(_f$maxGrowthDays),
      resetHourUtc: data.dec(_f$resetHourUtc),
      graceDays: data.dec(_f$graceDays),
      joinReminder: data.dec(_f$joinReminder),
      milestones: data.dec(_f$milestones),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DailyConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DailyConfig>(map);
  }

  static DailyConfig fromJson(String json) {
    return ensureInitialized().decodeJson<DailyConfig>(json);
  }
}

mixin DailyConfigMappable {
  String toJson() {
    return DailyConfigMapper.ensureInitialized().encodeJson<DailyConfig>(
      this as DailyConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return DailyConfigMapper.ensureInitialized().encodeMap<DailyConfig>(
      this as DailyConfig,
    );
  }

  DailyConfigCopyWith<DailyConfig, DailyConfig, DailyConfig> get copyWith =>
      _DailyConfigCopyWithImpl<DailyConfig, DailyConfig>(
        this as DailyConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DailyConfigMapper.ensureInitialized().stringifyValue(
      this as DailyConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return DailyConfigMapper.ensureInitialized().equalsValue(
      this as DailyConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return DailyConfigMapper.ensureInitialized().hashValue(this as DailyConfig);
  }
}

extension DailyConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DailyConfig, $Out> {
  DailyConfigCopyWith<$R, DailyConfig, $Out> get $asDailyConfig =>
      $base.as((v, t, t2) => _DailyConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DailyConfigCopyWith<$R, $In extends DailyConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    StreakMilestone,
    StreakMilestoneCopyWith<$R, StreakMilestone, StreakMilestone>
  >
  get milestones;
  $R call({
    bool? enabled,
    int? baseAmount,
    int? incrementPerDay,
    int? maxGrowthDays,
    int? resetHourUtc,
    int? graceDays,
    bool? joinReminder,
    List<StreakMilestone>? milestones,
  });
  DailyConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DailyConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DailyConfig, $Out>
    implements DailyConfigCopyWith<$R, DailyConfig, $Out> {
  _DailyConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DailyConfig> $mapper =
      DailyConfigMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    StreakMilestone,
    StreakMilestoneCopyWith<$R, StreakMilestone, StreakMilestone>
  >
  get milestones => ListCopyWith(
    $value.milestones,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(milestones: v),
  );
  @override
  $R call({
    bool? enabled,
    int? baseAmount,
    int? incrementPerDay,
    int? maxGrowthDays,
    int? resetHourUtc,
    int? graceDays,
    bool? joinReminder,
    List<StreakMilestone>? milestones,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (baseAmount != null) #baseAmount: baseAmount,
      if (incrementPerDay != null) #incrementPerDay: incrementPerDay,
      if (maxGrowthDays != null) #maxGrowthDays: maxGrowthDays,
      if (resetHourUtc != null) #resetHourUtc: resetHourUtc,
      if (graceDays != null) #graceDays: graceDays,
      if (joinReminder != null) #joinReminder: joinReminder,
      if (milestones != null) #milestones: milestones,
    }),
  );
  @override
  DailyConfig $make(CopyWithData data) => DailyConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    baseAmount: data.get(#baseAmount, or: $value.baseAmount),
    incrementPerDay: data.get(#incrementPerDay, or: $value.incrementPerDay),
    maxGrowthDays: data.get(#maxGrowthDays, or: $value.maxGrowthDays),
    resetHourUtc: data.get(#resetHourUtc, or: $value.resetHourUtc),
    graceDays: data.get(#graceDays, or: $value.graceDays),
    joinReminder: data.get(#joinReminder, or: $value.joinReminder),
    milestones: data.get(#milestones, or: $value.milestones),
  );

  @override
  DailyConfigCopyWith<$R2, DailyConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DailyConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlaytimeMilestoneMapper extends ClassMapperBase<PlaytimeMilestone> {
  PlaytimeMilestoneMapper._();

  static PlaytimeMilestoneMapper? _instance;
  static PlaytimeMilestoneMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlaytimeMilestoneMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PlaytimeMilestone';

  static int _$minutes(PlaytimeMilestone v) => v.minutes;
  static const Field<PlaytimeMilestone, int> _f$minutes = Field(
    'minutes',
    _$minutes,
  );
  static int _$currency(PlaytimeMilestone v) => v.currency;
  static const Field<PlaytimeMilestone, int> _f$currency = Field(
    'currency',
    _$currency,
  );

  @override
  final MappableFields<PlaytimeMilestone> fields = const {
    #minutes: _f$minutes,
    #currency: _f$currency,
  };

  static PlaytimeMilestone _instantiate(DecodingData data) {
    return PlaytimeMilestone(
      minutes: data.dec(_f$minutes),
      currency: data.dec(_f$currency),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlaytimeMilestone fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlaytimeMilestone>(map);
  }

  static PlaytimeMilestone fromJson(String json) {
    return ensureInitialized().decodeJson<PlaytimeMilestone>(json);
  }
}

mixin PlaytimeMilestoneMappable {
  String toJson() {
    return PlaytimeMilestoneMapper.ensureInitialized()
        .encodeJson<PlaytimeMilestone>(this as PlaytimeMilestone);
  }

  Map<String, dynamic> toMap() {
    return PlaytimeMilestoneMapper.ensureInitialized()
        .encodeMap<PlaytimeMilestone>(this as PlaytimeMilestone);
  }

  PlaytimeMilestoneCopyWith<
    PlaytimeMilestone,
    PlaytimeMilestone,
    PlaytimeMilestone
  >
  get copyWith =>
      _PlaytimeMilestoneCopyWithImpl<PlaytimeMilestone, PlaytimeMilestone>(
        this as PlaytimeMilestone,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlaytimeMilestoneMapper.ensureInitialized().stringifyValue(
      this as PlaytimeMilestone,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlaytimeMilestoneMapper.ensureInitialized().equalsValue(
      this as PlaytimeMilestone,
      other,
    );
  }

  @override
  int get hashCode {
    return PlaytimeMilestoneMapper.ensureInitialized().hashValue(
      this as PlaytimeMilestone,
    );
  }
}

extension PlaytimeMilestoneValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlaytimeMilestone, $Out> {
  PlaytimeMilestoneCopyWith<$R, PlaytimeMilestone, $Out>
  get $asPlaytimeMilestone => $base.as(
    (v, t, t2) => _PlaytimeMilestoneCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class PlaytimeMilestoneCopyWith<
  $R,
  $In extends PlaytimeMilestone,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? minutes, int? currency});
  PlaytimeMilestoneCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PlaytimeMilestoneCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlaytimeMilestone, $Out>
    implements PlaytimeMilestoneCopyWith<$R, PlaytimeMilestone, $Out> {
  _PlaytimeMilestoneCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlaytimeMilestone> $mapper =
      PlaytimeMilestoneMapper.ensureInitialized();
  @override
  $R call({int? minutes, int? currency}) => $apply(
    FieldCopyWithData({
      if (minutes != null) #minutes: minutes,
      if (currency != null) #currency: currency,
    }),
  );
  @override
  PlaytimeMilestone $make(CopyWithData data) => PlaytimeMilestone(
    minutes: data.get(#minutes, or: $value.minutes),
    currency: data.get(#currency, or: $value.currency),
  );

  @override
  PlaytimeMilestoneCopyWith<$R2, PlaytimeMilestone, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlaytimeMilestoneCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlaytimeConfigMapper extends ClassMapperBase<PlaytimeConfig> {
  PlaytimeConfigMapper._();

  static PlaytimeConfigMapper? _instance;
  static PlaytimeConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlaytimeConfigMapper._());
      PlaytimeMilestoneMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PlaytimeConfig';

  static int _$tickSeconds(PlaytimeConfig v) => v.tickSeconds;
  static const Field<PlaytimeConfig, int> _f$tickSeconds = Field(
    'tickSeconds',
    _$tickSeconds,
    opt: true,
    def: 60,
  );
  static List<PlaytimeMilestone> _$milestones(PlaytimeConfig v) => v.milestones;
  static const Field<PlaytimeConfig, List<PlaytimeMilestone>> _f$milestones =
      Field(
        'milestones',
        _$milestones,
        opt: true,
        def: const [
          PlaytimeMilestone(minutes: 60, currency: 250),
          PlaytimeMilestone(minutes: 600, currency: 1500),
          PlaytimeMilestone(minutes: 3000, currency: 5000),
        ],
      );

  @override
  final MappableFields<PlaytimeConfig> fields = const {
    #tickSeconds: _f$tickSeconds,
    #milestones: _f$milestones,
  };

  static PlaytimeConfig _instantiate(DecodingData data) {
    return PlaytimeConfig(
      tickSeconds: data.dec(_f$tickSeconds),
      milestones: data.dec(_f$milestones),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlaytimeConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlaytimeConfig>(map);
  }

  static PlaytimeConfig fromJson(String json) {
    return ensureInitialized().decodeJson<PlaytimeConfig>(json);
  }
}

mixin PlaytimeConfigMappable {
  String toJson() {
    return PlaytimeConfigMapper.ensureInitialized().encodeJson<PlaytimeConfig>(
      this as PlaytimeConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return PlaytimeConfigMapper.ensureInitialized().encodeMap<PlaytimeConfig>(
      this as PlaytimeConfig,
    );
  }

  PlaytimeConfigCopyWith<PlaytimeConfig, PlaytimeConfig, PlaytimeConfig>
  get copyWith => _PlaytimeConfigCopyWithImpl<PlaytimeConfig, PlaytimeConfig>(
    this as PlaytimeConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return PlaytimeConfigMapper.ensureInitialized().stringifyValue(
      this as PlaytimeConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlaytimeConfigMapper.ensureInitialized().equalsValue(
      this as PlaytimeConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return PlaytimeConfigMapper.ensureInitialized().hashValue(
      this as PlaytimeConfig,
    );
  }
}

extension PlaytimeConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlaytimeConfig, $Out> {
  PlaytimeConfigCopyWith<$R, PlaytimeConfig, $Out> get $asPlaytimeConfig =>
      $base.as((v, t, t2) => _PlaytimeConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlaytimeConfigCopyWith<$R, $In extends PlaytimeConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    PlaytimeMilestone,
    PlaytimeMilestoneCopyWith<$R, PlaytimeMilestone, PlaytimeMilestone>
  >
  get milestones;
  $R call({int? tickSeconds, List<PlaytimeMilestone>? milestones});
  PlaytimeConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PlaytimeConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlaytimeConfig, $Out>
    implements PlaytimeConfigCopyWith<$R, PlaytimeConfig, $Out> {
  _PlaytimeConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlaytimeConfig> $mapper =
      PlaytimeConfigMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    PlaytimeMilestone,
    PlaytimeMilestoneCopyWith<$R, PlaytimeMilestone, PlaytimeMilestone>
  >
  get milestones => ListCopyWith(
    $value.milestones,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(milestones: v),
  );
  @override
  $R call({int? tickSeconds, List<PlaytimeMilestone>? milestones}) => $apply(
    FieldCopyWithData({
      if (tickSeconds != null) #tickSeconds: tickSeconds,
      if (milestones != null) #milestones: milestones,
    }),
  );
  @override
  PlaytimeConfig $make(CopyWithData data) => PlaytimeConfig(
    tickSeconds: data.get(#tickSeconds, or: $value.tickSeconds),
    milestones: data.get(#milestones, or: $value.milestones),
  );

  @override
  PlaytimeConfigCopyWith<$R2, PlaytimeConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlaytimeConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RewardsConfigMapper extends ClassMapperBase<RewardsConfig> {
  RewardsConfigMapper._();

  static RewardsConfigMapper? _instance;
  static RewardsConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RewardsConfigMapper._());
      DailyConfigMapper.ensureInitialized();
      PlaytimeConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RewardsConfig';

  static DailyConfig _$daily(RewardsConfig v) => v.daily;
  static const Field<RewardsConfig, DailyConfig> _f$daily = Field(
    'daily',
    _$daily,
    opt: true,
    def: const DailyConfig(),
  );
  static PlaytimeConfig _$playtime(RewardsConfig v) => v.playtime;
  static const Field<RewardsConfig, PlaytimeConfig> _f$playtime = Field(
    'playtime',
    _$playtime,
    opt: true,
    def: const PlaytimeConfig(),
  );

  @override
  final MappableFields<RewardsConfig> fields = const {
    #daily: _f$daily,
    #playtime: _f$playtime,
  };

  static RewardsConfig _instantiate(DecodingData data) {
    return RewardsConfig(
      daily: data.dec(_f$daily),
      playtime: data.dec(_f$playtime),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RewardsConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RewardsConfig>(map);
  }

  static RewardsConfig fromJson(String json) {
    return ensureInitialized().decodeJson<RewardsConfig>(json);
  }
}

mixin RewardsConfigMappable {
  String toJson() {
    return RewardsConfigMapper.ensureInitialized().encodeJson<RewardsConfig>(
      this as RewardsConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return RewardsConfigMapper.ensureInitialized().encodeMap<RewardsConfig>(
      this as RewardsConfig,
    );
  }

  RewardsConfigCopyWith<RewardsConfig, RewardsConfig, RewardsConfig>
  get copyWith => _RewardsConfigCopyWithImpl<RewardsConfig, RewardsConfig>(
    this as RewardsConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RewardsConfigMapper.ensureInitialized().stringifyValue(
      this as RewardsConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return RewardsConfigMapper.ensureInitialized().equalsValue(
      this as RewardsConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return RewardsConfigMapper.ensureInitialized().hashValue(
      this as RewardsConfig,
    );
  }
}

extension RewardsConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RewardsConfig, $Out> {
  RewardsConfigCopyWith<$R, RewardsConfig, $Out> get $asRewardsConfig =>
      $base.as((v, t, t2) => _RewardsConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RewardsConfigCopyWith<$R, $In extends RewardsConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  DailyConfigCopyWith<$R, DailyConfig, DailyConfig> get daily;
  PlaytimeConfigCopyWith<$R, PlaytimeConfig, PlaytimeConfig> get playtime;
  $R call({DailyConfig? daily, PlaytimeConfig? playtime});
  RewardsConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RewardsConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RewardsConfig, $Out>
    implements RewardsConfigCopyWith<$R, RewardsConfig, $Out> {
  _RewardsConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RewardsConfig> $mapper =
      RewardsConfigMapper.ensureInitialized();
  @override
  DailyConfigCopyWith<$R, DailyConfig, DailyConfig> get daily =>
      $value.daily.copyWith.$chain((v) => call(daily: v));
  @override
  PlaytimeConfigCopyWith<$R, PlaytimeConfig, PlaytimeConfig> get playtime =>
      $value.playtime.copyWith.$chain((v) => call(playtime: v));
  @override
  $R call({DailyConfig? daily, PlaytimeConfig? playtime}) => $apply(
    FieldCopyWithData({
      if (daily != null) #daily: daily,
      if (playtime != null) #playtime: playtime,
    }),
  );
  @override
  RewardsConfig $make(CopyWithData data) => RewardsConfig(
    daily: data.get(#daily, or: $value.daily),
    playtime: data.get(#playtime, or: $value.playtime),
  );

  @override
  RewardsConfigCopyWith<$R2, RewardsConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RewardsConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DailyStateMapper extends ClassMapperBase<DailyState> {
  DailyStateMapper._();

  static DailyStateMapper? _instance;
  static DailyStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DailyStateMapper._());
      ItemRewardMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DailyState';

  static DateTime? _$lastClaimAt(DailyState v) => v.lastClaimAt;
  static const Field<DailyState, DateTime> _f$lastClaimAt = Field(
    'lastClaimAt',
    _$lastClaimAt,
    opt: true,
  );
  static int _$streak(DailyState v) => v.streak;
  static const Field<DailyState, int> _f$streak = Field(
    'streak',
    _$streak,
    opt: true,
    def: 0,
  );
  static int _$bestStreak(DailyState v) => v.bestStreak;
  static const Field<DailyState, int> _f$bestStreak = Field(
    'bestStreak',
    _$bestStreak,
    opt: true,
    def: 0,
  );
  static int _$totalClaims(DailyState v) => v.totalClaims;
  static const Field<DailyState, int> _f$totalClaims = Field(
    'totalClaims',
    _$totalClaims,
    opt: true,
    def: 0,
  );
  static List<ItemReward> _$pendingItems(DailyState v) => v.pendingItems;
  static const Field<DailyState, List<ItemReward>> _f$pendingItems = Field(
    'pendingItems',
    _$pendingItems,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<DailyState> fields = const {
    #lastClaimAt: _f$lastClaimAt,
    #streak: _f$streak,
    #bestStreak: _f$bestStreak,
    #totalClaims: _f$totalClaims,
    #pendingItems: _f$pendingItems,
  };

  static DailyState _instantiate(DecodingData data) {
    return DailyState(
      lastClaimAt: data.dec(_f$lastClaimAt),
      streak: data.dec(_f$streak),
      bestStreak: data.dec(_f$bestStreak),
      totalClaims: data.dec(_f$totalClaims),
      pendingItems: data.dec(_f$pendingItems),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DailyState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DailyState>(map);
  }

  static DailyState fromJson(String json) {
    return ensureInitialized().decodeJson<DailyState>(json);
  }
}

mixin DailyStateMappable {
  String toJson() {
    return DailyStateMapper.ensureInitialized().encodeJson<DailyState>(
      this as DailyState,
    );
  }

  Map<String, dynamic> toMap() {
    return DailyStateMapper.ensureInitialized().encodeMap<DailyState>(
      this as DailyState,
    );
  }

  DailyStateCopyWith<DailyState, DailyState, DailyState> get copyWith =>
      _DailyStateCopyWithImpl<DailyState, DailyState>(
        this as DailyState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DailyStateMapper.ensureInitialized().stringifyValue(
      this as DailyState,
    );
  }

  @override
  bool operator ==(Object other) {
    return DailyStateMapper.ensureInitialized().equalsValue(
      this as DailyState,
      other,
    );
  }

  @override
  int get hashCode {
    return DailyStateMapper.ensureInitialized().hashValue(this as DailyState);
  }
}

extension DailyStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DailyState, $Out> {
  DailyStateCopyWith<$R, DailyState, $Out> get $asDailyState =>
      $base.as((v, t, t2) => _DailyStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DailyStateCopyWith<$R, $In extends DailyState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, ItemReward, ItemRewardCopyWith<$R, ItemReward, ItemReward>>
  get pendingItems;
  $R call({
    DateTime? lastClaimAt,
    int? streak,
    int? bestStreak,
    int? totalClaims,
    List<ItemReward>? pendingItems,
  });
  DailyStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DailyStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DailyState, $Out>
    implements DailyStateCopyWith<$R, DailyState, $Out> {
  _DailyStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DailyState> $mapper =
      DailyStateMapper.ensureInitialized();
  @override
  ListCopyWith<$R, ItemReward, ItemRewardCopyWith<$R, ItemReward, ItemReward>>
  get pendingItems => ListCopyWith(
    $value.pendingItems,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(pendingItems: v),
  );
  @override
  $R call({
    Object? lastClaimAt = $none,
    int? streak,
    int? bestStreak,
    int? totalClaims,
    List<ItemReward>? pendingItems,
  }) => $apply(
    FieldCopyWithData({
      if (lastClaimAt != $none) #lastClaimAt: lastClaimAt,
      if (streak != null) #streak: streak,
      if (bestStreak != null) #bestStreak: bestStreak,
      if (totalClaims != null) #totalClaims: totalClaims,
      if (pendingItems != null) #pendingItems: pendingItems,
    }),
  );
  @override
  DailyState $make(CopyWithData data) => DailyState(
    lastClaimAt: data.get(#lastClaimAt, or: $value.lastClaimAt),
    streak: data.get(#streak, or: $value.streak),
    bestStreak: data.get(#bestStreak, or: $value.bestStreak),
    totalClaims: data.get(#totalClaims, or: $value.totalClaims),
    pendingItems: data.get(#pendingItems, or: $value.pendingItems),
  );

  @override
  DailyStateCopyWith<$R2, DailyState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DailyStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DailyFileMapper extends ClassMapperBase<DailyFile> {
  DailyFileMapper._();

  static DailyFileMapper? _instance;
  static DailyFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DailyFileMapper._());
      DailyStateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DailyFile';

  static Map<String, DailyState> _$players(DailyFile v) => v.players;
  static const Field<DailyFile, Map<String, DailyState>> _f$players = Field(
    'players',
    _$players,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<DailyFile> fields = const {#players: _f$players};

  static DailyFile _instantiate(DecodingData data) {
    return DailyFile(players: data.dec(_f$players));
  }

  @override
  final Function instantiate = _instantiate;

  static DailyFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DailyFile>(map);
  }

  static DailyFile fromJson(String json) {
    return ensureInitialized().decodeJson<DailyFile>(json);
  }
}

mixin DailyFileMappable {
  String toJson() {
    return DailyFileMapper.ensureInitialized().encodeJson<DailyFile>(
      this as DailyFile,
    );
  }

  Map<String, dynamic> toMap() {
    return DailyFileMapper.ensureInitialized().encodeMap<DailyFile>(
      this as DailyFile,
    );
  }

  DailyFileCopyWith<DailyFile, DailyFile, DailyFile> get copyWith =>
      _DailyFileCopyWithImpl<DailyFile, DailyFile>(
        this as DailyFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DailyFileMapper.ensureInitialized().stringifyValue(
      this as DailyFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return DailyFileMapper.ensureInitialized().equalsValue(
      this as DailyFile,
      other,
    );
  }

  @override
  int get hashCode {
    return DailyFileMapper.ensureInitialized().hashValue(this as DailyFile);
  }
}

extension DailyFileValueCopy<$R, $Out> on ObjectCopyWith<$R, DailyFile, $Out> {
  DailyFileCopyWith<$R, DailyFile, $Out> get $asDailyFile =>
      $base.as((v, t, t2) => _DailyFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DailyFileCopyWith<$R, $In extends DailyFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    DailyState,
    DailyStateCopyWith<$R, DailyState, DailyState>
  >
  get players;
  $R call({Map<String, DailyState>? players});
  DailyFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DailyFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DailyFile, $Out>
    implements DailyFileCopyWith<$R, DailyFile, $Out> {
  _DailyFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DailyFile> $mapper =
      DailyFileMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    DailyState,
    DailyStateCopyWith<$R, DailyState, DailyState>
  >
  get players => MapCopyWith(
    $value.players,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(players: v),
  );
  @override
  $R call({Map<String, DailyState>? players}) =>
      $apply(FieldCopyWithData({if (players != null) #players: players}));
  @override
  DailyFile $make(CopyWithData data) =>
      DailyFile(players: data.get(#players, or: $value.players));

  @override
  DailyFileCopyWith<$R2, DailyFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DailyFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlaytimeEntryMapper extends ClassMapperBase<PlaytimeEntry> {
  PlaytimeEntryMapper._();

  static PlaytimeEntryMapper? _instance;
  static PlaytimeEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlaytimeEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PlaytimeEntry';

  static int _$seconds(PlaytimeEntry v) => v.seconds;
  static const Field<PlaytimeEntry, int> _f$seconds = Field(
    'seconds',
    _$seconds,
    opt: true,
    def: 0,
  );
  static List<int> _$paidMilestones(PlaytimeEntry v) => v.paidMilestones;
  static const Field<PlaytimeEntry, List<int>> _f$paidMilestones = Field(
    'paidMilestones',
    _$paidMilestones,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<PlaytimeEntry> fields = const {
    #seconds: _f$seconds,
    #paidMilestones: _f$paidMilestones,
  };

  static PlaytimeEntry _instantiate(DecodingData data) {
    return PlaytimeEntry(
      seconds: data.dec(_f$seconds),
      paidMilestones: data.dec(_f$paidMilestones),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlaytimeEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlaytimeEntry>(map);
  }

  static PlaytimeEntry fromJson(String json) {
    return ensureInitialized().decodeJson<PlaytimeEntry>(json);
  }
}

mixin PlaytimeEntryMappable {
  String toJson() {
    return PlaytimeEntryMapper.ensureInitialized().encodeJson<PlaytimeEntry>(
      this as PlaytimeEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return PlaytimeEntryMapper.ensureInitialized().encodeMap<PlaytimeEntry>(
      this as PlaytimeEntry,
    );
  }

  PlaytimeEntryCopyWith<PlaytimeEntry, PlaytimeEntry, PlaytimeEntry>
  get copyWith => _PlaytimeEntryCopyWithImpl<PlaytimeEntry, PlaytimeEntry>(
    this as PlaytimeEntry,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return PlaytimeEntryMapper.ensureInitialized().stringifyValue(
      this as PlaytimeEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlaytimeEntryMapper.ensureInitialized().equalsValue(
      this as PlaytimeEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return PlaytimeEntryMapper.ensureInitialized().hashValue(
      this as PlaytimeEntry,
    );
  }
}

extension PlaytimeEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlaytimeEntry, $Out> {
  PlaytimeEntryCopyWith<$R, PlaytimeEntry, $Out> get $asPlaytimeEntry =>
      $base.as((v, t, t2) => _PlaytimeEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlaytimeEntryCopyWith<$R, $In extends PlaytimeEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, int, ObjectCopyWith<$R, int, int>> get paidMilestones;
  $R call({int? seconds, List<int>? paidMilestones});
  PlaytimeEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PlaytimeEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlaytimeEntry, $Out>
    implements PlaytimeEntryCopyWith<$R, PlaytimeEntry, $Out> {
  _PlaytimeEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlaytimeEntry> $mapper =
      PlaytimeEntryMapper.ensureInitialized();
  @override
  ListCopyWith<$R, int, ObjectCopyWith<$R, int, int>> get paidMilestones =>
      ListCopyWith(
        $value.paidMilestones,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(paidMilestones: v),
      );
  @override
  $R call({int? seconds, List<int>? paidMilestones}) => $apply(
    FieldCopyWithData({
      if (seconds != null) #seconds: seconds,
      if (paidMilestones != null) #paidMilestones: paidMilestones,
    }),
  );
  @override
  PlaytimeEntry $make(CopyWithData data) => PlaytimeEntry(
    seconds: data.get(#seconds, or: $value.seconds),
    paidMilestones: data.get(#paidMilestones, or: $value.paidMilestones),
  );

  @override
  PlaytimeEntryCopyWith<$R2, PlaytimeEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlaytimeEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlaytimeFileMapper extends ClassMapperBase<PlaytimeFile> {
  PlaytimeFileMapper._();

  static PlaytimeFileMapper? _instance;
  static PlaytimeFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlaytimeFileMapper._());
      PlaytimeEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PlaytimeFile';

  static Map<String, PlaytimeEntry> _$players(PlaytimeFile v) => v.players;
  static const Field<PlaytimeFile, Map<String, PlaytimeEntry>> _f$players =
      Field('players', _$players, opt: true, def: const {});

  @override
  final MappableFields<PlaytimeFile> fields = const {#players: _f$players};

  static PlaytimeFile _instantiate(DecodingData data) {
    return PlaytimeFile(players: data.dec(_f$players));
  }

  @override
  final Function instantiate = _instantiate;

  static PlaytimeFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlaytimeFile>(map);
  }

  static PlaytimeFile fromJson(String json) {
    return ensureInitialized().decodeJson<PlaytimeFile>(json);
  }
}

mixin PlaytimeFileMappable {
  String toJson() {
    return PlaytimeFileMapper.ensureInitialized().encodeJson<PlaytimeFile>(
      this as PlaytimeFile,
    );
  }

  Map<String, dynamic> toMap() {
    return PlaytimeFileMapper.ensureInitialized().encodeMap<PlaytimeFile>(
      this as PlaytimeFile,
    );
  }

  PlaytimeFileCopyWith<PlaytimeFile, PlaytimeFile, PlaytimeFile> get copyWith =>
      _PlaytimeFileCopyWithImpl<PlaytimeFile, PlaytimeFile>(
        this as PlaytimeFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlaytimeFileMapper.ensureInitialized().stringifyValue(
      this as PlaytimeFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlaytimeFileMapper.ensureInitialized().equalsValue(
      this as PlaytimeFile,
      other,
    );
  }

  @override
  int get hashCode {
    return PlaytimeFileMapper.ensureInitialized().hashValue(
      this as PlaytimeFile,
    );
  }
}

extension PlaytimeFileValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlaytimeFile, $Out> {
  PlaytimeFileCopyWith<$R, PlaytimeFile, $Out> get $asPlaytimeFile =>
      $base.as((v, t, t2) => _PlaytimeFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlaytimeFileCopyWith<$R, $In extends PlaytimeFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    PlaytimeEntry,
    PlaytimeEntryCopyWith<$R, PlaytimeEntry, PlaytimeEntry>
  >
  get players;
  $R call({Map<String, PlaytimeEntry>? players});
  PlaytimeFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PlaytimeFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlaytimeFile, $Out>
    implements PlaytimeFileCopyWith<$R, PlaytimeFile, $Out> {
  _PlaytimeFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlaytimeFile> $mapper =
      PlaytimeFileMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    PlaytimeEntry,
    PlaytimeEntryCopyWith<$R, PlaytimeEntry, PlaytimeEntry>
  >
  get players => MapCopyWith(
    $value.players,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(players: v),
  );
  @override
  $R call({Map<String, PlaytimeEntry>? players}) =>
      $apply(FieldCopyWithData({if (players != null) #players: players}));
  @override
  PlaytimeFile $make(CopyWithData data) =>
      PlaytimeFile(players: data.get(#players, or: $value.players));

  @override
  PlaytimeFileCopyWith<$R2, PlaytimeFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlaytimeFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

