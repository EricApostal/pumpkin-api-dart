/// The readable end of a component model `future<T>` returned by the host.
///
/// Plugins can't read it yet, it only keeps the handle. This is not a Dart
/// [Future].
final class ComponentFuture<T> {
  /// The handle of the readable end in the component's handle table.
  final int handle;

  const ComponentFuture(this.handle);
}
