import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> prepareInventoryDatabase() async {}

Future<Database> openInventoryDatabase(OpenDatabaseOptions options) {
  return databaseFactoryFfiWeb.openDatabase(
    'novelty_fashion.db',
    options: options,
  );
}
