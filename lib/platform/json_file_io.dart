import 'dart:io';

Future<void> writeTextFileImpl(String path, String content) async {
  await File(path).writeAsString(content, flush: true);
}
