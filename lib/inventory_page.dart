import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'biometric_gate.dart';
import 'data/inventory_repository.dart';
import 'models/inventory_item.dart';
import 'services/inventory_excel_exporter.dart';
import 'services/inventory_excel_importer.dart';
import 'services/spreadsheet_file_saver.dart';

String _inventoryLabel(InventoryItem item) => item.reference.isEmpty
    ? item.size.label
    : '${item.reference} · ${item.size.label}';

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    this.repository,
    this.authenticateClear,
    this.pickImportFile,
  });

  final InventoryRepository? repository;
  final Future<bool> Function()? authenticateClear;
  final Future<PlatformFile?> Function()? pickImportFile;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _searchController = TextEditingController();
  final _excelExporter = InventoryExcelExporter();
  final _excelImporter = InventoryExcelImporter();
  late final InventoryRepository _repository;
  late final bool _ownsRepository;
  List<InventoryItem> _items = [];
  List<InventoryRotation> _lowestRotations = [];
  List<InventoryRotation> _highestRotations = [];
  List<InventoryRotation> _allRotations = [];
  String _query = '';
  String? _loadError;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isDownloadingTemplate = false;
  bool _isDownloadingReference = false;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository = widget.repository ?? SqliteInventoryRepository();
    unawaited(_loadItems());
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsRepository) unawaited(_repository.close());
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final items = await _repository.getAll();
      final lowestRotations = await _repository.getLowestRotation();
      final allRotations = await _repository.getHighestRotation(
        limit: items.length,
      );
      if (!mounted) return;
      setState(() {
        _items = items..sort(compareInventoryItemsByName);
        _lowestRotations = lowestRotations;
        _allRotations = allRotations;
        _highestRotations = List.unmodifiable(allRotations.take(5));
        _loadError = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No fue posible abrir el inventario local.';
        _isLoading = false;
      });
    }
  }

  List<InventoryItem> get _visibleItems {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where(
          (item) =>
              item.name.toLowerCase().contains(query) ||
              item.reference.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _openEditor([InventoryItem? item]) async {
    String? nextSku;
    if (item == null) {
      try {
        nextSku = await _repository.getNextSku();
      } catch (_) {
        if (mounted) _showMessage('No fue posible crear el producto');
        return;
      }
      if (!mounted) return;
    }
    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (context) =>
          InventoryItemDialog(item: item, initialSku: nextSku),
    );
    if (result == null || !mounted) return;

    try {
      await _repository.save(result);
      if (!mounted) return;
      await _loadItems();
      _showMessage(item == null ? 'Producto creado' : 'Producto actualizado');
    } catch (_) {
      if (mounted) _showMessage('No fue posible guardar el producto');
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Deseas eliminar ${item.name} del inventario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await _repository.delete(item.id);
        if (!mounted) return;
        await _loadItems();
        _showMessage('Producto eliminado');
      } catch (_) {
        if (mounted) _showMessage('No fue posible eliminar el producto');
      }
    }
  }

  Future<void> _exportInventory() async {
    setState(() => _isExporting = true);
    try {
      final saved = await _excelExporter.export(_items);
      if (mounted && saved) _showMessage('Informe de inventario exportado');
    } catch (_) {
      if (mounted) _showMessage('No fue posible exportar el informe');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importInventory() async {
    setState(() => _isImporting = true);
    String? fileName;
    try {
      final selection =
          await (widget.pickImportFile?.call() ??
              FilePicker.pickFile(
                dialogTitle: 'Seleccionar inventario',
                type: FileType.custom,
                allowedExtensions: const ['xlsx'],
              ));
      if (selection == null) return;
      fileName = selection.name;
      final bytes = await selection.readAsBytes();
      final rows = _excelImporter.parse(bytes);
      final placeholderData = await rootBundle.load(
        'assets/images/product_placeholder.png',
      );
      final placeholderBytes = placeholderData.buffer.asUint8List(
        placeholderData.offsetInBytes,
        placeholderData.lengthInBytes,
      );
      final plan = _excelImporter.createImportPlan(
        rows: rows,
        existingItems: await _repository.getAll(),
        placeholderBytes: placeholderBytes,
      );
      await _repository.importFile(plan.items, selection.name, bytes);
      await _loadItems();
      if (mounted) {
        await _showImportResult(
          fileName: selection.name,
          rows: rows.length,
          created: plan.createdCount,
          updated: plan.updatedCount,
        );
      }
    } on InventoryImportException catch (error) {
      if (mounted) await _showImportError(error.message, fileName: fileName);
    } catch (_) {
      if (mounted) {
        await _showImportError(
          'No fue posible importar el archivo Excel.',
          fileName: fileName,
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _downloadImportTemplate() async {
    setState(() => _isDownloadingTemplate = true);
    try {
      final saved = await _excelImporter.downloadTemplate();
      if (mounted && saved) _showMessage('Plantilla de importación descargada');
    } catch (_) {
      if (mounted) _showMessage('No fue posible descargar la plantilla');
    } finally {
      if (mounted) setState(() => _isDownloadingTemplate = false);
    }
  }

  Future<void> _downloadInitialInventory() async {
    setState(() => _isDownloadingReference = true);
    try {
      final data = await rootBundle.load('assets/INVENTARIO INICIAL.xlsx');
      final saved = await saveSpreadsheet(
        name: 'INVENTARIO INICIAL',
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (mounted && saved) _showMessage('Inventario inicial descargado');
    } catch (_) {
      if (mounted) {
        _showMessage('No fue posible descargar el inventario inicial');
      }
    } finally {
      if (mounted) setState(() => _isDownloadingReference = false);
    }
  }

  Future<void> _showImportHistory() async {
    final filesFuture = _repository.getImportedFiles();
    int? downloadingId;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          return AlertDialog(
            title: const Text('Archivos importados'),
            content: SizedBox(
              width: 440,
              height: 350,
              child: FutureBuilder<List<ImportedInventoryFile>>(
                future: filesFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('No fue posible abrir el histórico.'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final files = snapshot.data!;
                  if (files.isEmpty) {
                    return const Center(
                      child: Text('Todavía no hay archivos importados.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final date = file.importedAt;
                      final dateLabel =
                          '${date.day.toString().padLeft(2, '0')}/'
                          '${date.month.toString().padLeft(2, '0')}/${date.year} '
                          '${date.hour.toString().padLeft(2, '0')}:'
                          '${date.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        title: Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(dateLabel),
                        trailing: IconButton(
                          tooltip: 'Descargar ${file.name}',
                          icon: downloadingId == file.id
                              ? const CircularProgressIndicator()
                              : const Icon(Icons.download_rounded),
                          onPressed: downloadingId != null
                              ? null
                              : () async {
                                  updateDialog(() => downloadingId = file.id);
                                  try {
                                    final bytes = await _repository
                                        .getImportedFileBytes(file.id);
                                    final name =
                                        file.name.toLowerCase().endsWith(
                                          '.xlsx',
                                        )
                                        ? file.name.substring(
                                            0,
                                            file.name.length - 5,
                                          )
                                        : file.name;
                                    final saved = await saveSpreadsheet(
                                      name: name,
                                      bytes: bytes,
                                    );
                                    if (mounted && saved) {
                                      _showMessage('Archivo descargado');
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      _showMessage(
                                        'No fue posible descargar el archivo',
                                      );
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      updateDialog(() => downloadingId = null);
                                    }
                                  }
                                },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearInventory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar todo el inventario'),
        content: const Text(
          'Se eliminarán todos los productos, fotos e historial de cantidades. '
          'Los archivos importados permanecerán disponibles en el histórico. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isClearing = true);
    try {
      final authenticated =
          await (widget.authenticateClear?.call() ??
              authenticateWithBiometrics(
                'Confirma con biometría el borrado de todo el inventario.',
              ));
      if (!authenticated || !mounted) return;
      await _repository.clearInventory();
      await _loadItems();
      if (mounted) _showMessage('Inventario eliminado');
    } catch (_) {
      if (mounted) _showMessage('No fue posible borrar el inventario');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  void _openProfitabilityDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfitabilityDetailPage(
          items: _items,
          onEdit: (item) async {
            await _openEditor(item);
            return _items;
          },
        ),
      ),
    );
  }

  void _openHighRotationDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            _RotationDetailPage(items: _allRotations, isAscending: false),
      ),
    );
  }

  void _openLowRotationDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            _RotationDetailPage(items: _allRotations, isAscending: true),
      ),
    );
  }

  void _openStockDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _StockDetailPage(items: _items),
      ),
    );
  }

  Future<void> _showImportResult({
    required String fileName,
    required int rows,
    required int created,
    required int updated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importación completada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName),
            const SizedBox(height: 16),
            Text('Productos procesados: $rows'),
            Text('Nuevos: $created'),
            Text('Actualizados: $updated'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportError(String message, {String? fileName}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No se pudo importar'),
        content: Text(fileName == null ? message : '$fileName\n\n$message'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final totalUnits = _items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );
    final stockValue = _items.fold<int>(
      0,
      (total, item) => total + item.stockValue,
    );
    final projectedProfit = _items.fold<int>(
      0,
      (total, item) => total + item.projectedProfit,
    );
    final topProfitItems = topItemsByProfitPercentage(_items);
    final lowStockItems = _items.where((item) => item.quantity < 2).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'Novelty Fashion',
              image: true,
              child: Image.asset(
                'assets/images/logo_novelty_transparent.png',
                height: 56,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'v1.0.10+11',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones de inventario',
            enabled:
                !_isLoading &&
                !_isImporting &&
                !_isClearing &&
                !_isDownloadingReference,
            onSelected: (value) {
              if (value == 'history') {
                _showImportHistory();
              } else if (value == 'reference') {
                _downloadInitialInventory();
              } else {
                _clearInventory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reference',
                child: Text('Descargar inventario inicial'),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Text('Archivos importados'),
              ),
              if (!kIsWeb && _items.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Borrar todo el inventario'),
                ),
            ],
          ),
          IconButton(
            onPressed:
                _isLoading ||
                    _isDownloadingTemplate ||
                    _isImporting ||
                    _isExporting ||
                    _isClearing
                ? null
                : _downloadImportTemplate,
            tooltip: 'Descargar plantilla de importación',
            icon: _isDownloadingTemplate
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            onPressed: _isLoading || _isImporting || _isExporting || _isClearing
                ? null
                : _importInventory,
            tooltip: 'Importar inventario desde Excel',
            icon: _isImporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            onPressed:
                _items.isEmpty || _isExporting || _isImporting || _isClearing
                ? null
                : _exportInventory,
            tooltip: 'Exportar informe a Excel',
            icon: _isExporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading || _isClearing ? null : _openEditor,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo producto'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventario',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Control de existencias y rentabilidad',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryTile(
                              key: const ValueKey('summary-units'),
                              icon: Icons.inventory_2_outlined,
                              label: 'Unidades',
                              value: '$totalUnits',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SummaryTile(
                              key: const ValueKey('summary-investment'),
                              icon: Icons.payments_outlined,
                              label: 'Inversión',
                              value: formatMoney(stockValue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SummaryTile(
                              key: const ValueKey('summary-profit'),
                              icon: Icons.trending_up_rounded,
                              label: 'Ganancia proyectada',
                              value: formatMoney(projectedProfit),
                            ),
                          ),
                        ],
                      ),
                      if (!_isLoading && topProfitItems.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _TopProfitProducts(
                          items: topProfitItems,
                          onViewAll: _openProfitabilityDetails,
                          onEdit: _openEditor,
                        ),
                      ],
                      if (!_isLoading) ...[
                        const SizedBox(height: 22),
                        _RotationSection(
                          highestItems: _highestRotations,
                          lowestItems: _lowestRotations,
                          onViewHighest: _openHighRotationDetails,
                          onViewLowest: _openLowRotationDetails,
                        ),
                      ],
                      if (!_isLoading && lowStockItems.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _LowStockAlerts(
                          items: lowStockItems,
                          onSelect: _openEditor,
                          onViewAll: _openStockDetails,
                        ),
                      ],
                      const SizedBox(height: 22),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Buscar por producto o referencia',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar búsqueda',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _InventoryError(message: _loadError!, onRetry: _loadItems),
            )
          else if (_visibleItems.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyInventory(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 390,
                  mainAxisExtent: 390,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _visibleItems.length,
                itemBuilder: (context, index) {
                  final item = _visibleItems[index];
                  return _InventoryCard(
                    item: item,
                    onEdit: () => _openEditor(item),
                    onDelete: () => _deleteItem(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.onSurface),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LowStockAlerts extends StatelessWidget {
  const _LowStockAlerts({
    required this.items,
    required this.onSelect,
    required this.onViewAll,
  });

  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onSelect;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.45),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alertas de inventario',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Productos con menos de 2 unidades disponibles',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onViewAll,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Ver todas las existencias'),
            ),
          ),
          const SizedBox(height: 10),
          if (items.length > 5)
            SizedBox(
              height: 360,
              child: ListView.builder(
                key: const ValueKey('low-stock-alerts-scroll'),
                primary: false,
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _buildAlertItem(context, items[index], colors),
              ),
            )
          else
            ...items.map((item) => _buildAlertItem(context, item, colors)),
        ],
      ),
    );
  }

  Widget _buildAlertItem(
    BuildContext context,
    InventoryItem item,
    ColorScheme colors,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
          child: Text('${item.quantity}'),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(_inventoryLabel(item)),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => onSelect(item),
      ),
    );
  }
}

class _StockDetailPage extends StatefulWidget {
  const _StockDetailPage({required this.items});

  final List<InventoryItem> items;

  @override
  State<_StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<_StockDetailPage> {
  final _searchController = TextEditingController();
  String _query = '';

  late final List<InventoryItem> _sortedItems = [...widget.items]
    ..sort(compareInventoryItemsByName);

  List<InventoryItem> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return _sortedItems
        .where(
          (item) =>
              query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.reference.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Existencias por producto')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Buscar producto o referencia',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              tooltip: 'Limpiar búsqueda',
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '${visibleItems.length} productos',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      Text(
                        'Orden alfabético',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? const Center(child: Text('No encontramos productos'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: visibleItems.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final item = visibleItems[index];
                            final isCritical = item.quantity < 2;
                            final accent = isCritical
                                ? colors.error
                                : colors.primary;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                child: Text(item.name.substring(0, 1)),
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(_inventoryLabel(item)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('Unidades'),
                                  Text(
                                    '${item.quantity}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopProfitProducts extends StatelessWidget {
  const _TopProfitProducts({
    required this.items,
    required this.onViewAll,
    required this.onEdit,
  });

  final List<InventoryItem> items;
  final VoidCallback onViewAll;
  final void Function(InventoryItem) onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Top 5 por porcentaje de ganancia',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: onViewAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Ver todos'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Rentabilidad calculada sobre el costo unitario',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ...items.indexed.map(
            (entry) => Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                title: Text(
                  entry.$2.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_inventoryLabel(entry.$2)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProfitTrafficLight(item: entry.$2),
                    IconButton(
                      tooltip: 'Editar ${entry.$2.name}',
                      onPressed: () => onEdit(entry.$2),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfitabilityDetailPage extends StatefulWidget {
  const _ProfitabilityDetailPage({required this.items, required this.onEdit});

  final List<InventoryItem> items;
  final Future<List<InventoryItem>> Function(InventoryItem) onEdit;

  @override
  State<_ProfitabilityDetailPage> createState() =>
      _ProfitabilityDetailPageState();
}

class _ProfitabilityDetailPageState extends State<_ProfitabilityDetailPage> {
  final _searchController = TextEditingController();
  String _query = '';

  late List<InventoryItem> _sortedItems = topItemsByProfitPercentage(
    widget.items,
    limit: widget.items.length,
  );

  Future<void> _editItem(InventoryItem item) async {
    final items = await widget.onEdit(item);
    if (!mounted) return;
    setState(() {
      _sortedItems = topItemsByProfitPercentage(items, limit: items.length);
    });
  }

  List<(int, InventoryItem)> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return _sortedItems.indexed
        .where(
          (entry) =>
              query.isEmpty ||
              entry.$2.name.toLowerCase().contains(query) ||
              entry.$2.reference.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    return Scaffold(
      appBar: AppBar(title: const Text('Rentabilidad de productos')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Buscar producto o referencia',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              tooltip: 'Limpiar búsqueda',
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '${visibleItems.length} productos',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      Text(
                        'Mayor a menor rentabilidad',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? const Center(child: Text('No encontramos productos'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: visibleItems.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final entry = visibleItems[index];
                            final item = entry.$2;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              leading: CircleAvatar(
                                child: Text('${entry.$1 + 1}'),
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_inventoryLabel(item)),
                                  Text(
                                    'Costo: ${formatMoney(item.cost)} · Venta: ${formatMoney(item.salePrice)}',
                                  ),
                                  Text(
                                    'Ganancia unitaria: ${formatMoney(item.profit)}',
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ProfitTrafficLight(item: item),
                                  IconButton(
                                    tooltip: 'Editar ${item.name}',
                                    onPressed: () => _editItem(item),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RotationSection extends StatelessWidget {
  const _RotationSection({
    required this.highestItems,
    required this.lowestItems,
    required this.onViewHighest,
    required this.onViewLowest,
  });

  final List<InventoryRotation> highestItems;
  final List<InventoryRotation> lowestItems;
  final VoidCallback onViewHighest;
  final VoidCallback onViewLowest;

  @override
  Widget build(BuildContext context) {
    final maxItems = highestItems.length > lowestItems.length
        ? highestItems.length
        : lowestItems.length;
    final isCompact = MediaQuery.sizeOf(context).width < 400;
    final panelHeight = isCompact
        ? 330.0 + maxItems * 160.0
        : 160.0 + maxItems * 82.0;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rotación de inventario',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: const TabBar(
              tabs: [
                Tab(text: 'Mayor rotación'),
                Tab(text: 'Menor rotación'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: panelHeight,
            child: TabBarView(
              children: [
                _RotationProducts(
                  key: const ValueKey('high-rotation-panel'),
                  items: highestItems,
                  isPositive: true,
                  onViewAll: onViewHighest,
                  viewAllLabel: 'Ver mayor rotación',
                ),
                _RotationProducts(
                  key: const ValueKey('low-rotation-panel'),
                  items: lowestItems,
                  isPositive: false,
                  onViewAll: onViewLowest,
                  viewAllLabel: 'Ver menor rotación',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RotationProducts extends StatelessWidget {
  const _RotationProducts({
    super.key,
    required this.items,
    required this.isPositive,
    this.onViewAll,
    this.viewAllLabel,
  });

  final List<InventoryRotation> items;
  final bool isPositive;
  final VoidCallback? onViewAll;
  final String? viewAllLabel;

  @override
  Widget build(BuildContext context) {
    final background = isPositive
        ? const Color(0xFFE2F4E8)
        : const Color(0xFFFFF3CD);
    final accent = isPositive
        ? const Color(0xFF2E7D32)
        : const Color(0xFFD6A100);
    final foreground = isPositive
        ? const Color(0xFF185C35)
        : const Color(0xFF6B5200);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: accent.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPositive
                ? 'Top 5 con mayor rotación en los últimos 30 días'
                : 'Top 5 con menor rotación en los últimos 30 días',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            isPositive
                ? 'Productos con mejor reducción de existencias'
                : 'Alerta de productos con menor movimiento',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground),
          ),
          if (onViewAll != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(viewAllLabel!),
              ),
            ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aún no hay 30 días de historial para calcular la rotación.',
                style: TextStyle(color: foreground),
              ),
            )
          else
            ...items.indexed.map(
              (entry) => Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    child: Text('${entry.$1 + 1}'),
                  ),
                  title: Text(
                    entry.$2.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hace 30 días: ${entry.$2.pastQuantity}'),
                      Text(
                        'Rotación estimada: ${entry.$2.rotationPercentage.toStringAsFixed(1)}%',
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Actual'),
                      Text(
                        '${entry.$2.currentQuantity}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RotationDetailPage extends StatefulWidget {
  const _RotationDetailPage({required this.items, required this.isAscending});

  final List<InventoryRotation> items;
  final bool isAscending;

  @override
  State<_RotationDetailPage> createState() => _RotationDetailPageState();
}

class _RotationDetailPageState extends State<_RotationDetailPage> {
  final _searchController = TextEditingController();
  String _query = '';

  late final List<InventoryRotation> _sortedItems = widget.isAscending
      ? lowestInventoryRotation(widget.items, limit: widget.items.length)
      : highestInventoryRotation(widget.items, limit: widget.items.length);

  List<(int, InventoryRotation)> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return _sortedItems.indexed
        .where(
          (entry) =>
              query.isEmpty ||
              entry.$2.name.toLowerCase().contains(query) ||
              entry.$2.reference.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    final accent = widget.isAscending
        ? const Color(0xFFD6A100)
        : const Color(0xFF2E7D32);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAscending ? 'Menor rotación' : 'Mayor rotación'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Buscar producto o referencia',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              tooltip: 'Limpiar búsqueda',
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '${visibleItems.length} productos',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      Text(
                        widget.isAscending
                            ? 'Menor a mayor rotación'
                            : 'Mayor a menor rotación',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? const Center(child: Text('No encontramos productos'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: visibleItems.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final entry = visibleItems[index];
                            final item = entry.$2;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                child: Text('${entry.$1 + 1}'),
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.reference.isEmpty
                                        ? item.size.label
                                        : '${item.reference} · ${item.size.label}',
                                  ),
                                  Text(
                                    'Hace 30 días: ${item.pastQuantity} · Actual: ${item.currentQuantity}',
                                  ),
                                ],
                              ),
                              trailing: Text(
                                '${item.rotationPercentage.toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final stockColor = item.quantity == 0
        ? Theme.of(context).colorScheme.error
        : item.quantity <= 5
        ? Theme.of(context).colorScheme.error
        : const Color(0xFF26734D);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ProductImage(photo: item.photos.first),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.quantity == 0
                          ? 'Agotado'
                          : '${item.quantity} disponibles',
                      style: TextStyle(
                        color: stockColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _ProfitTrafficLight(item: item),
                ),
                if (item.photos.length > 1)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Chip(
                      avatar: const Icon(
                        Icons.photo_library_outlined,
                        size: 16,
                      ),
                      label: Text('${item.photos.length}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      onSelected: (value) =>
                          value == 'edit' ? onEdit() : onDelete(),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ],
                ),
                Text(
                  _inventoryLabel(item),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PriceDetail(label: 'Costo', value: formatMoney(item.cost)),
                    _PriceDetail(
                      label: 'Venta',
                      value: formatMoney(item.salePrice),
                    ),
                    _PriceDetail(
                      label: 'Ganancia',
                      value: formatMoney(item.profit),
                      highlight: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfitTrafficLight extends StatelessWidget {
  const _ProfitTrafficLight({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.profitLevel) {
      ProfitLevel.yellow => const Color(0xFFD9A300),
      ProfitLevel.green => const Color(0xFF2E7D32),
      ProfitLevel.blue => const Color(0xFF1976D2),
    };
    final level = switch (item.profitLevel) {
      ProfitLevel.yellow => 'amarillo',
      ProfitLevel.green => 'verde',
      ProfitLevel.blue => 'azul',
    };
    final percentage = '${item.profitPercentage.toStringAsFixed(1)}%';
    return Semantics(
      label: 'Ganancia $percentage, nivel $level',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              percentage,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceDetail extends StatelessWidget {
  const _PriceDetail({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: highlight ? const Color(0xFF26734D) : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.photo});

  final ProductPhoto photo;

  @override
  Widget build(BuildContext context) {
    if (photo.bytes != null) {
      return Image.memory(photo.bytes!, fit: BoxFit.cover);
    }
    return Image.network(
      photo.url!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 42)),
      ),
    );
  }
}

class InventoryItemDialog extends StatefulWidget {
  const InventoryItemDialog({super.key, this.item, this.initialSku});

  final InventoryItem? item;
  final String? initialSku;

  @override
  State<InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends State<InventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _referenceController;
  late final TextEditingController _quantityController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;
  late List<ProductPhoto> _photos;
  late ClothingSize _selectedSize;
  late List<ClothingSize> _selectedRecommendedSizes;

  int get _profit =>
      (int.tryParse(_priceController.text) ?? 0) -
      (int.tryParse(_costController.text) ?? 0);

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _referenceController = TextEditingController(text: item?.reference ?? '');
    _quantityController = TextEditingController(
      text: '${item?.quantity ?? ''}',
    );
    _costController = TextEditingController(
      text: item == null ? '' : '${item.cost}',
    );
    _priceController = TextEditingController(
      text: item == null ? '' : '${item.salePrice}',
    );
    _selectedSize = item?.size ?? ClothingSize.oneSize;
    _selectedRecommendedSizes = [...?item?.recommendedSizes];
    _photos = [...?item?.photos];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _referenceController.dispose();
    _quantityController.dispose();
    _costController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 82);
      final photos = <ProductPhoto>[];
      for (final file in files) {
        photos.add(ProductPhoto.memory(await file.readAsBytes()));
      }
      if (mounted) setState(() => _photos.addAll(photos));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible abrir la galería')),
      );
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos una foto del producto')),
      );
      return;
    }
    Navigator.pop(
      context,
      InventoryItem(
        id: widget.item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        reference: _referenceController.text.trim().toUpperCase(),
        sku: widget.item?.sku ?? widget.initialSku!,
        size: _selectedSize,
        recommendedSizes: List.unmodifiable(_selectedRecommendedSizes),
        quantity: int.parse(_quantityController.text),
        cost: int.parse(_costController.text),
        salePrice: int.parse(_priceController.text),
        photos: List.unmodifiable(_photos),
      ),
    );
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return 'Campo requerido';
    return null;
  }

  String? _integerValidator(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) return 'Ingresa un valor válido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item == null
                          ? 'Nuevo producto'
                          : 'Editar producto',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fotos del producto',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (_photos.isNotEmpty)
                        SizedBox(
                          height: 104,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) => Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 90,
                                    height: 104,
                                    child: _ProductImage(photo: _photos[index]),
                                  ),
                                ),
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: IconButton.filled(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Quitar foto',
                                    onPressed: () =>
                                        setState(() => _photos.removeAt(index)),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pickPhotos,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Elegir fotos'),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del producto',
                        ),
                        validator: _requiredText,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Referencia',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: _requiredText,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<ClothingSize>(
                        initialValue: _selectedSize,
                        decoration: const InputDecoration(labelText: 'Talla'),
                        items: ClothingSize.values
                            .map(
                              (size) => DropdownMenuItem(
                                value: size,
                                child: Text(size.label),
                              ),
                            )
                            .toList(),
                        onChanged: (size) {
                          if (size != null) {
                            setState(() => _selectedSize = size);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Talla recomendada',
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: ClothingSize.values.map((size) {
                            final selected = _selectedRecommendedSizes.contains(
                              size,
                            );
                            return FilterChip(
                              label: Text(size.label),
                              selected: selected,
                              onSelected: (isSelected) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedRecommendedSizes.add(size);
                                  } else {
                                    _selectedRecommendedSizes.remove(size);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _integerValidator,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _costController,
                              decoration: const InputDecoration(
                                labelText: 'Costo',
                                prefixText: r'$ ',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: _integerValidator,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              decoration: const InputDecoration(
                                labelText: 'Precio de venta',
                                prefixText: r'$ ',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              validator: _integerValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.trending_up_rounded),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Ganancia por unidad')),
                            Text(
                              formatMoney(_profit),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar producto'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('No encontramos productos'),
        ],
      ),
    );
  }
}

class _InventoryError extends StatelessWidget {
  const _InventoryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

String formatMoney(int value) {
  final sign = value < 0 ? '-' : '';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '$sign\$ ${buffer.toString()}';
}
