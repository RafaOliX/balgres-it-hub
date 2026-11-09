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
  final String? email;
  final String? department;
  final bool active;
  const Employee({required this.id, required this.name, this.email, this.department, this.active = true});
  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String?,
        department: j['department'] as String?,
        active: j['active'] as bool? ?? true,
      );
}

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
