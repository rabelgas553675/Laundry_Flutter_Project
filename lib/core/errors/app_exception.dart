/// A small, user-facing exception for non-Firebase failures (validation,
/// file checks). Lets UI code show `e.message` directly instead of a
/// raw stack trace or a generic "something went wrong".
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}