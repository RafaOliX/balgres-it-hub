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
  final String brand;
  final String model;
  final String serialNumber;
  final String? location;
  final String? status;
  final String? notes;
  final List<ItAssetImage> images;
  final int quantity;
  final String unit;
  final String? assignedTo;

  const ItAsset({
    required this.id, required this.assetTag, required this.category,
    required this.brand, required this.model, required this.serialNumber,
    this.location, this.status, this.notes, this.images = const [],
    this.quantity = 1, this.unit = 'Unidad', this.assignedTo,
  });

  factory ItAsset.fromJson(Map<String, dynamic> j) => ItAsset(
        id: j['id'] as int,
        assetTag: j['asset_tag'] as String,
        category: j['category'] as String,
        brand: j['brand'] as String,
        model: j['model'] as String,
        serialNumber: j['serial_number'] ?? '',
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
  final String brand;
  final String model;
  final String serialNumber;
  final String? location;
  final String? status;
  final String? notes;
  final int quantity;
  final String unit;
  final String? assignedTo;

  ItAssetCreate({
    required this.assetTag, required this.category, required this.brand,
    required this.model, required this.serialNumber, this.location,
    this.status, this.notes, this.quantity = 1, this.unit = 'Unidad', this.assignedTo,
  });

  Map<String, dynamic> toJson() => {
        'asset_tag': assetTag, 'category': category, 'brand': brand,
        'model': model, 'serial_number': serialNumber,
        if (location != null && location!.isNotEmpty) 'location': location,
        if (status != null && status!.isNotEmpty) 'status': status,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (assignedTo != null && assignedTo!.isNotEmpty) 'assigned_to': assignedTo,
        'quantity': quantity, 'unit': unit,
      };
}
