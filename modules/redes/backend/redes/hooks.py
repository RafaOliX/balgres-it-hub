"""Puntos de extensión de redes: inventario los registra al importarse (redes no importa inventario)."""


class _Hooks:
    def __init__(self) -> None:
        # Activos vivos (no eliminados, borradores incluidos). Cada uno expone
        # .id .asset_tag .category .brand .model .specs .is_draft
        self.assets = lambda session: []


hooks = _Hooks()
