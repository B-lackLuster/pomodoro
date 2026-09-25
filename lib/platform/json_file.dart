/// 文件写入的跨平台封装：web 构建绑定空实现（数据导出仅桌面端提供）。
library;

import 'json_file_none.dart'
    if (dart.library.io) 'json_file_io.dart';

Future<void> writeTextFile(String path, String content) =>
    writeTextFileImpl(path, content);
