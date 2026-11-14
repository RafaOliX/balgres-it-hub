class Location {
  final int id;
  final String name;
  final int? parentId;
  final String? kind;
  final String fullName;
  const Location({required this.id, required this.name, this.parentId, this.kind, required this.fullName});
  factory Location.fromJson(Map<String, dynamic> j) => Location(
        id: j['id'] as int,
        name: j['name'] as String,
        parentId: j['parent_id'] as int?,
        kind: j['kind'] as String?,
        fullName: (j['full_name'] as String?) ?? (j['name'] as String),
      );
}

class Employee {
  final int id;
  final String name;
  final String? email, department, employeeCode, position, phone, extension, location, notes;
  final int? locationId;
  final bool active;
  final int assetCount;
  const Employee({
    required this.id, required this.name, this.email, this.department, this.employeeCode, this.position,
    this.phone, this.extension, this.locationId, this.location, this.notes, this.active = true, this.assetCount = 0,
  });
  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String?,
        department: j['department'] as String?,
        employeeCode: j['employee_code'] as String?,
        position: j['position'] as String?,
        phone: j['phone'] as String?,
        extension: j['extension'] as String?,
        locationId: j['location_id'] as int?,
        location: j['location'] as String?,
        notes: j['notes'] as String?,
        active: j['active'] as bool? ?? true,
        assetCount: (j['asset_count'] as num?)?.toInt() ?? 0,
      );
}
