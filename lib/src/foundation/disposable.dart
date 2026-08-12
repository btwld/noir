/// Interface for objects that release resources explicitly.
abstract interface class Disposable {
  /// Release resources held by this object.
  void dispose();
}
