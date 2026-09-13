import 'dart:js_interop';
import 'dart:js_interop_unsafe';

(Object, StackTrace)? tryUnwrapJsConversionError(
  Object error,
  StackTrace stackTrace,
) {
  try {
    if (error is! JSObject) return null;

    final boxedError = error.getProperty<JSAny?>('error'.toJS);
    if (boxedError == null || boxedError.isUndefinedOrNull) return null;
    if (boxedError is! JSBoxedDartObject) return null;

    final unboxedError = boxedError.toDart;

    var unboxedStack = stackTrace;
    final rawStack = error.getProperty<JSAny?>('stack'.toJS);
    if (rawStack is JSString) {
      unboxedStack = StackTrace.fromString(rawStack.toDart);
    }

    return (unboxedError, unboxedStack);
  } catch (_) {
    return null;
  }
}