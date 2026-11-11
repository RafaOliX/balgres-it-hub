import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../models/it_asset.dart';
import '../ui/swiss.dart';
import 'asset_thumbnail.dart';

/// Abre el detalle y recarga la lista al volver.
Future<void> openAsset(BuildContext context, String tag) async {
  final container = ProviderScope.containerOf(context);
  await context.push('/inventario/detalle/$tag');
  container.invalidate(inventarioListProvider);
}

/// Abre el alta y recarga la lista al volver (incluye borradores autoguardados).
Future<void> openNewAsset(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await context.push('/inventario/nuevo');
  container.invalidate(inventarioListProvider);
}

class AssetCard extends StatelessWidget {
  final ItAsset asset;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggle;
  const AssetCard({super.key, required this.asset, this.selected = false, this.selectionMode = false, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardDeco(context, radius: 14, color: selected ? Color.alphaBlend(c.accent.withValues(alpha: 0.09), c.bg) : null),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: selectionMode ? onToggle : () => openAsset(context, asset.assetTag),
          onLongPress: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selectionMode)
                Padding(padding: const EdgeInsets.only(right: 10, top: 12), child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? c.accent : c.edge)),
              AssetThumbnail(asset: asset, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(asset.assetTag, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: asset.isDraft ? c.muted : c.ink))),
                    StatusTag(status: asset.status, draft: asset.isDraft),
                  ]),
                  const SizedBox(height: 4),
                  Text('${asset.brand} ${asset.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${asset.category} · ${asset.serialNumber ?? 'Sin S/N'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                  if (asset.location != null || asset.assignedTo != null) ...[
                    const SizedBox(height: 2),
                    Text([asset.location, asset.assignedTo].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
