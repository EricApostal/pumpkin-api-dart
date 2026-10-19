// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'orders.dart';

class PackageOrderMapper extends ClassMapperBase<PackageOrder> {
  PackageOrderMapper._();

  static PackageOrderMapper? _instance;
  static PackageOrderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PackageOrderMapper._());
      BigStackMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PackageOrder';

  static List<BigStack> _$entries(PackageOrder v) => v.entries;
  static const Field<PackageOrder, List<BigStack>> _f$entries = Field(
    'entries',
    _$entries,
  );

  @override
  final MappableFields<PackageOrder> fields = const {#entries: _f$entries};

  static PackageOrder _instantiate(DecodingData data) {
    return PackageOrder(data.dec(_f$entries));
  }

  @override
  final Function instantiate = _instantiate;

  static PackageOrder fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PackageOrder>(map);
  }

  static PackageOrder fromJson(String json) {
    return ensureInitialized().decodeJson<PackageOrder>(json);
  }
}

mixin PackageOrderMappable {
  String toJson() {
    return PackageOrderMapper.ensureInitialized().encodeJson<PackageOrder>(
      this as PackageOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return PackageOrderMapper.ensureInitialized().encodeMap<PackageOrder>(
      this as PackageOrder,
    );
  }

  PackageOrderCopyWith<PackageOrder, PackageOrder, PackageOrder> get copyWith =>
      _PackageOrderCopyWithImpl<PackageOrder, PackageOrder>(
        this as PackageOrder,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PackageOrderMapper.ensureInitialized().stringifyValue(
      this as PackageOrder,
    );
  }

  @override
  bool operator ==(Object other) {
    return PackageOrderMapper.ensureInitialized().equalsValue(
      this as PackageOrder,
      other,
    );
  }

  @override
  int get hashCode {
    return PackageOrderMapper.ensureInitialized().hashValue(
      this as PackageOrder,
    );
  }
}

extension PackageOrderValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PackageOrder, $Out> {
  PackageOrderCopyWith<$R, PackageOrder, $Out> get $asPackageOrder =>
      $base.as((v, t, t2) => _PackageOrderCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PackageOrderCopyWith<$R, $In extends PackageOrder, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, BigStack, BigStackCopyWith<$R, BigStack, BigStack>>
  get entries;
  $R call({List<BigStack>? entries});
  PackageOrderCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PackageOrderCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PackageOrder, $Out>
    implements PackageOrderCopyWith<$R, PackageOrder, $Out> {
  _PackageOrderCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PackageOrder> $mapper =
      PackageOrderMapper.ensureInitialized();
  @override
  ListCopyWith<$R, BigStack, BigStackCopyWith<$R, BigStack, BigStack>>
  get entries => ListCopyWith(
    $value.entries,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(entries: v),
  );
  @override
  $R call({List<BigStack>? entries}) =>
      $apply(FieldCopyWithData({if (entries != null) #entries: entries}));
  @override
  PackageOrder $make(CopyWithData data) =>
      PackageOrder(data.get(#entries, or: $value.entries));

  @override
  PackageOrderCopyWith<$R2, PackageOrder, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PackageOrderCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class CraftingEntryMapper extends ClassMapperBase<CraftingEntry> {
  CraftingEntryMapper._();

  static CraftingEntryMapper? _instance;
  static CraftingEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CraftingEntryMapper._());
      PackageOrderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'CraftingEntry';

  static PackageOrder _$pattern(CraftingEntry v) => v.pattern;
  static const Field<CraftingEntry, PackageOrder> _f$pattern = Field(
    'pattern',
    _$pattern,
  );
  static int _$count(CraftingEntry v) => v.count;
  static const Field<CraftingEntry, int> _f$count = Field('count', _$count);

  @override
  final MappableFields<CraftingEntry> fields = const {
    #pattern: _f$pattern,
    #count: _f$count,
  };

  static CraftingEntry _instantiate(DecodingData data) {
    return CraftingEntry(data.dec(_f$pattern), data.dec(_f$count));
  }

  @override
  final Function instantiate = _instantiate;

  static CraftingEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<CraftingEntry>(map);
  }

  static CraftingEntry fromJson(String json) {
    return ensureInitialized().decodeJson<CraftingEntry>(json);
  }
}

mixin CraftingEntryMappable {
  String toJson() {
    return CraftingEntryMapper.ensureInitialized().encodeJson<CraftingEntry>(
      this as CraftingEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return CraftingEntryMapper.ensureInitialized().encodeMap<CraftingEntry>(
      this as CraftingEntry,
    );
  }

  CraftingEntryCopyWith<CraftingEntry, CraftingEntry, CraftingEntry>
  get copyWith => _CraftingEntryCopyWithImpl<CraftingEntry, CraftingEntry>(
    this as CraftingEntry,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return CraftingEntryMapper.ensureInitialized().stringifyValue(
      this as CraftingEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return CraftingEntryMapper.ensureInitialized().equalsValue(
      this as CraftingEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return CraftingEntryMapper.ensureInitialized().hashValue(
      this as CraftingEntry,
    );
  }
}

extension CraftingEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, CraftingEntry, $Out> {
  CraftingEntryCopyWith<$R, CraftingEntry, $Out> get $asCraftingEntry =>
      $base.as((v, t, t2) => _CraftingEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class CraftingEntryCopyWith<$R, $In extends CraftingEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  PackageOrderCopyWith<$R, PackageOrder, PackageOrder> get pattern;
  $R call({PackageOrder? pattern, int? count});
  CraftingEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _CraftingEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, CraftingEntry, $Out>
    implements CraftingEntryCopyWith<$R, CraftingEntry, $Out> {
  _CraftingEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<CraftingEntry> $mapper =
      CraftingEntryMapper.ensureInitialized();
  @override
  PackageOrderCopyWith<$R, PackageOrder, PackageOrder> get pattern =>
      $value.pattern.copyWith.$chain((v) => call(pattern: v));
  @override
  $R call({PackageOrder? pattern, int? count}) => $apply(
    FieldCopyWithData({
      if (pattern != null) #pattern: pattern,
      if (count != null) #count: count,
    }),
  );
  @override
  CraftingEntry $make(CopyWithData data) => CraftingEntry(
    data.get(#pattern, or: $value.pattern),
    data.get(#count, or: $value.count),
  );

  @override
  CraftingEntryCopyWith<$R2, CraftingEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _CraftingEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PackageOrderWithCraftsMapper
    extends ClassMapperBase<PackageOrderWithCrafts> {
  PackageOrderWithCraftsMapper._();

  static PackageOrderWithCraftsMapper? _instance;
  static PackageOrderWithCraftsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PackageOrderWithCraftsMapper._());
      PackageOrderMapper.ensureInitialized();
      CraftingEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PackageOrderWithCrafts';

  static PackageOrder _$orderedStacks(PackageOrderWithCrafts v) =>
      v.orderedStacks;
  static const Field<PackageOrderWithCrafts, PackageOrder> _f$orderedStacks =
      Field('orderedStacks', _$orderedStacks, key: r'ordered_stacks');
  static List<CraftingEntry> _$orderedCrafts(PackageOrderWithCrafts v) =>
      v.orderedCrafts;
  static const Field<PackageOrderWithCrafts, List<CraftingEntry>>
  _f$orderedCrafts = Field(
    'orderedCrafts',
    _$orderedCrafts,
    key: r'ordered_crafts',
  );

  @override
  final MappableFields<PackageOrderWithCrafts> fields = const {
    #orderedStacks: _f$orderedStacks,
    #orderedCrafts: _f$orderedCrafts,
  };

  static PackageOrderWithCrafts _instantiate(DecodingData data) {
    return PackageOrderWithCrafts(
      data.dec(_f$orderedStacks),
      data.dec(_f$orderedCrafts),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PackageOrderWithCrafts fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PackageOrderWithCrafts>(map);
  }

  static PackageOrderWithCrafts fromJson(String json) {
    return ensureInitialized().decodeJson<PackageOrderWithCrafts>(json);
  }
}

mixin PackageOrderWithCraftsMappable {
  String toJson() {
    return PackageOrderWithCraftsMapper.ensureInitialized()
        .encodeJson<PackageOrderWithCrafts>(this as PackageOrderWithCrafts);
  }

  Map<String, dynamic> toMap() {
    return PackageOrderWithCraftsMapper.ensureInitialized()
        .encodeMap<PackageOrderWithCrafts>(this as PackageOrderWithCrafts);
  }

  PackageOrderWithCraftsCopyWith<
    PackageOrderWithCrafts,
    PackageOrderWithCrafts,
    PackageOrderWithCrafts
  >
  get copyWith =>
      _PackageOrderWithCraftsCopyWithImpl<
        PackageOrderWithCrafts,
        PackageOrderWithCrafts
      >(this as PackageOrderWithCrafts, $identity, $identity);
  @override
  String toString() {
    return PackageOrderWithCraftsMapper.ensureInitialized().stringifyValue(
      this as PackageOrderWithCrafts,
    );
  }

  @override
  bool operator ==(Object other) {
    return PackageOrderWithCraftsMapper.ensureInitialized().equalsValue(
      this as PackageOrderWithCrafts,
      other,
    );
  }

  @override
  int get hashCode {
    return PackageOrderWithCraftsMapper.ensureInitialized().hashValue(
      this as PackageOrderWithCrafts,
    );
  }
}

extension PackageOrderWithCraftsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PackageOrderWithCrafts, $Out> {
  PackageOrderWithCraftsCopyWith<$R, PackageOrderWithCrafts, $Out>
  get $asPackageOrderWithCrafts => $base.as(
    (v, t, t2) => _PackageOrderWithCraftsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class PackageOrderWithCraftsCopyWith<
  $R,
  $In extends PackageOrderWithCrafts,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  PackageOrderCopyWith<$R, PackageOrder, PackageOrder> get orderedStacks;
  ListCopyWith<
    $R,
    CraftingEntry,
    CraftingEntryCopyWith<$R, CraftingEntry, CraftingEntry>
  >
  get orderedCrafts;
  $R call({PackageOrder? orderedStacks, List<CraftingEntry>? orderedCrafts});
  PackageOrderWithCraftsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PackageOrderWithCraftsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PackageOrderWithCrafts, $Out>
    implements
        PackageOrderWithCraftsCopyWith<$R, PackageOrderWithCrafts, $Out> {
  _PackageOrderWithCraftsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PackageOrderWithCrafts> $mapper =
      PackageOrderWithCraftsMapper.ensureInitialized();
  @override
  PackageOrderCopyWith<$R, PackageOrder, PackageOrder> get orderedStacks =>
      $value.orderedStacks.copyWith.$chain((v) => call(orderedStacks: v));
  @override
  ListCopyWith<
    $R,
    CraftingEntry,
    CraftingEntryCopyWith<$R, CraftingEntry, CraftingEntry>
  >
  get orderedCrafts => ListCopyWith(
    $value.orderedCrafts,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(orderedCrafts: v),
  );
  @override
  $R call({PackageOrder? orderedStacks, List<CraftingEntry>? orderedCrafts}) =>
      $apply(
        FieldCopyWithData({
          if (orderedStacks != null) #orderedStacks: orderedStacks,
          if (orderedCrafts != null) #orderedCrafts: orderedCrafts,
        }),
      );
  @override
  PackageOrderWithCrafts $make(CopyWithData data) => PackageOrderWithCrafts(
    data.get(#orderedStacks, or: $value.orderedStacks),
    data.get(#orderedCrafts, or: $value.orderedCrafts),
  );

  @override
  PackageOrderWithCraftsCopyWith<$R2, PackageOrderWithCrafts, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _PackageOrderWithCraftsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PackageOrderDataMapper extends ClassMapperBase<PackageOrderData> {
  PackageOrderDataMapper._();

  static PackageOrderDataMapper? _instance;
  static PackageOrderDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PackageOrderDataMapper._());
      PackageOrderWithCraftsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PackageOrderData';

  static int _$orderId(PackageOrderData v) => v.orderId;
  static const Field<PackageOrderData, int> _f$orderId = Field(
    'orderId',
    _$orderId,
    key: r'order_id',
  );
  static int _$linkIndex(PackageOrderData v) => v.linkIndex;
  static const Field<PackageOrderData, int> _f$linkIndex = Field(
    'linkIndex',
    _$linkIndex,
    key: r'link_index',
  );
  static bool _$isFinalLink(PackageOrderData v) => v.isFinalLink;
  static const Field<PackageOrderData, bool> _f$isFinalLink = Field(
    'isFinalLink',
    _$isFinalLink,
    key: r'is_final_link',
  );
  static int _$fragmentIndex(PackageOrderData v) => v.fragmentIndex;
  static const Field<PackageOrderData, int> _f$fragmentIndex = Field(
    'fragmentIndex',
    _$fragmentIndex,
    key: r'fragment_index',
  );
  static bool _$isFinal(PackageOrderData v) => v.isFinal;
  static const Field<PackageOrderData, bool> _f$isFinal = Field(
    'isFinal',
    _$isFinal,
    key: r'is_final',
  );
  static PackageOrderWithCrafts? _$orderContext(PackageOrderData v) =>
      v.orderContext;
  static const Field<PackageOrderData, PackageOrderWithCrafts> _f$orderContext =
      Field('orderContext', _$orderContext, key: r'order_context', opt: true);

  @override
  final MappableFields<PackageOrderData> fields = const {
    #orderId: _f$orderId,
    #linkIndex: _f$linkIndex,
    #isFinalLink: _f$isFinalLink,
    #fragmentIndex: _f$fragmentIndex,
    #isFinal: _f$isFinal,
    #orderContext: _f$orderContext,
  };

  static PackageOrderData _instantiate(DecodingData data) {
    return PackageOrderData(
      data.dec(_f$orderId),
      data.dec(_f$linkIndex),
      data.dec(_f$isFinalLink),
      data.dec(_f$fragmentIndex),
      data.dec(_f$isFinal),
      data.dec(_f$orderContext),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PackageOrderData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PackageOrderData>(map);
  }

  static PackageOrderData fromJson(String json) {
    return ensureInitialized().decodeJson<PackageOrderData>(json);
  }
}

mixin PackageOrderDataMappable {
  String toJson() {
    return PackageOrderDataMapper.ensureInitialized()
        .encodeJson<PackageOrderData>(this as PackageOrderData);
  }

  Map<String, dynamic> toMap() {
    return PackageOrderDataMapper.ensureInitialized()
        .encodeMap<PackageOrderData>(this as PackageOrderData);
  }

  PackageOrderDataCopyWith<PackageOrderData, PackageOrderData, PackageOrderData>
  get copyWith =>
      _PackageOrderDataCopyWithImpl<PackageOrderData, PackageOrderData>(
        this as PackageOrderData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PackageOrderDataMapper.ensureInitialized().stringifyValue(
      this as PackageOrderData,
    );
  }

  @override
  bool operator ==(Object other) {
    return PackageOrderDataMapper.ensureInitialized().equalsValue(
      this as PackageOrderData,
      other,
    );
  }

  @override
  int get hashCode {
    return PackageOrderDataMapper.ensureInitialized().hashValue(
      this as PackageOrderData,
    );
  }
}

extension PackageOrderDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PackageOrderData, $Out> {
  PackageOrderDataCopyWith<$R, PackageOrderData, $Out>
  get $asPackageOrderData =>
      $base.as((v, t, t2) => _PackageOrderDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PackageOrderDataCopyWith<$R, $In extends PackageOrderData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  PackageOrderWithCraftsCopyWith<
    $R,
    PackageOrderWithCrafts,
    PackageOrderWithCrafts
  >?
  get orderContext;
  $R call({
    int? orderId,
    int? linkIndex,
    bool? isFinalLink,
    int? fragmentIndex,
    bool? isFinal,
    PackageOrderWithCrafts? orderContext,
  });
  PackageOrderDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PackageOrderDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PackageOrderData, $Out>
    implements PackageOrderDataCopyWith<$R, PackageOrderData, $Out> {
  _PackageOrderDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PackageOrderData> $mapper =
      PackageOrderDataMapper.ensureInitialized();
  @override
  PackageOrderWithCraftsCopyWith<
    $R,
    PackageOrderWithCrafts,
    PackageOrderWithCrafts
  >?
  get orderContext =>
      $value.orderContext?.copyWith.$chain((v) => call(orderContext: v));
  @override
  $R call({
    int? orderId,
    int? linkIndex,
    bool? isFinalLink,
    int? fragmentIndex,
    bool? isFinal,
    Object? orderContext = $none,
  }) => $apply(
    FieldCopyWithData({
      if (orderId != null) #orderId: orderId,
      if (linkIndex != null) #linkIndex: linkIndex,
      if (isFinalLink != null) #isFinalLink: isFinalLink,
      if (fragmentIndex != null) #fragmentIndex: fragmentIndex,
      if (isFinal != null) #isFinal: isFinal,
      if (orderContext != $none) #orderContext: orderContext,
    }),
  );
  @override
  PackageOrderData $make(CopyWithData data) => PackageOrderData(
    data.get(#orderId, or: $value.orderId),
    data.get(#linkIndex, or: $value.linkIndex),
    data.get(#isFinalLink, or: $value.isFinalLink),
    data.get(#fragmentIndex, or: $value.fragmentIndex),
    data.get(#isFinal, or: $value.isFinal),
    data.get(#orderContext, or: $value.orderContext),
  );

  @override
  PackageOrderDataCopyWith<$R2, PackageOrderData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PackageOrderDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

