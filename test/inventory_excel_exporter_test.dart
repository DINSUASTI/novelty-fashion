import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novelty_fashion/data/inventory_repository.dart';
import 'package:novelty_fashion/models/inventory_item.dart';
import 'package:novelty_fashion/services/inventory_excel_exporter.dart';

void main() {
  test('genera un Excel con detalle y consolidados', () {
    final items = [
      InventoryItem(
        id: 'seed-1',
        name: 'Vestido Aura',
        reference: 'REF-001',
        sku: 'VES-AUR-001',
        size: ClothingSize.m,
        recommendedSizes: [ClothingSize.xs, ClothingSize.m],
        quantity: 12,
        cost: 78000,
        salePrice: 139900,
        photos: seedInventoryItems.first.photos,
      ),
      ...seedInventoryItems.skip(1),
    ];
    final bytes = InventoryExcelExporter().build(items);
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables['Inventario']!;
    final totalsRow = sheet.rows.singleWhere(
      (row) => row.any(
        (cell) =>
            cell?.value is TextCellValue && cell!.value.toString() == 'TOTALES',
      ),
    );

    expect(sheet.maxColumns, 11);
    expect(
      sheet.rows.first.map((cell) => cell?.value.toString()),
      isNot(contains('SKU')),
    );
    expect(sheet.rows[1][1]!.value.toString(), 'REF-001');
    expect(sheet.rows[1][2]!.value.toString(), 'M');
    expect(sheet.rows[1][3]!.value.toString(), 'XS;M');
    expect(_numberValue(totalsRow[4]!.value), 16);
    expect(_numberValue(totalsRow[6]!.value), 1344000);
    expect(_numberValue(totalsRow[9]!.value), 1094400);
    expect(totalsRow[6]!.value, isA<IntCellValue>());
  });
}

num _numberValue(CellValue? value) => switch (value) {
  IntCellValue() => value.value,
  DoubleCellValue() => value.value,
  _ => throw StateError('La celda no contiene un número'),
};
