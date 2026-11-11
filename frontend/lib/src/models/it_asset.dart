String? dateToApi(DateTime? d) => d == null ? null : d.toIso8601String().substring(0, 10);

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
  final int? locationId;
  final String? status;
  final String? notes;
  final List<ItAssetImage> images;
  final int quantity;
  final String unit;
  final String? assignedTo;
  final int? employeeId;
  final DateTime createdAt;
  final bool isDraft;
  final Map<String, String> specs;
  final DateTime? deletedAt;

  const ItAsset({
    required this.id, required this.assetTag, required this.category, this.categoryId,
    required this.brand, required this.model, this.serialNumber, this.location, this.locationId,
    this.status, this.notes, this.images = const [], this.quantity = 1, this.unit = 'Unidad',
    this.assignedTo, this.employeeId, required this.createdAt, this.isDraft = false,
    this.specs = const {}, this.deletedAt,
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
        locationId: j['location_id'] as int?,
        status: j['status'] as String?,
        notes: j['notes'] as String?,
        quantity: j['quantity'] as int? ?? 1,
        unit: j['unit'] as String? ?? 'Unidad',
        assignedTo: j['assigned_to'] as String?,
        employeeId: j['employee_id'] as int?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        isDraft: j['is_draft'] as bool? ?? false,
        images: ((j['images'] as List<dynamic>?) ?? []).map((e) => ItAssetImage.fromJson(e as Map<String, dynamic>)).toList(),
        specs: ((j['specs'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(k, v?.toString() ?? '')),
        deletedAt: j['deleted_at'] == null ? null : DateTime.parse(j['deleted_at'] as String).toLocal(),
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
  final int? locationId;
  final String? status;
  final String? notes;
  final int quantity;
  final String unit;
  final bool isDraft;
  final Map<String, String> specs;

  ItAssetCreate({
    required this.assetTag, required this.category, this.categoryId,
    required this.brand, required this.model, this.serialNumber, this.locationId,
    this.status, this.notes, this.quantity = 1, this.unit = 'Unidad', this.isDraft = false,
    this.specs = const {},
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'asset_tag': assetTag, 'category': category, 'category_id': categoryId,
      'brand': brand, 'model': model, 'quantity': quantity, 'unit': unit, 'is_draft': isDraft,
      'location_id': locationId, 'specs': specs.isEmpty ? null : specs,
    };
    if (serialNumber != null && serialNumber!.trim().isNotEmpty) map['serial_number'] = serialNumber;
    if (status != null && status!.isNotEmpty) map['status'] = status;
    if (notes != null && notes!.trim().isNotEmpty) map['notes'] = notes;
    return map;
  }
}
