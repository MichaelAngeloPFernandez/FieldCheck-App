import 'dart:typed_data';

class FileDownload {
  static Future<void> downloadBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) {
    throw UnsupportedError('File download is not available on this platform');
  }
}
