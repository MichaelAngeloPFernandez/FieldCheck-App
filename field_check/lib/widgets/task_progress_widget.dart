import 'package:flutter/material.dart';

class TaskProgressWidget extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final String title;
  final String? subtitle;
  final Color? backgroundColor;
  final Color? progressColor;
  final double height;
  final bool showPercentage;

  const TaskProgressWidget({
    super.key,
    required this.progress,
    required this.title,
    this.subtitle,
    this.backgroundColor,
    this.progressColor,
    this.height = 8.0,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percentage = (clampedProgress * 100).toStringAsFixed(0);
    final bgColor =
        backgroundColor ??
        Theme.of(context).dividerColor.withValues(alpha: 0.35);
    final pColor = progressColor ?? _getProgressColor(clampedProgress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (showPercentage)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: pColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(
            value: clampedProgress,
            minHeight: height,
            backgroundColor: bgColor,
            valueColor: AlwaysStoppedAnimation<Color>(pColor),
          ),
        ),
      ],
    );
  }

  Color _getProgressColor(double progress) {
    if (progress < 0.33) {
      return Colors.red;
    } else if (progress < 0.66) {
      return Colors.orange;
    } else if (progress < 1.0) {
      return Colors.amber;
    } else {
      return Colors.green;
    }
  }
}
