import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novelty_fashion/data/inventory_repository.dart';
import 'package:novelty_fashion/inventory_page.dart';
import 'package:novelty_fashion/main.dart';
import 'package:novelty_fashion/models/inventory_item.dart';
import 'package:novelty_fashion/services/inventory_excel_importer.dart';

void main() {
  testWidgets('muestra el inventario y los datos financieros', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inventario'), findsOneWidget);
    final colors = Theme.of(tester.element(find.text('Inventario')))
        .colorScheme;
    expect(colors.primary, const Color(0xFF007C83));
    expect(colors.secondary, const Color(0xFF3157C8));
    expect(colors.error, const Color(0xFFBA1A1A));
    expect(find.text('Nuevo producto'), findsOneWidget);
    expect(find.text('Inversión'), findsOneWidget);
    expect(find.text(r'$ 1.344.000'), findsOneWidget);
    expect(find.text('Ganancia proyectada'), findsOneWidget);
    expect(find.text(r'$ 1.094.400'), findsOneWidget);
    expect(find.text('Top 5 por porcentaje de ganancia'), findsOneWidget);
    expect(find.text('Ver todos'), findsOneWidget);
    expect(
      find.text('Rentabilidad calculada sobre el costo unitario'),
      findsOneWidget,
    );
    expect(
      find.text('Top 5 con mayor rotación en los últimos 30 días'),
      findsOneWidget,
    );
    expect(find.text('Rotación de inventario'), findsOneWidget);
    expect(find.text('Mayor rotación'), findsOneWidget);
    expect(find.text('Menor rotación'), findsOneWidget);
    expect(find.text('Ver mayor rotación'), findsOneWidget);
    expect(find.text('Hace 30 días: 14'), findsOneWidget);
    expect(find.text('Actual'), findsNWidgets(3));
    expect(find.text('Alertas de inventario'), findsOneWidget);
    expect(
      find.text('Productos con menos de 2 unidades disponibles'),
      findsOneWidget,
    );
    expect(find.text('Ver todas las existencias'), findsOneWidget);
    expect(find.text('Blusa Lino Marfil'), findsWidgets);
    expect(find.byTooltip('Exportar informe a Excel'), findsOneWidget);
    expect(find.byTooltip('Importar inventario desde Excel'), findsOneWidget);
    expect(
      find.byTooltip('Descargar plantilla de importación'),
      findsOneWidget,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(find.text('Vestido Aura'), findsWidgets);
    expect(find.text('Costo'), findsWidgets);
    expect(find.text('Venta'), findsWidgets);
    expect(find.text('Ganancia'), findsWidgets);
    expect(find.text(r'$ 61.900 · 79.4%'), findsNothing);
    expect(find.text(r'$ 61.900'), findsOneWidget);
    expect(find.text('VES-AUR-001 · M'), findsNothing);
    expect(find.text('M'), findsWidgets);
  });

  testWidgets('muestra las tres métricas en una fila a 320 píxeles', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    final units = tester.getRect(find.byKey(const ValueKey('summary-units')));
    final investment = tester.getRect(
      find.byKey(const ValueKey('summary-investment')),
    );
    final profit = tester.getRect(find.byKey(const ValueKey('summary-profit')));
    expect(investment.top, units.top);
    expect(profit.top, units.top);
    expect(units.left, greaterThanOrEqualTo(0));
    expect(profit.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desplaza solo las alertas cuando hay más de cinco', (
    WidgetTester tester,
  ) async {
    final items = [
      for (var index = 0; index < 7; index++)
        InventoryItem(
          id: 'alert-$index',
          name: 'Alerta $index',
          sku: 'ALR-$index',
          size: ClothingSize.s,
          quantity: 0,
          cost: 10,
          salePrice: 20,
          photos: const [ProductPhoto.network('https://example.com/foto.jpg')],
        ),
    ];
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository(items: items)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Alertas de inventario'));
    await tester.pumpAndSettle();

    final mainScroll = find.byType(CustomScrollView).first;
    final alertsScroll = find.byKey(const ValueKey('low-stock-alerts-scroll'));
    final mainScrollable = find
        .descendant(of: mainScroll, matching: find.byType(Scrollable))
        .first;
    final mainOffsetBefore = tester
        .state<ScrollableState>(mainScrollable)
        .position
        .pixels;

    await tester.drag(alertsScroll, const Offset(0, -240));
    await tester.pumpAndSettle();

    final mainOffsetAfter = tester
        .state<ScrollableState>(mainScrollable)
        .position
        .pixels;
    expect(mainOffsetAfter, mainOffsetBefore);
    expect(find.text('Alerta 6'), findsOneWidget);
  });

  testWidgets('muestra y busca la referencia compartida entre SKU', (
    WidgetTester tester,
  ) async {
    final items = [
      for (final sku in ['1', '2'])
        InventoryItem(
          id: sku,
          name: 'Chaqueta $sku',
          reference: 'REF-001',
          sku: sku,
          size: ClothingSize.oneSize,
          quantity: 1,
          cost: 98000,
          salePrice: 180000,
          photos: const [ProductPhoto.network('https://example.com/foto.jpg')],
        ),
    ];
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository(items: items)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar por producto o referencia'),
      'REF-001',
    );
    await tester.pumpAndSettle();
    expect(find.text('REF-001 · Talla única'), findsWidgets);
    expect(find.text('Chaqueta 1'), findsWidgets);
    expect(find.text('Chaqueta 2'), findsWidgets);
    expect(find.textContaining('SKU'), findsNothing);
  });

  test('expone únicamente las tallas permitidas', () {
    expect(ClothingSize.values.map((size) => size.label), [
      'XS',
      'S',
      'M',
      'L',
      'XL',
      'Talla única',
    ]);
  });

  testWidgets('requiere confirmación y biometría para vaciar el inventario', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository();
    var authenticated = false;
    var attempts = 0;
    await tester.pumpWidget(
      NoveltyFashionApp(
        repository: repository,
        authenticateClear: () async {
          attempts++;
          return authenticated;
        },
      ),
    );
    await tester.pumpAndSettle();

    Future<void> chooseClear() async {
      await tester.tap(find.byTooltip('Opciones de inventario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar todo el inventario'));
      await tester.pumpAndSettle();
    }

    await chooseClear();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(repository._items, isNotEmpty);

    await chooseClear();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(repository._items, isNotEmpty);

    authenticated = true;
    await chooseClear();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(repository._items, isEmpty);
  });

  testWidgets('lista los archivos importados aunque el inventario esté vacío', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository(items: []);
    await tester.pumpWidget(NoveltyFashionApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones de inventario'));
    await tester.pumpAndSettle();
    expect(find.text('Descargar inventario inicial'), findsOneWidget);
    await tester.tap(find.text('Archivos importados'));
    await tester.pumpAndSettle();
    expect(find.text('original.xlsx'), findsOneWidget);
    expect(find.byTooltip('Descargar original.xlsx'), findsOneWidget);
  });

  testWidgets('muestra la versión junto al logo principal', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository(items: [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('v1.0.10+11'), findsOneWidget);
  });

  testWidgets('informa productos creados y actualizados tras importar', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository(items: []);
    final bytes = InventoryExcelImporter().buildTemplate();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryPage(
          repository: repository,
          pickImportFile: () async =>
              _TestInventoryFile('correccion.xlsx', bytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Importar inventario desde Excel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Importación completada'), findsOneWidget);
    expect(find.text('correccion.xlsx'), findsOneWidget);
    expect(find.text('Productos procesados: 2'), findsOneWidget);
    expect(find.text('Nuevos: 2'), findsOneWidget);
    expect(find.text('Actualizados: 0'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(await repository.getAll(), hasLength(2));
  });

  testWidgets('informa el archivo y motivo de una importación fallida', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository(items: []);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryPage(
          repository: repository,
          pickImportFile: () async => _TestInventoryFile(
            'incorrecto.xlsx',
            Uint8List.fromList([1, 2, 3]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Importar inventario desde Excel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No se pudo importar'), findsOneWidget);
    expect(find.textContaining('incorrecto.xlsx'), findsOneWidget);
    expect(find.textContaining('no es un Excel válido'), findsOneWidget);
    expect(await repository.getAll(), isEmpty);
  });

  testWidgets('rechaza valores decimales en la creación manual', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo producto'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    expect(find.text('Talla única'), findsWidgets);
    await tester.enterText(field('Nombre del producto'), 'Producto decimal');
    await tester.enterText(field('Cantidad'), '2');
    await tester.enterText(field('Costo'), '10.5');
    await tester.enterText(field('Precio de venta'), '20');
    await tester.tap(find.text('Guardar producto'));
    await tester.pump();

    expect(find.text('Ingresa un valor válido'), findsOneWidget);
  });

  testWidgets('permite seleccionar varias tallas recomendadas', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo producto'));
    await tester.pumpAndSettle();

    final xsChip = find.widgetWithText(FilterChip, 'XS');
    final xlChip = find.widgetWithText(FilterChip, 'XL');
    expect(tester.widget<FilterChip>(xsChip).selected, isFalse);
    expect(tester.widget<FilterChip>(xlChip).selected, isFalse);

    await tester.ensureVisible(xsChip);
    await tester.tap(xsChip);
    await tester.ensureVisible(xlChip);
    await tester.tap(xlChip);
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(xsChip).selected, isTrue);
    expect(tester.widget<FilterChip>(xlChip).selected, isTrue);
  });

  testWidgets('asigna el identificador interno sin mostrarlo al crear', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository(
      items: [
        const InventoryItem(
          id: 'last',
          name: 'Producto anterior',
          reference: 'REF-050',
          sku: '83',
          size: ClothingSize.oneSize,
          quantity: 1,
          cost: 10,
          salePrice: 20,
          photos: [ProductPhoto.network('https://example.com/foto.jpg')],
        ),
      ],
    );
    await tester.pumpWidget(NoveltyFashionApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo producto'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Agregar URL'), findsNothing);
    expect(find.text('Elegir fotos'), findsOneWidget);
    expect(find.textContaining('SKU'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'SKU'), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Referencia'),
              matching: find.byType(EditableText),
            ),
          )
          .readOnly,
      isFalse,
    );
    expect(await repository.getNextSku(), '84');
  });

  testWidgets('permite modificar la referencia al editar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InventoryItemDialog(
            item: InventoryItem(
              id: 'existing',
              name: 'Chaqueta',
              reference: 'REF-001',
              sku: '83',
              size: ClothingSize.oneSize,
              quantity: 1,
              cost: 10,
              salePrice: 20,
              photos: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reference = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Referencia'),
    );
    expect(reference.controller!.text, 'REF-001');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Referencia'),
              matching: find.byType(EditableText),
            ),
          )
          .readOnly,
      isFalse,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Referencia'),
      'REF-002',
    );
    expect(reference.controller!.text, 'REF-002');
    expect(find.widgetWithText(TextFormField, 'SKU'), findsNothing);
  });

  test('calcula la ganancia como precio de venta menos costo', () {
    const item = InventoryItem(
      id: 'test',
      name: 'Producto',
      sku: 'SKU-1',
      size: ClothingSize.m,
      quantity: 2,
      cost: 40000,
      salePrice: 75000,
      photos: [ProductPhoto.network('https://example.com/foto.jpg')],
    );

    expect(item.profit, 35000);
    expect(item.projectedProfit, 70000);
    expect(item.profitPercentage, 87.5);
    expect(item.profitLevel, ProfitLevel.green);
  });

  test('clasifica los límites del semáforo y ordena el top 5', () {
    InventoryItem item(String name, int percentage) => InventoryItem(
      id: name,
      name: name,
      sku: name,
      size: ClothingSize.s,
      quantity: 1,
      cost: 100,
      salePrice: 100 + percentage,
      photos: const [ProductPhoto.network('https://example.com/foto.jpg')],
    );

    final yellow = item('Amarillo', 35);
    final blue = item('Azul', 50);
    final green = item('Verde', 51);
    final fourth = item('Cuarto', 10);

    expect(yellow.profitLevel, ProfitLevel.yellow);
    expect(blue.profitLevel, ProfitLevel.blue);
    expect(green.profitLevel, ProfitLevel.green);
    expect(topItemsByProfitPercentage([yellow, fourth, blue, green]), [
      green,
      blue,
      yellow,
      fourth,
    ]);
  });

  testWidgets('abre y filtra la vista completa de rentabilidad', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver todos'));
    await tester.pumpAndSettle();
    expect(find.text('Rentabilidad de productos'), findsOneWidget);
    expect(find.text('3 productos'), findsOneWidget);
    expect(find.text('Mayor a menor rentabilidad'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar producto o referencia'),
      'Vestido',
    );
    await tester.pump();
    expect(find.text('1 productos'), findsOneWidget);
    expect(find.text('Vestido Aura'), findsOneWidget);
    expect(find.text('Blazer Siena'), findsNothing);
  });

  testWidgets('edita desde el Top 5 y guarda el producto', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository();
    await tester.pumpWidget(NoveltyFashionApp(repository: repository));
    await tester.pumpAndSettle();

    final editButton = find.byTooltip('Editar Blazer Siena');
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Agregar URL'), findsNothing);
    expect(find.text('Elegir fotos'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Referencia'),
      'REF-EDITADA',
    );
    await tester.tap(find.text('Guardar producto'));
    await tester.pumpAndSettle();

    expect(
      (await repository.getAll())
          .singleWhere((item) => item.name == 'Blazer Siena')
          .reference,
      'REF-EDITADA',
    );
    expect(find.text('REF-EDITADA · S'), findsWidgets);
  });

  testWidgets('edita desde Ver todos y actualiza la lista abierta', (
    WidgetTester tester,
  ) async {
    final repository = _FakeInventoryRepository();
    await tester.pumpWidget(NoveltyFashionApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todos'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar Blazer Siena'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Referencia'),
      'REF-DETALLE',
    );
    await tester.tap(find.text('Guardar producto'));
    await tester.pumpAndSettle();

    expect(find.text('Rentabilidad de productos'), findsOneWidget);
    expect(find.text('REF-DETALLE · S'), findsOneWidget);
    expect(
      (await repository.getAll())
          .singleWhere((item) => item.name == 'Blazer Siena')
          .reference,
      'REF-DETALLE',
    );
  });

  testWidgets('abre y filtra toda la rotación de mayor a menor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver mayor rotación'));
    await tester.pumpAndSettle();
    expect(find.text('Mayor rotación'), findsOneWidget);
    expect(find.text('3 productos'), findsOneWidget);
    expect(find.text('Mayor a menor rotación'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar producto o referencia'),
      'Vestido',
    );
    await tester.pump();
    expect(find.text('1 productos'), findsOneWidget);
    expect(find.text('Vestido Aura'), findsOneWidget);
    expect(find.text('Blazer Siena'), findsNothing);
  });

  testWidgets('abre y filtra toda la rotación de menor a mayor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    final tabController = DefaultTabController.of(
      tester.element(find.text('Menor rotación')),
    );
    tabController.animateTo(1);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver menor rotación'));
    await tester.pumpAndSettle();
    expect(find.text('Menor rotación'), findsOneWidget);
    expect(find.text('3 productos'), findsOneWidget);
    expect(find.text('Menor a mayor rotación'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar producto o referencia'),
      'Blazer',
    );
    await tester.pump();
    expect(find.text('1 productos'), findsOneWidget);
    expect(find.text('Blazer Siena'), findsOneWidget);
    expect(find.text('Vestido Aura'), findsNothing);
  });

  testWidgets('abre y filtra todas las existencias en orden alfabético', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todas las existencias'));
    await tester.pumpAndSettle();
    expect(find.text('Existencias por producto'), findsOneWidget);
    expect(find.text('3 productos'), findsOneWidget);
    expect(find.text('Orden alfabético'), findsOneWidget);
    expect(find.text('Unidades'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar producto o referencia'),
      'Blusa',
    );
    await tester.pump();
    expect(find.text('1 productos'), findsOneWidget);
    expect(find.text('Blusa Lino Marfil'), findsOneWidget);
    expect(find.text('Vestido Aura'), findsNothing);
  });

  testWidgets('aplica verde a mayor rotación y amarillo a menor rotación', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NoveltyFashionApp(repository: _FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();

    BoxDecoration panelDecoration(String key) {
      final panel = find.byKey(ValueKey(key));
      final container = find.descendant(
        of: panel,
        matching: find.byType(Container),
      );
      return tester.widget<Container>(container.first).decoration!
          as BoxDecoration;
    }

    expect(
      panelDecoration('high-rotation-panel').color,
      const Color(0xFFE2F4E8),
    );
    final tabController = DefaultTabController.of(
      tester.element(find.text('Menor rotación')),
    );
    tabController.animateTo(1);
    await tester.pumpAndSettle();
    expect(
      panelDecoration('low-rotation-panel').color,
      const Color(0xFFFFF3CD),
    );
  });
}

base class _TestInventoryFile extends PlatformFile {
  _TestInventoryFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.dataFromBytes(bytes);

  @override
  Never get xFile => throw UnsupportedError('No se usa en estas pruebas');

  @override
  int lengthSync() => bytes.length;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _FakeInventoryRepository implements InventoryRepository {
  _FakeInventoryRepository({List<InventoryItem>? items})
    : _items = items ?? [...seedInventoryItems];

  final List<InventoryItem> _items;

  @override
  Future<String> getNextSku() async {
    final highest = _items
        .map((item) => int.tryParse(item.sku))
        .whereType<int>()
        .fold<int>(0, (maxSku, sku) => sku > maxSku ? sku : maxSku);
    return '${highest + 1}';
  }

  @override
  Future<List<InventoryItem>> getAll() async => [..._items];

  @override
  Future<void> save(InventoryItem item) async {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
  }

  @override
  Future<void> saveAll(List<InventoryItem> items) async {
    for (final item in items) {
      await save(item);
    }
  }

  @override
  Future<void> importFile(
    List<InventoryItem> items,
    String name,
    Uint8List bytes,
  ) => saveAll(items);

  @override
  Future<List<ImportedInventoryFile>> getImportedFiles() async => [
    ImportedInventoryFile(
      id: 1,
      name: 'original.xlsx',
      importedAt: DateTime(2026, 9, 26),
    ),
  ];

  @override
  Future<Uint8List> getImportedFileBytes(int id) async =>
      Uint8List.fromList([1, 2]);

  @override
  Future<void> clearInventory() async => _items.clear();

  @override
  Future<List<InventoryRotation>> getLowestRotation({
    int days = 30,
    int limit = 5,
  }) async {
    return lowestInventoryRotation(_rotations, limit: limit);
  }

  @override
  Future<List<InventoryRotation>> getHighestRotation({
    int days = 30,
    int limit = 5,
  }) async {
    return highestInventoryRotation(_rotations, limit: limit);
  }

  static const _rotations = [
    InventoryRotation(
      itemId: 'seed-1',
      name: 'Vestido Aura',
      sku: 'VES-AUR-001',
      size: ClothingSize.m,
      pastQuantity: 14,
      currentQuantity: 12,
    ),
    InventoryRotation(
      itemId: 'seed-2',
      name: 'Blazer Siena',
      sku: 'BLA-SIE-004',
      size: ClothingSize.s,
      pastQuantity: 7,
      currentQuantity: 4,
    ),
    InventoryRotation(
      itemId: 'seed-3',
      name: 'Blusa Lino Marfil',
      sku: 'BLU-LIN-012',
      size: ClothingSize.oneSize,
      pastQuantity: 1,
      currentQuantity: 0,
    ),
  ];

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> close() async {}
}
