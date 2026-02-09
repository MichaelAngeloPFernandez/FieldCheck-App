import 'package:flutter/material.dart';

class AdminControlOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const AdminControlOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

class AdminControlBar<TPrimary, TSecondary> extends StatelessWidget {
  final String? title;
  final String? subtitle;

  final List<AdminControlOption<TPrimary>> primaryOptions;
  final TPrimary primaryValue;
  final ValueChanged<TPrimary> onPrimaryChanged;

  final String? secondaryLabel;
  final List<AdminControlOption<TSecondary>> secondaryOptions;
  final TSecondary? secondaryValue;
  final ValueChanged<TSecondary>? onSecondaryChanged;

  final List<Widget> actions;

  final double collapseBelowWidth;
  final String filtersButtonLabel;

  const AdminControlBar({
    super.key,
    this.title,
    this.subtitle,
    required this.primaryOptions,
    required this.primaryValue,
    required this.onPrimaryChanged,
    this.secondaryLabel,
    this.secondaryOptions = const [],
    this.secondaryValue,
    this.onSecondaryChanged,
    this.actions = const [],
    this.collapseBelowWidth = 720,
    this.filtersButtonLabel = 'Filters',
  });

  Future<void> _openFiltersSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                _SegmentedSingle<TPrimary>(
                  options: primaryOptions,
                  value: primaryValue,
                  onChanged: onPrimaryChanged,
                ),
                if (secondaryOptions.isNotEmpty &&
                    secondaryValue != null &&
                    onSecondaryChanged != null) ...[
                  const SizedBox(height: 14),
                  if (secondaryLabel != null)
                    Text(
                      secondaryLabel!,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  const SizedBox(height: 8),
                  _SegmentedSingle<TSecondary>(
                    options: secondaryOptions,
                    value: secondaryValue as TSecondary,
                    onChanged: onSecondaryChanged!,
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsed = constraints.maxWidth < collapseBelowWidth;

        final header = (title == null && subtitle == null)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (header != null) Expanded(child: header),
                  if (header == null) const Spacer(),
                  if (actions.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: actions,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (collapsed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openFiltersSheet(context),
                    icon: const Icon(Icons.tune),
                    label: Text(filtersButtonLabel),
                  ),
                )
              else ...[
                _SegmentedSingle<TPrimary>(
                  options: primaryOptions,
                  value: primaryValue,
                  onChanged: onPrimaryChanged,
                ),
                if (secondaryOptions.isNotEmpty &&
                    secondaryValue != null &&
                    onSecondaryChanged != null) ...[
                  const SizedBox(height: 12),
                  if (secondaryLabel != null)
                    Text(
                      secondaryLabel!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 8),
                  _SegmentedSingle<TSecondary>(
                    options: secondaryOptions,
                    value: secondaryValue as TSecondary,
                    onChanged: onSecondaryChanged!,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SegmentedSingle<T> extends StatelessWidget {
  final List<AdminControlOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const _SegmentedSingle({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: options
          .map(
            (o) => ButtonSegment<T>(
              value: o.value,
              label: Text(o.label),
              icon: o.icon == null ? null : Icon(o.icon, size: 18),
            ),
          )
          .toList(),
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        onChanged(set.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
