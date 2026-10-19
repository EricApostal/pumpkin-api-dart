/// `DisplaySource` / `DisplayTarget` (Create's display link API) for other modules. The
/// implementations and the registries live in the redstone module; this is the API path.
///
/// ```dart
/// final display = ctx.services.require<RedstoneDisplayApi>();
/// display.registerSource(MySource(), ['create:my_block']);
/// ```
library;

export '../redstone.dart'
    show
        DisplayEnv,
        DisplayLinkContext,
        DisplaySource,
        DisplayTarget,
        DisplayTargetStats,
        FlapControllerView,
        FlapTarget,
        GaugeEntryView,
        TrainPredictionView;
