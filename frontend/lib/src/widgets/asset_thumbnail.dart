import 'package:flutter/material.dart';

import '../models/it_asset.dart';
import '../ui/swiss.dart';

class AssetThumbnail extends StatelessWidget {
  final ItAsset asset;
  final double size;
  const AssetThumbnail({super.key, required this.asset, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    Widget placeholder() => Container(
          color: c.panel,
          child: Icon(Icons.inventory_2_outlined, size: size * 0.45, color: c.muted),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: size,
        height: size,
        child: asset.imageUrl != null
            ? Image.network(asset.imageUrl!, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => placeholder())
            : placeholder(),
      ),
    );
  }
}
