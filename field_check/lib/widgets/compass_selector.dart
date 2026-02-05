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

  const CompassSelector({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.size = 180,
    this.accentColor,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    final selectedIndex = options.indexWhere((o) => o.value == selectedValue);
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final pointerTurns = options.isEmpty ? 0.0 : safeIndex / options.length;
    final radius = size / 2 - 28;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.12),
                      theme.colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: pointerTurns,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOutCubic,
                child: Transform.translate(
                  offset: Offset(0, -size / 2 + 22),
                  child: Icon(
                    Icons.navigation,
                    color: accent,
                    size: 22,
                  ),
                ),
              ),
              ...options.asMap().entries.map((entry) {
                final index = entry.key;
                final opt = entry.value;
                final angle =
                    -math.pi / 2 + (index / options.length) * 2 * math.pi;
                final offset =
                    Offset(math.cos(angle) * radius, math.sin(angle) * radius);
                final isSelected = opt.value == selectedValue;

                return Transform.translate(
                  offset: offset,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => onSelected(opt.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.18)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : theme.dividerColor.withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: accent.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            opt.icon,
                            size: 16,
                            color: isSelected
                                ? accent
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            opt.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? accent
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.explore,
                  color: accent,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
