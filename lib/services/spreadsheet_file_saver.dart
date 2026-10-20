import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

Future<bool> saveSpreadsheet({
  required String name,
  required Uint8List bytes,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    return true;
  }

  final location = await FileSaver.instance.saveAs(
    name: name,
    bytes: bytes,
    fileExtension: 'xlsx',
    mimeType: MimeType.microsoftExcel,
    initialDirectory:
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '/storage/emulated/0/Download'
        : null,
  );
  return location != null;
}