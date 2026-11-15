import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'models.dart';

final notasApiProvider = Provider<NotasApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

final notasQueryProvider = StateProvider<String>((ref) => '');
final notasTagProvider = StateProvider<String?>((ref) => null);

final notasProvider = FutureProvider.autoDispose<List<Nota>>((ref) {
  final q = ref.watch(notasQueryProvider);
  final tag = ref.watch(notasTagProvider);
  return ref.watch(notasApiProvider).listar(q: q, tag: tag);
});

final notasTagsProvider = FutureProvider.autoDispose<List<TagCount>>((ref) => ref.watch(notasApiProvider).getTags());
