class Pin {
  final int id;
  final double x, y; // porcentaje 0-100
  final String kind;
  final String? label, assetTag, notes, ip;
  final bool? isUp;
  const Pin({required this.id, required this.x, required this.y, required this.kind, this.label, this.assetTag, this.notes, this.ip, this.isUp});
  factory Pin.fromJson(Map<String, dynamic> j) => Pin(
        id: j['id'] as int,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        kind: (j['kind'] as String?) ?? 'otro',
        label: j['label'] as String?,
        assetTag: j['asset_tag'] as String?,
        notes: j['notes'] as String?,
        ip: j['ip'] as String?,
        isUp: j['is_up'] as bool?,
      );
}

class Plano {
  final int id;
  final String name, filename;
  final String? notes;
  final int width, height, pinCount;
  final List<Pin> pins;
  final DateTime updatedAt;
  const Plano({
    required this.id, required this.name, required this.filename, this.notes, required this.width,
    required this.height, this.pinCount = 0, this.pins = const [], required this.updatedAt,
  });
  factory Plano.fromJson(Map<String, dynamic> j) => Plano(
        id: j['id'] as int,
        name: j['name'] as String,
        filename: j['filename'] as String,
        notes: j['notes'] as String?,
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        pinCount: (j['pin_count'] as num?)?.toInt() ?? 0,
        pins: ((j['pins'] as List?) ?? const []).map((e) => Pin.fromJson(e as Map<String, dynamic>)).toList(),
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      );

  /// Mismo criterio que las fotos de inventario: Caddy sirve /uploads/.
  String get imageUrl => '/uploads/planos/$filename';
  double get aspect => (width > 0 && height > 0) ? width / height : 1.5;
}
