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
  final String? imagePath;

  const ItAsset({
    required this.id,
    required this.assetTag,
    required this.category,
    required this.brand,
    required this.model,
    required this.serialNumber,
    this.location,
    this.status,
    this.notes,
    this.imagePath,
  });

  factory ItAsset.fromJson(Map<String, dynamic> j) => ItAsset(
        id: j['id'] as int,
        assetTag: j['asset_tag'] as String,
        category: j['category'] as String,
        brand: j['brand'] as String,
        model: j['model'] as String,
        serialNumber: j['serial_number'] as String,
        location: j['location'] as String?,
        status: j['status'] as String?,
        notes: j['notes'] as String?,
        imagePath: j['image_path'] as String?,
      );

  /// URL pública de la imagen (relativa al host donde corre la app).
  String? get imageUrl => imagePath == null ? null : '/uploads/$imagePath';
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

  ItAssetCreate({
    required this.assetTag,
    required this.category,
    required this.brand,
    required this.model,
    required this.serialNumber,
    this.location,
    this.status,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'asset_tag': assetTag,
        'category': category,
        'brand': brand,
        'model': model,
        'serial_number': serialNumber,
        if (location != null && location!.isNotEmpty) 'location': location,
        if (status != null && status!.isNotEmpty) 'status': status,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}
