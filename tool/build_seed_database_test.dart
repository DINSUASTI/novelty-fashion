import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novelty_fashion/data/inventory_repository.dart';
import 'package:novelty_fashion/services/inventory_excel_importer.dart';

void main() {
  sqfliteFfiInit();

  test('genera la base de datos inicial para el APK', () async {
    final directory = await Directory.systemTemp.createTemp('novelty-seed-');
    final databasePath = path.join(directory.path, 'novelty_fashion.db');
    final inventoryBytes = await File('assets/INVENTARIO INICIAL.xlsx')
        .readAsBytes();
    final placeholderBytes = await File('assets/images/product_placeholder.png')
        .readAsBytes();
    final repository = SqliteInventoryRepository(
      openDatabase: (options) =>
          databaseFactoryFfi.openDatabase(databasePath, options: options),
    );

    try {
      final importer = InventoryExcelImporter();
      final plan = importer.createImportPlan(
        rows: importer.parse(inventoryBytes),
        existingItems: const [],
        placeholderBytes: placeholderBytes,
      );
      await repository.saveAll(plan.items);
      final items = await repository.getAll();
      expect(items, hasLength(83));
      expect(items.fold<int>(0, (sum, item) => sum + item.stockValue), 4766000);
      expect(
        items.fold<int>(0, (sum, item) => sum + item.projectedProfit),
        4485000,
      );
      expect(await repository.getImportedFiles(), isEmpty);
      await repository.close();
      await File(databasePath).copy('assets/novelty_fashion.db');
    } finally {
      await repository.close();
      await directory.delete(recursive: true);
    }
  });
}
