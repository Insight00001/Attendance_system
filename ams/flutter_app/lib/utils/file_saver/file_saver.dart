/// Platform-aware file saving.
///
/// - Desktop/mobile (dart:io): saves to the Downloads folder, can open it.
/// - Web: triggers a browser download.
///
/// Import THIS file only — never the _io/_web variants directly.
export 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.html) 'file_saver_web.dart';
