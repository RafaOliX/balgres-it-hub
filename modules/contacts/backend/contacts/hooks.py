"""Puntos de extensión: otros módulos (inventario) los reemplazan al importarse.

Por defecto no hacen nada, así contacts funciona solo y no importa a nadie.
"""


class _Hooks:
    def __init__(self) -> None:
        # {employee_id: n} de equipos asignados; con emp_id filtra a ese empleado
        self.asset_counts = lambda session, emp_id=None: {}
        # equipos vigentes asignados al empleado (bloquea inactivarlo)
        self.open_assets = lambda session, emp_id: 0
        # True si tiene historial de custodia (bloquea eliminarlo)
        self.has_history = lambda session, emp_id: False
        # se llama al renombrar, antes del commit
        self.renamed = lambda session, emp_id, name: None


hooks = _Hooks()
