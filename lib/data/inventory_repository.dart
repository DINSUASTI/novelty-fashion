import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

import '../models/inventory_item.dart';
import 'database_factory.dart';

abstract interface class InventoryRepository {
  Future<List<InventoryItem>> getAll();

  Future<String> getNextSku();

  Future<void> save(InventoryItem item);

  Future<void> saveAll(List<InventoryItem> items);

  Future<void> importFile(
    List<InventoryItem> items,
    String name,
    Uint8List bytes,
  );

  Future<List<ImportedInventoryFile>> getImportedFiles();

  Future<Uint8List> getImportedFileBytes(int id);

  Future<void> clearInventory();

  Future<List<InventoryRotation>> getLowestRotation({
    int days = 30,
    int limit = 5,
  });

  Future<List<InventoryRotation>> getHighestRotation({
    int days = 30,
    int limit = 5,
  });

  Future<void> delete(String id);

  Future<void> close();
}

class ImportedInventoryFile {
  const ImportedInventoryFile({
    required this.id,
    required this.name,
    required this.importedAt,
  });

  final int id;
  final String name;
  final DateTime importedAt;
}

typedef InventoryDatabaseOpener = Future<Database> Function(
  OpenDatabaseOptions options,
);

class SqliteInventoryRepository implements InventoryRepository {
  SqliteInventoryRepository({
    InventoryDatabaseOpener? openDatabase,
    DateTime Function()? now,
  }) : _openDatabase = openDatabase ?? openInventoryDatabase,
       _now = now ?? DateTime.now;

  final InventoryDatabaseOpener _openDatabase;
  final DateTime Function() _now;
  Database? _database;

  Future<Database> get _db async {
    return _database ??= await _openDatabase(
      OpenDatabaseOptions(
        version: 8,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE inventory_items (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              reference TEXT NOT NULL DEFAULT '',
              sku TEXT NOT NULL COLLATE NOCASE UNIQUE,
              size TEXT NOT NULL,
              recommended_sizes TEXT NOT NULL DEFAULT '',
              quantity INTEGER NOT NULL CHECK (quantity >= 0),
              cost INTEGER NOT NULL CHECK (cost >= 0),
              sale_price INTEGER NOT NULL CHECK (sale_price >= 0),
              created_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE product_photos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              inventory_item_id TEXT NOT NULL,
              position INTEGER NOT NULL,
              url TEXT,
              bytes BLOB,
              CHECK (url IS NOT NULL OR bytes IS NOT NULL),
              FOREIGN KEY (inventory_item_id)
                REFERENCES inventory_items (id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE INDEX idx_product_photos_item
            ON product_photos (inventory_item_id, position)
          ''');
          await _createHistorySchema(database);
          await _createImportSchema(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createHistorySchema(database);
            await database.rawInsert(
              '''
                INSERT INTO inventory_quantity_history (
                  inventory_item_id, quantity, recorded_at
                )
                SELECT id, quantity, ? FROM inventory_items
              ''',
              [_now().millisecondsSinceEpoch],
            );
          }
          if (oldVersion < 5) {
            await database.execute(
              "ALTER TABLE inventory_items ADD COLUMN size TEXT NOT NULL DEFAULT 'Talla única'",
            );
            await database.execute(
              'UPDATE inventory_items SET cost = ROUND(cost), sale_price = ROUND(sale_price)',
            );
          }
          if (oldVersion < 6) {
            await database.execute(
              "ALTER TABLE inventory_items ADD COLUMN recommended_sizes TEXT NOT NULL DEFAULT ''",
            );
          }
          if (oldVersion < 3) {
            await _insertRotationDemoSnapshot(database);
          }
          if (oldVersion < 7) {
            await _createImportSchema(database);
          }
          if (oldVersion < 8) {
            final columns = await database.rawQuery(
              'PRAGMA table_info(inventory_items)',
            );
            if (!columns.any((column) => column['name'] == 'reference')) {
              await database.execute(
                "ALTER TABLE inventory_items ADD COLUMN reference TEXT NOT NULL DEFAULT ''",
              );
            }
          }
        },
      ),
    );
  }

  @override
  Future<List<InventoryItem>> getAll() async {
    final database = await _db;
    final itemRows = await database.query(
      'inventory_items',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final photoRows = await database.query(
      'product_photos',
      orderBy: 'inventory_item_id, position',
    );
    final photosByItem = <String, List<ProductPhoto>>{};
    for (final row in photoRows) {
      final itemId = row['inventory_item_id']! as String;
      final photos = photosByItem.putIfAbsent(itemId, () => []);
      final bytes = row['bytes'] as Uint8List?;
      photos.add(
        bytes != null
            ? ProductPhoto.memory(bytes)
            : ProductPhoto.network(row['url']! as String),
      );
    }
    return itemRows
        .map(
          (row) => InventoryItem(
            id: row['id']! as String,
            name: row['name']! as String,
            reference: row['reference']! as String,
            sku: row['sku']! as String,
            size:
                ClothingSize.tryParse(row['size']! as String) ??
                ClothingSize.oneSize,
            recommendedSizes:
                ClothingSize.tryParseRecommendations(
                  row['recommended_sizes']! as String,
                ) ??
                const [],
            quantity: row['quantity']! as int,
            cost: (row['cost']! as num).round(),
            salePrice: (row['sale_price']! as num).round(),
            photos: List.unmodifiable(photosByItem[row['id']] ?? []),
          ),
        )
        .toList();
  }

  @override
  Future<String> getNextSku() async {
    final database = await _db;
    final rows = await database.rawQuery('''
      SELECT MAX(CAST(sku AS INTEGER)) AS max_sku
      FROM inventory_items
      WHERE sku <> '' AND sku NOT GLOB '*[^0-9]*'
    ''');
    return '${((rows.single['max_sku'] as int?) ?? 0) + 1}';
  }

  @override
  Future<void> save(InventoryItem item) async {
    final database = await _db;
    await database.transaction((transaction) => _writeItem(transaction, item));
  }

  @override
  Future<void> saveAll(List<InventoryItem> items) async {
    final database = await _db;
    await database.transaction((transaction) async {
      for (final item in items) {
        await _writeItem(transaction, item);
      }
    });
  }

  @override
  Future<void> importFile(
    List<InventoryItem> items,
    String name,
    Uint8List bytes,
  ) async {
    final database = await _db;
    await database.transaction((transaction) async {
      for (final item in items) {
        await _writeItem(transaction, item);
      }
      await transaction.insert('imported_inventory_files', {
        'name': name,
        'bytes': bytes,
        'imported_at': _now().millisecondsSinceEpoch,
      });
    });
  }

  @override
  Future<List<ImportedInventoryFile>> getImportedFiles() async {
    final database = await _db;
    final rows = await database.query(
      'imported_inventory_files',
      columns: ['id', 'name', 'imported_at'],
      orderBy: 'imported_at DESC, id DESC',
    );
    return rows
        .map(
          (row) => ImportedInventoryFile(
            id: row['id']! as int,
            name: row['name']! as String,
            importedAt: DateTime.fromMillisecondsSinceEpoch(
              row['imported_at']! as int,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<Uint8List> getImportedFileBytes(int id) async {
    final database = await _db;
    final rows = await database.query(
      'imported_inventory_files',
      columns: ['bytes'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Archivo importado no encontrado');
    return rows.single['bytes']! as Uint8List;
  }

  @override
  Future<void> clearInventory() async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('inventory_items');
    });
  }

  @override
  Future<List<InventoryRotation>> getLowestRotation({
    int days = 30,
    int limit = 5,
  }) async {
    final rotations = await _getRotations(days);
    return lowestInventoryRotation(rotations, limit: limit);
  }

  @override
  Future<List<InventoryRotation>> getHighestRotation({
    int days = 30,
    int limit = 5,
  }) async {
    final rotations = await _getRotations(days);
    return highestInventoryRotation(rotations, limit: limit);
  }

  Future<List<InventoryRotation>> _getRotations(int days) async {
    final database = await _db;
    final items = await getAll();
    final cutoff = _now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rotations = <InventoryRotation>[];
    for (final item in items) {
      final rows = await database.query(
        'inventory_quantity_history',
        columns: ['quantity'],
        where: 'inventory_item_id = ? AND recorded_at <= ?',
        whereArgs: [item.id, cutoff],
        orderBy: 'recorded_at DESC, id DESC',
        limit: 1,
      );
      if (rows.isEmpty) continue;
      rotations.add(
        InventoryRotation(
          itemId: item.id,
          name: item.name,
          reference: item.reference,
          sku: item.sku,
          size: item.size,
          pastQuantity: rows.first['quantity']! as int,
          currentQuantity: item.quantity,
        ),
      );
    }
    return rotations;
  }

  @override
  Future<void> delete(String id) async {
    final database = await _db;
    await database.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<void> _writeItem(DatabaseExecutor executor, InventoryItem item) async {
    final timestamp = _now().millisecondsSinceEpoch;
    final existing = await executor.query(
      'inventory_items',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [item.id],
      limit: 1,
    );
    final values = {
      'name': item.name,
      'reference': item.reference,
      'sku': item.sku,
      'size': item.size.label,
      'recommended_sizes': ClothingSize.serializeRecommendations(
        item.recommendedSizes,
      ),
      'quantity': item.quantity,
      'cost': item.cost,
      'sale_price': item.salePrice,
    };
    if (existing.isEmpty) {
      await executor.insert('inventory_items', {
        'id': item.id,
        ...values,
        'created_at': timestamp,
      });
    } else {
      await executor.update(
        'inventory_items',
        values,
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    await executor.delete(
      'product_photos',
      where: 'inventory_item_id = ?',
      whereArgs: [item.id],
    );
    for (var index = 0; index < item.photos.length; index++) {
      final photo = item.photos[index];
      await executor.insert('product_photos', {
        'inventory_item_id': item.id,
        'position': index,
        'url': photo.url,
        'bytes': photo.bytes,
      });
    }
    final lastSnapshots = await executor.query(
      'inventory_quantity_history',
      columns: ['quantity'],
      where: 'inventory_item_id = ?',
      whereArgs: [item.id],
      orderBy: 'recorded_at DESC, id DESC',
      limit: 1,
    );
    if (lastSnapshots.isEmpty ||
        lastSnapshots.first['quantity'] != item.quantity) {
      await executor.insert('inventory_quantity_history', {
        'inventory_item_id': item.id,
        'quantity': item.quantity,
        'recorded_at': timestamp,
      });
    }
  }

  Future<void> _createHistorySchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE inventory_quantity_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_item_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity >= 0),
        recorded_at INTEGER NOT NULL,
        FOREIGN KEY (inventory_item_id)
          REFERENCES inventory_items (id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_inventory_quantity_history_lookup
      ON inventory_quantity_history (inventory_item_id, recorded_at DESC)
    ''');
  }

  Future<void> _createImportSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE imported_inventory_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        bytes BLOB NOT NULL,
        imported_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _insertRotationDemoSnapshot(DatabaseExecutor database) async {
    final recordedAt = _now()
        .subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    final cutoff = _now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await database.rawInsert(
      '''
        INSERT INTO inventory_quantity_history (
          inventory_item_id, quantity, recorded_at
        )
        SELECT id, 8, ?
        FROM inventory_items
        WHERE id = 'seed-2'
          AND NOT EXISTS (
            SELECT 1
            FROM inventory_quantity_history
            WHERE inventory_item_id = 'seed-2'
              AND recorded_at <= ?
          )
      ''',
      [recordedAt, cutoff],
    );
  }
}

final seedInventoryItems = [
  InventoryItem(
    id: 'seed-1',
    name: 'Vestido Aura',
    sku: 'VES-AUR-001',
    size: ClothingSize.m,
    quantity: 12,
    cost: 78000,
    salePrice: 139900,
    photos: const [
      ProductPhoto.network(
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=900',
      ),
    ],
  ),
  InventoryItem(
    id: 'seed-2',
    name: 'Blazer Siena',
    sku: 'BLA-SIE-004',
    size: ClothingSize.s,
    quantity: 4,
    cost: 102000,
    salePrice: 189900,
    photos: const [
      ProductPhoto.network(
        'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?w=900',
      ),
    ],
  ),
  InventoryItem(
    id: 'seed-3',
    name: 'Blusa Lino Marfil',
    sku: 'BLU-LIN-012',
    size: ClothingSize.oneSize,
    quantity: 0,
    cost: 45000,
    salePrice: 89900,
    photos: const [
      ProductPhoto.network(
        'https://images.unsplash.com/photo-1564257577054-92524e8e57fb?w=900',
      ),
    ],
  ),
];
