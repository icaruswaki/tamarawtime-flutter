import 'package:flutter/material.dart';

import 'responsive.dart';

/// Color tokens translated from migration_source/styles.css (including v7 themes).
class TamarawPalette {
  const TamarawPalette({
    required this.name,
    required this.forest,
    required this.green,
    required this.yellow,
    required this.paper,
    required this.muted,
    required this.border,
    required this.heroEnd,
    required this.surface,
    required this.soft,
    required this.highlight,
    required this.link,
    required this.ink,
    this.dark = false,
  });
  final String name;
  final Color forest,
      green,
      yellow,
      paper,
      muted,
      border,
      heroEnd,
      surface,
      soft,
      highlight,
      link,
      ink;
  final bool dark;
  Color get sidebar => dark ? const Color(0xff18253a) : forest;
  Color get primary => dark ? const Color(0xff456c86) : forest;
  Color get accent => dark ? const Color(0xff2f4566) : forest;
  Color get heroStart => dark ? const Color(0xff243b5c) : forest;
  Color get heroFinish => dark ? const Color(0xff38517c) : heroEnd;
  Color get onAccent => dark ? const Color(0xff14243c) : forest;
  static const themes = <String, TamarawPalette>{
    'forest': TamarawPalette(
      name: 'FEU Forest',
      forest: Color(0xff17643d),
      green: Color(0xffc5e8d2),
      yellow: Color(0xffe9c95e),
      paper: Color(0xfff5f7f5),
      muted: Color(0xff596d61),
      border: Color(0xffe1e8e2),
      heroEnd: Color(0xff245c46),
      surface: Colors.white,
      soft: Color(0xffeaf4ed),
      highlight: Color(0xfff8efd4),
      link: Color(0xff246d50),
      ink: Color(0xff172b20),
    ),
    'ocean': TamarawPalette(
      name: 'Coastal Blue',
      forest: Color(0xff133e67),
      green: Color(0xff79c8e1),
      yellow: Color(0xffffda74),
      paper: Color(0xfff0f7fb),
      muted: Color(0xff57768d),
      border: Color(0xffd6e8f2),
      heroEnd: Color(0xff28789a),
      surface: Colors.white,
      soft: Color(0xffe9f4fa),
      highlight: Color(0xffe8f6fe),
      link: Color(0xff166995),
      ink: Color(0xff133e67),
    ),
    'sunset': TamarawPalette(
      name: 'Golden Hour',
      forest: Color(0xff612c3a),
      green: Color(0xffffd0a5),
      yellow: Color(0xffffc06e),
      paper: Color(0xfffff6f0),
      muted: Color(0xff846976),
      border: Color(0xfff0dfd7),
      heroEnd: Color(0xffab5362),
      surface: Colors.white,
      soft: Color(0xfffff0e9),
      highlight: Color(0xfffff0d6),
      link: Color(0xff95475b),
      ink: Color(0xff612c3a),
    ),
    'night': TamarawPalette(
      name: 'Midnight',
      forest: Color(0xffcadcf4),
      green: Color(0xff6de3c8),
      yellow: Color(0xfff8d27a),
      paper: Color(0xff101a2a),
      muted: Color(0xff9fb0c6),
      border: Color(0xff3b4c63),
      heroEnd: Color(0xff30476f),
      surface: Color(0xff1d2b42),
      soft: Color(0xff26374f),
      highlight: Color(0xff354159),
      link: Color(0xff83dcc9),
      ink: Color(0xffe7f1ff),
      dark: true,
    ),
  };
  static TamarawPalette of(BuildContext context) =>
      Theme.of(context).extension<TamarawStyle>()!.palette;
}

class TamarawStyle extends ThemeExtension<TamarawStyle> {
  const TamarawStyle(this.palette);
  final TamarawPalette palette;
  @override
  TamarawStyle copyWith({TamarawPalette? palette}) =>
      TamarawStyle(palette ?? this.palette);
  @override
  TamarawStyle lerp(covariant TamarawStyle? other, double t) => other == null
      ? this
      : TamarawStyle(
          TamarawPalette(
            name: t < .5 ? palette.name : other.palette.name,
            dark: t < .5 ? palette.dark : other.palette.dark,
            forest: Color.lerp(palette.forest, other.palette.forest, t)!,
            green: Color.lerp(palette.green, other.palette.green, t)!,
            yellow: Color.lerp(palette.yellow, other.palette.yellow, t)!,
            paper: Color.lerp(palette.paper, other.palette.paper, t)!,
            muted: Color.lerp(palette.muted, other.palette.muted, t)!,
            border: Color.lerp(palette.border, other.palette.border, t)!,
            heroEnd: Color.lerp(palette.heroEnd, other.palette.heroEnd, t)!,
            surface: Color.lerp(palette.surface, other.palette.surface, t)!,
            soft: Color.lerp(palette.soft, other.palette.soft, t)!,
            highlight: Color.lerp(
              palette.highlight,
              other.palette.highlight,
              t,
            )!,
            link: Color.lerp(palette.link, other.palette.link, t)!,
            ink: Color.lerp(palette.ink, other.palette.ink, t)!,
          ),
        );
}

ThemeData tamarawTheme(String name) {
  final p = TamarawPalette.themes[name] ?? TamarawPalette.themes['forest']!;
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
  );
  final text = base.textTheme
      .apply(bodyColor: p.ink, displayColor: p.ink)
      .copyWith(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: p.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
          color: p.ink,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
          color: p.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: p.ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: p.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: p.ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: p.link,
        ),
      )
      .apply(fontFamily: base.textTheme.bodyMedium?.fontFamily);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: p.border),
  );
  return base.copyWith(
    extensions: [TamarawStyle(p)],
    textTheme: text,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.forest,
          brightness: p.dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: p.primary,
          onPrimary: Colors.white,
          secondary: p.green,
          onSecondary: p.onAccent,
          surface: p.surface,
          onSurface: p.ink,
          onSurfaceVariant: p.muted,
          primaryContainer: p.soft,
          onPrimaryContainer: p.ink,
          outline: p.border,
        ),
    scaffoldBackgroundColor: p.paper,
    dividerColor: p.border,
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x14143525),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: p.border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: p.green, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: p.muted,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: p.soft,
        foregroundColor: p.ink,
        side: BorderSide(color: p.border),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.link,
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.soft,
      labelStyle: text.bodySmall?.copyWith(color: p.ink),
      side: BorderSide(color: p.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      titleTextStyle: text.headlineMedium,
      contentTextStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.sidebar,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      iconColor: p.link,
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodySmall,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.soft,
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected) ? p.link : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? p.link : p.muted,
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.sidebar,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

class TamarawLogo extends StatelessWidget {
  const TamarawLogo({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Image.asset(
      'assets/images/tamaraw-logo.png',
      fit: BoxFit.contain,
      semanticLabel: 'Tamaraw Time logo',
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.inverse = false, this.compact = false});
  final bool inverse, compact;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TamarawLogo(size: compact ? 40 : 52),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Tamaraw',
                      style: TextStyle(color: inverse ? Colors.white : p.ink),
                    ),
                    TextSpan(
                      text: ' Time',
                      style: TextStyle(color: inverse ? p.yellow : p.link),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              if (!compact)
                Text(
                  'FEU student companion',
                  style: TextStyle(
                    fontSize: 11,
                    color: inverse ? const Color(0xffbcd1c4) : p.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Native replacement for the original CSS sidebar and mobile bottom bar.
class PlannerShell extends StatelessWidget {
  const PlannerShell({
    super.key,
    required this.page,
    required this.onPage,
    required this.onExit,
    required this.child,
    this.floatingActionButton,
    this.local = false,
  });
  final int page;
  final ValueChanged<int> onPage;
  final VoidCallback onExit;
  final Widget child;
  final Widget? floatingActionButton;
  final bool local;
  static const labels = [
    'Dashboard',
    'Class Schedule',
    'Commute Planner',
    'Settings',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.calendar_month,
    Icons.route,
    Icons.settings_outlined,
  ];
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = AppLayout.desktop(width);
    final mobile = AppLayout.mobile(width);
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              toolbarHeight: 56 * AppLayout.textScale(context),
              title: const Brand(compact: true),
              actions: [
                IconButton(
                  tooltip: local ? 'Exit planner' : 'Log out',
                  onPressed: onExit,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: mobile
          ? NavigationBar(
              selectedIndex: page,
              onDestinationSelected: onPage,
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: const ['Home', 'Schedule', 'Commute', 'Settings'][i],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!mobile && !wide)
              LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: page,
                        onDestinationSelected: onPage,
                        labelType: NavigationRailLabelType.selected,
                        destinations: List.generate(
                          4,
                          (i) => NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(
                              const [
                                'Home',
                                'Schedule',
                                'Commute',
                                'Settings',
                              ][i],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (wide)
              Container(
                width: 250,
                color: p.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 26,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Brand(),
                      const SizedBox(height: 35),
                      for (int i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: TextButton.icon(
                            onPressed: () => onPage(i),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              backgroundColor: page == i
                                  ? p.soft
                                  : Colors.transparent,
                              foregroundColor: page == i ? p.link : p.muted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 17,
                                vertical: 17,
                              ),
                            ),
                            icon: Icon(icons[i], size: 21),
                            label: Text(
                              labels[i],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 48),
                      Text(
                        'Plan smarter. Arrive earlier.',
                        style: TextStyle(color: p.link, fontSize: 13),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Built for FEU students',
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: onExit,
                        style: TextButton.styleFrom(
                          foregroundColor: p.muted,
                          alignment: Alignment.centerLeft,
                        ),
                        icon: const Icon(Icons.logout, size: 18),
                        label: Text(local ? 'Exit planner' : 'Log out'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide
                      ? 42
                      : mobile
                      ? 18
                      : 24,
                  wide ? 38 : 22,
                  wide
                      ? 42
                      : mobile
                      ? 18
                      : 24,
                  90,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthSurface extends StatelessWidget {
  const AuthSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    return Container(
      color: p.paper,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 475),
              padding: EdgeInsets.all(
                AppLayout.mobile(MediaQuery.sizeOf(context).width) ? 20 : 32,
              ),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(23),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0d09271f),
                    blurRadius: 32,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Material(color: Colors.transparent, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class PageEntrance extends StatelessWidget {
  const PageEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 9 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    this.accent = false,
  });
  final String label, value, note;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        color: accent ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(19),
        border: accent ? null : Border.all(color: p.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0b143525),
            blurRadius: 22,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent ? const Color(0xffbbd3c6) : p.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: accent ? p.yellow : p.ink,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 5),
          Text(
            note,
            style: TextStyle(
              fontSize: 12,
              color: accent ? const Color(0xffbbd3c6) : p.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeChoices extends StatelessWidget {
  const ThemeChoices({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = TamarawPalette.of(context);
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 9,
        runSpacing: 9,
        children: TamarawPalette.themes.entries.map((entry) {
          final selected = value == entry.key, p = entry.value;
          return SizedBox(
            width: box.maxWidth < 310 ? box.maxWidth : (box.maxWidth - 9) / 2,
            child: Semantics(
              selected: selected,
              button: true,
              label: p.name,
              child: Material(
                color: selected ? colors.soft : colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: BorderSide(
                    color: selected ? colors.link : colors.border,
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onChanged(entry.key),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [p.heroStart, p.heroFinish],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: p.yellow,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.ink,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check, size: 18, color: colors.link),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class RoutineResults extends StatelessWidget {
  const RoutineResults({
    super.key,
    required this.ready,
    required this.leave,
    required this.arrive,
  });
  final String ready, leave, arrive;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    final values = {
      'Get ready': ready,
      'Leave by': leave,
      'Be there by': arrive,
    };
    final cells = values.entries
        .map(
          (e) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: p.soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.key, style: TextStyle(fontSize: 12, color: p.muted)),
                const SizedBox(height: 3),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, box) =>
          AppLayout.columns(
            box.maxWidth,
            textScale: AppLayout.textScale(context),
          )
          ? Row(
              children: [
                for (int i = 0; i < cells.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: cells[i]),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final cell in cells)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: cell,
                  ),
              ],
            ),
    );
  }
}
