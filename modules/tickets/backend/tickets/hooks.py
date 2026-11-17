"""Puntos de extensión de tickets: core-api los registra al arrancar (tickets no importa auth)."""


class _Hooks:
    def __init__(self) -> None:
        # Usuarios activos que pueden ser responsables: [{"username", "full_name"}]
        self.users = lambda session: []


hooks = _Hooks()
