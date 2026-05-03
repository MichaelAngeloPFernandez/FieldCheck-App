import 'dart:math' as math;

import 'package:flutter/material.dart';

class CompassOption {
  final String value;
  final String label;
  final IconData icon;

  const CompassOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class CompassSelector extends StatelessWidget {
  final List<CompassOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final double size;
  final Color? accentColor;
  final String? title;
  final bool showArrows;
  final Widget Function(BuildContext context, CompassOption? selectedOption)?
  centerBuilder;

  const CompassSelector({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.size = 220,
    this.accentColor,
    this.title,
    this.showArrows = true,
    this.centerBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return _CompassSelectorBody(
      options: options,
      selectedValue: selectedValue,
      onSelected: onSelected,
      size: size,
      accentColor: accentColor,
      title: title,
      showArrows: showArrows,
      centerBuilder: centerBuilder,
    );
  }
}

class _CompassSelectorBody extends StatefulWidget {
  final List<CompassOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final double size;
  final Color? accentColor;
  final String? title;
  final bool showArrows;
  final Widget Function(BuildContext context, CompassOption? selectedOption)?
  centerBuilder;

  const _CompassSelectorBody({
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    required this.size,
    required this.accentColor,
    required this.title,
    required this.showArrows,
    required this.centerBuilder,
  });

  @override
  State<_CompassSelectorBody> createState() => _CompassSelectorBodyState();
}

class _CompassSelectorBodyState extends State<_CompassSelectorBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  void _selectPrev() {
    if (widget.options.isEmpty) return;
    final i = widget.options.indexWhere((o) => o.value == widget.selectedValue);
    final safe = i < 0 ? 0 : i;
    final prev = (safe - 1 + widget.options.length) % widget.options.length;
    widget.onSelected(widget.options[prev].value);
  }

  void _selectNext() {
    if (widget.options.isEmpty) return;
    final i = widget.options.indexWhere((o) => o.value == widget.selectedValue);
    final safe = i < 0 ? 0 : i;
    final next = (safe + 1) % widget.options.length;
    widget.onSelected(widget.options[next].value);
  }

  Color _revolvingColor({
    required Color base,
    required double t,
    required int index,
    double saturation = 0.78,
    double value = 0.92,
  }) {
    final hsv = HSVColor.fromColor(base);
    final hue = (hsv.hue + (t * 360.0) + (index * 28.0)) % 360.0;
    return HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final selectedIndex = widget.options.indexWhere(
      (o) => o.value == widget.selectedValue,
    );
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final pointerTurns = widget.options.isEmpty
        ? 0.0
        : safeIndex / widget.options.length;
    final radius = widget.size / 2 - 34;
    final selectedOption = safeIndex >= 0 && safeIndex < widget.options.length
        ? widget.options[safeIndex]
        : null;

    return AnimatedBuilder(
      animation: _colorController,
      builder: (context, _) {
        final t = _colorController.value;
        final center =
            widget.centerBuilder?.call(context, selectedOption) ??
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selectedOption?.icon ?? Icons.explore,
                  color: _revolvingColor(base: accent, t: t, index: safeIndex),
                  size: 22,
                ),
                const SizedBox(height: 2),
                Text(
                  selectedOption?.label ?? '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  widget.title!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.14),
                          theme.colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.55),
                        width: 1.6,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: pointerTurns,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    child: Transform.translate(
                      offset: Offset(0, -widget.size / 2 + 24),
                      child: Icon(
                        Icons.navigation,
                        color: _revolvingColor(base: accent, t: t, index: 0),
                        size: 24,
                      ),
                    ),
                  ),
                  ...widget.options.asMap().entries.map((entry) {
                    final index = entry.key;
                    final opt = entry.value;
                    final angle =
                        -math.pi / 2 +
                        (index / widget.options.length) * 2 * math.pi;
                    final offset = Offset(
                      math.cos(angle) * radius,
                      math.sin(angle) * radius,
                    );
                    final isSelected = opt.value == widget.selectedValue;
                    final iconColor = isSelected
                        ? _revolvingColor(base: accent, t: t, index: index)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.72);

                    return Transform.translate(
                      offset: offset,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => widget.onSelected(opt.value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accent.withValues(alpha: 0.18)
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? accent.withValues(alpha: 0.9)
                                  : theme.dividerColor.withValues(alpha: 0.55),
                            ),
                            boxShadow: [
                              if (isSelected)
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(opt.icon, size: 18, color: iconColor),
                              const SizedBox(height: 3),
                              Text(
                                opt.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? iconColor
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.75,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.45),
                        width: 1.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(child: center),
                  ),
                  if (widget.showArrows && widget.options.length >= 2) ...[
                    Positioned(
                      left: -10,
                      child: _CompassArrowButton(
                        icon: Icons.chevron_left,
                        onPressed: _selectPrev,
                      ),
                    ),
                    Positioned(
                      right: -10,
                      child: _CompassArrowButton(
                        icon: Icons.chevron_right,
                        onPressed: _selectNext,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CompassArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CompassArrowButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 22,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
