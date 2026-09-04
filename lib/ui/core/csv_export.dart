import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

String csvCell(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toString();
  final text = '$value';
  if (!text.contains(RegExp(r'[,"\r\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

Future<bool> saveCsvFile({
  required String fileName,
  required String content,
}) async {
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save CSV file',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    return path != null;
  } catch (_) {
    return false;
  }
}
