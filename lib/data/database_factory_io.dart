import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> prepareInventoryDatabase() async {
  if (!Platform.isAndroid) return;
  final databasePath = path.join(
    await sqflite.databaseFactory.getDatabasesPath(),
    'novelty_fashion.db',
  );
  await installBundledDatabaseIfMissing(databasePath);
}

Future<Database> openInventoryDatabase(OpenDatabaseOptions options) async {
  final DatabaseFactory factory;
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    factory = sqflite.databaseFactory;
  } else {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  }
  final databasePath = path.join(
    await factory.getDatabasesPath(),
    'novelty_fashion.db',
  );
  if (Platform.isAndroid) await installBundledDatabaseIfMissing(databasePath);
  return factory.openDatabase(databasePath, options: options);
}

Future<void> installBundledDatabaseIfMissing(String databasePath) async {
  if (await File(databasePath).exists()) return;
  final data = await rootBundle.load('assets/novelty_fashion.db');
  await Directory(path.dirname(databasePath)).create(recursive: true);
  final temporaryPath = '$databasePath.seed';
  await File(temporaryPath).writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  await File(temporaryPath).rename(databasePath);
}
