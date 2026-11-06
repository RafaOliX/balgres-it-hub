class ItAssetImage {
  final int id;
  final String filename;
  const ItAssetImage({required this.id, required this.filename});
  factory ItAssetImage.fromJson(Map<String, dynamic> j) => ItAssetImage(id: j['id'], filename: j['filename']);
  String get url => '/uploads/$filename';
}

class ItAsset {
  final int id;
  final String assetTag;
  final String category;
  final int? categoryId;
  final String brand;
  final String model;
  final String? serialNumber;
  final String? location;
  final String? status;
  final String? notes;
  final List<ItAssetImage> images;
  final int quantity;
  final String unit;
  final String? assignedTo;

  const ItAsset({
    required this.id, required this.assetTag, required this.category, this.categoryId,
    required this.brand, required this.model, this.serialNumber, this.location, this.status, this.notes,
    this.images = const [], this.quantity = 1, this.unit = 'Unidad', this.assignedTo,
  });

  factory ItAsset.fromJson(Map<String, dynamic> j) => ItAsset(
    id: j['id'] as int,
    assetTag: j['asset_tag'] as String,
    category: j['category'] as String,
    categoryId: j['category_id'] as int?,
    brand: j['brand'] as String,
    model: j['model'] as String,
    serialNumber: j['serial_number'] as String?,
    location: j['location'] as String?,
    status: j['status'] as String?,
    notes: j['notes'] as String?,
    quantity: j['quantity'] as int? ?? 1,
    unit: j['unit'] as String? ?? 'Unidad',
    assignedTo: j['assigned_to'] as String?,
    images: ((j['images'] as List<dynamic>?) ?? []).map((e) => ItAssetImage.fromJson(e as Map<String, dynamic>)).toList(),
  );

  String? get imageUrl => images.isNotEmpty ? images.first.url : null;
}

class ItAssetCreate {
  final String assetTag;
  final String category;
  final int? categoryId;
  final String brand;
  final String model;
  final String? serialNumber;
  final String? location;
  final String? status;
  final String? notes;
  final int quantity;
  final String unit;
  final String? assignedTo;

  ItAssetCreate({
    required this.assetTag, required this.category, this.categoryId,
    required this.brand, required this.model, this.serialNumber, this.location,
    this.status, this.notes, this.quantity = 1, this.unit = 'Unidad', this.assignedTo,
  });

  Map<String, dynamic> toJson() => {
    'asset_tag': assetTag, 'category': category, 'category_id': categoryId,
    'brand': brand, 'model': model, 'serial_number': serialNumber,
    'location': location, 'status': status, 'notes': notes,
    'quantity': quantity, 'unit': unit, 'assigned_to': assignedTo,
  };
}
