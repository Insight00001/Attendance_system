/// Fallback implementation — should never be reached on supported platforms.

/// Saves [bytes] as [filename]. Returns the saved path, or null when the
/// platform handles the download itself (web).
Future<String?> saveReportFile(String filename, List<int> bytes) async {
  throw UnsupportedError('File saving is not supported on this platform');
}

/// Whether [openSavedFile] does anything on this platform.
bool get canOpenSavedFile => false;

/// Opens a previously saved file (best-effort).
void openSavedFile(String path) {}
