/// Web Serial printer service – conditional export.
///
/// On web, exports the real JS-interop implementation.
/// On native platforms, exports a no-op stub so the rest of the
/// app (and tests) can compile without `dart:js_interop`.
library;

export 'web_serial_printer_service_stub.dart'
    if (dart.library.js_interop) 'web_serial_printer_service_web.dart';
