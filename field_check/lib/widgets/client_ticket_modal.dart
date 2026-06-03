import 'package:flutter/material.dart';
import 'package:field_check/widgets/client_ticket_form.dart';

class ClientTicketModal extends StatelessWidget {
  final Function(String ticketNumber)? onSuccess;

  const ClientTicketModal({
    super.key,
    this.onSuccess,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ClientTicketForm(
          onSuccess: (ticketNumber) {
            onSuccess?.call(ticketNumber);
            // Let the form handle its own navigation closure
            Navigator.pop(context);
          },
          onClose: () {
            // Only pop if not already popped by onSuccess
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }
}
