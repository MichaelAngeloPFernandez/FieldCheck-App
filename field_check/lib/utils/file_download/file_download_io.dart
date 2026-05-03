import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class FileDownload {
  static Future<void> downloadBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
  }
}
