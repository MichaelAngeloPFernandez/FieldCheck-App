import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Sample attendance data
    final attendanceRecords = [
      {
        'date': 'Today',
        'checkIn': '08:30 AM',
        'checkOut': '05:15 PM',
        'location': 'Main Office',
        'status': 'Completed'
      },
      {
        'date': 'Yesterday',
        'checkIn': '08:45 AM',
        'checkOut': '05:30 PM',
        'location': 'Main Office',
        'status': 'Completed'
      },
      {
        'date': '2023-06-15',
        'checkIn': '09:00 AM',
        'checkOut': '04:45 PM',
        'location': 'Site A',
        'status': 'Completed'
      },
      {
        'date': '2023-06-14',
        'checkIn': '08:15 AM',
        'checkOut': '05:00 PM',
        'location': 'Site B',
        'status': 'Completed'
      },
      {
        'date': '2023-06-13',
        'checkIn': '08:30 AM',
        'checkOut': '05:30 PM',
        'location': 'Main Office',
        'status': 'Completed'
      },
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: attendanceRecords.length,
              itemBuilder: (context, index) {
                final record = attendanceRecords[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          record['date']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            record['status']!,
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 16),
                            const SizedBox(width: 4),
                            Text('Check In: ${record['checkIn']}'),
                            const SizedBox(width: 16),
                            const Icon(Icons.access_time, size: 16),
                            const SizedBox(width: 4),
                            Text('Check Out: ${record['checkOut']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16),
                            const SizedBox(width: 4),
                            Text(record['location']!),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}