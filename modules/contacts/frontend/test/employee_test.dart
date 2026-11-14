import 'package:balgres_it_contacts/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Employee.fromJson lee los campos y asset_count', () {
    final e = Employee.fromJson({'id': 1, 'name': 'Ana', 'extension': '204', 'asset_count': 3, 'active': false});
    expect(e.name, 'Ana');
    expect(e.extension, '204');
    expect(e.assetCount, 3);
    expect(e.active, isFalse);
  });

  test('Location.fullName cae en name', () {
    expect(Location.fromJson({'id': 1, 'name': 'Sede'}).fullName, 'Sede');
  });
}
