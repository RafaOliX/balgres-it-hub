import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

/// Contexto que contacts le pasa a las extensiones de otros módulos.
class EmployeeCtx {
  final Employee employee;
  final VoidCallback reload; // recarga los datos del empleado en la ficha
  const EmployeeCtx(this.employee, this.reload);
}

class EmployeeMenuEntry {
  final String label;
  final Future<void> Function(BuildContext context, WidgetRef ref) onSelected;
  const EmployeeMenuEntry(this.label, this.onSelected);
}

/// Punto de extensión (estilo Odoo): otros módulos añaden menú, botones y secciones
/// a la lista y a la ficha de empleados sin que contacts los conozca.
class EmployeeExtension {
  final List<EmployeeMenuEntry> menu;
  final List<Widget> Function(BuildContext context, EmployeeCtx ctx)? appBarActions;
  final List<Widget> Function(BuildContext context, EmployeeCtx ctx)? actions;
  final Widget Function(BuildContext context, EmployeeCtx ctx)? body;
  final void Function(WidgetRef ref)? onChanged; // tras editar un empleado

  const EmployeeExtension({this.menu = const [], this.appBarActions, this.actions, this.body, this.onChanged});
}
