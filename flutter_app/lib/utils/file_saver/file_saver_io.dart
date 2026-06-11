/// Desktop / mobile implementation — saves to the Downloads folder.
import 'dart:io';

/// Saves [bytes] as [filename] in Downloads (or temp dir as fallback).
/// Returns the full file path.
Future<String?> saveReportFile(String filename, List<int> bytes) async {
  Directory dir = Directory.systemTemp;
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null) {
    final downloads = Directory('$home${Platform.pathSeparator}Downloads');
    if (downloads.existsSync()) dir = downloads;
  }
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

bool get canOpenSavedFile =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Opens the file with the system default app (best-effort).
void openSavedFile(String path) {
  try {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    }
  } catch (_) {
    // File is saved either way; opening is best-effort.
  }
}
