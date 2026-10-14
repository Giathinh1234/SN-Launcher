import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import 'launcher_sheet.dart';
import 'nest_glyphs.dart';

/// The full "Actions on Google" drawer reached from the See all pill.
///
/// The device lays this out alphabetically in a **six column** grid (verified
/// against a rectified photo of the Nest Hub Max: Assistant / Broadcast /
/// Calendar / Contacts / Duo / Games on row one). Larger, rounder icons than
/// the quick row, with the name beneath each one.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.metrics,
    required this.palette,
    required this.actions,
    required this.reveal,
    required this.onActionTap,
  });

  final NestMetrics metrics;
  final AmbientPalette palette;
  final List<NestAction> actions;

  /// 0..1 — the drawer's own entry animation, decoupled from the sheet.
  final double reveal;

  final ValueChanged<NestAction> onActionTap;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final type = NestType(m);
    final fg = widget.palette.onSurface;

    final padding = m.px(NestMetrics.sheetPaddingX);
    final cellH = m.px(NestMetrics.gridCellHeight);
    final icon = m.px(NestMetrics.gridIconSize);

    return IgnorePointer(
      ignoring: widget.reveal < 0.05,
      child: Opacity(
        opacity: widget.reveal.clamp(0.0, 1.0),
        child: ColoredBox(
          color: widget.palette.surface,
          child: Column(
            children: [
              SizedBox(height: m.sheetTop * 0.16),
              Expanded(
                child: GridView.builder(
                  controller: _controller,
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: NestMetrics.gridColumns,
                    mainAxisSpacing: m.px(10),
                    crossAxisSpacing: m.px(10),
                    // Nest's drawer scrolls continuously with no bounce, so the
                    // long tail stays predictable on a resistive touchscreen.
                    mainAxisExtent: cellH,
                  ),
                  itemCount: widget.actions.length,
                  // 24 icons is tiny; building them all up front avoids a
                  // scroll jank spike the first time the user flicks.
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  itemBuilder: (context, i) {
                    final a = widget.actions[i];
                    return _GridCell(
                      action: a,
                      iconSize: icon,
                      label: a.label,
                      labelStyle: type.appLabel(color: fg.withValues(alpha: 0.82)),
                      onTap: () => widget.onActionTap(a),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.action,
    required this.iconSize,
    required this.label,
    required this.labelStyle,
    required this.onTap,
  });

  final NestAction action;
  final double iconSize;
  final String label;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.92,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          NestAppBadge(action: action, size: iconSize),
          SizedBox(height: iconSize * 0.14),
          Text(
            label,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}