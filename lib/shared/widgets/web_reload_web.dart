import 'dart:js_interop';

@JS('location.reload')
external void _jsReload();

void webReload() {
  _jsReload();
}
