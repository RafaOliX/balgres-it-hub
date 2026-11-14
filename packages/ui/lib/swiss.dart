import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ====================================================================== marca
const kBrandNavy = Color(0xFF010080);
const kBrandCyan = Color(0xFF019FE6);
const kBrandCoral = Color(0xFFF26B3A); // auxiliar: solo para alertas / "retirados"
const kDefaultAccent = kBrandNavy;
const kRadius = 12.0;
const kCardRadius = 16.0;

Color _l(Color a, Color b, double t) => Color.lerp(a, b, t)!;

@immutable
class SwissColors extends ThemeExtension<SwissColors> {
  final Color page, bg, panel, ink, muted, line, edge, accent, accent2, ok, warn, bad;
  const SwissColors({
    required this.page, required this.bg, required this.panel, required this.ink, required this.muted,
    required this.line, required this.edge, required this.accent, required this.accent2,
    required this.ok, required this.warn, required this.bad,
  });

  // bg = superficie de las tarjetas; page = fondo de la app
  static const light = SwissColors(
    page: Color(0xFFEBEFF7), bg: Color(0xFFFFFFFF), panel: Color(0xFFF3F5FA), ink: Color(0xFF0B1020),
    muted: Color(0xFF5B6478), line: Color(0xFFE2E7F1), edge: Color(0xFFC9D1E1),
    accent: kBrandNavy, accent2: kBrandCyan,
    ok: Color(0xFF0E9F6E), warn: Color(0xFFD97706), bad: Color(0xFFDC2626),
  );

  static const dark = SwissColors(
    page: Color(0xFF0A0E1A), bg: Color(0xFF131A2B), panel: Color(0xFF1A2236), ink: Color(0xFFEEF1F8),
    muted: Color(0xFF98A2B8), line: Color(0xFF232C44), edge: Color(0xFF34405E),
    accent: kBrandCyan, accent2: Color(0xFF3DB8F5),
    ok: Color(0xFF34D399), warn: Color(0xFFFBBF24), bad: Color(0xFFF87171),
  );

  @override
  SwissColors copyWith({
    Color? page, Color? bg, Color? panel, Color? ink, Color? muted, Color? line, Color? edge,
    Color? accent, Color? accent2, Color? ok, Color? warn, Color? bad,
  }) =>
      SwissColors(
        page: page ?? this.page, bg: bg ?? this.bg, panel: panel ?? this.panel, ink: ink ?? this.ink,
        muted: muted ?? this.muted, line: line ?? this.line, edge: edge ?? this.edge,
        accent: accent ?? this.accent, accent2: accent2 ?? this.accent2,
        ok: ok ?? this.ok, warn: warn ?? this.warn, bad: bad ?? this.bad,
      );

  @override
  SwissColors lerp(ThemeExtension<SwissColors>? other, double t) {
    if (other is! SwissColors) return this;
    return SwissColors(
      page: _l(page, other.page, t), bg: _l(bg, other.bg, t), panel: _l(panel, other.panel, t),
      ink: _l(ink, other.ink, t), muted: _l(muted, other.muted, t), line: _l(line, other.line, t),
      edge: _l(edge, other.edge, t), accent: _l(accent, other.accent, t), accent2: _l(accent2, other.accent2, t),
      ok: _l(ok, other.ok, t), warn: _l(warn, other.warn, t), bad: _l(bad, other.bad, t),
    );
  }
}

extension SwissContext on BuildContext {
  SwissColors get sw => Theme.of(this).extension<SwissColors>() ?? SwissColors.light;
}

// ====================================================================== profundidad
List<BoxShadow> softShadow(BuildContext context, {double elevation = 1}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (dark) {
    return [BoxShadow(color: const Color(0x66000000), blurRadius: 24 * elevation, offset: Offset(0, 8 * elevation))];
  }
  return [
    const BoxShadow(color: Color(0x0F0B1020), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: const Color(0x160B1020), blurRadius: 28 * elevation, offset: Offset(0, 10 * elevation)),
  ];
}

BoxDecoration cardDeco(BuildContext context, {double radius = kCardRadius, Color? color, bool shadow = true}) {
  final c = context.sw;
  return BoxDecoration(
    color: color ?? c.bg,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: c.line),
    boxShadow: shadow ? softShadow(context) : null,
  );
}

// ====================================================================== tema
Color _liftForDark(Color c) => Color.lerp(c, Colors.white, c.computeLuminance() < 0.2 ? 0.45 : 0.18)!;

ThemeData buildSwissTheme(Brightness b, [Color? accentColor]) {
  final dark = b == Brightness.dark;
  final isDefault = accentColor == null || accentColor.toARGB32() == kDefaultAccent.toARGB32();
  final accent = dark ? (isDefault ? kBrandCyan : _liftForDark(accentColor!)) : (accentColor ?? kDefaultAccent);
  final c = (dark ? SwissColors.dark : SwissColors.light).copyWith(accent: accent);
  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : const Color(0xFF0A0A0A);
  final r = BorderRadius.circular(kRadius);

  OutlineInputBorder ob(Color col, [double w = 1]) => OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: col, width: w));

  final scheme = ColorScheme(
    brightness: b,
    primary: accent, onPrimary: onAccent,
    secondary: c.accent2, onSecondary: Colors.white,
    error: c.bad, onError: Colors.white,
    surface: c.bg, onSurface: c.ink,
    surfaceContainerHighest: c.panel,
    primaryContainer: accent.withValues(alpha: 0.14), onPrimaryContainer: c.ink,
    secondaryContainer: accent.withValues(alpha: 0.14), onSecondaryContainer: c.ink,
    outline: c.edge, outlineVariant: c.line,
  );

  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.page,
    canvasColor: c.bg,
    dividerColor: c.line,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Helvetica Neue', 'Helvetica', 'Arial', 'Roboto'],
    hoverColor: accent.withValues(alpha: 0.05),
    highlightColor: Colors.transparent,
    splashColor: accent.withValues(alpha: 0.08),
    extensions: [c],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    iconTheme: IconThemeData(color: c.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg, foregroundColor: c.ink, elevation: 0, scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent, centerTitle: false,
      shape: Border(bottom: BorderSide(color: c.line)),
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.ink),
    ),
    cardTheme: CardThemeData(
      color: c.bg, elevation: 0, margin: EdgeInsets.zero, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kCardRadius), side: BorderSide(color: c.line)),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true, filled: true, fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: ob(c.line), enabledBorder: ob(c.line), focusedBorder: ob(accent, 1.6),
      errorBorder: ob(c.bad), focusedErrorBorder: ob(c.bad, 1.6), disabledBorder: ob(c.line),
      labelStyle: TextStyle(color: c.muted), floatingLabelStyle: TextStyle(color: accent), hintStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent, foregroundColor: onAccent, minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20), elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: r),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink, backgroundColor: c.bg, side: BorderSide(color: c.edge), minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: r),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent, shape: RoundedRectangleBorder(borderRadius: r),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent, foregroundColor: onAccent, elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.bg, selectedColor: accent.withValues(alpha: 0.14), side: BorderSide(color: c.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), checkmarkColor: accent, deleteIconColor: c.muted,
      labelStyle: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w500),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent, unselectedLabelColor: c.muted, indicatorColor: accent,
      indicatorSize: TabBarIndicatorSize.tab, dividerColor: c.line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.bg, surfaceTintColor: Colors.transparent, elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.bg, modalBackgroundColor: c.bg, surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.bg, surfaceTintColor: Colors.transparent, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: c.line)),
      textStyle: TextStyle(color: c.ink, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? c.panel : c.ink, contentTextStyle: TextStyle(color: dark ? c.ink : c.bg),
      behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: r),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: c.bg, fontSize: 12),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: c.edge, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(onAccent),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent, indicatorColor: accent.withValues(alpha: 0.14),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selectedIconTheme: IconThemeData(color: accent), unselectedIconTheme: IconThemeData(color: c.muted),
      selectedLabelTextStyle: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelTextStyle: TextStyle(color: c.muted, fontWeight: FontWeight.w500, fontSize: 11),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg, surfaceTintColor: Colors.transparent, indicatorColor: accent.withValues(alpha: 0.14),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), height: 66, elevation: 8,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((s) => TextStyle(
            fontSize: 11, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? accent : c.muted)),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : c.muted)),
    ),
  );
}

// ====================================================================== modo claro/oscuro
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }
  static const _key = 'theme_mode';

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      state = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, m.name);
    } catch (_) {}
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());

// ====================================================================== acento y apariencia
const accentOptions = <(String, Color)>[
  ('Balgres azul', kBrandNavy),
  ('Balgres cian', kBrandCyan),
  ('Petróleo', Color(0xFF0F766E)),
  ('Ámbar', Color(0xFFD97706)),
  ('Bosque', Color(0xFF166534)),
  ('Burdeos', Color(0xFF9F1239)),
  ('Grafito', Color(0xFF27272A)),
];

class AccentNotifier extends StateNotifier<Color> {
  AccentNotifier() : super(kDefaultAccent) {
    _load();
  }
  static const _key = 'accent_color';

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getInt(_key);
      if (v != null) state = Color(v);
    } catch (_) {}
  }

  Future<void> set(Color c) async {
    state = c;
    try {
      await (await SharedPreferences.getInstance()).setInt(_key, c.toARGB32());
    } catch (_) {}
  }
}

final accentProvider = StateNotifierProvider<AccentNotifier, Color>((ref) => AccentNotifier());

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Apariencia',
        icon: const Icon(Icons.palette_outlined),
        onPressed: () => showDialog(context: context, builder: (_) => const _AppearanceDialog()),
      );
}

class _AppearanceDialog extends ConsumerStatefulWidget {
  const _AppearanceDialog();
  @override
  ConsumerState<_AppearanceDialog> createState() => _AppearanceDialogState();
}

class _AppearanceDialogState extends ConsumerState<_AppearanceDialog> {
  final _hex = TextEditingController();
  String? _hexError;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyHex() {
    final t = _hex.text.trim().replaceAll('#', '');
    final v = t.length == 6 ? int.tryParse('FF$t', radix: 16) : null;
    if (v == null) {
      setState(() => _hexError = 'Usa 6 dígitos, ej: 010080');
      return;
    }
    setState(() => _hexError = null);
    ref.read(accentProvider.notifier).set(Color(v));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final mode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentProvider);

    return AlertDialog(
      title: const Text('Apariencia'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const SectionLabel('Tema'),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Color de acento'),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final o in accentOptions)
                Tooltip(
                  message: o.$1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ref.read(accentProvider.notifier).set(o.$2),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: o.$2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.toARGB32() == o.$2.toARGB32() ? c.ink : c.line,
                          width: accent.toARGB32() == o.$2.toARGB32() ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  controller: _hex,
                  onSubmitted: (_) => _applyHex(),
                  decoration: InputDecoration(labelText: 'Color propio (hex)', hintText: '010080', prefixText: '# ', errorText: _hexError),
                ),
              ),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 2), child: FilledButton(onPressed: _applyHex, child: const Text('Aplicar'))),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => ref.read(accentProvider.notifier).set(kDefaultAccent), child: const Text('Restablecer')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}

// ====================================================================== componentes
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: context.sw.muted),
      );
}

/// Tarjeta con título y marca de color.
class SwissSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const SwissSection(this.title, this.children, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(22),
      decoration: cardDeco(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 14, decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: SectionLabel(title)),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }
}

/// Fila etiqueta / valor con línea fina.
class Kv extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  const Kv(this.label, this.value, {super.key}) : child = null;
  const Kv.widget(this.label, this.child, {super.key}) : value = null;

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 13, color: c.muted))),
        Expanded(child: child ?? Text(value ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

class StatusTag extends StatelessWidget {
  final String? status;
  final bool draft;
  const StatusTag({super.key, this.status, this.draft = false});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final (label, col) = draft
        ? ('Borrador', c.muted)
        : switch (status) {
            'Operativo' => ('Operativo', c.ok),
            'En Revisión' => ('En Revisión', c.warn),
            'Retirado' => ('Retirado', c.bad),
            _ => (status ?? '—', c.muted),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: col)),
        ),
      ]),
    );
  }
}

class KpiTile extends StatelessWidget {
  final String label, value;
  final Color? color;
  final IconData? icon;
  const KpiTile(this.label, this.value, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final col = color ?? c.accent;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDeco(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: col.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: col),
          ),
        if (icon != null) const SizedBox(height: 14),
        Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1, color: color ?? c.ink)),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
    );
  }
}

/// Tarjeta de color con círculos translúcidos y barra de progreso.
class HeroCard extends StatelessWidget {
  final String title, value, caption;
  final double progress;
  final Color color;
  final IconData icon;
  const HeroCard({super.key, required this.title, required this.value, required this.caption, required this.progress, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 158,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: Stack(children: [
        Positioned(right: -34, top: -34, child: Container(width: 130, height: 130, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle))),
        Positioned(right: 34, bottom: -56, child: Container(width: 110, height: 110, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
            ]),
            const Spacer(),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 6, backgroundColor: Colors.white.withValues(alpha: 0.28), valueColor: const AlwaysStoppedAnimation(Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Text(caption, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: c.accent),
        ),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: TextStyle(color: c.muted))),
        if (action != null) ...[const SizedBox(height: 16), FilledButton(onPressed: onAction, child: Text(action!))],
      ]),
    );
  }
}
