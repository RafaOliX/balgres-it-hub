import 'package:balgres_it_tickets/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ticket.fromJson y toBody conservan los campos', () {
    final t = Ticket.fromJson({
      'id': 12, 'title': 'PC lenta', 'status': 'En curso', 'priority': 'Alta', 'asset_tag': 'PC-001',
      'assignee': 'luis', 'due_date': '2026-11-20', 'created_by': 'admin', 'vencido': true,
      'created_at': '2026-11-16T10:00:00Z', 'updated_at': '2026-11-16T11:00:00Z',
    });
    expect(t.code, 'T-0012');
    expect(t.overdue, isTrue);
    expect(t.toBody({'status': 'Resuelto'})['status'], 'Resuelto');
    expect(t.toBody()['due_date'], '2026-11-20');
    expect(t.isClosed, isFalse);
  });
}
