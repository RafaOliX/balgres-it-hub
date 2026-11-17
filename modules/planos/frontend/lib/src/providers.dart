import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'models.dart';

final planosApiProvider = Provider<PlanosApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

final planosProvider = FutureProvider.autoDispose<List<Plano>>((ref) => ref.watch(planosApiProvider).listar());
