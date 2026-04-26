import 'package:flutter/material.dart';

/// Renders any JSON Schema as a Flutter form
/// 
/// Supports: string, number, boolean, enum, array, date, email
/// Auto-generates validation from schema constraints
class DynamicFormRenderer extends StatefulWidget {
  final Map<String, dynamic> jsonSchema;
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic> formData)? onDataChanged;
  final ValueChanged<bool>? onValidationChanged;

  const DynamicFormRenderer({
    Key? key,
    required this.jsonSchema,
    this.initialData,
    this.onDataChanged,
    this.onValidationChanged,
  }) : super(key: key);

  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

class _DynamicFormRendererState extends State<DynamicFormRenderer> {
  late final Map<String, dynamic> _formData;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, FocusNode> _focusNodes;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _formData = widget.initialData ?? {};
    _controllers = {};
    _focusNodes = {};

    // Initialize controllers for all text/number fields
    _initializeControllers();
  }

  void _initializeControllers() {
    final properties = widget.jsonSchema['properties'] as Map<String, dynamic>? ?? {};

    for (final field in properties.keys) {
      final value = _formData[field];
      final controller = TextEditingController(
        text: value != null ? value.toString() : '',
      );
      _controllers[field] = controller;
      _focusNodes[field] = FocusNode();

      // Listen for changes
      controller.addListener(() {
        _updateFormData(field, controller.text);
      });
    }
  }

  void _updateFormData(String field, dynamic value) {
    setState(() {
      _formData[field] = value;
      widget.onDataChanged?.call(_formData);
      widget.onValidationChanged?.call(_validateForm());
    });
  }

  bool _validateForm() {
    return _formKey.currentState?.validate() ?? false;
  }

  Map<String, dynamic> getFormData() {
    return _formData;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final properties = widget.jsonSchema['properties'] as Map<String, dynamic>? ?? {};
    final required = (widget.jsonSchema['required'] as List?) ?? [];

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...properties.entries.map((entry) {
            final fieldName = entry.key;
            final schema = entry.value as Map<String, dynamic>;
            final isRequired = required.contains(fieldName);

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildFormField(
                fieldName: fieldName,
                schema: schema,
                isRequired: isRequired,
                value: _formData[fieldName],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required bool isRequired,
    dynamic value,
  }) {
    final type = schema['type'] as String?;
    final title = schema['title'] as String? ?? fieldName;
    final description = schema['description'] as String?;

    // Handle different field types
    switch (type) {
      case 'string':
        return _buildStringField(
          fieldName: fieldName,
          schema: schema,
          title: title,
          description: description,
          isRequired: isRequired,
        );

      case 'number':
      case 'integer':
        return _buildNumberField(
          fieldName: fieldName,
          schema: schema,
          title: title,
          description: description,
          isRequired: isRequired,
        );

      case 'boolean':
        return _buildBooleanField(
          fieldName: fieldName,
          schema: schema,
          title: title,
          description: description,
          value: value as bool? ?? false,
        );

      case 'array':
        return _buildArrayField(
          fieldName: fieldName,
          schema: schema,
          title: title,
          isRequired: isRequired,
          value: value as List? ?? [],
        );

      case 'object':
        return _buildObjectField(
          fieldName: fieldName,
          schema: schema,
          title: title,
          value: value as Map? ?? {},
        );

      default:
        return _buildStringField(
          fieldName: fieldName,
          schema: schema,
          title: title,
          description: description,
          isRequired: isRequired,
        );
    }
  }

  /// String field (text, email, pattern)
  Widget _buildStringField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required String title,
    String? description,
    required bool isRequired,
  }) {
    final format = schema['format'] as String?;
    final minLength = schema['minLength'] as int?;
    final maxLength = schema['maxLength'] as int?;
    final pattern = schema['pattern'] as String?;
    final enumValues = schema['enum'] as List?;

    // Enum as dropdown
    if (enumValues != null && enumValues.isNotEmpty) {
      return _buildEnumField(
        fieldName: fieldName,
        title: title,
        enumValues: enumValues,
        value: _formData[fieldName],
        isRequired: isRequired,
      );
    }

    // Get keyboard type from format
    TextInputType keyboardType = TextInputType.text;
    if (format == 'email') keyboardType = TextInputType.emailAddress;
    if (format == 'date') keyboardType = TextInputType.datetime;
    if (pattern?.contains(RegExp(r'\\d')) ?? false) {
      keyboardType = TextInputType.number;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controllers[fieldName],
          focusNode: _focusNodes[fieldName],
          decoration: InputDecoration(
            labelText: title + (isRequired ? ' *' : ''),
            hintText: description,
            border: OutlineInputBorder(),
          ),
          keyboardType: keyboardType,
          minLines: 1,
          maxLines: maxLength != null && maxLength > 100 ? 3 : 1,
          validator: (value) {
            if (isRequired && (value?.isEmpty ?? true)) {
              return '$title is required';
            }
            if (value != null && value.isNotEmpty) {
              if (minLength != null && value.length < minLength) {
                return '$title must be at least $minLength characters';
              }
              if (maxLength != null && value.length > maxLength) {
                return '$title must be at most $maxLength characters';
              }
              if (format == 'email' && !_isValidEmail(value)) {
                return 'Invalid email address';
              }
              if (pattern != null && !RegExp(pattern).hasMatch(value)) {
                return '$title format is invalid';
              }
            }
            return null;
          },
        ),
      ],
    );
  }

  /// Number field (int or double)
  Widget _buildNumberField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required String title,
    String? description,
    required bool isRequired,
  }) {
    final minimum = schema['minimum'] as num?;
    final maximum = schema['maximum'] as num?;
    final isInteger = schema['type'] == 'integer';

    return TextFormField(
      controller: _controllers[fieldName],
      decoration: InputDecoration(
        labelText: title + (isRequired ? ' *' : ''),
        hintText: description,
        border: OutlineInputBorder(),
      ),
      keyboardType: isInteger
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (isRequired && (value?.isEmpty ?? true)) {
          return '$title is required';
        }
        if (value != null && value.isNotEmpty) {
          try {
            final num = isInteger ? int.parse(value) : double.parse(value);
            if (minimum != null && num < minimum) {
              return '$title must be at least $minimum';
            }
            if (maximum != null && num > maximum) {
              return '$title must be at most $maximum';
            }
          } catch (e) {
            return 'Invalid number';
          }
        }
        return null;
      },
    );
  }

  /// Boolean field (checkbox)
  Widget _buildBooleanField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required String title,
    String? description,
    required bool value,
  }) {
    return CheckboxListTile(
      title: Text(title),
      subtitle: description != null ? Text(description) : null,
      value: value,
      onChanged: (newValue) {
        _updateFormData(fieldName, newValue ?? false);
      },
    );
  }

  /// Enum field (dropdown)
  Widget _buildEnumField({
    required String fieldName,
    required String title,
    required List<dynamic> enumValues,
    dynamic value,
    required bool isRequired,
  }) {
    return DropdownButtonFormField<String>(
      value: value?.toString(),
      items: enumValues
          .map((e) => DropdownMenuItem<String>(
                value: e.toString(),
                child: Text(_humanizeEnumValue(e.toString())),
              ))
          .toList(),
      onChanged: (newValue) {
        if (newValue != null) {
          _updateFormData(fieldName, newValue);
        }
      },
      decoration: InputDecoration(
        labelText: title + (isRequired ? ' *' : ''),
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (isRequired && (value?.isEmpty ?? true)) {
          return '$title is required';
        }
        return null;
      },
    );
  }

  /// Array field (checklist or object array)
  Widget _buildArrayField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required String title,
    required bool isRequired,
    required List<dynamic> value,
  }) {
    final itemSchema = schema['items'] as Map<String, dynamic>?;
    final itemType = itemSchema?['type'] as String?;

    if (itemType == 'object') {
      return _buildObjectArrayField(
        fieldName: fieldName,
        schema: itemSchema ?? {},
        title: title,
        items: value.cast<Map<String, dynamic>>(),
      );
    }

    // Simple string array
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...List.generate(
          value.length,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: value[index].toString(),
                    onChanged: (newValue) {
                      value[index] = newValue;
                      _updateFormData(fieldName, value);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () {
                    value.removeAt(index);
                    _updateFormData(fieldName, value);
                  },
                ),
              ],
            ),
          ),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.add),
          label: Text('Add'),
          onPressed: () {
            value.add('');
            _updateFormData(fieldName, value);
          },
        ),
      ],
    );
  }

  /// Object array (like checklist items)
  Widget _buildObjectArrayField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required String title,
    required List<Map<String, dynamic>> items,
  }) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...List.generate(
          items.length,
          (index) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...properties.entries.map((entry) {
                    final propName = entry.key;
                    final propSchema = entry.value as Map<String, dynamic>;
                    final itemValue = items[index][propName];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildPropertyEditor(
                        fieldName: '$fieldName[$index][$propName]',
                        propName: propName,
                        schema: propSchema,
                        value: itemValue,
                        onChanged: (newValue) {
                          items[index][propName] = newValue;
                          _updateFormData(fieldName, items);
                        },
                      ),
                    );
                  }).toList(),
                  if (items.length > 1)
                    TextButton.icon(
                      icon: Icon(Icons.delete),
                      label: Text('Remove'),
                      onPressed: () {
                        items.removeAt(index);
                        _updateFormData(fieldName, items);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.add),
          label: Text('Add Item'),
          onPressed: () {
            // Add empty object with all properties
            final newItem = <String, dynamic>{};
            for (final prop in properties.keys) {
              newItem[prop] = null;
            }
            items.add(newItem);
            _updateFormData(fieldName, items);
          },
        ),
      ],
    );
  }

  /// Simple property editor for nested objects
  Widget _buildPropertyEditor({
    required String fieldName,
    required String propName,
    required Map<String, dynamic> schema,
    dynamic value,
    required ValueChanged<dynamic> onChanged,
  }) {
    final type = schema['type'] as String?;
    final title = schema['title'] as String? ?? propName;
    final enumValues = schema['enum'] as List?;

    if (enumValues != null && enumValues.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: value?.toString(),
        items: enumValues
            .map((e) => DropdownMenuItem<String>(
                  value: e.toString(),
                  child: Text(_humanizeEnumValue(e.toString())),
                ))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: title,
          isDense: true,
          border: OutlineInputBorder(),
        ),
      );
    }

    if (type == 'boolean') {
      return CheckboxListTile(
        title: Text(title),
        value: value as bool? ?? false,
        dense: true,
        onChanged: onChanged,
      );
    }

    return TextFormField(
      initialValue: value?.toString() ?? '',
      decoration: InputDecoration(
        labelText: title,
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }

  /// Object field (nested object)
  Widget _buildObjectField({
    required String fieldName,
    required Map<String, dynamic> schema,
    required String title,
    required Map<String, dynamic> value,
  }) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...properties.entries.map((entry) {
              final propName = entry.key;
              final propSchema = entry.value as Map<String, dynamic>;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildPropertyEditor(
                  fieldName: '$fieldName.$propName',
                  propName: propName,
                  schema: propSchema,
                  value: value[propName],
                  onChanged: (newValue) {
                    value[propName] = newValue;
                    _updateFormData(fieldName, value);
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return regex.hasMatch(email);
  }

  String _humanizeEnumValue(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
