import 'package:flutter/material.dart';

/// Vertical space reserved at the bottom of any modal sheet so it never
/// overlaps the floating Merci nav pill in MainShell.
///
/// Breakdown:
///   pill height ............. ~64
///   FAB lift above pill ..... ~18
///   bottom edge offset ...... ~14
const double kAppNavReservedHeight = 96;

/// App-standard modal bottom sheet. Wraps [showModalBottomSheet] with the
/// padding required to clear the floating Merci nav and keyboard, plus
/// `isScrollControlled: true` so sheets can grow with their content.
///
/// Use this for short action-style sheets. For tall lists or forms, push a
/// full-screen [MaterialPageRoute] with `fullscreenDialog: true` instead —
/// that gives the content full vertical space and hides the nav pill.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    backgroundColor: backgroundColor ?? Colors.transparent,
    shape: shape,
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottom + kAppNavReservedHeight),
        child: Material(
          type: MaterialType.transparency,
          child: builder(ctx),
        ),
      );
    },
  );
}
