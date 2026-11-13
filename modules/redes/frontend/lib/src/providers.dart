import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'models.dart';

final redesApiProvider = Provider<RedesApi>((ref) {
  throw UnimplementedError('Debe override desde apps/shell');
});

final ipsProvider = FutureProvider.autoDispose<List<IpEntry>>((ref) => ref.watch(redesApiProvider).getIps());

final subnetsProvider = FutureProvider.autoDispose<List<Subnet>>((ref) => ref.watch(redesApiProvider).getSubnets());
