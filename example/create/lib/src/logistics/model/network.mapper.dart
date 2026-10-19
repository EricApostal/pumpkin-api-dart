// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'network.dart';

class RequestPromiseMapper extends ClassMapperBase<RequestPromise> {
  RequestPromiseMapper._();

  static RequestPromiseMapper? _instance;
  static RequestPromiseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RequestPromiseMapper._());
      BigStackMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RequestPromise';

  static BigStack _$promisedStack(RequestPromise v) => v.promisedStack;
  static const Field<RequestPromise, BigStack> _f$promisedStack = Field(
    'promisedStack',
    _$promisedStack,
    key: r'promised_stack',
  );
  static int _$ticksExisted(RequestPromise v) => v.ticksExisted;
  static const Field<RequestPromise, int> _f$ticksExisted = Field(
    'ticksExisted',
    _$ticksExisted,
    key: r'ticks_existed',
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<RequestPromise> fields = const {
    #promisedStack: _f$promisedStack,
    #ticksExisted: _f$ticksExisted,
  };

  static RequestPromise _instantiate(DecodingData data) {
    return RequestPromise(
      data.dec(_f$promisedStack),
      data.dec(_f$ticksExisted),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RequestPromise fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RequestPromise>(map);
  }

  static RequestPromise fromJson(String json) {
    return ensureInitialized().decodeJson<RequestPromise>(json);
  }
}

mixin RequestPromiseMappable {
  String toJson() {
    return RequestPromiseMapper.ensureInitialized().encodeJson<RequestPromise>(
      this as RequestPromise,
    );
  }

  Map<String, dynamic> toMap() {
    return RequestPromiseMapper.ensureInitialized().encodeMap<RequestPromise>(
      this as RequestPromise,
    );
  }

  RequestPromiseCopyWith<RequestPromise, RequestPromise, RequestPromise>
  get copyWith => _RequestPromiseCopyWithImpl<RequestPromise, RequestPromise>(
    this as RequestPromise,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RequestPromiseMapper.ensureInitialized().stringifyValue(
      this as RequestPromise,
    );
  }

  @override
  bool operator ==(Object other) {
    return RequestPromiseMapper.ensureInitialized().equalsValue(
      this as RequestPromise,
      other,
    );
  }

  @override
  int get hashCode {
    return RequestPromiseMapper.ensureInitialized().hashValue(
      this as RequestPromise,
    );
  }
}

extension RequestPromiseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RequestPromise, $Out> {
  RequestPromiseCopyWith<$R, RequestPromise, $Out> get $asRequestPromise =>
      $base.as((v, t, t2) => _RequestPromiseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RequestPromiseCopyWith<$R, $In extends RequestPromise, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  BigStackCopyWith<$R, BigStack, BigStack> get promisedStack;
  $R call({BigStack? promisedStack, int? ticksExisted});
  RequestPromiseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RequestPromiseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RequestPromise, $Out>
    implements RequestPromiseCopyWith<$R, RequestPromise, $Out> {
  _RequestPromiseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RequestPromise> $mapper =
      RequestPromiseMapper.ensureInitialized();
  @override
  BigStackCopyWith<$R, BigStack, BigStack> get promisedStack =>
      $value.promisedStack.copyWith.$chain((v) => call(promisedStack: v));
  @override
  $R call({BigStack? promisedStack, int? ticksExisted}) => $apply(
    FieldCopyWithData({
      if (promisedStack != null) #promisedStack: promisedStack,
      if (ticksExisted != null) #ticksExisted: ticksExisted,
    }),
  );
  @override
  RequestPromise $make(CopyWithData data) => RequestPromise(
    data.get(#promisedStack, or: $value.promisedStack),
    data.get(#ticksExisted, or: $value.ticksExisted),
  );

  @override
  RequestPromiseCopyWith<$R2, RequestPromise, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RequestPromiseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GlobalPosMapper extends ClassMapperBase<GlobalPos> {
  GlobalPosMapper._();

  static GlobalPosMapper? _instance;
  static GlobalPosMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GlobalPosMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'GlobalPos';

  static String _$dimension(GlobalPos v) => v.dimension;
  static const Field<GlobalPos, String> _f$dimension = Field(
    'dimension',
    _$dimension,
  );
  static int _$x(GlobalPos v) => v.x;
  static const Field<GlobalPos, int> _f$x = Field('x', _$x);
  static int _$y(GlobalPos v) => v.y;
  static const Field<GlobalPos, int> _f$y = Field('y', _$y);
  static int _$z(GlobalPos v) => v.z;
  static const Field<GlobalPos, int> _f$z = Field('z', _$z);

  @override
  final MappableFields<GlobalPos> fields = const {
    #dimension: _f$dimension,
    #x: _f$x,
    #y: _f$y,
    #z: _f$z,
  };

  static GlobalPos _instantiate(DecodingData data) {
    return GlobalPos(
      data.dec(_f$dimension),
      data.dec(_f$x),
      data.dec(_f$y),
      data.dec(_f$z),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GlobalPos fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GlobalPos>(map);
  }

  static GlobalPos fromJson(String json) {
    return ensureInitialized().decodeJson<GlobalPos>(json);
  }
}

mixin GlobalPosMappable {
  String toJson() {
    return GlobalPosMapper.ensureInitialized().encodeJson<GlobalPos>(
      this as GlobalPos,
    );
  }

  Map<String, dynamic> toMap() {
    return GlobalPosMapper.ensureInitialized().encodeMap<GlobalPos>(
      this as GlobalPos,
    );
  }

  GlobalPosCopyWith<GlobalPos, GlobalPos, GlobalPos> get copyWith =>
      _GlobalPosCopyWithImpl<GlobalPos, GlobalPos>(
        this as GlobalPos,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GlobalPosMapper.ensureInitialized().stringifyValue(
      this as GlobalPos,
    );
  }

  @override
  bool operator ==(Object other) {
    return GlobalPosMapper.ensureInitialized().equalsValue(
      this as GlobalPos,
      other,
    );
  }

  @override
  int get hashCode {
    return GlobalPosMapper.ensureInitialized().hashValue(this as GlobalPos);
  }
}

extension GlobalPosValueCopy<$R, $Out> on ObjectCopyWith<$R, GlobalPos, $Out> {
  GlobalPosCopyWith<$R, GlobalPos, $Out> get $asGlobalPos =>
      $base.as((v, t, t2) => _GlobalPosCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GlobalPosCopyWith<$R, $In extends GlobalPos, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? dimension, int? x, int? y, int? z});
  GlobalPosCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _GlobalPosCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GlobalPos, $Out>
    implements GlobalPosCopyWith<$R, GlobalPos, $Out> {
  _GlobalPosCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GlobalPos> $mapper =
      GlobalPosMapper.ensureInitialized();
  @override
  $R call({String? dimension, int? x, int? y, int? z}) => $apply(
    FieldCopyWithData({
      if (dimension != null) #dimension: dimension,
      if (x != null) #x: x,
      if (y != null) #y: y,
      if (z != null) #z: z,
    }),
  );
  @override
  GlobalPos $make(CopyWithData data) => GlobalPos(
    data.get(#dimension, or: $value.dimension),
    data.get(#x, or: $value.x),
    data.get(#y, or: $value.y),
    data.get(#z, or: $value.z),
  );

  @override
  GlobalPosCopyWith<$R2, GlobalPos, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GlobalPosCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LogisticsNetworkDataMapper extends ClassMapperBase<LogisticsNetworkData> {
  LogisticsNetworkDataMapper._();

  static LogisticsNetworkDataMapper? _instance;
  static LogisticsNetworkDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LogisticsNetworkDataMapper._());
      RequestPromiseMapper.ensureInitialized();
      GlobalPosMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LogisticsNetworkData';

  static String _$id(LogisticsNetworkData v) => v.id;
  static const Field<LogisticsNetworkData, String> _f$id = Field('id', _$id);
  static List<RequestPromise> _$promises(LogisticsNetworkData v) => v.promises;
  static const Field<LogisticsNetworkData, List<RequestPromise>> _f$promises =
      Field('promises', _$promises);
  static List<GlobalPos> _$links(LogisticsNetworkData v) => v.links;
  static const Field<LogisticsNetworkData, List<GlobalPos>> _f$links = Field(
    'links',
    _$links,
  );
  static String? _$owner(LogisticsNetworkData v) => v.owner;
  static const Field<LogisticsNetworkData, String> _f$owner = Field(
    'owner',
    _$owner,
  );
  static bool _$locked(LogisticsNetworkData v) => v.locked;
  static const Field<LogisticsNetworkData, bool> _f$locked = Field(
    'locked',
    _$locked,
  );

  @override
  final MappableFields<LogisticsNetworkData> fields = const {
    #id: _f$id,
    #promises: _f$promises,
    #links: _f$links,
    #owner: _f$owner,
    #locked: _f$locked,
  };

  static LogisticsNetworkData _instantiate(DecodingData data) {
    return LogisticsNetworkData(
      data.dec(_f$id),
      data.dec(_f$promises),
      data.dec(_f$links),
      data.dec(_f$owner),
      data.dec(_f$locked),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LogisticsNetworkData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LogisticsNetworkData>(map);
  }

  static LogisticsNetworkData fromJson(String json) {
    return ensureInitialized().decodeJson<LogisticsNetworkData>(json);
  }
}

mixin LogisticsNetworkDataMappable {
  String toJson() {
    return LogisticsNetworkDataMapper.ensureInitialized()
        .encodeJson<LogisticsNetworkData>(this as LogisticsNetworkData);
  }

  Map<String, dynamic> toMap() {
    return LogisticsNetworkDataMapper.ensureInitialized()
        .encodeMap<LogisticsNetworkData>(this as LogisticsNetworkData);
  }

  LogisticsNetworkDataCopyWith<
    LogisticsNetworkData,
    LogisticsNetworkData,
    LogisticsNetworkData
  >
  get copyWith =>
      _LogisticsNetworkDataCopyWithImpl<
        LogisticsNetworkData,
        LogisticsNetworkData
      >(this as LogisticsNetworkData, $identity, $identity);
  @override
  String toString() {
    return LogisticsNetworkDataMapper.ensureInitialized().stringifyValue(
      this as LogisticsNetworkData,
    );
  }

  @override
  bool operator ==(Object other) {
    return LogisticsNetworkDataMapper.ensureInitialized().equalsValue(
      this as LogisticsNetworkData,
      other,
    );
  }

  @override
  int get hashCode {
    return LogisticsNetworkDataMapper.ensureInitialized().hashValue(
      this as LogisticsNetworkData,
    );
  }
}

extension LogisticsNetworkDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LogisticsNetworkData, $Out> {
  LogisticsNetworkDataCopyWith<$R, LogisticsNetworkData, $Out>
  get $asLogisticsNetworkData => $base.as(
    (v, t, t2) => _LogisticsNetworkDataCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LogisticsNetworkDataCopyWith<
  $R,
  $In extends LogisticsNetworkData,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    RequestPromise,
    RequestPromiseCopyWith<$R, RequestPromise, RequestPromise>
  >
  get promises;
  ListCopyWith<$R, GlobalPos, GlobalPosCopyWith<$R, GlobalPos, GlobalPos>>
  get links;
  $R call({
    String? id,
    List<RequestPromise>? promises,
    List<GlobalPos>? links,
    String? owner,
    bool? locked,
  });
  LogisticsNetworkDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LogisticsNetworkDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LogisticsNetworkData, $Out>
    implements LogisticsNetworkDataCopyWith<$R, LogisticsNetworkData, $Out> {
  _LogisticsNetworkDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LogisticsNetworkData> $mapper =
      LogisticsNetworkDataMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    RequestPromise,
    RequestPromiseCopyWith<$R, RequestPromise, RequestPromise>
  >
  get promises => ListCopyWith(
    $value.promises,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(promises: v),
  );
  @override
  ListCopyWith<$R, GlobalPos, GlobalPosCopyWith<$R, GlobalPos, GlobalPos>>
  get links => ListCopyWith(
    $value.links,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(links: v),
  );
  @override
  $R call({
    String? id,
    List<RequestPromise>? promises,
    List<GlobalPos>? links,
    Object? owner = $none,
    bool? locked,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (promises != null) #promises: promises,
      if (links != null) #links: links,
      if (owner != $none) #owner: owner,
      if (locked != null) #locked: locked,
    }),
  );
  @override
  LogisticsNetworkData $make(CopyWithData data) => LogisticsNetworkData(
    data.get(#id, or: $value.id),
    data.get(#promises, or: $value.promises),
    data.get(#links, or: $value.links),
    data.get(#owner, or: $value.owner),
    data.get(#locked, or: $value.locked),
  );

  @override
  LogisticsNetworkDataCopyWith<$R2, LogisticsNetworkData, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LogisticsNetworkDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LogisticsSavedDataMapper extends ClassMapperBase<LogisticsSavedData> {
  LogisticsSavedDataMapper._();

  static LogisticsSavedDataMapper? _instance;
  static LogisticsSavedDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LogisticsSavedDataMapper._());
      LogisticsNetworkDataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LogisticsSavedData';

  static List<LogisticsNetworkData> _$logisticsNetworks(LogisticsSavedData v) =>
      v.logisticsNetworks;
  static const Field<LogisticsSavedData, List<LogisticsNetworkData>>
  _f$logisticsNetworks = Field(
    'logisticsNetworks',
    _$logisticsNetworks,
    key: r'logistics_networks',
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<LogisticsSavedData> fields = const {
    #logisticsNetworks: _f$logisticsNetworks,
  };

  static LogisticsSavedData _instantiate(DecodingData data) {
    return LogisticsSavedData(data.dec(_f$logisticsNetworks));
  }

  @override
  final Function instantiate = _instantiate;

  static LogisticsSavedData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LogisticsSavedData>(map);
  }

  static LogisticsSavedData fromJson(String json) {
    return ensureInitialized().decodeJson<LogisticsSavedData>(json);
  }
}

mixin LogisticsSavedDataMappable {
  String toJson() {
    return LogisticsSavedDataMapper.ensureInitialized()
        .encodeJson<LogisticsSavedData>(this as LogisticsSavedData);
  }

  Map<String, dynamic> toMap() {
    return LogisticsSavedDataMapper.ensureInitialized()
        .encodeMap<LogisticsSavedData>(this as LogisticsSavedData);
  }

  LogisticsSavedDataCopyWith<
    LogisticsSavedData,
    LogisticsSavedData,
    LogisticsSavedData
  >
  get copyWith =>
      _LogisticsSavedDataCopyWithImpl<LogisticsSavedData, LogisticsSavedData>(
        this as LogisticsSavedData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LogisticsSavedDataMapper.ensureInitialized().stringifyValue(
      this as LogisticsSavedData,
    );
  }

  @override
  bool operator ==(Object other) {
    return LogisticsSavedDataMapper.ensureInitialized().equalsValue(
      this as LogisticsSavedData,
      other,
    );
  }

  @override
  int get hashCode {
    return LogisticsSavedDataMapper.ensureInitialized().hashValue(
      this as LogisticsSavedData,
    );
  }
}

extension LogisticsSavedDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LogisticsSavedData, $Out> {
  LogisticsSavedDataCopyWith<$R, LogisticsSavedData, $Out>
  get $asLogisticsSavedData => $base.as(
    (v, t, t2) => _LogisticsSavedDataCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LogisticsSavedDataCopyWith<
  $R,
  $In extends LogisticsSavedData,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    LogisticsNetworkData,
    LogisticsNetworkDataCopyWith<$R, LogisticsNetworkData, LogisticsNetworkData>
  >
  get logisticsNetworks;
  $R call({List<LogisticsNetworkData>? logisticsNetworks});
  LogisticsSavedDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LogisticsSavedDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LogisticsSavedData, $Out>
    implements LogisticsSavedDataCopyWith<$R, LogisticsSavedData, $Out> {
  _LogisticsSavedDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LogisticsSavedData> $mapper =
      LogisticsSavedDataMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    LogisticsNetworkData,
    LogisticsNetworkDataCopyWith<$R, LogisticsNetworkData, LogisticsNetworkData>
  >
  get logisticsNetworks => ListCopyWith(
    $value.logisticsNetworks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(logisticsNetworks: v),
  );
  @override
  $R call({List<LogisticsNetworkData>? logisticsNetworks}) => $apply(
    FieldCopyWithData({
      if (logisticsNetworks != null) #logisticsNetworks: logisticsNetworks,
    }),
  );
  @override
  LogisticsSavedData $make(CopyWithData data) => LogisticsSavedData(
    data.get(#logisticsNetworks, or: $value.logisticsNetworks),
  );

  @override
  LogisticsSavedDataCopyWith<$R2, LogisticsSavedData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LogisticsSavedDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

