import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// What a JavaScript promise settled to: a value, or the `name` of the
/// `DOMException` it rejected with.
typedef JsResult<T extends JSAny?> = ({T? value, String? errorName});

/// Waits for [promise] and reports how it settled.
///
/// The rejection is read on the JavaScript side of the boundary, where it
/// is still a JS value. Catching it as a Dart object instead behaves
/// differently under dart2js and dart2wasm, and a camera error that cannot
/// be classified is a camera error nobody can act on.
Future<JsResult<T>> settle<T extends JSAny?>(JSPromise<T> promise) {
  final settled = Completer<JsResult<T>>();
  (promise as JSObject).callMethod(
    'then'.toJS,
    ((JSAny? value) {
      if (!settled.isCompleted) {
        settled.complete((value: value as T?, errorName: null));
      }
    }).toJS,
    ((JSAny? error) {
      if (!settled.isCompleted) {
        settled.complete((value: null, errorName: nameOf(error)));
      }
    }).toJS,
  );
  return settled.future;
}

/// The `name` of a `DOMException`, or an empty string when it has none.
String nameOf(JSAny? error) {
  if (!error.isA<JSObject>()) return '';
  final object = error as JSObject;
  if (!object.has('name')) return '';
  final name = object['name'];
  return name.isA<JSString>() ? (name as JSString).toDart : '';
}
