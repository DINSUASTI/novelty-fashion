import 'dart:typed_data';

enum ProfitLevel { yellow, green, blue }

enum ClothingSize {
  xs('XS'),
  s('S'),
  m('M'),
  l('L'),
  xl('XL'),
  oneSize('Talla única');

  const ClothingSize(this.label);

  final String label;

  static ClothingSize? tryParse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final size in values) {
      if (size.label.toLowerCase() == normalized) return size;
    }
    return null;
  }

  static List<ClothingSize>? tryParseRecommendations(String value) {
    if (value.trim().isEmpty) return const [];
    final parsed = <ClothingSize>{};
    for (final label in value.split(';')) {
      final size = tryParse(label);
      if (size == null) return null;
      parsed.add(size);
    }
    return List.unmodifiable(values.where(parsed.contains));
  }

  static String serializeRecommendations(Iterable<ClothingSize> sizes) {
    final selected = sizes.toSet();
    return values.where(selected.contains).map((size) => size.label).join(';');
  }
}

class InventoryRotation {
  const InventoryRotation({
    required this.itemId,
    required this.name,
    this.reference = '',
    required this.sku,
    required this.size,
    required this.pastQuantity,
    required this.currentQuantity,
  });

  final String itemId;
  final String name;
  final String reference;
  final String sku;
  final ClothingSize size;
  final int pastQuantity;
  final int currentQuantity;

  int get rotatedUnits =>
      (pastQuantity - currentQuantity).clamp(0, pastQuantity);

  double get rotationPercentage =>
      pastQuantity <= 0 ? 0 : (rotatedUnits / pastQuantity) * 100;
}

class ProductPhoto {
  const ProductPhoto.network(this.url) : bytes = null;

  const ProductPhoto.memory(this.bytes) : url = null;

  final String? url;
  final Uint8List? bytes;
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    this.reference = '',
    required this.sku,
    required this.size,
    this.recommendedSizes = const [],
    required this.quantity,
    required this.cost,
    required this.salePrice,
    required this.photos,
  });

  final String id;
  final String name;
  final String reference;
  final String sku;
  final ClothingSize size;
  final List<ClothingSize> recommendedSizes;
  final int quantity;
  final int cost;
  final int salePrice;
  final List<ProductPhoto> photos;

  int get profit => salePrice - cost;

  int get stockValue => cost * quantity;

  int get projectedProfit => profit * quantity;

  double get profitPercentage => cost <= 0 ? 0 : (profit / cost) * 100;

  ProfitLevel get profitLevel {
    if (profitPercentage <= 35) return ProfitLevel.yellow;
    if (profitPercentage <= 50) return ProfitLevel.blue;
    return ProfitLevel.green;
  }
}

int compareInventoryItemsByName(InventoryItem first, InventoryItem second) {
  return first.name.trim().toLowerCase().compareTo(
    second.name.trim().toLowerCase(),
  );
}

List<InventoryItem> topItemsByProfitPercentage(
  Iterable<InventoryItem> items, {
  int limit = 5,
}) {
  final sorted = items.toList()
    ..sort((first, second) {
      final percentageOrder = second.profitPercentage.compareTo(
        first.profitPercentage,
      );
      return percentageOrder != 0
          ? percentageOrder
          : compareInventoryItemsByName(first, second);
    });
  return List.unmodifiable(sorted.take(limit));
}

List<InventoryRotation> lowestInventoryRotation(
  Iterable<InventoryRotation> rotations, {
  int limit = 5,
}) {
  final sorted = rotations.toList()
    ..sort((first, second) {
      final percentageOrder = first.rotationPercentage.compareTo(
        second.rotationPercentage,
      );
      if (percentageOrder != 0) return percentageOrder;
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
  return List.unmodifiable(sorted.take(limit));
}

List<InventoryRotation> highestInventoryRotation(
  Iterable<InventoryRotation> rotations, {
  int limit = 5,
}) {
  final sorted = rotations.toList()
    ..sort((first, second) {
      final percentageOrder = second.rotationPercentage.compareTo(
        first.rotationPercentage,
      );
      if (percentageOrder != 0) return percentageOrder;
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
  return List.unmodifiable(sorted.take(limit));
}
