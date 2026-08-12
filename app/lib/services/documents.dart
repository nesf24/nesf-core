import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';

/// Fetches an issued PDF from the API and hands it to the platform — opened in a
/// viewer, or passed to the native share sheet so staff can WhatsApp or email it.
class DocumentService {
  DocumentService(this.api);
  final Api api;

  /// Downloads [path] and opens it. On web the bytes are pushed through the
  /// share/download path instead, since there is no local filesystem.
  Future<void> openPdf(String path, String filename, {Map<String, dynamic>? query}) async {
    final bytes = await api.download(path, query);
    final file = await _write(bytes, filename);
    if (file == null) return;
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      // No PDF viewer installed is common on cheap Android handsets; falling
      // back to the share sheet lets the user pick an app that can read it.
      await sharePdfBytes(bytes, filename);
    }
  }

  Future<void> sharePdf(String path, String filename, {Map<String, dynamic>? query, String? text}) async {
    final bytes = await api.download(path, query);
    await sharePdfBytes(bytes, filename, text: text);
  }

  Future<void> sharePdfBytes(Uint8List bytes, String filename, {String? text}) async {
    await SharePlus.instance.share(ShareParams(
      text: text,
      files: [XFile.fromData(bytes, name: filename, mimeType: 'application/pdf')],
      fileNameOverrides: [filename],
    ));
  }

  Future<File?> _write(Uint8List bytes, String filename) async {
    if (kIsWeb) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
