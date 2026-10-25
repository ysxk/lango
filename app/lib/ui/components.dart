import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.maxWidth = LangoTheme.maxContent,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width >= 1100 ? 48.0 : width >= 700 ? 32.0 : 20.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: horizontal),
          child: child,
        ),
      ),
    );
  }
}

class LangoMark extends StatelessWidget {
  const LangoMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(c.canvas, c.mint, c.teal)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ivory, this.mint, this.teal);
  final Color ivory;
  final Color mint;
  final Color teal;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.36)),
      Paint()..color = teal,
    );
    final stroke = Paint()
      ..color = ivory
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.065
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width * 0.46, size.height * 0.5);
    for (final scale in [0.14, 0.25]) {
      final radius = size.width * scale;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.32,
        math.pi * 0.64,
        false,
        stroke,
      );
    }
    canvas.drawCircle(
      Offset(size.width * 0.27, size.height * 0.5),
      size.width * 0.045,
      Paint()..color = mint,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.teal != teal || oldDelegate.ivory != ivory || oldDelegate.mint != mint;
}

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 24,
    this.color,
    this.border = false,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool border;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: context.motion(200),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: c.line.withValues(alpha: 0.8)) : null,
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: c.ink.withValues(alpha: c.isDark ? 0.26 : 0.055),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: context.texts.labelSmall?.copyWith(
                    color: c.teal,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(title, style: context.texts.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: context.texts.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.emphasis = false, this.icon});
  final String label;
  final bool emphasis;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emphasis ? c.mint : c.sunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: emphasis ? c.mintInk : c.secondary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: emphasis ? c.mintInk : c.secondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class LangoField extends StatefulWidget {
  const LangoField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.prefixIcon,
    this.suffix,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.autofillHints,
    this.focusNode,
    this.enableSuggestions = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? minLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final bool enableSuggestions;

  @override
  State<LangoField> createState() => _LangoFieldState();
}

class _LangoFieldState extends State<LangoField> {
  FocusNode? _owned;
  FocusNode get _focus => widget.focusNode ?? (_owned ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final invalid = widget.errorText != null && widget.errorText!.isNotEmpty;
    final ringColor = invalid ? c.danger.withValues(alpha: 0.32) : c.teal.withValues(alpha: 0.30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            widget.label,
            style: context.texts.labelMedium?.copyWith(
              color: _focused ? c.ink : c.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        AnimatedContainer(
          duration: context.motion(180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _focused ? c.surface : c.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: invalid
                  ? c.danger.withValues(alpha: _focused ? 0.55 : 0.34)
                  : _focused
                      ? c.teal.withValues(alpha: 0.34)
                      : c.line.withValues(alpha: 0.9),
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(color: ringColor, blurRadius: 0, spreadRadius: 3),
                    BoxShadow(
                      color: c.ink.withValues(alpha: c.isDark ? 0.16 : 0.045),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            minLines: widget.obscure ? 1 : widget.minLines,
            onSubmitted: widget.onSubmitted,
            onChanged: widget.onChanged,
            autofillHints: widget.autofillHints,
            enableSuggestions: widget.enableSuggestions,
            autocorrect: !widget.obscure,
            style: context.texts.bodyLarge?.copyWith(fontSize: 15, height: 1.4),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: Icon(widget.prefixIcon, size: 18, color: c.faint),
                    ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: widget.suffix,
              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
        ),
        if (widget.errorText != null && widget.errorText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 7),
            child: Text(
              widget.errorText!,
              style: context.texts.bodySmall?.copyWith(color: c.danger),
            ),
          )
        else if (widget.helper != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 7),
            child: Text(widget.helper!, style: context.texts.bodySmall),
          ),
      ],
    );
  }
}

enum LangoButtonVariant { filled, tonal, outline, ghost, danger }

class LangoButton extends StatelessWidget {
  const LangoButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = LangoButtonVariant.filled,
    this.loading = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LangoButtonVariant variant;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == LangoButtonVariant.filled || variant == LangoButtonVariant.danger
                  ? c.onTeal
                  : c.teal,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 18),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 15)
        : const EdgeInsets.symmetric(horizontal: 22);

    Widget button;
    switch (variant) {
      case LangoButtonVariant.filled:
        button = FilledButton(onPressed: enabled ? onPressed : null, child: child);
        break;
      case LangoButtonVariant.tonal:
        button = FilledButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return c.sunken;
              if (states.contains(WidgetState.pressed)) return c.mint.withValues(alpha: 0.72);
              return c.mint;
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled) ? c.faint : c.mintInk,
            ),
          ),
          onPressed: enabled ? onPressed : null,
          child: child,
        );
        break;
      case LangoButtonVariant.outline:
        button = OutlinedButton(onPressed: enabled ? onPressed : null, child: child);
        break;
      case LangoButtonVariant.ghost:
        button = TextButton(onPressed: enabled ? onPressed : null, child: child);
        break;
      case LangoButtonVariant.danger:
        button = FilledButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return c.danger.withValues(alpha: 0.14);
              return c.danger;
            }),
            foregroundColor: WidgetStatePropertyAll(c.isDark ? const Color(0xFF20100D) : Colors.white),
          ),
          onPressed: enabled ? onPressed : null,
          child: child,
        );
        break;
    }
    final withPadding = Padding(padding: padding, child: button);
    return expand ? SizedBox(width: double.infinity, child: withPadding) : withPadding;
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry, this.onDismiss});
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
      decoration: BoxDecoration(
        color: c.dangerWash,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodySmall?.copyWith(color: c.danger, height: 1.45),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              child: const Text('重试'),
            ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: c.danger,
              tooltip: '关闭提示',
            ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.icon = Icons.eco_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: c.mint.withValues(alpha: c.isDark ? 0.8 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.mintInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodySmall?.copyWith(color: c.mintInk, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.wb_sunny_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: c.mint, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, size: 24, color: c.mintInk),
          ),
          const SizedBox(height: 18),
          Text(title, style: context.texts.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message,
              style: context.texts.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.label = '正在加载…', this.compact = false});
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 20 : 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.teal),
          ),
          const SizedBox(width: 12),
          Text(label, style: context.texts.bodySmall),
        ],
      ),
    );
  }
}

class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.childIndex = 0,
  });

  final int index;
  final int childIndex;
  final Widget child;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    final order = widget.index.clamp(0, 10);
    final duration = 240 + order * 34;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );
    final start = (order * 0.05).clamp(0.0, 0.42);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: const Cubic(0.16, 1, 0.3, 1)),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curve);
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion && _controller.value != 1) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: context.motion(160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? c.mint : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? Colors.transparent : c.line),
            ),
            child: Text(
              count == null ? label : '$label · $count',
              style: context.texts.labelMedium?.copyWith(
                color: selected ? c.mintInk : c.secondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChoiceOption<T> {
  const ChoiceOption({required this.value, required this.label, this.hint});
  final T value;
  final String label;
  final String? hint;
}

class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.wrap = true,
  });

  final List<ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final children = options.map((option) {
      final isSelected = option.value == selected;
      return Semantics(
        button: true,
        selected: isSelected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(option.value),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: context.motion(170),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? c.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: c.ink.withValues(alpha: c.isDark ? 0.22 : 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    style: context.texts.labelMedium?.copyWith(
                      color: isSelected ? c.ink : c.secondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (option.hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.hint!,
                      style: context.texts.labelSmall?.copyWith(
                        color: isSelected ? c.teal : c.faint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(16),
      ),
      child: wrap
          ? Wrap(spacing: 3, runSpacing: 3, children: children)
          : Row(
              children: [
                for (final child in children) Expanded(child: child),
              ],
            ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      radius: 20,
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: c.teal),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.texts.labelSmall?.copyWith(color: c.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: tabular(context.texts.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ) ??
                    const TextStyle()),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: context.texts.labelSmall?.copyWith(color: c.secondary)),
              ],
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: context.texts.bodySmall?.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class CopyAction extends StatefulWidget {
  const CopyAction({super.key, required this.text, this.label = '复制', this.compact = false});
  final String text;
  final String label;
  final bool compact;

  @override
  State<CopyAction> createState() => _CopyActionState();
}

class _CopyActionState extends State<CopyAction> {
  Timer? _timer;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _copied ? '已复制' : widget.label,
      child: AnimatedSwitcher(
        duration: context.motion(180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: LangoButton(
          key: ValueKey(_copied),
          label: _copied ? '已复制' : widget.label,
          icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
          variant: _copied ? LangoButtonVariant.tonal : LangoButtonVariant.outline,
          compact: widget.compact,
          onPressed: _copy,
        ),
      ),
    );
  }
}
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.pulse = false, this.size = 7});
  final Color color;
  final bool pulse;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.62, end: 1),
      duration: context.motion(900),
      curve: Curves.easeInOut,
      builder: (context, value, child) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: pulse ? value : 1),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
