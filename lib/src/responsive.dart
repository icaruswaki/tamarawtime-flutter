import 'package:flutter/material.dart';

abstract final class AppLayout {
  static const mobileBreakpoint = 600.0;
  static const desktopBreakpoint = 1024.0;
  static const columnsBreakpoint = 740.0;

  static bool mobile(double width) => width < mobileBreakpoint;
  static bool desktop(double width) => width >= desktopBreakpoint;
  static bool columns(double width, {double textScale = 1}) =>
      width >= columnsBreakpoint * textScale.clamp(1, 1.5);

  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14;
}

class ResponsiveFormActions extends StatelessWidget {
  const ResponsiveFormActions({
    super.key,
    required this.field,
    required this.action,
  });
  final Widget field, action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        AppLayout.mobile(box.maxWidth) && AppLayout.textScale(context) > 1.3
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [field, const SizedBox(height: 8), action],
          )
        : Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 8),
              action,
            ],
          ),
  );
}
