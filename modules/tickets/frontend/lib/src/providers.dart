import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'models.dart';

final ticketsApiProvider = Provider<TicketsApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

final ticketsQueryProvider = StateProvider<String>((ref) => '');

/// 'abiertos' (por defecto), 'todos' o uno de kStatuses.
final ticketsStatusProvider = StateProvider<String>((ref) => 'abiertos');
final ticketsPriorityProvider = StateProvider<String?>((ref) => null);
final ticketsMineProvider = StateProvider<bool>((ref) => false);

final ticketsProvider = FutureProvider.autoDispose<List<Ticket>>((ref) {
  final st = ref.watch(ticketsStatusProvider);
  return ref.watch(ticketsApiProvider).listar(
        q: ref.watch(ticketsQueryProvider),
        status: kStatuses.contains(st) ? st : null,
        abiertos: st == 'abiertos',
        priority: ref.watch(ticketsPriorityProvider),
        mios: ref.watch(ticketsMineProvider),
      );
});

final ticketsResumenProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(ticketsApiProvider).resumen());

final ticketsUsersProvider = FutureProvider.autoDispose<List<TicketUser>>((ref) => ref.watch(ticketsApiProvider).usuarios());
