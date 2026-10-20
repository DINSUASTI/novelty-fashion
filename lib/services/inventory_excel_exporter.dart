import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/inventory_item.dart';
import 'spreadsheet_file_saver.dart';

class InventoryExcelExporter {
  Future<bool> export(List<InventoryItem> items) async {
    final bytes = build(items);
    final now = DateTime.now();
    final date = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}';
    return saveSpreadsheet(
      name: 'inventario_novelty_fashion_$date',
      bytes: bytes,
    );
  }

  Uint8List build(List<InventoryItem> items) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Inventario'];
    workbook.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Producto'),
      TextCellValue('Referencia'),
      TextCellValue('Talla'),
      TextCellValue('Talla recomendada'),
      TextCellValue('Cantidad'),
      TextCellValue('Costo unitario'),
      TextCellValue('Inversión total'),
      TextCellValue('Precio de venta'),
      TextCellValue('Ganancia unitaria'),
      TextCellValue('Ganancia proyectada'),
      TextCellValue('Número de fotos'),
    ]);
    for (final item in items) {
      sheet.appendRow([
        TextCellValue(item.name),
        TextCellValue(item.reference),
        TextCellValue(item.size.label),
        TextCellValue(
          ClothingSize.serializeRecommendations(item.recommendedSizes),
        ),
        IntCellValue(item.quantity),
        IntCellValue(item.cost),
        IntCellValue(item.stockValue),
        IntCellValue(item.salePrice),
        IntCellValue(item.profit),
        IntCellValue(item.projectedProfit),
        IntCellValue(item.photos.length),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTALES'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(items.fold(0, (total, item) => total + item.quantity)),
      TextCellValue(''),
      IntCellValue(items.fold(0, (total, item) => total + item.stockValue)),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(
        items.fold(0, (total, item) => total + item.projectedProfit),
      ),
      TextCellValue(''),
    ]);
    for (var column = 0; column < 11; column++) {
      sheet.setColumnAutoFit(column);
    }
    final encoded = workbook.encode();
    if (encoded == null) throw StateError('No fue posible generar el archivo');
    return Uint8List.fromList(encoded);
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
