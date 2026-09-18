import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Unwraps a Dart error that was boxed inside a JS error object.
///
/// Returns the original Dart error and its stack trace, or `null` if [error]
/// is not a boxed Dart error.
(Object, StackTrace)? tryUnwrapJsConversionError(
  Object error,
  StackTrace stackTrace,
) {
  try {
    // The incoming value is a plain Dart `Object`. Detecting a raw JS object
    // requires a runtime check between a Dart type and a JS interop type, and
    // `isA` isn't available on `Object`, so this one check is intentional.
    // ignore: invalid_runtime_check_with_js_interop_types
    if (error is! JSObject) return null;

    final boxedError = error.getProperty<JSAny?>('error'.toJS);
    if (boxedError.isUndefinedOrNull) return null;
    if (!boxedError.isA<JSBoxedDartObject>()) return null;

    // dartify() unwraps a JSBoxedDartObject back into the original Dart object.
    final unboxedError = boxedError.dartify();
    if (unboxedError == null) return null;

    var unboxedStack = stackTrace;
    final rawStack = error.getProperty<JSAny?>('stack'.toJS);
    if (rawStack.isA<JSString>()) {
      final stackString = rawStack.dartify();
      if (stackString is String) {
        unboxedStack = StackTrace.fromString(stackString);
      }
    }

    return (unboxedError, unboxedStack);
  } catch (_) {
    return null;
  }
}