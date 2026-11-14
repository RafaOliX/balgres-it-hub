export 'package:balgres_it_contacts/balgres_it_contacts.dart' show Employee, Location;

class Assignment {
  final int id;
  final int? employeeId;
  final String employeeName;
  final DateTime assignedAt;
  final DateTime? returnedAt;
  final String deliveredBy;
  final String? notes;
  final String? returnNotes;
  const Assignment({
    required this.id, this.employeeId, required this.employeeName, required this.assignedAt,
    this.returnedAt, required this.deliveredBy, this.notes, this.returnNotes,
  });
  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        id: j['id'] as int,
        employeeId: j['employee_id'] as int?,
        employeeName: j['employee_name'] as String,
        assignedAt: DateTime.parse(j['assigned_at'] as String).toLocal(),
        returnedAt: j['returned_at'] == null ? null : DateTime.parse(j['returned_at'] as String).toLocal(),
        deliveredBy: (j['delivered_by'] as String?) ?? '',
        notes: j['notes'] as String?,
        returnNotes: j['return_notes'] as String?,
      );
}


// ---- plantillas de acta (las claves deben coincidir con backend/actas.py)
const kActaEmployeeFields = <(String, String)>[
  ('name', 'Nombre'), ('employee_code', 'Código / ID'), ('position', 'Cargo'), ('department', 'Departamento'),
  ('email', 'Correo'), ('phone', 'Teléfono'), ('extension', 'Extensión'), ('location', 'Sede / ubicación'),
];

const kActaAssetColumns = <(String, String)>[
  ('tag', 'Tag'), ('equipo', 'Equipo (categoría, marca, modelo)'), ('category', 'Categoría'), ('brand', 'Marca'),
  ('model', 'Modelo'), ('serial', 'S/N'), ('quantity', 'Cantidad'), ('status', 'Estado'), ('location', 'Ubicación'),
  ('specs', 'Datos técnicos'), ('notes', 'Notas'),
];

class ActaTemplate {
  final int id;
  final String name;
  final Map<String, dynamic> config;
  const ActaTemplate({required this.id, required this.name, required this.config});
  factory ActaTemplate.fromJson(Map<String, dynamic> j) =>
      ActaTemplate(id: j['id'] as int, name: j['name'] as String, config: Map<String, dynamic>.from(j['config'] as Map? ?? {}));
  List<String> get employeeFields => List<String>.from(config['employee_fields'] as List? ?? const []);
  List<String> get assetColumns => List<String>.from(config['asset_columns'] as List? ?? const []);
  String get title => (config['title'] as String?) ?? '';
}
