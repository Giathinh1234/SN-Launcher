import 'package:flutter/material.dart';

import '../models/nest_action.dart' show AssistantBackend;
import '../state/shell_controller.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_theme.dart';
import '../theme/nest_type.dart';

/// Everything the settings page can change about the assistant.
///
/// Declared here, callback-shaped, rather than imported from the assistant's
/// own half of the app. The shell holds the real state and maps between the
/// two models at the wiring point, so neither side can collide on one class.
@immutable
class AssistantSettings {
  const AssistantSettings({
    required this.enabled,
    required this.backend,
    required this.geminiKey,
    required this.homeAssistantUrl,
    required this.homeAssistantToken,
    required this.voiceEnabled,
    required this.busy,
  });

  /// Master switch. Off means the microphone and keyword listening are down;
  /// the controls below stay visible but greyed out rather than vanishing, so
  /// the page keeps explaining what is available.
  final bool enabled;

  /// Which backend answers whatever the on-device intents cannot.
  final AssistantBackend backend;

  /// Gemini API key, if one was entered. Displayed obscured.
  final String geminiKey;

  /// Home Assistant base URL, e.g. `http://homeassistant.local:8123`.
  final String homeAssistantUrl;

  /// Home Assistant long-lived access token. Displayed obscured.
  final String homeAssistantToken;

  /// Whether replies are read aloud.
  final bool voiceEnabled;

  /// True while the caller is running a connection test. The page shows its
  /// own busy state from this — it never runs the test itself.
  final bool busy;

  AssistantSettings copyWith({
    bool? enabled,
    AssistantBackend? backend,
    String? geminiKey,
    String? homeAssistantUrl,
    String? homeAssistantToken,
    bool? voiceEnabled,
    bool? busy,
  }) {
    return AssistantSettings(
      enabled: enabled ?? this.enabled,
      backend: backend ?? this.backend,
      geminiKey: geminiKey ?? this.geminiKey,
      homeAssistantUrl: homeAssistantUrl ?? this.homeAssistantUrl,
      homeAssistantToken: homeAssistantToken ?? this.homeAssistantToken,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      busy: busy ?? this.busy,
    );
  }
}

/// Full-bleed settings surface for the launcher.
///
/// Sections, in order: **Appearance**, **Display**, **Assistant**.
///
/// There is deliberately **no Background section**. Photo rotation already has
/// honest controls on the digest page's Photos card; a second set here would
/// either duplicate state or force a new `ShellController` field that another
/// half of the app must then own. Omitting it is the cheaper mistake.
///
/// Two ownership boundaries shape the API:
///  * Shell settings (theme, 24-hour clock, DND, ambient light, zoom) are read
///    from and written to [ShellController] directly, the same way the digest
///    page calls `setTheme` — the controller persists them itself.
///  * Everything about the assistant flows out through a single
///    [onAssistantChanged] callback carrying a locally-declared
///    [AssistantSettings]. That class is declared *here*, shaped around what
///    this page edits, rather than imported from the assistant's own half, so
///    the two cannot collide on one shared model.
///
/// The page is fully scrollable: at the native 1024x600 canvas a settings
/// surface with this many rows cannot fit, and clipping is not an option on a
/// touch panel. It paints no background of its own — the ambient gradient
/// behind it (whatever the shell puts there) is the backdrop, matching how the
/// digest page composes over [AmbientPalette].
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.controller,
    required this.assistant,
    this.onAssistantChanged,
    this.onTestConnection,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final ShellController controller;

  /// Current assistant configuration. The source of truth lives in the caller;
  /// this page never mutates it in place, only reports edits.
  final AssistantSettings assistant;

  /// Called whenever the user changes anything about the assistant.
  ///
  /// Optional only in the sense that the page renders (with everything
  /// disabled) without it; without a listener no change can be kept.
  final void Function(AssistantSettings assistant)? onAssistantChanged;

  /// Runs the Home Assistant connection test.
  ///
  /// Deliberately a separate callback from [onAssistantChanged]: flipping
  /// `busy` on and calling back would make the page *claim* a test it cannot
  /// run — the services half owns the actual HTTP call. When null, the Test
  /// connection button renders disabled.
  final Future<void> Function()? onTestConnection;

  /// The one place every mutation funnels through.
  void _emit(AssistantSettings next) => onAssistantChanged?.call(next);

  // ── Copy ─────────────────────────────────────────────────────────────────
  // Every string below states what a feature *can* do, not what we wish it
  // did. The digest page's "never report an action that did not happen" rule
  // applies to copy too.

  static String _backendLabel(AssistantBackend backend) => switch (backend) {
        AssistantBackend.homeAssistant => 'Home Assistant',
        AssistantBackend.gemini => 'Gemini',
        AssistantBackend.localOnly => 'Local only',
      };

  static String _backendNote(AssistantBackend backend) => switch (backend) {
        AssistantBackend.homeAssistant =>
          'Controls your own server — lights, switches, media. No general questions.',
        AssistantBackend.gemini =>
          "Answers anything via Google's API. Requests leave this device.",
        AssistantBackend.localOnly =>
          'Timers, media and volume. No network needed.',
      };

  /// Presence-only facts: "set" and "missing", never "working".
  String _assistantStatus(AssistantSettings a) => switch (a.backend) {
        AssistantBackend.homeAssistant => _haStatus(a),
        AssistantBackend.gemini => a.geminiKey.trim().isEmpty
            ? 'No API key yet.'
            : 'API key saved.',
        AssistantBackend.localOnly => 'Runs entirely on this device.',
      };

  static String _haStatus(AssistantSettings a) {
    final url = a.homeAssistantUrl.trim().isNotEmpty;
    final token = a.homeAssistantToken.trim().isNotEmpty;
    if (!url && !token) {
      return 'Not configured. Enter the server URL and a long-lived token.';
    }
    return '${url ? 'URL set' : 'URL missing'} · '
        '${token ? 'token set' : 'token missing'}';
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  Widget _appearance(NestMetrics m) {
    final c = controller;
    return _Section(
      metrics: m,
      type: type,
      palette: palette,
      icon: NestIcons.Palette,
      title: 'Appearance',
      children: [
        Text('Theme', style: type.caption(color: palette.onSurfaceStrong)),
        SizedBox(height: m.px(8)),
        // Same honest-swatch language as the digest page's Theme card: each
        // chip renders the palette it would actually pin, in its own ink.
        Wrap(
          spacing: m.px(8),
          runSpacing: m.px(8),
          children: [
            for (final theme in NestTheme.values)
              _ThemeSwatch(
                theme: theme,
                selected: theme == c.theme,
                live: palette,
                metrics: m,
                type: type,
                onTap: () => c.setTheme(theme),
              ),
          ],
        ),
        SizedBox(height: m.px(10)),
        Text(
          c.themeIsDynamic ? 'Follows the time of day' : 'Pinned',
          style: type.caption(color: palette.onSurfaceVariant),
        ),
        _hairline(m),
        _ToggleRow(
          label: '24-hour time',
          metrics: m,
          type: type,
          palette: palette,
          value: c.use24Hour,
          onChanged: (_) => c.toggleUse24Hour(),
        ),
        _ToggleRow(
          label: 'Show seconds',
          metrics: m,
          type: type,
          palette: palette,
          value: c.showSeconds,
          onChanged: (_) => c.toggleShowSeconds(),
        ),
        _SliderRow(
          label: 'Clock face size',
          valueText: '${c.zoom.toStringAsFixed(1)}×',
          metrics: m,
          type: type,
          palette: palette,
          value: c.zoom,
          min: 1.0,
          max: 2.0,
          divisions: 10,
          // The setter clamps and notifies; the shell's own listener drives
          // the repaint, same as the digest page's pickers.
          onChanged: (v) => c.zoom = v,
        ),
      ],
    );
  }

  Widget _display(NestMetrics m) {
    final c = controller;
    return _Section(
      metrics: m,
      type: type,
      palette: palette,
      icon: NestIcons.Brightness6,
      title: 'Display',
      children: [
        _ToggleRow(
          label: 'Do Not Disturb',
          metrics: m,
          type: type,
          palette: palette,
          value: c.doNotDisturb,
          onChanged: (_) => c.toggleDoNotDisturb(),
        ),
        _ToggleRow(
          label: 'Ambient EQ',
          note: 'Tints the screen by time of day.',
          metrics: m,
          type: type,
          palette: palette,
          value: c.ambientEq,
          onChanged: (_) => c.toggleAmbientEq(),
        ),
        _SliderRow(
          label: 'Ambient light',
          valueText: '${(c.ambientLight * 100).round()}%',
          note: 'Manual — applies as-is unless the device has a light sensor.',
          metrics: m,
          type: type,
          palette: palette,
          value: c.ambientLight,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          onChanged: c.setAmbientLight,
        ),
      ],
    );
  }

  Widget _assistant(NestMetrics m) {
    final a = assistant;
    final interactive = a.enabled && onAssistantChanged != null;
    final backend = a.backend;

    return _Section(
      metrics: m,
      type: type,
      palette: palette,
      icon: NestIcons.AutoAwesome,
      title: 'Assistant',
      children: [
        // The master switch must stay operable when everything under it is
        // off — it is the way back.
        _ToggleRow(
          label: 'Assistant',
          metrics: m,
          type: type,
          palette: palette,
          value: a.enabled,
          onChanged: onAssistantChanged == null
              ? null
              : (v) => _emit(a.copyWith(enabled: v)),
        ),
        _hairline(m),
        // Everything below is inert when the assistant is off: switches lose
        // their callbacks (Material renders them grey), fields report
        // `enabled: false`, pills render their muted style — and IgnorePointer
        // guarantees nothing answers a tap regardless.
        IgnorePointer(
          ignoring: !interactive,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Answers come from',
                style: type.caption(color: palette.onSurfaceStrong),
              ),
              SizedBox(height: m.px(8)),
              Wrap(
                spacing: m.px(8),
                runSpacing: m.px(8),
                children: [
                  for (final b in AssistantBackend.values)
                    _PillToggle(
                      label: _backendLabel(b),
                      on: b == backend,
                      enabled: interactive,
                      metrics: m,
                      type: type,
                      palette: palette,
                      onTap: interactive
                          ? () => _emit(a.copyWith(backend: b))
                          : null,
                    ),
                ],
              ),
              SizedBox(height: m.px(8)),
              Text(
                _backendNote(backend),
                style: type.caption(color: palette.onSurfaceVariant),
              ),
              if (backend == AssistantBackend.homeAssistant) ...[
                SizedBox(height: m.px(12)),
                _SyncedTextField(
                  value: a.homeAssistantUrl,
                  label: 'Server URL',
                  hint: 'http://homeassistant.local:8123',
                  keyboardType: TextInputType.url,
                  enabled: interactive,
                  metrics: m,
                  type: type,
                  palette: palette,
                  onChanged: (v) => _emit(a.copyWith(homeAssistantUrl: v)),
                ),
                SizedBox(height: m.px(10)),
                _SyncedTextField(
                  value: a.homeAssistantToken,
                  label: 'Long-lived access token',
                  obscure: true,
                  enabled: interactive,
                  metrics: m,
                  type: type,
                  palette: palette,
                  onChanged: (v) => _emit(a.copyWith(homeAssistantToken: v)),
                ),
                SizedBox(height: m.px(12)),
                _TestConnectionRow(
                  canTest: interactive &&
                      !a.busy &&
                      a.homeAssistantUrl.trim().isNotEmpty &&
                      a.homeAssistantToken.trim().isNotEmpty &&
                      onTestConnection != null,
                  busy: a.busy,
                  status: _assistantStatus(a),
                  metrics: m,
                  type: type,
                  palette: palette,
                  onTest: onTestConnection,
                ),
              ],
              if (backend == AssistantBackend.gemini) ...[
                SizedBox(height: m.px(12)),
                _SyncedTextField(
                  value: a.geminiKey,
                  label: 'API key',
                  hint: 'AIza…',
                  obscure: true,
                  enabled: interactive,
                  metrics: m,
                  type: type,
                  palette: palette,
                  onChanged: (v) => _emit(a.copyWith(geminiKey: v)),
                ),
                SizedBox(height: m.px(10)),
                Text(
                  _assistantStatus(a),
                  style: type.caption(color: palette.onSurfaceVariant),
                ),
              ],
              _hairline(m),
              _ToggleRow(
                label: 'Speak replies',
                metrics: m,
                type: type,
                palette: palette,
                value: a.voiceEnabled,
                onChanged: interactive
                    ? (v) => _emit(a.copyWith(voiceEnabled: v))
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hairline(NestMetrics m) => Padding(
        padding: EdgeInsets.symmetric(vertical: m.px(12)),
        child: Container(
          height: m.px(1),
          color: palette.onSurfaceVariant.withValues(alpha: 0.14),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = metrics;

    // Listenable rebuild, not a parent-driven one: sliders and switches must
    // repaint on every frame of a drag even if the hosting shell does not
    // listen to the controller. A settings page rebuilding during a drag is a
    // dozen widgets — trivial next to the sheet's budget.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Theme(
        // Text fields, sliders and switches all reach for the ambient scheme.
        // The shell already wraps itself in this theme; wrapping again is
        // cheap and makes the page correct if it is ever pushed outside the
        // shell (a modal route, say).
        data: nestTheme(palette, type),
        child: Material(
          // TextField requires a Material ancestor; transparency keeps the
          // page's own background out of the way of the ambient gradient.
          type: MaterialType.transparency,
          child: Padding(
            padding: EdgeInsets.fromLTRB(m.px(48), m.px(36), m.px(48), m.px(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: type.sheetTitle(color: palette.onSurface)),
                SizedBox(height: m.px(14)),
                Expanded(
                  child: SingleChildScrollView(
                    // Typing then dragging should not fight the on-screen
                    // keyboard.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _appearance(m),
                        SizedBox(height: m.px(14)),
                        _display(m),
                        SizedBox(height: m.px(14)),
                        _assistant(m),
                        // Handle-side clearance at the bottom of the scroll.
                        SizedBox(height: m.px(28)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One settings card: surface fill, the theme's own 20px corner language, a
/// section title and its rows. Rows are intrinsic — the cards live in a
/// scroll view, so nothing inside may use [Expanded].
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    required this.metrics,
    required this.type,
    required this.palette,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Container(
      padding: EdgeInsets.all(m.px(20)),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(m.px(20)),
        // Hairline so the card still reads on backgrounds close to its own
        // colour (Day's surface and background differ by a few RGB points).
        border: Border.all(
          color: palette.onSurfaceVariant.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: m.px(22), color: palette.onSurfaceStrong),
              SizedBox(width: m.px(10)),
              Text(title, style: type.sheetTitle(color: palette.onSurfaceStrong)),
            ],
          ),
          SizedBox(height: m.px(14)),
          ...children,
        ],
      ),
    );
  }
}

/// A labelled row with a trailing switch. `onChanged == null` renders the
/// switch genuinely disabled (grey), which is how the page dims the assistant
/// block when the master toggle is off.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.metrics,
    required this.type,
    required this.palette,
    this.note,
    this.onChanged,
  });

  final String label;

  /// Optional one-line note under the label.
  final String? note;
  final bool value;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: type.body(color: palette.onSurfaceStrong),
              ),
            ),
            SizedBox(width: m.px(12)),
            Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        if (note != null) ...[
          SizedBox(height: m.px(2)),
          Text(
            note!,
            style: type.caption(color: palette.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// A labelled slider with its current value right-aligned and an optional
/// note. `onChanged == null` greys the whole track — the disabled state is
/// the widget's own, not an overlay.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.metrics,
    required this.type,
    required this.palette,
    this.valueText,
    this.note,
    this.onChanged,
  });

  final String label;
  final String? valueText;
  final String? note;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final valueLabel = valueText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: type.body(color: palette.onSurfaceStrong),
              ),
            ),
            if (valueLabel != null)
              Text(
                valueLabel,
                style: type.caption(color: palette.onSurfaceVariant),
              ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
        if (note != null)
          Text(note!, style: type.caption(color: palette.onSurfaceVariant)),
      ],
    );
  }
}

/// The digest page's pill toggle, restated here because that class is private
/// to `nest_shell.dart`. Same colours, same radii — the pages must read as one
/// control language. `onTap == null` renders the muted, unresponsive state.
class _PillToggle extends StatelessWidget {
  const _PillToggle({
    required this.label,
    required this.on,
    required this.metrics,
    required this.type,
    required this.palette,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final bool on;
  final bool enabled;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final active = on && enabled;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.px(14),
          vertical: m.px(7),
        ),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF4285F4)
              : palette.onSurfaceVariant.withValues(alpha: enabled ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(m.px(10)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.caption(
            color: active
                ? Colors.white
                : palette.onSurfaceStrong.withValues(
                    alpha: enabled ? 0.85 : 0.38,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A theme chip that previews the palette it would pin — with the pinned
/// scheme's own surface and ink, never a decorative approximation. The
/// Dynamic chip previews the *live* palette, which is what "dynamic" means
/// right now.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.live,
    required this.metrics,
    required this.type,
    required this.onTap,
  });

  final NestTheme theme;
  final bool selected;
  final AmbientPalette live;
  final NestMetrics metrics;
  final NestType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final preview =
        theme == NestTheme.dynamic ? live : AmbientPalette.of(theme);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: m.px(96),
        padding: EdgeInsets.symmetric(vertical: m.px(8)),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: preview.surface,
          borderRadius: BorderRadius.circular(m.px(10)),
          border: Border.all(
            color: selected
                ? const Color(0xFF4285F4)
                : preview.onSurfaceVariant.withValues(alpha: 0.28),
            width: selected ? m.px(2) : m.px(1),
          ),
        ),
        child: Text(
          theme.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.caption(color: preview.onSurfaceStrong),
        ),
      ),
    );
  }
}

/// A text field whose text is owned by the caller ([value]) but kept live in
/// a local controller, because [SettingsPage] is stateless by contract.
///
/// Sync rule: adopt an external change only while the field is not focused.
/// While the user types, the parent echoes the same string back and the
/// update is a no-op; a genuinely remote change (settings restored from disk,
/// a reset) lands the moment the field loses focus, and never clobbers the
/// caret mid-edit.
class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.value,
    required this.label,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.onChanged,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.enabled = true,
  });

  final String value;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool enabled;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final ValueChanged<String> onChanged;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focus.hasFocus) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final p = widget.palette;
    final radius = BorderRadius.circular(m.px(12));
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      obscureText: widget.obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: widget.keyboardType,
      textInputAction: TextInputAction.done,
      style: widget.type.body(color: p.onSurfaceStrong),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: m.px(14),
          vertical: m.px(12),
        ),
        filled: true,
        fillColor: Color.lerp(p.surface, p.onSurface, 0.06),
        labelStyle: widget.type.caption(color: p.onSurfaceVariant),
        hintStyle: widget.type.caption(
          color: p.onSurfaceVariant.withValues(alpha: 0.55),
        ),
        enabledBorder:
            border(p.onSurfaceVariant.withValues(alpha: 0.32)),
        focusedBorder: border(
          Theme.of(context).colorScheme.primary,
          m.px(1.5),
        ),
        disabledBorder:
            border(p.onSurfaceVariant.withValues(alpha: 0.12)),
      ),
    );
  }
}

/// The Home Assistant test row: the button, a spinner while the caller runs
/// the test, and a presence-only status line. The page never states an
/// outcome — "Connected" is the caller's claim to make, not ours.
class _TestConnectionRow extends StatelessWidget {
  const _TestConnectionRow({
    required this.canTest,
    required this.busy,
    required this.status,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.onTest,
  });

  /// False when the assistant is off, a test is running, the credentials are
  /// incomplete, or no callback was wired.
  final bool canTest;
  final bool busy;
  final String status;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final Future<void> Function()? onTest;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Row(
      children: [
        OutlinedButton(
          // Disabled while busy, even though `canTest` already covers it:
          // the two reasons produce the same grey, and the row below says
          // which one is in effect.
          onPressed: canTest ? onTest : null,
          style: OutlinedButton.styleFrom(
            // Shape only; the border colour comes from the ambient scheme, so
            // the disabled state (grey side, grey text) is the theme's own.
            shape: const StadiumBorder(),
            padding: EdgeInsets.symmetric(horizontal: m.px(16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                SizedBox(
                  width: m.px(14),
                  height: m.px(14),
                  child: CircularProgressIndicator(
                    strokeWidth: m.px(2),
                    color: palette.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: m.px(8)),
              ],
              Text(
                busy ? 'Testing…' : 'Test connection',
                style: type.caption(
                  color: canTest
                      ? palette.onSurfaceStrong
                      : palette.onSurfaceStrong.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: m.px(12)),
        Expanded(
          child: Text(
            status,
            style: type.caption(color: palette.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
