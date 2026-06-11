/// Web implementation — triggers a browser download via a Blob anchor.
import 'dart:html' as html;
import 'dart:typed_data';

/// Downloads [bytes] as [filename] through the browser.
/// Returns null — the browser decides where the file lands.
Future<String?> saveReportFile(String filename, List<int> bytes) async {
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none'
    ..click();
  html.Url.revokeObjectUrl(url);
  return null;
}

bool get canOpenSavedFile => false;

void openSavedFile(String path) {
  // No-op on web — the browser already handled the download.
}
