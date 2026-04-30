import 'package:flutter/material.dart';

/// Renders a dynamic form from a JSON Schema.
/// Maps JSON Schema types to Flutter widgets:
///   string         → TextField
///   string + enum  → DropdownButtonFormField
///   boolean        → CheckboxListTile
///   number/integer → TextField with number keyboard
///   object         → Grouped card with nested fields
///   array of uri   → placeholder (attachment handled externally)
class DynamicFormRenderer extends StatefulWidget {
  final Map<String, dynamic> jsonSchema;
  final Map<String, dynamic> initialData;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  const DynamicFormRenderer({
    super.key,
    required this.jsonSchema,
    this.initialData = const {},
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

class _DynamicFormRendererState extends State<DynamicFormRenderer> {
  late Map<String, dynamic> _formData;

  @override
  void initState() {
    super.initState();
    _formData = Map<String, dynamic>.from(widget.initialData);
  }

  void _updateField(String key, dynamic value) {
    setState(() {
      _formData[key] = value;
    });
    widget.onChanged(_formData);
  }

  void _updateNestedField(String parentKey, String childKey, dynamic value) {
    setState(() {
      if (_formData[parentKey] is! Map) {
        _formData[parentKey] = <String, dynamic>{};
      }
      (_formData[parentKey] as Map<String, dynamic>)[childKey] = value;
    });
    widget.onChanged(_formData);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final props = _properties;
    final required = _requiredFields;

    if (props.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No form fields defined in template.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: props.entries.map((entry) {
        final key = entry.key;
        final schema =
            entry.value is Map<String, dynamic> ? entry.value as Map<String, dynamic> : <String, dynamic>{};
        final isRequired = required.contains(key);
        return _buildField(key, schema, isRequired, theme);
      }).toList(),
    );
  }

  Widget _buildField(
      String key, Map<String, dynamic> schema, bool isRequired, ThemeData theme) {
    final type = schema['type']?.toString() ?? 'string';
    final title = schema['title']?.toString() ?? _humanize(key);
    final enumValues = schema['enum'];

    // Skip array fields (photos/attachments handled separately)
    if (type == 'array') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title ${isRequired ? "*" : ""}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.attach_file, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Attachments handled via upload button',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Object type → nested fields
    if (type == 'object') {
      return _buildObjectField(key, schema, isRequired, theme);
    }

    // Boolean → Checkbox
    if (type == 'boolean') {
      return _buildBooleanField(key, title, isRequired, theme);
    }

    // String with enum → Dropdown
    if (type == 'string' && enumValues is List && enumValues.isNotEmpty) {
      return _buildEnumField(key, title, isRequired, enumValues, theme);
    }

    // Number/Integer → Number input
    if (type == 'number' || type == 'integer') {
      return _buildNumberField(key, title, isRequired, theme);
    }

    // Default: String → TextField
    return _buildStringField(key, title, isRequired, schema, theme);
  }

  Widget _buildStringField(String key, String title, bool isRequired,
      Map<String, dynamic> schema, ThemeData theme) {
    final format = schema['format']?.toString();
    final isDate = format == 'date';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: _formData[key]?.toString() ?? '',
        readOnly: widget.readOnly || isDate,
        decoration: InputDecoration(
          labelText: '$title${isRequired ? " *" : ""}',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          suffixIcon: isDate
              ? IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: widget.readOnly
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            _updateField(key,
                                picked.toIso8601String().split('T').first);
                          }
                        },
                )
              : null,
        ),
        maxLines: key.contains('note') || key.contains('description') ? 3 : 1,
        onChanged: widget.readOnly ? null : (v) => _updateField(key, v),
      ),
    );
  }

  Widget _buildEnumField(String key, String title, bool isRequired,
      List enumValues, ThemeData theme) {
    final currentValue = _formData[key]?.toString();
    final items = enumValues.map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: items.contains(currentValue) ? currentValue : null,
        decoration: InputDecoration(
          labelText: '$title${isRequired ? " *" : ""}',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        ),
        items: items.map((v) {
          return DropdownMenuItem(
            value: v,
            child: Text(_humanize(v)),
          );
        }).toList(),
        onChanged: widget.readOnly ? null : (v) => _updateField(key, v),
      ),
    );
  }

  Widget _buildBooleanField(
      String key, String title, bool isRequired, ThemeData theme) {
    final value = _formData[key] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CheckboxListTile(
        value: value,
        title: Text('$title${isRequired ? " *" : ""}'),
        onChanged: widget.readOnly
            ? null
            : (v) => _updateField(key, v ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildNumberField(
      String key, String title, bool isRequired, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: _formData[key]?.toString() ?? '',
        readOnly: widget.readOnly,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '$title${isRequired ? " *" : ""}',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        ),
        onChanged: widget.readOnly
            ? null
            : (v) {
                final n = num.tryParse(v);
                _updateField(key, n ?? v);
              },
      ),
    );
  }

  Widget _buildObjectField(
      String key, Map<String, dynamic> schema, bool isRequired, ThemeData theme) {
    final title = schema['title']?.toString() ?? _humanize(key);
    final props = schema['properties'];
    final required = schema['required'];
    final requiredList =
        required is List ? required.map((e) => e.toString()).toList() : <String>[];

    if (props is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }

    if (_formData[key] is! Map) {
      _formData[key] = <String, dynamic>{};
    }
    final objectData = _formData[key] as Map<String, dynamic>;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title${isRequired ? " *" : ""}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ...props.entries.map((e) {
                final childKey = e.key;
                final childSchema = e.value is Map<String, dynamic>
                    ? e.value as Map<String, dynamic>
                    : <String, dynamic>{};
                final childType = childSchema['type']?.toString() ?? 'string';
                final childTitle =
                    childSchema['title']?.toString() ?? _humanize(childKey);
                final childRequired = requiredList.contains(childKey);

                if (childType == 'boolean') {
                  final val = objectData[childKey] == true;
                  return CheckboxListTile(
                    value: val,
                    title: Text('$childTitle${childRequired ? " *" : ""}'),
                    onChanged: widget.readOnly
                        ? null
                        : (v) => _updateNestedField(key, childKey, v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextFormField(
                    initialValue: objectData[childKey]?.toString() ?? '',
                    readOnly: widget.readOnly,
                    decoration: InputDecoration(
                      labelText:
                          '$childTitle${childRequired ? " *" : ""}',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: widget.readOnly
                        ? null
                        : (v) => _updateNestedField(key, childKey, v),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _humanize(String key) {
    return key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'),
            (m) => '${m.group(1)} ${m.group(2)}')
        .split(' ')
        .map((w) => w.isNotEmpty
            ? '${w[0].toUpperCase()}${w.substring(1)}'
            : '')
        .join(' ');
  }
}
