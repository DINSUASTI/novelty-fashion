import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novelty_fashion/data/database_factory_io.dart';
import 'package:novelty_fashion/data/inventory_repository.dart';
import 'package:novelty_fashion/models/inventory_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('SQLite guarda, recupera y elimina productos con sus fotos', () async {
    final repository = SqliteInventoryRepository(
      openDatabase: (options) => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: options,
      ),
    );

    final initialItems = await repository.getAll();
    expect(initialItems, isEmpty);
    final rotations = await repository.getLowestRotation(limit: 200);
    expect(rotations, isEmpty);

    final item = InventoryItem(
      id: 'local-1',
      name: 'Falda Prisma',
      reference: 'REF-001',
      sku: 'FAL-PRI-001',
      size: ClothingSize.xl,
      recommendedSizes: [ClothingSize.s, ClothingSize.xl],
      quantity: 6,
      cost: 50000,
      salePrice: 95000,
      photos: [
        ProductPhoto.memory(Uint8List.fromList([1, 2, 3])),
      ],
    );
    await repository.save(item);

    final saved = (await repository.getAll()).singleWhere(
      (candidate) => candidate.id == item.id,
    );
    expect(saved.sku, 'FAL-PRI-001');
    expect(saved.reference, 'REF-001');
    expect(saved.size, ClothingSize.xl);
    expect(saved.recommendedSizes, [ClothingSize.s, ClothingSize.xl]);
    expect(saved.projectedProfit, 270000);
    expect(saved.photos.single.bytes, [1, 2, 3]);
    expect((await repository.getAll()).map((candidate) => candidate.name), [
      'Falda Prisma',
    ]);

    await repository.delete(item.id);
    expect(
      (await repository.getAll()).where((candidate) => candidate.id == item.id),
      isEmpty,
    );
    await repository.close();
  });

  test('calcula el siguiente SKU numérico desde la base de datos', () async {
    final repository = SqliteInventoryRepository(
      openDatabase: (options) => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: options,
      ),
    );
    try {
      expect(await repository.getNextSku(), '1');
      for (final sku in ['9', '83', 'SKU-500', '007']) {
        await repository.save(
          InventoryItem(
            id: sku,
            name: 'Producto $sku',
            sku: sku,
            size: ClothingSize.oneSize,
            quantity: 1,
            cost: 10,
            salePrice: 20,
            photos: const [],
          ),
        );
      }
      expect(await repository.getNextSku(), '84');
      await repository.delete('83');
      expect(await repository.getNextSku(), '10');
    } finally {
      await repository.close();
    }
  });

  test(
    'el SQLite incluido ya tiene datos y no reemplaza cambios locales',
    () async {
      final directory = await Directory.systemTemp.createTemp('bundled-db-');
      final databasePath = path.join(directory.path, 'novelty_fashion.db');
      SqliteInventoryRepository openRepository() => SqliteInventoryRepository(
        openDatabase: (options) =>
            databaseFactoryFfi.openDatabase(databasePath, options: options),
      );
      try {
        await installBundledDatabaseIfMissing(databasePath);
        final repository = openRepository();
        final items = await repository.getAll();
        expect(items, hasLength(83));
        expect(
          items.fold<int>(0, (sum, item) => sum + item.stockValue),
          4766000,
        );
        expect(
          items.fold<int>(0, (sum, item) => sum + item.projectedProfit),
          4485000,
        );
        expect(await repository.getNextSku(), '84');
        expect(await repository.getImportedFiles(), isEmpty);
        await repository.delete(items.first.id);
        await repository.close();

        final bytesBeforeUpdate = await File(databasePath).readAsBytes();
        await installBundledDatabaseIfMissing(databasePath);
        expect(await File(databasePath).readAsBytes(), bytesBeforeUpdate);
        final reopened = openRepository();
        expect(await reopened.getAll(), hasLength(82));
        await reopened.clearInventory();
        await reopened.close();

        await installBundledDatabaseIfMissing(databasePath);
        final cleared = openRepository();
        expect(await cleared.getAll(), isEmpty);
        await cleared.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('conserva productos y fotos al reabrir la base existente', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventory-update-',
    );
    final databasePath = path.join(directory.path, 'novelty_fashion.db');
    SqliteInventoryRepository createRepository() => SqliteInventoryRepository(
      openDatabase: (options) =>
          databaseFactoryFfi.openDatabase(databasePath, options: options),
    );

    try {
      final original = createRepository();
      await original.save(
        InventoryItem(
          id: 'persistent-1',
          name: 'Falda Prisma',
          sku: 'FAL-PRI-001',
          size: ClothingSize.xl,
          quantity: 6,
          cost: 50000,
          salePrice: 95000,
          photos: [
            ProductPhoto.memory(Uint8List.fromList([1, 2, 3])),
          ],
        ),
      );
      await original.close();

      final updated = createRepository();
      final items = await updated.getAll();
      expect(items, hasLength(1));
      expect(items.single.id, 'persistent-1');
      expect(items.single.quantity, 6);
      expect(items.single.photos.single.bytes, [1, 2, 3]);
      await updated.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'conserva los Excel originales al vaciar el inventario y reabrir',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inventory-archive-',
      );
      final databasePath = path.join(directory.path, 'novelty_fashion.db');
      SqliteInventoryRepository openRepository() => SqliteInventoryRepository(
        openDatabase: (options) =>
            databaseFactoryFfi.openDatabase(databasePath, options: options),
      );

      try {
        final repository = openRepository();
        final bytes = Uint8List.fromList([4, 5, 6]);
        await repository.importFile(
          [
            InventoryItem(
              id: 'one',
              name: 'Vestido',
              sku: 'VES-1',
              size: ClothingSize.m,
              quantity: 2,
              cost: 10,
              salePrice: 20,
              photos: [
                ProductPhoto.memory(Uint8List.fromList([1, 2])),
              ],
            ),
          ],
          'original.xlsx',
          bytes,
        );
        await repository.clearInventory();
        expect(await repository.getAll(), isEmpty);
        await repository.close();

        final reopened = openRepository();
        final files = await reopened.getImportedFiles();
        expect(files.single.name, 'original.xlsx');
        expect(await reopened.getImportedFileBytes(files.single.id), bytes);
        expect(await reopened.getAll(), isEmpty);
        await reopened.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('migra la base anterior sin eliminar productos', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventory-migration-',
    );
    final databasePath = path.join(directory.path, 'novelty_fashion.db');
    try {
      final original = SqliteInventoryRepository(
        openDatabase: (options) =>
            databaseFactoryFfi.openDatabase(databasePath, options: options),
      );
      await original.save(
        InventoryItem(
          id: 'existing',
          name: 'Blusa',
          sku: 'BLU-1',
          size: ClothingSize.s,
          quantity: 3,
          cost: 10,
          salePrice: 20,
          photos: const [],
        ),
      );
      await original.close();
      final previousVersion = await databaseFactoryFfi.openDatabase(
        databasePath,
      );
      await previousVersion.execute('DROP TABLE imported_inventory_files');
      await previousVersion.execute(
        'ALTER TABLE inventory_items DROP COLUMN reference',
      );
      await previousVersion.execute('PRAGMA user_version = 6');
      await previousVersion.close();

      final migrated = SqliteInventoryRepository(
        openDatabase: (options) =>
            databaseFactoryFfi.openDatabase(databasePath, options: options),
      );
      expect((await migrated.getAll()).single.id, 'existing');
      expect((await migrated.getAll()).single.reference, isEmpty);
      expect(await migrated.getImportedFiles(), isEmpty);
      await migrated.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('obtiene el top 3 de menor rotación de los últimos 30 días', () async {
    var currentTime = DateTime.utc(2026, 1, 1);
    final repository = SqliteInventoryRepository(
      openDatabase: (options) => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: options,
      ),
      now: () => currentTime,
    );
    final blazer = InventoryItem(
      id: 'blazer',
      name: 'Blazer Siena',
      sku: 'BLA-SIE-004',
      size: ClothingSize.s,
      quantity: 4,
      cost: 102000,
      salePrice: 189900,
      photos: const [],
    );
    final dress = InventoryItem(
      id: 'dress',
      name: 'Vestido Aura',
      sku: 'VES-AUR-001',
      size: ClothingSize.m,
      quantity: 12,
      cost: 78000,
      salePrice: 139900,
      photos: const [],
    );
    await repository.saveAll([blazer, dress]);
    currentTime = currentTime.add(const Duration(days: 31));

    await repository.save(_withQuantity(blazer, 3));
    await repository.save(_withQuantity(dress, 6));

    final rotations = await repository.getLowestRotation(limit: 200);
    final blazerRotation = rotations.singleWhere(
      (rotation) => rotation.name == 'Blazer Siena',
    );
    final dressRotation = rotations.singleWhere(
      (rotation) => rotation.name == 'Vestido Aura',
    );
    expect(blazerRotation.pastQuantity, 4);
    expect(blazerRotation.currentQuantity, 3);
    expect(blazerRotation.rotationPercentage, 25);
    expect(dressRotation.pastQuantity, 12);
    expect(dressRotation.currentQuantity, 6);
    expect(dressRotation.rotationPercentage, 50);
    final highestRotations = await repository.getHighestRotation();
    expect(highestRotations, hasLength(2));
    expect(
      highestRotations.first.rotationPercentage,
      greaterThanOrEqualTo(highestRotations.last.rotationPercentage),
    );
    await repository.close();
  });
}

InventoryItem _withQuantity(InventoryItem item, int quantity) {
  return InventoryItem(
    id: item.id,
    name: item.name,
    sku: item.sku,
    size: item.size,
    quantity: quantity,
    cost: item.cost,
    salePrice: item.salePrice,
    photos: item.photos,
  );
}
