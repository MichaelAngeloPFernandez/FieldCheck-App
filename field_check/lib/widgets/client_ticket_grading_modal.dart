import 'package:flutter/material.dart';
import 'package:field_check/services/client_ticket_service.dart';

class ClientTicketGradingModal extends StatefulWidget {
  final void Function(
    String ticketNumber,
    String accessToken,
    bool rememberOnDevice,
  )
  onAccessGranted;

  const ClientTicketGradingModal({super.key, required this.onAccessGranted});

  @override
  State<ClientTicketGradingModal> createState() =>
      _ClientTicketGradingModalState();
}

class _ClientTicketGradingModalState extends State<ClientTicketGradingModal> {
  final _ticketController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _rememberOnDevice = false;

  Future<void> _submit() async {
    final ticketNumber = _ticketController.text.trim().toUpperCase();
    final clientEmail = _emailController.text.trim();

    if (ticketNumber.isEmpty || clientEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter both the exact RNG ticket number and your email.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await ClientTicketService().requestTicketAccess(
        ticketNumber: ticketNumber,
        clientEmail: clientEmail,
      );
      final data = result['data'] as Map<String, dynamic>? ?? const {};
      final accessToken = (data['accessToken'] ?? '').toString();
      if (!mounted) return;
      if (accessToken.isEmpty) {
        throw Exception(result['error'] ?? 'Failed to open ticket grading');
      }
      widget.onAccessGranted(ticketNumber, accessToken, _rememberOnDevice);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _ticketController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Grade a Task Report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the exact RNG ticket number and the client email used for that ticket.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ticketController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Exact RNG Ticket',
              hintText: 'RNG-20260601-AB12',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Client Email',
              hintText: 'client@example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'The report can only be graded after it is reviewed, and each assigned employee can be graded separately.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _rememberOnDevice,
            onChanged: _isSubmitting
                ? null
                : (value) {
                    setState(() {
                      _rememberOnDevice = value ?? false;
                    });
                  },
            title: const Text('Remember this ticket on this device'),
            subtitle: const Text(
              'Use this only on your own device.',
              style: TextStyle(fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Open Grading'),
        ),
      ],
    );
  }
}
