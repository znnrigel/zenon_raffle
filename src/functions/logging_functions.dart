import 'dart:io';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

initLogger() {
  Directory logDir = Directory(path.join('.', 'log'));
  if (!logDir.existsSync()) {
    logDir.createSync(recursive: true);
  }

  final logFile = File(
      '${logDir.path}${path.separator}raffle_${DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now())}.log');

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (!filtered(record.message)) {
      print('${record.level.name}: ${record.time}: ${record.message}');
      logFile.writeAsString(
        '${record.level.name}: ${record.time}: ${record.message} '
        '${record.error != null ? record.error.toString() : ''} '
        '${record.stackTrace != null ? record.stackTrace.toString() : ''}${Platform.isWindows ? '\r\n' : '\n'}',
        mode: FileMode.append,
        flush: true,
      );
    }
  });
}

// Add strings here if you don't want to log them
bool filtered(String message) {
  return [
    'Published account-block',
    'Loading argon2',
  ].any((e) => message.contains(e));
}
