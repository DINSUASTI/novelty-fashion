import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/inventory_item.dart';
import 'spreadsheet_file_saver.dart';

class ImportedInventoryRow {
  const ImportedInventoryRow({
    required this.name,
    this.reference = '',
    required this.sku,
    required this.size,
    this.recommendedSizes = const [],
    required this.quantity,
    required this.cost,
    required this.salePrice,
  });

  final String name;
  final String reference;
  final String sku;
  final ClothingSize size;
  final List<ClothingSize> recommendedSizes;
  final int quantity;
  final int cost;
  final int salePrice;
}

class InventoryImportException implements Exception {
  const InventoryImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InventoryImportPlan {
  const InventoryImportPlan({
    required this.items,
    required this.createdCount,
    required this.updatedCount,
  });

  final List<InventoryItem> items;
  final int createdCount;
  final int updatedCount;
}

enum _InventorySheetFormat { initial, template, legacy }

class InventoryExcelImporter {
  static const initialInventoryHeaders = [
    'PRODUCTO',
    'REFERENCIA',
    'SKU',
    'TALLA',
    'TALLA RECOMENDADA',
    'CANTIDAD',
    'COSTO',
    'VENTA',
  ];

  static const templateHeaders = [
    'PRODUCTO',
    'REFERENCIA',
    'TALLA',
    'TALLA RECOMENDADA',
    'CANTIDAD',
    'COSTO',
    'VENTA',
  ];

  static const headers = [
    'Producto',
    'SKU',
    'Talla',
    'Talla recomendada',
    'Cantidad',
    'Costo unitario',
    'Precio de venta',
  ];

  Future<bool> downloadTemplate() async {
    return saveSpreadsheet(
      name: 'plantilla_importacion_inventario',
      bytes: buildTemplate(),
    );
  }

  Uint8List buildTemplate() {
    final workbook = Excel.createExcel();
    final sheet = workbook['Ventas'];
    workbook.delete('Sheet1');
    sheet.appendRow(templateHeaders.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue('Producto de ejemplo - talla única'),
      TextCellValue('REF-001'),
      TextCellValue(ClothingSize.oneSize.label),
      TextCellValue(ClothingSize.serializeRecommendations(ClothingSize.values)),
      IntCellValue(1),
      IntCellValue(0),
      IntCellValue(0),
    ]);
    sheet.appendRow([
      TextCellValue('Producto de ejemplo - talla S'),
      TextCellValue('REF-002'),
      TextCellValue(ClothingSize.s.label),
      TextCellValue(ClothingSize.s.label),
      IntCellValue(1),
      IntCellValue(0),
      IntCellValue(0),
    ]);
    for (var column = 0; column < templateHeaders.length; column++) {
      sheet.setColumnAutoFit(column);
    }
    final encoded = workbook.encode();
    if (encoded == null) {
      throw StateError('No fue posible generar la plantilla');
    }
    return Uint8List.fromList(encoded);
  }

  InventoryImportPlan createImportPlan({
    required List<ImportedInventoryRow> rows,
    required List<InventoryItem> existingItems,
    required Uint8List placeholderBytes,
    int? idSeed,
  }) {
    final existingBySku = {
      for (final item in existingItems) item.sku.toLowerCase(): item,
    };
    var highestSku =
        [
              ...existingItems.map((item) => item.sku),
              ...rows.map((row) => row.sku),
            ]
            .map(int.tryParse)
            .whereType<int>()
            .fold<int>(0, (highest, sku) => sku > highest ? sku : highest);
    var createdCount = 0;
    var updatedCount = 0;
    final seed = idSeed ?? DateTime.now().microsecondsSinceEpoch;
    final items = <InventoryItem>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final existing = row.sku.isEmpty
          ? null
          : existingBySku[row.sku.toLowerCase()];
      final sku = row.sku.isEmpty ? '${++highestSku}' : row.sku;
      if (existing == null) {
        createdCount++;
      } else {
        updatedCount++;
      }
      items.add(
        InventoryItem(
          id: existing?.id ?? 'import-$seed-$index',
          name: row.name,
          reference: row.reference,
          sku: sku,
          size: row.size,
          recommendedSizes: row.recommendedSizes,
          quantity: row.quantity,
          cost: row.cost,
          salePrice: row.salePrice,
          photos:
              existing?.photos ??
              [ProductPhoto.memory(Uint8List.fromList(placeholderBytes))],
        ),
      );
    }
    return InventoryImportPlan(
      items: List.unmodifiable(items),
      createdCount: createdCount,
      updatedCount: updatedCount,
    );
  }

  List<ImportedInventoryRow> parse(Uint8List bytes) {
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const InventoryImportException('El archivo no es un Excel válido.');
    }
    final sheet =
        workbook.tables['Inventario'] ??
        (workbook.tables.isEmpty ? null : workbook.tables.values.first);
    if (sheet == null || sheet.rows.isEmpty) {
      throw const InventoryImportException(
        'El archivo no contiene una hoja de inventario.',
      );
    }
    final format = _validateHeaders(sheet.rows.first);

    final importedRows = <ImportedInventoryRow>[];
    final seenSkus = <String>{};
    for (var index = 1; index < sheet.rows.length; index++) {
      final cells = sheet.rows[index];
      final rowNumber = index + 1;
      final name = _textAt(cells, 0);
      if (name.isEmpty) continue;
      if (name.toUpperCase() == 'TOTALES') continue;
      final offset = format == _InventorySheetFormat.initial ? 1 : 0;
      final reference = format == _InventorySheetFormat.legacy
          ? ''
          : _textAt(cells, 1);
      if (format != _InventorySheetFormat.legacy && reference.isEmpty) {
        throw InventoryImportException(
          'Fila $rowNumber: la referencia es obligatoria.',
        );
      }
      final sku = format == _InventorySheetFormat.template
          ? ''
          : _textAt(cells, 1 + offset).toUpperCase();
      if (format != _InventorySheetFormat.template && sku.isEmpty) {
        throw InventoryImportException(
          'Fila $rowNumber: falta un identificador interno en el archivo antiguo.',
        );
      }
      if (sku.isNotEmpty && !seenSkus.add(sku.toLowerCase())) {
        throw InventoryImportException(
          'Fila $rowNumber: hay un identificador interno repetido en el archivo.',
        );
      }
      final sizeText = _textAt(cells, 2 + offset);
      final size = ClothingSize.tryParse(sizeText);
      if (size == null) {
        throw InventoryImportException(
          'Fila $rowNumber: la talla debe ser XS, S, M, L, XL o Talla única.',
        );
      }
      final recommendedSizesText = _textAt(cells, 3 + offset);
      final recommendedSizes = ClothingSize.tryParseRecommendations(
        recommendedSizesText,
      );
      if (recommendedSizes == null) {
        throw InventoryImportException(
          'Fila $rowNumber: las tallas recomendadas deben ser XS, S, M, L, XL o Talla única, separadas por punto y coma (;).',
        );
      }
      final quantity = _integerAt(cells, 4 + offset, rowNumber, 'Cantidad');
      final cost = _integerAt(cells, 5 + offset, rowNumber, 'Costo unitario');
      final salePrice = _integerAt(
        cells,
        6 + offset,
        rowNumber,
        'Precio de venta',
      );
      if (cost < 0 || salePrice < 0) {
        throw InventoryImportException(
          'Fila $rowNumber: costo y precio deben ser mayores o iguales a cero.',
        );
      }
      if (quantity < 0) {
        throw InventoryImportException(
          'Fila $rowNumber: la cantidad debe ser un entero mayor o igual a cero.',
        );
      }
      importedRows.add(
        ImportedInventoryRow(
          name: name,
          reference: reference,
          sku: sku,
          size: size,
          recommendedSizes: recommendedSizes,
          quantity: quantity,
          cost: cost,
          salePrice: salePrice,
        ),
      );
    }
    if (importedRows.isEmpty) {
      throw const InventoryImportException(
        'El archivo no contiene productos para importar.',
      );
    }
    return importedRows;
  }

  _InventorySheetFormat _validateHeaders(List<Data?> row) {
    final actual = row
        .map((cell) => cell?.value.toString().trim() ?? '')
        .toList();
    while (actual.isNotEmpty && actual.last.isEmpty) {
      actual.removeLast();
    }
    final isInitialInventory =
        actual.length == initialInventoryHeaders.length &&
        actual[1].toLowerCase() == 'referencia';
    final isTemplate =
        actual.length == templateHeaders.length &&
        actual[1].toLowerCase() == 'referencia';
    final expected = isInitialInventory
        ? initialInventoryHeaders
        : isTemplate
        ? templateHeaders
        : headers;
    if (actual.length != expected.length) {
      throw const InventoryImportException(
        'La estructura debe tener 7 columnas en la plantilla o 8 en el inventario inicial.',
      );
    }
    for (var index = 0; index < expected.length; index++) {
      if (actual[index].toLowerCase() != expected[index].toLowerCase()) {
        throw InventoryImportException(
          'Columna ${index + 1}: estructura de inventario no compatible.',
        );
      }
    }
    return isInitialInventory
        ? _InventorySheetFormat.initial
        : isTemplate
        ? _InventorySheetFormat.template
        : _InventorySheetFormat.legacy;
  }

  String _textAt(List<Data?> row, int index) {
    if (index >= row.length) return '';
    return row[index]?.value?.toString().trim() ?? '';
  }

  double _numberAt(List<Data?> row, int index, int rowNumber, String label) {
    if (index >= row.length || row[index]?.value == null) {
      throw InventoryImportException('Fila $rowNumber: falta $label.');
    }
    final value = row[index]!.value;
    final number = switch (value) {
      IntCellValue() => value.value.toDouble(),
      DoubleCellValue() => value.value,
      _ => _parseTextNumber(value.toString()),
    };
    if (number == null || !number.isFinite) {
      throw InventoryImportException(
        'Fila $rowNumber: $label debe ser un número válido.',
      );
    }
    return number;
  }

  int _integerAt(List<Data?> row, int index, int rowNumber, String label) {
    final number = _numberAt(row, index, rowNumber, label);
    if (number != number.roundToDouble()) {
      throw InventoryImportException(
        'Fila $rowNumber: $label debe ser un número entero.',
      );
    }
    return number.toInt();
  }

  double? _parseTextNumber(String text) {
    var normalized = text.replaceAll(RegExp(r'[\$\s]'), '');
    if (normalized.contains(',')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^[-+]?\d{1,3}(\.\d{3})+$').hasMatch(normalized)) {
      normalized = normalized.replaceAll('.', '');
    }
    return double.tryParse(normalized);
  }
}
