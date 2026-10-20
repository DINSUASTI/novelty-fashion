import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novelty_fashion/models/inventory_item.dart';
import 'package:novelty_fashion/services/inventory_excel_importer.dart';

void main() {
  final importer = InventoryExcelImporter();

  test('importa el inventario inicial real y calcula sus totales', () async {
    final rows = importer.parse(
      await File('assets/INVENTARIO INICIAL.xlsx').readAsBytes(),
    );

    expect(rows, hasLength(83));
    expect(rows.every((row) => row.sku.isEmpty), isTrue);
    expect(rows.map((row) => row.reference).toSet(), hasLength(50));
    expect(rows.fold<int>(0, (sum, row) => sum + row.quantity), 83);
    expect(
      rows.fold<int>(0, (sum, row) => sum + row.cost * row.quantity),
      4766000,
    );
    expect(
      rows.fold<int>(
        0,
        (sum, row) => sum + (row.salePrice - row.cost) * row.quantity,
      ),
      4485000,
    );
  });

  test('genera una plantilla de siete columnas sin SKU', () {
    final workbook = Excel.decodeBytes(importer.buildTemplate());
    final sheet = workbook.tables['Ventas']!;

    expect(sheet.maxColumns, 7);
    expect(
      sheet.rows.first.map((cell) => cell?.value.toString()),
      InventoryExcelImporter.templateHeaders,
    );
    expect(sheet.rows, hasLength(3));
  });

  test('incluye ejemplos de talla única y talla S recomendada', () {
    final rows = importer.parse(importer.buildTemplate());

    expect(rows, hasLength(2));
    expect(rows.every((row) => row.sku.isEmpty), isTrue);
    expect(rows.first.reference, 'REF-001');
    expect(rows.first.size, ClothingSize.oneSize);
    expect(rows.first.recommendedSizes, ClothingSize.values);
    expect(rows.last.size, ClothingSize.s);
    expect(rows.last.recommendedSizes, [ClothingSize.s]);
  });

  test('asigna SKU internos consecutivos al importar sin esa columna', () {
    final existing = InventoryItem(
      id: 'existing',
      name: 'Existente',
      sku: '83',
      size: ClothingSize.oneSize,
      quantity: 1,
      cost: 10,
      salePrice: 20,
      photos: const [],
    );
    final plan = importer.createImportPlan(
      rows: importer.parse(importer.buildTemplate()),
      existingItems: [existing],
      placeholderBytes: Uint8List.fromList([1, 2]),
      idSeed: 100,
    );

    expect(plan.items.map((item) => item.sku), ['84', '85']);
    expect(plan.createdCount, 2);
  });

  test('importa datos base y la plataforma calcula los valores derivados', () {
    final bytes = _buildWorkbook(
      headers: InventoryExcelImporter.headers,
      row: [
        TextCellValue('Vestido Horizonte'),
        TextCellValue('VES-HOR-001'),
        TextCellValue('M'),
        TextCellValue('XS;S;M'),
        IntCellValue(6),
        IntCellValue(40000),
        IntCellValue(110000),
      ],
    );

    final row = importer.parse(bytes).single;
    final item = InventoryItem(
      id: 'test',
      name: row.name,
      sku: row.sku,
      size: row.size,
      recommendedSizes: row.recommendedSizes,
      quantity: row.quantity,
      cost: row.cost,
      salePrice: row.salePrice,
      photos: const [ProductPhoto.network('https://example.com/foto.jpg')],
    );

    expect(item.stockValue, 240000);
    expect(item.size, ClothingSize.m);
    expect(item.recommendedSizes, [
      ClothingSize.xs,
      ClothingSize.s,
      ClothingSize.m,
    ]);
    expect(item.profit, 70000);
    expect(item.projectedProfit, 420000);
  });

  test('lee la hoja Ventas con referencia y filas formateadas vacías', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Ventas'];
    workbook.delete('Sheet1');
    sheet.appendRow(
      InventoryExcelImporter.initialInventoryHeaders
          .map(TextCellValue.new)
          .toList(),
    );
    sheet.appendRow([
      TextCellValue('Chaqueta mangas bombachas Azul'),
      TextCellValue('REF-001'),
      IntCellValue(1),
      TextCellValue('Talla única  '),
      TextCellValue('S;M;L'),
      IntCellValue(1),
      IntCellValue(98000),
      IntCellValue(180000),
    ]);
    sheet.appendRow([]);

    final rows = importer.parse(Uint8List.fromList(workbook.encode()!));
    expect(rows, hasLength(1));
    expect(rows.single.reference, 'REF-001');
    expect(rows.single.sku, '1');
    expect(rows.single.size, ClothingSize.oneSize);
    expect(rows.single.recommendedSizes, [
      ClothingSize.s,
      ClothingSize.m,
      ClothingSize.l,
    ]);
    expect(rows.single.salePrice - rows.single.cost, 82000);
  });

  test('importa varias tallas recomendadas separadas por punto y coma', () {
    final bytes = _buildWorkbook(
      headers: InventoryExcelImporter.headers,
      row: [
        TextCellValue('Vestido Horizonte'),
        TextCellValue('VES-HOR-001'),
        TextCellValue('M'),
        TextCellValue('XS; S; XL'),
        IntCellValue(6),
        IntCellValue(40000),
        IntCellValue(110000),
      ],
    );

    expect(importer.parse(bytes).single.recommendedSizes, [
      ClothingSize.xs,
      ClothingSize.s,
      ClothingSize.xl,
    ]);
  });

  test('conserva fotos existentes y asigna placeholder a productos nuevos', () {
    final existingPhotos = [
      ProductPhoto.memory(Uint8List.fromList([9, 8, 7])),
    ];
    final existingItem = InventoryItem(
      id: 'existing-id',
      name: 'Blusa Actual',
      sku: 'BLU-001',
      size: ClothingSize.s,
      quantity: 2,
      cost: 30000,
      salePrice: 60000,
      photos: existingPhotos,
    );
    final placeholderBytes = Uint8List.fromList([1, 2, 3, 4]);

    final plan = importer.createImportPlan(
      rows: const [
        ImportedInventoryRow(
          name: 'Blusa Actualizada',
          sku: 'BLU-001',
          size: ClothingSize.l,
          recommendedSizes: [ClothingSize.s, ClothingSize.m],
          quantity: 5,
          cost: 32000,
          salePrice: 65000,
        ),
        ImportedInventoryRow(
          name: 'Falda Nueva',
          sku: 'FAL-001',
          size: ClothingSize.xs,
          recommendedSizes: [ClothingSize.xs, ClothingSize.xl],
          quantity: 3,
          cost: 40000,
          salePrice: 80000,
        ),
      ],
      existingItems: [existingItem],
      placeholderBytes: placeholderBytes,
      idSeed: 100,
    );

    final updated = plan.items.first;
    final created = plan.items.last;
    expect(plan.createdCount, 1);
    expect(plan.updatedCount, 1);
    expect(updated.id, existingItem.id);
    expect(updated.size, ClothingSize.l);
    expect(updated.recommendedSizes, [ClothingSize.s, ClothingSize.m]);
    expect(identical(updated.photos, existingPhotos), isTrue);
    expect(updated.photos.single.bytes, [9, 8, 7]);
    expect(created.id, 'import-100-1');
    expect(created.recommendedSizes, [ClothingSize.xs, ClothingSize.xl]);
    expect(created.photos.single.bytes, placeholderBytes);
    expect(identical(created.photos.single.bytes, placeholderBytes), isFalse);
  });

  test('rechaza columnas calculadas o adicionales', () {
    final bytes = _buildWorkbook(
      headers: [...InventoryExcelImporter.headers, 'Ganancia proyectada'],
      row: [
        TextCellValue('Producto'),
        TextCellValue('SKU-001'),
        TextCellValue('XL'),
        IntCellValue(1),
        IntCellValue(10),
        IntCellValue(20),
        IntCellValue(10),
      ],
    );

    expect(
      () => importer.parse(bytes),
      throwsA(
        isA<InventoryImportException>().having(
          (error) => error.message,
          'message',
          contains('7 columnas'),
        ),
      ),
    );
  });

  test('rechaza tallas no permitidas y valores monetarios decimales', () {
    final invalidSize = _buildWorkbook(
      headers: InventoryExcelImporter.headers,
      row: [
        TextCellValue('Producto'),
        TextCellValue('SKU-001'),
        TextCellValue('XXL'),
        TextCellValue(''),
        IntCellValue(1),
        IntCellValue(10),
        IntCellValue(20),
      ],
    );
    final decimalCost = _buildWorkbook(
      headers: InventoryExcelImporter.headers,
      row: [
        TextCellValue('Producto'),
        TextCellValue('SKU-002'),
        TextCellValue('Talla única'),
        TextCellValue(''),
        IntCellValue(1),
        DoubleCellValue(10.5),
        IntCellValue(20),
      ],
    );

    expect(
      () => importer.parse(invalidSize),
      throwsA(
        isA<InventoryImportException>().having(
          (error) => error.message,
          'message',
          contains('XS, S, M, L, XL o Talla única'),
        ),
      ),
    );
    expect(
      () => importer.parse(decimalCost),
      throwsA(
        isA<InventoryImportException>().having(
          (error) => error.message,
          'message',
          contains('debe ser un número entero'),
        ),
      ),
    );
  });

  test('rechaza tallas recomendadas no permitidas', () {
    final bytes = _buildWorkbook(
      headers: InventoryExcelImporter.headers,
      row: [
        TextCellValue('Producto'),
        TextCellValue('SKU-003'),
        TextCellValue('M'),
        TextCellValue('S;XXL'),
        IntCellValue(1),
        IntCellValue(10),
        IntCellValue(20),
      ],
    );

    expect(
      () => importer.parse(bytes),
      throwsA(
        isA<InventoryImportException>().having(
          (error) => error.message,
          'message',
          contains('separadas por punto y coma'),
        ),
      ),
    );
  });
}

Uint8List _buildWorkbook({
  required List<String> headers,
  required List<CellValue> row,
}) {
  final workbook = Excel.createExcel();
  final sheet = workbook['Inventario'];
  workbook.delete('Sheet1');
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  sheet.appendRow(row);
  return Uint8List.fromList(workbook.encode()!);
}
