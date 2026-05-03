import 'package:flutter/material.dart';

class DynamicFormRenderer extends StatefulWidget {
  final Map<String, dynamic> jsonSchema;
  final Map<String, dynamic> initialData;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final bool readOnly;
  final ValueChanged<bool>? onValidationChanged;

  const DynamicFormRenderer({
    super.key,
    required this.jsonSchema,
    this.initialData = const {},
    this.onChanged,
    this.readOnly = false,
    this.onValidationChanged,
  });

  @override
  State<DynamicFormRenderer> createState() => DynamicFormRendererState();
}

class DynamicFormRendererState extends State<DynamicFormRenderer> {
  late Map<String, dynamic> _formData;

  @override
  void initState() {
    super.initState();
    _formData = Map<String, dynamic>.from(widget.initialData);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onValidationChanged?.call(_computeIsValid());
    });
  }

  void _updateField(String key, dynamic value) {
    setState(() {
      _formData[key] = value;
    });
    widget.onChanged?.call(_formData);
    widget.onValidationChanged?.call(_computeIsValid());
  }

  void _updateNestedField(String parentKey, String childKey, dynamic value) {
    setState(() {
      if (_formData[parentKey] is! Map) {
        _formData[parentKey] = <String, dynamic>{};
      }
      (_formData[parentKey] as Map<String, dynamic>)[childKey] = value;
    });
    widget.onChanged?.call(_formData);
    widget.onValidationChanged?.call(_computeIsValid());
  }

  List<String> get _requiredFields {
    final req = widget.jsonSchema['required'];
    if (req is List) return req.map((e) => e.toString()).toList();
    return [];
  }

  Map<String, dynamic> get _properties {
    final props = widget.jsonSchema['properties'];
    if (props is Map<String, dynamic>) return props;
    return {};
  }

  bool _computeIsValid() {
    for (final key in _requiredFields) {
      final val = _formData[key];
      if (val == null) return false;
      if (val is String && val.trim().isEmpty) return false;
      if (val is Map && val.isEmpty) return false;
      if (val is List && val.isEmpty) return false;
    }
    return true;
  }

  Map<String, dynamic> getFormData() => _formData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final props = _properties;
    final required = _requiredFields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: props.entries.map((entry) {
        final key = entry.key;
        final schema = entry.value;
        final isRequired = required.contains(key);

        if (schema is! Map<String, dynamic>) {
          return const SizedBox.shrink();
        }

        final type = schema['type']?.toString() ?? 'string';
        final title = schema['title']?.toString() ?? _humanize(key);
        final description = schema['description']?.toString();

        Widget field;
        if (type == 'boolean') {
          field = CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: (_formData[key] as bool?) ?? false,
            onChanged: widget.readOnly
                ? null
                : (v) => _updateField(key, v == true),
            title: Text(title),
            subtitle: description != null && description.isNotEmpty
                ? Text(description)
                : null,
          );
        } else if (type == 'string' && schema['enum'] is List) {
          final items = (schema['enum'] as List)
              .map((e) => e.toString())
              .toList();
          field = DropdownButtonFormField<String>(
            initialValue: _formData[key]?.toString(),
            items: items
                .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                .toList(),
            onChanged: widget.readOnly ? null : (v) => _updateField(key, v),
            decoration: InputDecoration(
              labelText: isRequired ? '$title *' : title,
              border: const OutlineInputBorder(),
            ),
          );
        } else if (type == 'object' && schema['properties'] is Map) {
          final childProps = (schema['properties'] as Map)
              .cast<String, dynamic>();
          field = Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRequired ? '$title *' : title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ...childProps.entries.map((child) {
                    final childKey = child.key;
                    final childSchema = child.value;
                    if (childSchema is! Map<String, dynamic>) {
                      return const SizedBox.shrink();
                    }
                    final childType =
                        childSchema['type']?.toString() ?? 'string';
                    final childTitle =
                        childSchema['title']?.toString() ?? _humanize(childKey);
                    final nested = _formData[key] is Map
                        ? (_formData[key] as Map).cast<String, dynamic>()
                        : <String, dynamic>{};

                    if (childType == 'boolean') {
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: (nested[childKey] as bool?) ?? false,
                        onChanged: widget.readOnly
                            ? null
                            : (v) =>
                                  _updateNestedField(key, childKey, v == true),
                        title: Text(childTitle),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        initialValue: nested[childKey]?.toString() ?? '',
                        readOnly: widget.readOnly,
                        onChanged: (v) => _updateNestedField(key, childKey, v),
                        decoration: InputDecoration(
                          labelText: childTitle,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        } else {
          final keyboardType = (type == 'number' || type == 'integer')
              ? TextInputType.number
              : TextInputType.text;
          field = TextFormField(
            initialValue: _formData[key]?.toString() ?? '',
            readOnly: widget.readOnly,
            keyboardType: keyboardType,
            onChanged: (v) {
              if (type == 'integer') {
                final parsed = int.tryParse(v);
                _updateField(key, parsed ?? v);
                return;
              }
              if (type == 'number') {
                final parsed = double.tryParse(v);
                _updateField(key, parsed ?? v);
                return;
              }
              _updateField(key, v);
            },
            decoration: InputDecoration(
              labelText: isRequired ? '$title *' : title,
              helperText: description,
              border: const OutlineInputBorder(),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: field,
        );
      }).toList(),
    );
  }

  String _humanize(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        )
        .join(' ');
  }
}
