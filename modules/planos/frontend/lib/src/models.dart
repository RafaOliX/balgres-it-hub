class Pin {
  final int id;
  final double x, y; // porcentaje 0-100
  final String kind;
  final String? label, assetTag, notes, ip, notaTitle;
  final int? notaId;
  final bool? isUp;
  const Pin({
    required this.id, required this.x, required this.y, required this.kind, this.label, this.assetTag,
    this.notes, this.ip, this.isUp, this.notaId, this.notaTitle,
  });
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
        notaId: j['nota_id'] as int?,
        notaTitle: j['nota_title'] as String?,
      );
}

/// Dibujo sobre el plano. points = [[x%, y%], ...]; width relativo a un lienzo de 1000 px.
class Trazo {
  final int id;
  final String kind, color; // kind: libre | flecha; color: #RRGGBB
  final double width;
  final List<List<double>> points;
  const Trazo({required this.id, required this.kind, required this.color, required this.width, required this.points});
  factory Trazo.fromJson(Map<String, dynamic> j) => Trazo(
        id: j['id'] as int,
        kind: (j['kind'] as String?) ?? 'libre',
        color: (j['color'] as String?) ?? '#E11D48',
        width: (j['width'] as num?)?.toDouble() ?? 4,
        points: ((j['points'] as List?) ?? const [])
            .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
      );
}

class NotaRef {
  final int id;
  final String title;
  const NotaRef(this.id, this.title);
  factory NotaRef.fromJson(Map<String, dynamic> j) => NotaRef(j['id'] as int, j['title'] as String);
}

class Plano {
  final int id;
  final String name, filename;
  final String? notes, notaTitle;
  final int? notaId;
  final int width, height, pinCount;
  final List<Pin> pins;
  final List<Trazo> trazos;
  final DateTime updatedAt;
  const Plano({
    required this.id, required this.name, required this.filename, this.notes, required this.width,
    required this.height, this.pinCount = 0, this.pins = const [], this.trazos = const [],
    this.notaId, this.notaTitle, required this.updatedAt,
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
        trazos: ((j['trazos'] as List?) ?? const []).map((e) => Trazo.fromJson(e as Map<String, dynamic>)).toList(),
        notaId: j['nota_id'] as int?,
        notaTitle: j['nota_title'] as String?,
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      );

  /// Mismo criterio que las fotos de inventario: Caddy sirve /uploads/.
  String get imageUrl => '/uploads/planos/$filename';
  double get aspect => (width > 0 && height > 0) ? width / height : 1.5;
}
