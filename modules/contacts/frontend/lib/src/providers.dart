import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'extensions.dart';
import 'models.dart';

final contactsApiProvider = Provider<ContactsApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

/// Extensiones registradas por otros módulos (el shell las inyecta).
final employeeExtensionsProvider = Provider<List<EmployeeExtension>>((ref) => const []);

final empleadosProvider = FutureProvider.autoDispose<List<Employee>>((ref) async {
  return ref.watch(contactsApiProvider).getEmpleados();
});

final contactLocationsProvider = FutureProvider.autoDispose<List<Location>>((ref) async {
  return ref.watch(contactsApiProvider).getUbicaciones();
});
