// ignore_for_file: use_build_context_synchronously, library_prefixes, unnecessary_null_aware_operator, unnecessary_null_comparison, unnecessary_non_null_assertion
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/availability_service.dart';
import 'package:field_check/services/client_ticket_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/models/user_model.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:field_check/config/api_config.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/widgets/admin_control_bar.dart';

class AdminTaskManagementScreen extends StatefulWidget {
  final bool embedded;

  const AdminTaskManagementScreen({super.key, this.embedded = false});

  @override
  State<AdminTaskManagementScreen> createState() =>
      _AdminTaskManagementScreenState();
}

class _AdminTaskManagementScreenState extends State<AdminTaskManagementScreen> {
  final TaskService _taskService = TaskService();
  final UserService _userService = UserService();
  final AvailabilityService _availabilityService = AvailabilityService();
  final ClientTicketService _clientTicketService = ClientTicketService();

  List<Task> _tasks = [];
  List<Task> _archivedTasks = [];
  bool _isLoading = true;
  String _tab = 'current';
  String _difficultyFilter = 'all';
  String _sortBy = 'dueDate'; // 'dueDate', 'difficulty', 'status'
  io.Socket? _socket;

  // Workload tracking
  final Map<String, int> _employeeActiveTaskCount = {};
  final Map<String, double> _employeeDifficultyWeight = {};
  final Map<String, int> _employeeOverdueCount = {};

  static const int _taskLimitPerEmployee = 3;

  Timer? _fetchDebounce;

  // Task filtering state
  final String _typeFilter = 'all';
  final String _assigneeFilter = 'all';
  String _searchQuery = '';

  // Task details state

  Future<String?> _promptAdminReviewNote({
    required BuildContext context,
    required String title,
    required String actionLabel,
  }) async {
    final controller = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Admin note is required.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Admin review note',
                      errorText: error,
                    ),
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final note = controller.text.trim();
                    if (note.isEmpty) {
                      setDialogState(() => error = 'Required');
                      return;
                    }
                    Navigator.of(ctx).pop(note);
                  },
                  child: Text(actionLabel),
                ),
              ],
            );
          },
        );
      },
    );

    return result?.trim().isNotEmpty == true ? result!.trim() : null;
  }

  String _canonicalUserId(UserModel user) {
    if (user.id.isNotEmpty) return user.id;
    final fallback = user.employeeId;
    return (fallback ?? '').trim();
  }

  /// Filter tasks based on current filter state
  List<Task> _getFilteredTasks(List<Task> tasks) {
    return tasks.where((task) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!task.title.toLowerCase().contains(query) &&
            !task.description.toLowerCase().contains(query)) {
          return false;
        }
      }

      // Type filter
      if (_typeFilter != 'all' && (task.type ?? 'general') != _typeFilter) {
        return false;
      }

      // Assignee filter
      if (_assigneeFilter != 'all') {
        final assignees = task.assignedToMultiple.map(_canonicalUserId);
        if (!assignees.contains(_assigneeFilter)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _initSocket();
  }

  Future<void> _escalateTask(Task task) async {
    try {
      final result = await _taskService.escalateTask(task.id);
      if (!mounted) return;

      final sent = result['sent'];
      String message;
      if (sent is int) {
        if (sent > 0) {
          message = 'Escalation SMS sent to $sent assignee(s).';
        } else {
          message = 'No active assignees to escalate for this task.';
        }
      } else {
        message = 'Escalation request completed.';
      }

      AppWidgets.showSuccessSnackbar(context, message);
    } catch (e) {
      debugPrint('Error escalating task: $e');
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to escalate task',
          ),
        );
      }
    }
  }

  Future<void> _archiveTask(Task task) async {
    try {
      await _taskService.archiveTask(task.id);
      await _fetchTasks();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Task archived');
      }
    } catch (e) {
      debugPrint('Error archiving task: $e');
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to archive task',
          ),
        );
      }
    }
  }

  Future<void> _restoreTask(Task task) async {
    try {
      await _taskService.restoreTask(task.id);
      await _fetchTasks();
      if (mounted) {
        AppWidgets.showSuccessSnackbar(context, 'Task restored');
      }
    } catch (e) {
      debugPrint('Error restoring task: $e');
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to restore task',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _socket?.disconnect();
    super.dispose();
  }

  void _scheduleFetchTasks() {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _fetchTasks();
    });
  }

  void _initSocket() {
    // Include auth header and robust reconnection/backoff settings
    final baseOptions = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setTimeout(20000)
        .build();
    baseOptions['reconnection'] = true;
    baseOptions['reconnectionAttempts'] = 999999;
    baseOptions['reconnectionDelay'] = 500;
    baseOptions['reconnectionDelayMax'] = 10000;
    // Attach Authorization header if available
    _userService.getToken().then((token) {
      final options = Map<String, dynamic>.from(baseOptions);
      if (token != null) {
        options['extraHeaders'] = {'Authorization': 'Bearer $token'};
      }
      _socket = io.io(ApiConfig.baseUrl, options);

      _socket?.onConnect((_) => debugPrint('Connected to Socket.IO'));
      _socket?.onDisconnect((_) => debugPrint('Disconnected from Socket.IO'));
      _socket?.onConnectError(
        (err) => debugPrint('Socket.IO Connect Error: $err'),
      );
      _socket?.onError((err) => debugPrint('Socket.IO Error: $err'));
      _socket?.on(
        'reconnect_attempt',
        (_) => debugPrint('Socket.IO reconnect attempt'),
      );
      _socket?.on('reconnect', (_) => debugPrint('Socket.IO reconnected'));
      _socket?.on(
        'reconnect_error',
        (err) => debugPrint('Socket.IO reconnect error: $err'),
      );
      _socket?.on(
        'reconnect_failed',
        (_) => debugPrint('Socket.IO reconnect failed'),
      );

      _socket?.on('newTask', (data) {
        debugPrint('New task received: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('updatedTask', (data) {
        debugPrint('Task updated: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('deletedTask', (data) {
        debugPrint('Task deleted: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('taskAssignedToMultiple', (data) {
        debugPrint('Task assigned to multiple: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('taskUnassigned', (data) {
        debugPrint('Task unassigned: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('userTaskArchived', (data) {
        debugPrint('User task archived: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('userTaskRestored', (data) {
        debugPrint('User task restored: $data');
        _scheduleFetchTasks();
      });

      _socket?.on('updatedUserTask', (data) {
        debugPrint('User task updated: $data');
        _scheduleFetchTasks();
      });
    });
  }

  Future<void> _fetchTasks() async {
    try {
      final current = await _taskService.getCurrentTasks();
      final archived = await _taskService.getArchivedTasks();
      if (!mounted) return;
      setState(() {
        _tasks = current;
        _archivedTasks = archived;
        _isLoading = false;
        _calculateWorkload();
      });
    } catch (e) {
      // Handle error
      debugPrint('Error fetching tasks: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _sortTasks(List<Task> tasks) {
    switch (_sortBy) {
      case 'difficulty':
        tasks.sort((a, b) {
          final diffMap = {'easy': 1, 'medium': 2, 'hard': 3};
          final aVal = diffMap[a.difficulty?.toLowerCase() ?? 'medium'] ?? 2;
          final bVal = diffMap[b.difficulty?.toLowerCase() ?? 'medium'] ?? 2;
          return aVal.compareTo(bVal);
        });
        break;
      case 'status':
        final statusMap = {'pending': 0, 'in_progress': 1, 'completed': 2};
        tasks.sort((a, b) {
          final aVal = statusMap[a.status] ?? 0;
          final bVal = statusMap[b.status] ?? 0;
          return aVal.compareTo(bVal);
        });
        break;
      case 'dueDate':
      default:
        tasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        break;
    }
  }

  void _calculateWorkload() {
    _employeeActiveTaskCount.clear();
    _employeeDifficultyWeight.clear();
    _employeeOverdueCount.clear();

    final now = DateTime.now();

    for (final task in _tasks) {
      // Only count non-completed tasks
      if (task.status == 'completed') continue;

      final Set<String> assigneeIds = <String>{
        ...task.assignedToMultiple
            .map(_canonicalUserId)
            .where((id) => id.isNotEmpty),
        ...?task.teamMembers?.where((id) => id.trim().isNotEmpty),
      };

      for (final userId in assigneeIds) {
        // Count active tasks
        _employeeActiveTaskCount[userId] =
            (_employeeActiveTaskCount[userId] ?? 0) + 1;

        // Calculate difficulty weight
        double weight = 1.0;
        switch (task.difficulty?.toLowerCase() ?? 'medium') {
          case 'easy':
            weight = 1.0;
            break;
          case 'medium':
            weight = 2.0;
            break;
          case 'hard':
            weight = 3.0;
            break;
          case 'critical':
            weight = 5.0;
            break;
          default:
            weight = 2.0;
        }
        _employeeDifficultyWeight[userId] =
            (_employeeDifficultyWeight[userId] ?? 0.0) + weight;

        // Count overdue tasks
        if (task.dueDate != null) {
          if (task.dueDate!.isBefore(now)) {
            _employeeOverdueCount[userId] =
                (_employeeOverdueCount[userId] ?? 0) + 1;
          }
        }
      }
    }
  }

  Future<void> _addTask() async {
    // ── Pre-load employees before opening the dialog ──────────
    List<UserModel> employees = [];
    try {
      employees = (await _userService.fetchEmployees())
          .where((e) => e.id.isNotEmpty && e.isActive)
          .toList();
    } catch (e) {
      debugPrint('Error pre-loading employees: $e');
      // Non-fatal — dialog still opens, dropdowns will just be empty
    }

    final TextEditingController titleController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    DateTime? dueDate;
    String taskType = 'general';
    String taskDifficulty = 'medium';
    String? dialogError;
    bool isSubmitting = false;

    // ── New fields ───────────────────────────────────────────────────────────
    UserModel? selectedEmployee;
    
    // ── Ticket linking fields ────────────────────────────────────────────────
    List<Map<String, dynamic>> pendingTickets = [];
    bool loadingTickets = false;
    String? selectedTicketId;
    Map<String, dynamic>? selectedTicket;
    final TextEditingController manualTicketController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            
            // Helper functions for ticket linking (moved inside StatefulBuilder)
            Future<void> fetchPendingTickets() async {
              dialogSetState(() {
                loadingTickets = true;
                dialogError = null;
              });
              
              try {
                final response = await _clientTicketService.fetchPendingTickets(limit: 50);
                final tickets = response['data'] as List<dynamic>? ?? [];
                
                dialogSetState(() {
                  pendingTickets = tickets.cast<Map<String, dynamic>>();
                  loadingTickets = false;
                });
              } catch (e) {
                dialogSetState(() {
                  loadingTickets = false;
                  dialogError = 'Failed to load pending tickets: ${e.toString()}';
                });
              }
            }
            
            void onTicketSelected(String? ticketId) {
              dialogSetState(() {
                selectedTicketId = ticketId;
                selectedTicket = ticketId == null 
                    ? null 
                    : pendingTickets.firstWhere(
                        (ticket) => ticket['_id'] == ticketId,
                        orElse: () => <String, dynamic>{},
                      );
                
                // Auto-fill description when ticket is selected
                if (selectedTicket != null && selectedTicket!.isNotEmpty) {
                  final ticketNumber = selectedTicket!['ticketNumber'] ?? 'Unknown';
                  final clientName = selectedTicket!['clientName'] ?? 'Unknown Client';
                  final serviceType = selectedTicket!['serviceType'] ?? 'Unknown Service';
                  final description = selectedTicket!['description'] ?? '';
                  
                  // Auto-fill task details based on ticket
                  titleController.text = 'Task for Ticket $ticketNumber';
                  descriptionController.text = 'Client: $clientName\n'
                      'Service Type: $serviceType\n'
                      'Request: $description\n\n'
                      'Follow standard workflow: Accept → Work → Submit for Review';
                  
                  // Clear manual ticket field when dropdown is used
                  manualTicketController.clear();
                }
                
                dialogError = null;
              });
            }
            
            void onManualTicketChanged(String value) {
              dialogSetState(() {
                // Clear dropdown selection when manual field is used
                if (value.trim().isNotEmpty) {
                  selectedTicketId = null;
                  selectedTicket = null;
                }
                dialogError = null;
              });
            }
            
            // Load pending tickets when dialog opens (only once)
            if (pendingTickets.isEmpty && !loadingTickets) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                fetchPendingTickets();
              });
            }
            return AlertDialog(
              title: const Text('Create New Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Error banner ─────────────────────────────────────────
                    if (dialogError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Title ────────────────────────────────────────────────
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // ── Description ──────────────────────────────────────────
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // ── Task Type ────────────────────────────────────────────
                    DropdownButtonFormField<String>(
                      initialValue: taskType,
                      decoration: const InputDecoration(
                        labelText: 'Task Type',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'general',
                          child: Text('General'),
                        ),
                        DropdownMenuItem(
                          value: 'inspection',
                          child: Text('Inspection'),
                        ),
                        DropdownMenuItem(
                          value: 'maintenance',
                          child: Text('Maintenance'),
                        ),
                        DropdownMenuItem(
                          value: 'delivery',
                          child: Text('Delivery'),
                        ),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        dialogSetState(() {
                          taskType = value;
                          dialogError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // ── Difficulty ───────────────────────────────────────────
                    DropdownButtonFormField<String>(
                      initialValue: taskDifficulty,
                      decoration: const InputDecoration(
                        labelText: 'Difficulty',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'easy', child: Text('Easy')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(value: 'hard', child: Text('Hard')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        dialogSetState(() {
                          taskDifficulty = value;
                          dialogError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // ── Link to Pending Ticket dropdown ─────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedTicketId,
                            decoration: const InputDecoration(
                              labelText: 'Link to Pending Ticket (optional)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              prefixIcon: Icon(Icons.link),
                            ),
                            hint: loadingTickets 
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Loading tickets...'),
                                    ],
                                  )
                                : const Text('Select a pending ticket...'),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('— No ticket linking —'),
                              ),
                              ...pendingTickets.map((ticket) {
                                final ticketNumber = ticket['ticketNumber'] ?? 'Unknown';
                                final clientName = ticket['clientName'] ?? 'Unknown Client';
                                final serviceType = ticket['serviceType'] ?? 'Unknown Service';
                                return DropdownMenuItem<String>(
                                  value: ticket['_id'],
                                  child: Text(
                                    '$ticketNumber - $clientName - $serviceType',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: loadingTickets ? null : onTicketSelected,
                            isExpanded: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: loadingTickets ? null : fetchPendingTickets,
                          icon: loadingTickets 
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          tooltip: 'Refresh pending tickets',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Manual Client Ticket Number field ───────────────────
                    TextField(
                      controller: manualTicketController,
                      decoration: const InputDecoration(
                        labelText: 'Client Ticket Number (optional)',
                        hintText: 'e.g., RNG-20240101-ABCD',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        prefixIcon: Icon(Icons.confirmation_number),
                        helperText: 'Alternative to dropdown - enter ticket number manually',
                      ),
                      onChanged: onManualTicketChanged,
                    ),
                    const SizedBox(height: 10),

                    // ── Due Date ─────────────────────────────────────────────
                    InkWell(
                      onTap: () async {
                        final DateTime? selected = await showDatePicker(
                          context: context,
                          initialDate: dueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          dialogSetState(() {
                            dueDate = selected;
                            dialogError = null;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Due Date *',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          suffixIcon: const Icon(Icons.calendar_today),
                          errorText:
                              dueDate == null &&
                                  dialogError != null &&
                                  dialogError!.contains('due')
                              ? 'Required'
                              : null,
                        ),
                        child: Text(
                          dueDate == null
                              ? 'Tap to select…'
                              : formatManila(dueDate, 'yyyy-MM-dd'),
                          style: TextStyle(
                            color: dueDate == null
                                ? Colors.grey.shade500
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Assign Employee dropdown ──────────────────────────────
                    const Text(
                      'Assign To (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: selectedEmployee?.id,
                      decoration: InputDecoration(
                        hintText: employees.isEmpty
                            ? 'No employees available'
                            : 'Select an employee…',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            '— Unassigned —',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        ...employees.map((e) {
                          final label =
                              e.employeeId != null && e.employeeId!.isNotEmpty
                              ? '${e.name} (${e.employeeId})'
                              : e.name;
                          final activeTasks = e.activeTaskCount ?? 0;
                          final atLimit = activeTasks >= _taskLimitPerEmployee;
                          return DropdownMenuItem<String>(
                            value: e.id,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: atLimit
                                          ? Colors.orange.shade700
                                          : null,
                                    ),
                                  ),
                                ),
                                if (activeTasks > 0)
                                  Text(
                                    ' $activeTasks active',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: atLimit
                                          ? Colors.orange.shade700
                                          : Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: employees.isEmpty
                          ? null
                          : (id) {
                              final emp = id == null
                                  ? null
                                  : employees
                                        .where((e) => e.id == id)
                                        .cast<UserModel?>()
                                        .firstWhere(
                                          (_) => true,
                                          orElse: () => null,
                                        );
                              dialogSetState(() {
                                selectedEmployee = emp;
                                dialogError = null;
                              });
                            },
                      isExpanded: true,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final String title = titleController.text.trim();
                          final String description = descriptionController.text
                              .trim();

                          if (title.isEmpty) {
                            dialogSetState(
                              () => dialogError = 'Title is required.',
                            );
                            return;
                          }
                          if (description.isEmpty) {
                            dialogSetState(
                              () => dialogError = 'Description is required.',
                            );
                            return;
                          }
                          if (dueDate == null) {
                            dialogSetState(
                              () => dialogError = 'Due date is required.',
                            );
                            return;
                          }

                          dialogSetState(() {
                            dialogError = null;
                            isSubmitting = true;
                          });

                          // Determine final ticket information for linking
                          String? linkedTicketNumber;
                          String? linkedTicketId;
                          
                          if (selectedTicket != null && selectedTicket!.isNotEmpty) {
                            // Use dropdown selection
                            linkedTicketNumber = selectedTicket!['ticketNumber'];
                            linkedTicketId = selectedTicket!['_id'];
                          } else if (manualTicketController.text.trim().isNotEmpty) {
                            // Use manual entry
                            linkedTicketNumber = manualTicketController.text.trim();
                            // Note: Manual entry doesn't have an ID, just the number
                          }
                          
                          // Enhance description with ticket linking info if provided
                          String finalDescription = description;
                          if (linkedTicketNumber != null) {
                            finalDescription = '$description\n\n--- LINKED TO CLIENT TICKET ---\n'
                                'Ticket Number: $linkedTicketNumber\n'
                                'Linked at: ${DateTime.now().toIso8601String()}';
                          }

                          final newTask = Task(
                            id: '',
                            title: title,
                            description: finalDescription,
                            type: taskType,
                            difficulty: taskDifficulty,
                            dueDate: dueDate!,
                            assignedBy:
                                _userService.currentUser?.id ?? 'unknown_admin',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                            lastViewedAt: null,
                            status: 'pending',
                            rawStatus: 'pending',
                            progressPercent: 0,
                            userTaskId: null,
                            assignedTo: null,
                            geofenceId: null,
                            latitude: null,
                            longitude: null,
                          );

                          try {
                            final created = await _taskService.createTask(
                              newTask,
                            );

                            // Auto-assign the selected employee if one was chosen
                            if (selectedEmployee != null &&
                                created.id.isNotEmpty) {
                              try {
                                await _taskService.assignTask(
                                  created.id,
                                  selectedEmployee!.id,
                                );
                              } catch (assignErr) {
                                debugPrint(
                                  'Task created but assignment failed: $assignErr',
                                );
                                // Task was created — show a partial-success message
                                _fetchTasks();
                                if (mounted) {
                                  AppWidgets.showWarningSnackbar(
                                    context,
                                    'Task created, but could not assign to '
                                    '${selectedEmployee!.name}: $assignErr',
                                  );
                                }
                                Navigator.of(context).pop();
                                return;
                              }
                            }

                            _fetchTasks();
                            if (mounted) {
                              final assignMsg = selectedEmployee != null
                                  ? ' and assigned to ${selectedEmployee!.name}'
                                  : '';
                              final ticketMsg = linkedTicketNumber != null
                                  ? ' (linked to ticket $linkedTicketNumber)'
                                  : '';
                              AppWidgets.showSuccessSnackbar(
                                context,
                                'Task created$assignMsg$ticketMsg!',
                              );
                            }
                            Navigator.of(context).pop();
                          } catch (e) {
                            debugPrint('Error adding task: $e');
                            dialogSetState(() {
                              dialogError = 'Failed to add task: $e';
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editTask(Task task) async {
    final TextEditingController titleController = TextEditingController(
      text: task.title,
    );
    final TextEditingController descriptionController = TextEditingController(
      text: task.description,
    );
    DateTime? dueDate = task.dueDate;
    String taskType = task.type ?? 'general';
    String taskDifficulty = task.difficulty ?? 'medium';
    String? dialogError;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return AlertDialog(
              title: const Text('Edit Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          dialogSetState(() => dialogError = null);
                        }
                      },
                    ),
                    ListTile(
                      title: Text(
                        dueDate == null
                            ? 'Due Date: (required)'
                            : 'Due Date: ${formatManila(dueDate, 'yyyy-MM-dd')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final DateTime? selected = await showDatePicker(
                          context: context,
                          initialDate: dueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          dialogSetState(() {
                            dueDate = selected;
                            dialogError = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final String title = titleController.text.trim();
                          final String description = descriptionController.text
                              .trim();

                          if (title.isEmpty) {
                            dialogSetState(() {
                              dialogError = 'Title is required.';
                            });
                            return;
                          }
                          if (description.isEmpty) {
                            dialogSetState(() {
                              dialogError = 'Description is required.';
                            });
                            return;
                          }
                          if (dueDate == null) {
                            dialogSetState(() {
                              dialogError = 'Due date is required.';
                            });
                            return;
                          }

                          dialogSetState(() {
                            dialogError = null;
                            isSubmitting = true;
                          });

                          final updatedTask = task.copyWith(
                            title: title,
                            description: description,
                            type: taskType,
                            difficulty: taskDifficulty,
                            dueDate: dueDate!,
                          );
                          try {
                            await _taskService.updateTask(updatedTask);
                            _fetchTasks();
                            if (mounted) {
                              AppWidgets.showSuccessSnackbar(
                                context,
                                'Task updated successfully!',
                              );
                            }
                            Navigator.of(context).pop();
                          } catch (e) {
                            debugPrint('Error updating task: $e');
                            dialogSetState(() {
                              dialogError = 'Failed to update task: $e';
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTask(String taskId) async {
    final bool confirmDelete =
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Confirm Delete'),
              content: const Text('Are you sure you want to delete this task?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirmDelete) {
      try {
        await _taskService.deleteTask(taskId);
        _fetchTasks(); // Refresh the task list
        AppWidgets.showSuccessSnackbar(context, 'Task deleted successfully!');
      } catch (e) {
        debugPrint('Error deleting task: $e');
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(e, fallback: 'Failed to delete task'),
        );
      }
    }
  }

  Future<void> _assignTask(Task task) async {
    List<UserModel> employees = [];
    try {
      employees = await _userService.fetchEmployees();
      if (employees.isEmpty) {
        if (mounted) {
          AppWidgets.showWarningSnackbar(context, 'No employees available');
        }
        return;
      }
      employees = employees.where((e) => e.id.isNotEmpty).toList();
      if (employees.isEmpty) {
        if (mounted) {
          AppWidgets.showWarningSnackbar(context, 'No valid employees found');
        }
        return;
      }
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      if (mounted) {
        AppWidgets.showErrorSnackbar(
          context,
          AppWidgets.friendlyErrorMessage(
            e,
            fallback: 'Failed to fetch employees',
          ),
        );
      }
      return;
    }

    final Map<String, String> assigneeIdToEmployeeModelId = {};
    for (final e in employees) {
      if (e.id.isNotEmpty) {
        assigneeIdToEmployeeModelId[e.id] = e.id;
      }
      final empId = e.employeeId;
      if (empId != null && empId.trim().isNotEmpty) {
        assigneeIdToEmployeeModelId[empId] = e.id;
      }
    }

    final Map<String, _AvailabilityInfo> availability = {};
    final Set<String> availabilityAssignedIds = <String>{};
    try {
      final nearby = await _availabilityService.getNearbyForTask(task.id);
      assert(() {
        if (nearby.isNotEmpty) {
          try {
            final first = nearby.first;
            debugPrint(
              'Assign dialog debug: availability first keys=${first.keys.toList()}',
            );
          } catch (_) {}
        }
        return true;
      }());
      for (final item in nearby) {
        final dynamic rawId =
            item['userId'] ?? item['employeeId'] ?? item['_id'] ?? item['id'];
        final String idStr = (rawId ?? '').toString();
        if (idStr.isEmpty) continue;
        final String normalizedId = assigneeIdToEmployeeModelId[idStr] ?? idStr;

        final dynamic assignedValue =
            item['isAssigned'] ??
            item['assigned'] ??
            item['assignedToTask'] ??
            item['isAssignedToTask'] ??
            item['alreadyAssigned'] ??
            item['hasTask'] ??
            item['hasThisTask'];
        final bool isAssignedFlag =
            assignedValue == true || assignedValue == 'true';
        if (isAssignedFlag) {
          availabilityAssignedIds.add(normalizedId);
        }

        availability[normalizedId] = _AvailabilityInfo(
          distanceMeters: (item['distanceMeters'] is num)
              ? (item['distanceMeters'] as num).toDouble()
              : 0,
          activeTasksCount: item['activeTasksCount'] is int
              ? item['activeTasksCount'] as int
              : (item['activeTasksCount'] ?? 0) as int,
          overdueTasksCount: item['overdueTasksCount'] is int
              ? item['overdueTasksCount'] as int
              : (item['overdueTasksCount'] ?? 0) as int,
          workloadStatus: (item['workloadStatus'] ?? 'available') as String,
        );
      }
    } catch (e) {
      debugPrint('Error fetching nearby availability: $e');
    }

    Task serverTask = task;
    try {
      serverTask = await _taskService.getTaskById(task.id);
    } catch (e) {
      debugPrint('Error fetching task details for assignment: $e');
    }

    List<String> serverAssigneeIdsFromApi = <String>[];
    try {
      serverAssigneeIdsFromApi = await _taskService.getAssigneeIdsForTask(
        task.id,
      );
    } catch (e) {
      debugPrint('Error fetching task assignees for assignment: $e');
    }

    assert(() {
      final assignedIds = serverTask.assignedToMultiple
          .map(_canonicalUserId)
          .where((id) => id.isNotEmpty)
          .toList();
      debugPrint(
        'Assign dialog debug: taskId=${task.id} assignedToMultipleIds=$assignedIds teamMembers=${serverTask.teamMembers}',
      );
      final sampleEmployees = employees
          .take(5)
          .map((e) => 'id=${e.id}, employeeId=${e.employeeId}')
          .toList();
      debugPrint('Assign dialog debug: sample employees: $sampleEmployees');
      debugPrint(
        'Assign dialog debug: assigneeIdToEmployeeModelId keys sample: ${assigneeIdToEmployeeModelId.keys.take(10).toList()}',
      );
      return true;
    }());

    final selectedEmployeeIds = <String>{};

    if (serverAssigneeIdsFromApi.isNotEmpty) {
      selectedEmployeeIds.addAll(
        serverAssigneeIdsFromApi.where((id) => id.trim().isNotEmpty),
      );
    }

    final initialSelectedEmployeeIds = <String>{...selectedEmployeeIds};

    assert(() {
      if (availabilityAssignedIds.isNotEmpty) {
        debugPrint(
          'Assign dialog debug: availabilityAssignedIds=$availabilityAssignedIds',
        );
      }
      debugPrint(
        'Assign dialog debug: selectedEmployeeIds(initial)=${selectedEmployeeIds.toList()} (count=${selectedEmployeeIds.length})',
      );
      return true;
    }());

    if (!mounted) return;

    bool replaceAssignees = false;

    String? dialogNotice;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, dialogSetState) {
          void showDialogNotice(String message) {
            dialogSetState(() {
              dialogNotice = message;
            });
          }

          return AlertDialog(
            title: Text('Assign Task: ${task.title}'),
            content: SizedBox(
              width: double.maxFinite,
              height: 520,
              child: Column(
                children: [
                  if (dialogNotice != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Action needed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dialogNotice!,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss',
                            onPressed: () {
                              dialogSetState(() {
                                dialogNotice = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('Replace assignees'),
                    subtitle: const Text(
                      'When enabled, unchecking an employee will unassign them from this task.',
                    ),
                    value: replaceAssignees,
                    onChanged: (val) {
                      dialogSetState(() {
                        replaceAssignees = val;
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final ids = employees
                                  .map((e) => e.id)
                                  .where((id) => id.trim().isNotEmpty)
                                  .where((id) {
                                    final info = availability[id];
                                    final employee = employees
                                        .where((e) => e.id == id)
                                        .cast<UserModel?>()
                                        .firstWhere(
                                          (_) => true,
                                          orElse: () => null,
                                        );
                                    final activeCount =
                                        [
                                          info?.activeTasksCount ?? 0,
                                          _employeeActiveTaskCount[id] ?? 0,
                                          employee?.activeTaskCount ?? 0,
                                        ].cast<int>().reduce(
                                          (a, b) => a > b ? a : b,
                                        );
                                    final atLimit =
                                        activeCount >= _taskLimitPerEmployee;
                                    final isAlreadyAssigned =
                                        initialSelectedEmployeeIds.contains(id);
                                    return !atLimit || isAlreadyAssigned;
                                  })
                                  .toList();

                              dialogSetState(() {
                                selectedEmployeeIds
                                  ..clear()
                                  ..addAll(ids);
                              });
                            },
                            icon: const Icon(Icons.select_all),
                            label: const Text('Assign to All'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            dialogSetState(() {
                              selectedEmployeeIds.clear();
                            });
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: employees.isEmpty
                        ? const Center(child: Text('No employees available'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: employees.length,
                            itemBuilder: (context, index) {
                              final employee = employees[index];
                              final isSelected = selectedEmployeeIds.contains(
                                employee.id,
                              );
                              final info = availability[employee.id];

                              final int activeCount = [
                                info?.activeTasksCount ?? 0,
                                _employeeActiveTaskCount[employee.id] ?? 0,
                                employee.activeTaskCount ?? 0,
                              ].cast<int>().reduce((a, b) => a > b ? a : b);

                              final atLimit =
                                  activeCount >= _taskLimitPerEmployee;
                              final isAlreadyAssigned =
                                  initialSelectedEmployeeIds.contains(
                                    employee.id,
                                  );

                              Color? nameColor;
                              if (info != null) {
                                switch (info.workloadStatus) {
                                  case 'overloaded':
                                    nameColor = Colors.redAccent;
                                    break;
                                  case 'busy':
                                    nameColor = Colors.orange;
                                    break;
                                  default:
                                    nameColor = Colors.green;
                                }
                              }

                              String subtitle = employee.email;
                              if (info != null) {
                                final parts = <String>[];
                                parts.add(info.workloadStatus);
                                if (info.activeTasksCount > 0) {
                                  parts.add('${info.activeTasksCount} active');
                                }
                                if (info.overdueTasksCount > 0) {
                                  parts.add(
                                    '${info.overdueTasksCount} overdue',
                                  );
                                }
                                if (info.distanceMeters > 0) {
                                  if (info.distanceMeters >= 1000) {
                                    parts.add(
                                      '${(info.distanceMeters / 1000).toStringAsFixed(1)} km',
                                    );
                                  } else {
                                    parts.add(
                                      '${info.distanceMeters.toStringAsFixed(0)} m',
                                    );
                                  }
                                }
                                subtitle =
                                    '${employee.email} · ${parts.join(' · ')}';
                              } else {
                                subtitle =
                                    '${employee.email} · $activeCount active';
                              }

                              if (atLimit &&
                                  !(isAlreadyAssigned && isSelected)) {
                                subtitle =
                                    '$subtitle · limit reached ($_taskLimitPerEmployee)';
                              }

                              return CheckboxListTile(
                                key: ValueKey('assign:${employee.id}'),
                                title: Text(
                                  employee.name,
                                  style: TextStyle(color: nameColor),
                                ),
                                subtitle: Text(subtitle),
                                value: isSelected,
                                onChanged: (bool? selected) {
                                  final isNewlySelecting =
                                      selected == true && !isAlreadyAssigned;

                                  if (isNewlySelecting && atLimit) {
                                    showDialogNotice(
                                      '${employee.name} is already at/above the max active tasks ($_taskLimitPerEmployee). Unassign/archive some tasks first.',
                                    );
                                    return;
                                  }

                                  dialogSetState(() {
                                    if (selected == true) {
                                      selectedEmployeeIds.add(employee.id);
                                    } else {
                                      selectedEmployeeIds.remove(employee.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: initialSelectedEmployeeIds.isEmpty
                    ? null
                    : () async {
                        final bool confirm =
                            await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('Unassign all assignees?'),
                                content: const Text(
                                  'This will remove all current assignees from this task.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dCtx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dCtx).pop(true),
                                    child: const Text('Unassign all'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;

                        if (!confirm) return;

                        try {
                          await Future.wait(
                            initialSelectedEmployeeIds.map(
                              (id) => _taskService.unassignUserFromTask(
                                task.id,
                                id,
                              ),
                            ),
                          );

                          selectedEmployeeIds.clear();

                          _fetchTasks();

                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                          AppWidgets.showSuccessSnackbar(
                            context,
                            'All assignees unassigned.',
                          );
                        } catch (e) {
                          debugPrint('Error unassigning all: $e');
                          if (!mounted) return;
                          showDialogNotice(
                            'Failed to unassign all assignees: $e',
                          );
                        }
                      },
                child: const Text('Unassign all'),
              ),
              TextButton(
                onPressed: () async {
                  if (selectedEmployeeIds.isNotEmpty || replaceAssignees) {
                    try {
                      final validIds = selectedEmployeeIds
                          .where((id) => id.isNotEmpty)
                          .toList();
                      if (validIds.isEmpty && !replaceAssignees) {
                        showDialogNotice('Selected employees have invalid IDs');
                        return;
                      }

                      final idsToAssign = replaceAssignees
                          ? validIds
                                .where(
                                  (id) =>
                                      !initialSelectedEmployeeIds.contains(id),
                                )
                                .toList()
                          : validIds;
                      final idsToUnassign = replaceAssignees
                          ? initialSelectedEmployeeIds
                                .where(
                                  (id) => !selectedEmployeeIds.contains(id),
                                )
                                .toList()
                          : <String>[];

                      final blocked = idsToAssign.where((id) {
                        final info = availability[id];
                        final employee = employees
                            .where((e) => e.id == id)
                            .cast<UserModel?>()
                            .firstWhere((_) => true, orElse: () => null);
                        final activeCount = [
                          info?.activeTasksCount ?? 0,
                          _employeeActiveTaskCount[id] ?? 0,
                          employee?.activeTaskCount ?? 0,
                        ].cast<int>().reduce((a, b) => a > b ? a : b);
                        return activeCount >= _taskLimitPerEmployee;
                      }).toList();
                      if (blocked.isNotEmpty) {
                        showDialogNotice(
                          'Some selected employees are at the task limit ($_taskLimitPerEmployee). Deselect them to continue.',
                        );
                        return;
                      }

                      Map<String, dynamic> result = <String, dynamic>{};
                      if (idsToAssign.isNotEmpty) {
                        result = await _taskService.assignTaskToMultiple(
                          task.id,
                          idsToAssign,
                        );
                      }

                      if (idsToUnassign.isNotEmpty) {
                        await Future.wait(
                          idsToUnassign.map(
                            (id) =>
                                _taskService.unassignUserFromTask(task.id, id),
                          ),
                        );
                      }

                      if (_socket?.connected == true) {
                        _socket!.emit('taskAssigned', {
                          'taskId': task.id,
                          'employeeIds': idsToAssign,
                        });
                      }

                      _fetchTasks();

                      if (!mounted) return;

                      final summary =
                          result['summary'] as Map<String, dynamic>?;
                      final total = summary?['total'] as int?;
                      final successful = summary?['successful'] as int?;
                      final failed = summary?['failed'] as int?;

                      String message;
                      if (replaceAssignees) {
                        final assignedCount = idsToAssign.length;
                        final unassignedCount = idsToUnassign.length;
                        if (assignedCount == 0 && unassignedCount == 0) {
                          message = 'No changes to task assignees.';
                        } else if (assignedCount > 0 && unassignedCount > 0) {
                          message =
                              'Assignees updated. Added $assignedCount, removed $unassignedCount.';
                        } else if (assignedCount > 0) {
                          message = 'Assignees updated. Added $assignedCount.';
                        } else {
                          message =
                              'Assignees updated. Removed $unassignedCount.';
                        }
                      } else if (summary != null &&
                          total != null &&
                          successful != null &&
                          failed != null) {
                        if (failed == 0) {
                          message =
                              'Task assigned to $successful of $total employees.';
                        } else if (successful == 0) {
                          message =
                              'Failed to assign task to all $total employees (check task limits).';
                        } else {
                          message =
                              'Task assigned to $successful of $total employees. $failed failed (see task limits).';
                        }
                      } else {
                        message = 'Task assignment request completed.';
                      }

                      if (!replaceAssignees &&
                          summary != null &&
                          total != null &&
                          successful != null &&
                          failed != null &&
                          failed > 0) {
                        showDialogNotice(message);
                        return;
                      }

                      Navigator.of(ctx).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        AppWidgets.showSuccessSnackbar(context, message);
                      });
                    } catch (e) {
                      debugPrint('Error assigning task: $e');
                      if (mounted) {
                        showDialogNotice('Failed to assign task: $e');
                      }
                    }
                  } else {
                    showDialogNotice('Please select at least one employee');
                  }
                },
                child: Text(replaceAssignees ? 'Apply' : 'Assign'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTaskDetailsDialog(Task task) {
    showDialog(
      context: context,
      builder: (ctx) {
        final due = task.dueDate;

        Future<List<Map<String, dynamic>>> loadAssignees() async {
          try {
            final list = await _taskService.getTaskAssigneesDetailed(task.id);
            return list;
          } catch (e) {
            debugPrint('Error loading task assignees: $e');
            return <Map<String, dynamic>>[];
          }
        }

        return AlertDialog(
          title: Text(task.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (task.description.isNotEmpty) Text(task.description),
                const SizedBox(height: 12),

                // ── Metadata section ──
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (due != null)
                      _detailRow(
                        Icons.calendar_today,
                        'Due: ${formatManila(due, 'yyyy-MM-dd HH:mm')}',
                      ),
                    _detailRow(
                      Icons.flag,
                      'Status: ${task.status.replaceAll('_', ' ')}',
                    ),
                    if (task.type != null && task.type!.isNotEmpty)
                      _detailRow(Icons.category, 'Type: ${task.type}'),
                    if (task.difficulty != null && task.difficulty!.isNotEmpty)
                      _detailRow(Icons.speed, 'Difficulty: ${task.difficulty}'),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Origin & Service info ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SizedBox.shrink(),
                ),

                // ── Checklist ──
                if (task.checklist.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Checklist (${task.checklist.where((c) => c.isCompleted).length}/${task.checklist.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  ...task.checklist.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            item.isCompleted
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 18,
                            color: item.isCompleted
                                ? const Color(0xFF43A047)
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                decoration: item.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: item.isCompleted
                                    ? Colors.grey.shade500
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Text(
                  'Assignees',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadAssignees(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final rows = snapshot.data ?? <Map<String, dynamic>>[];
                    if (rows.isEmpty) {
                      return const Text('No assignees found.');
                    }

                    bool isBlockedRow(Map<String, dynamic> m) {
                      final s = (m['status'] ?? '')
                          .toString()
                          .toLowerCase()
                          .trim();
                      if (s == 'blocked') return true;
                      final b = (m['blockStatus'] ?? '')
                          .toString()
                          .toLowerCase()
                          .trim();
                      return b == 'blocked';
                    }

                    return Column(
                      children: rows.map((m) {
                        final name =
                            (m['name'] ??
                                    m['username'] ??
                                    m['userId'] ??
                                    'Employee')
                                .toString();
                        final employeeId = (m['employeeId'] ?? '').toString();
                        final status = (m['status'] ?? '').toString();
                        final userTaskId = (m['userTaskId'] ?? '').toString();
                        final blocked = isBlockedRow(m);
                        final reasonCat = (m['blockReasonCategory'] ?? '')
                            .toString()
                            .trim();
                        final reasonText = (m['blockReasonText'] ?? '')
                            .toString()
                            .trim();
                        final evidence = (m['blockEvidencePhotos'] is List)
                            ? (m['blockEvidencePhotos'] as List)
                                  .map((e) => e.toString())
                                  .where((s) => s.trim().isNotEmpty)
                                  .toList()
                            : <String>[];

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: blocked
                                ? Colors.red.withValues(alpha: 0.06)
                                : Colors.grey.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: blocked
                                  ? Colors.red.withValues(alpha: 0.25)
                                  : Colors.grey.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      employeeId.isNotEmpty
                                          ? '$name ($employeeId)'
                                          : name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: blocked
                                          ? Colors.red.shade700
                                          : Colors.grey.shade800,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (blocked) ...[
                                const SizedBox(height: 8),
                                if (reasonCat.isNotEmpty)
                                  Text('Category: $reasonCat'),
                                if (reasonText.isNotEmpty)
                                  Text('Reason: $reasonText'),
                                if (evidence.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('Evidence: ${evidence.length} photo(s)'),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: userTaskId.isEmpty
                                            ? null
                                            : () async {
                                                final note =
                                                    await _promptAdminReviewNote(
                                                      context: context,
                                                      title:
                                                          'Unblock assignment',
                                                      actionLabel: 'Unblock',
                                                    );
                                                if (note == null) return;
                                                try {
                                                  await _taskService
                                                      .unblockUserTask(
                                                        userTaskId,
                                                        note,
                                                      );
                                                  if (!mounted) return;
                                                  AppWidgets.showSuccessSnackbar(
                                                    context,
                                                    'Assignment unblocked',
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  AppWidgets.showErrorSnackbar(
                                                    context,
                                                    AppWidgets.friendlyErrorMessage(
                                                      e,
                                                      fallback:
                                                          'Failed to unblock assignment',
                                                    ),
                                                  );
                                                }
                                              },
                                        child: const Text('Unblock'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: userTaskId.isEmpty
                                            ? null
                                            : () async {
                                                final note =
                                                    await _promptAdminReviewNote(
                                                      context: context,
                                                      title: 'Close assignment',
                                                      actionLabel: 'Close',
                                                    );
                                                if (note == null) return;
                                                try {
                                                  await _taskService
                                                      .closeUserTask(
                                                        userTaskId,
                                                        note,
                                                      );
                                                  if (!mounted) return;
                                                  AppWidgets.showSuccessSnackbar(
                                                    context,
                                                    'Assignment closed',
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  AppWidgets.showErrorSnackbar(
                                                    context,
                                                    AppWidgets.friendlyErrorMessage(
                                                      e,
                                                      fallback:
                                                          'Failed to close assignment',
                                                    ),
                                                  );
                                                }
                                              },
                                        child: const Text('Close'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (status.toLowerCase() == 'pending_review') ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: userTaskId.isEmpty
                                            ? null
                                            : () async {
                                                final note =
                                                    await _promptAdminReviewNote(
                                                      context: context,
                                                      title: 'Reject submission',
                                                      actionLabel: 'Reject',
                                                    );
                                                if (note == null) return;
                                                try {
                                                  await TaskService()
                                                      .rejectUserTask(
                                                        userTaskId,
                                                        note,
                                                      );
                                                  if (!mounted) return;
                                                  AppWidgets.showSuccessSnackbar(
                                                    context,
                                                    'Task rejected',
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  AppWidgets.showErrorSnackbar(
                                                    context,
                                                    AppWidgets.friendlyErrorMessage(
                                                      e,
                                                      fallback:
                                                          'Failed to reject task',
                                                    ),
                                                  );
                                                }
                                              },
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.orange.shade600),
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: userTaskId.isEmpty
                                            ? null
                                            : () async {
                                                final note =
                                                    await _promptAdminReviewNote(
                                                      context: context,
                                                      title: 'Approve submission',
                                                      actionLabel: 'Approve',
                                                    );
                                                if (note == null) return;
                                                try {
                                                  await TaskService()
                                                      .approveUserTask(
                                                        userTaskId,
                                                        note,
                                                      );
                                                  if (!mounted) return;
                                                  AppWidgets.showSuccessSnackbar(
                                                    context,
                                                    'Task approved',
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  AppWidgets.showErrorSnackbar(
                                                    context,
                                                    AppWidgets.friendlyErrorMessage(
                                                      e,
                                                      fallback:
                                                          'Failed to approve task',
                                                    ),
                                                  );
                                                }
                                              },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.green.shade600,
                                        ),
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _editTask(task);
              },
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _assignTask(task);
              },
              child: const Text('Assign'),
            ),
          ],
        );
      },
    );
  }

  // ── Helper widgets for enhanced task cards ──

  Widget _detailRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'in_progress':
        return const Color(0xFF1565C0);
      case 'blocked':
        return const Color(0xFFC62828);
      case 'overdue':
        return const Color(0xFFE65100);
      case 'pending':
      default:
        return const Color(0xFF757575);
    }
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return const Color(0xFF43A047);
      case 'hard':
        return const Color(0xFFE53935);
      case 'medium':
      default:
        return const Color(0xFFFB8C00);
    }
  }

  IconData _difficultyIcon(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Icons.sentiment_satisfied_alt;
      case 'hard':
        return Icons.local_fire_department;
      case 'medium':
      default:
        return Icons.trending_up;
    }
  }

  Widget _buildBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistProgress(Task task) {
    final total = task.checklist.length;
    final completed = task.checklist.where((c) => c.isCompleted).length;
    final progress = total > 0 ? completed / total : 0.0;
    return Row(
      children: [
        Icon(Icons.checklist, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0
                    ? const Color(0xFF43A047)
                    : const Color(0xFF2688d4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$completed/$total',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF2688d4);

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              AdminControlBar<String, String>(
                title: 'Task Management',
                subtitle: 'Manage and assign tasks to employees',
                primaryOptions: const [
                  AdminControlOption(
                    value: 'current',
                    label: 'Active',
                    icon: Icons.schedule,
                  ),
                  AdminControlOption(
                    value: 'expired',
                    label: 'Overdue',
                    icon: Icons.warning_amber_rounded,
                  ),
                  AdminControlOption(
                    value: 'completed',
                    label: 'Completed',
                    icon: Icons.check_circle,
                  ),
                  AdminControlOption(
                    value: 'archived',
                    label: 'Archived',
                    icon: Icons.inventory_2,
                  ),
                ],
                primaryValue: _tab,
                onPrimaryChanged: (value) {
                  if (value == _tab) return;
                  setState(() => _tab = value);
                },
                secondaryLabel: 'Difficulty',
                secondaryOptions: const [
                        AdminControlOption(value: 'all', label: 'All'),
                        AdminControlOption(
                          value: 'easy',
                          label: 'Easy',
                          icon: Icons.sentiment_satisfied_alt,
                        ),
                        AdminControlOption(
                          value: 'medium',
                          label: 'Medium',
                          icon: Icons.trending_up,
                        ),
                        AdminControlOption(
                          value: 'hard',
                          label: 'Hard',
                          icon: Icons.local_fire_department,
                        ),
                      ],
                secondaryValue: _difficultyFilter,
                onSecondaryChanged: (value) {
                  if (value == _difficultyFilter) return;
                  setState(() => _difficultyFilter = value);
                },
                actions: _tab == 'services'
                    ? []
                    : [
                        FilledButton.icon(
                          onPressed: _addTask,
                          icon: const Icon(Icons.add),
                          label: const Text('Create Task'),
                          style: FilledButton.styleFrom(
                            backgroundColor: brandColor,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final selected = await showMenu<String>(
                              context: context,
                              position: const RelativeRect.fromLTRB(
                                999,
                                80,
                                12,
                                0,
                              ),
                              items: const [
                                PopupMenuItem(
                                  value: 'dueDate',
                                  child: Text('Sort by Due Date'),
                                ),
                                PopupMenuItem(
                                  value: 'difficulty',
                                  child: Text('Sort by Difficulty'),
                                ),
                                PopupMenuItem(
                                  value: 'status',
                                  child: Text('Sort by Status'),
                                ),
                              ],
                            );
                            if (selected == null || !mounted) return;
                            setState(() => _sortBy = selected);
                          },
                          icon: const Icon(Icons.sort),
                          label: const Text('Sort'),
                          style: OutlinedButton.styleFrom(
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
              ),
              const SizedBox(height: 12),
              // Search bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search tasks...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.trim());
                },
              ),
            ],
          ),
        ),
        // Status filter chips
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : () {
                  final List<Task> source;
                  if (_tab == 'archived') {
                    source = _archivedTasks;
                  } else {
                    source = _tasks;
                  }

                  // Apply tab filtering first
                  final tabFiltered = source.where((task) {
                    final isCompleted = task.status == 'completed';
                    if (_tab == 'completed' && !isCompleted) return false;
                    if (_tab == 'current' && (task.isOverdue || isCompleted)) {
                      return false;
                    }
                    if (_tab == 'expired' && (!task.isOverdue || isCompleted)) {
                      return false;
                    }
                    // Difficulty filtering
                    if (_difficultyFilter != 'all') {
                      final d = (task.difficulty ?? '').toLowerCase();
                      if (d != _difficultyFilter) return false;
                    }
                    return true;
                  }).toList();

                  // Apply search/status/origin/assignee filters
                  final filtered = _getFilteredTasks(tabFiltered);

                  _sortTasks(filtered);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _tab == 'archived'
                            ? 'No archived tasks.'
                            : _tab == 'completed'
                            ? 'No completed tasks.'
                            : _tab == 'expired'
                            ? 'No expired tasks.'
                            : 'No tasks available.',
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final task = filtered[index];
                      final isOverdue = task.isOverdue;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isOverdue
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.15),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showTaskDetailsDialog(task),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title row
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        task.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isOverdue
                                              ? Colors.red.shade700
                                              : null,
                                        ),
                                      ),
                                    ),
                                    // Status chip
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(
                                          task.status,
                                        ).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        task.status.replaceAll('_', ' '),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _statusColor(task.status),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Actions menu
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      iconSize: 20,
                                      tooltip: 'Actions',
                                      icon: Icon(
                                        Icons.more_vert,
                                        size: 20,
                                        color: Colors.grey.shade600,
                                      ),
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'edit':
                                            _editTask(task);
                                            return;
                                          case 'assign':
                                            _assignTask(task);
                                            return;
                                          case 'escalate':
                                            _escalateTask(task);
                                            return;
                                          case 'archive':
                                            _archiveTask(task);
                                            return;
                                          case 'restore':
                                            _restoreTask(task);
                                            return;
                                          case 'delete':
                                            _deleteTask(task.id);
                                            return;
                                        }
                                      },
                                      itemBuilder: (context) {
                                        if (_tab == 'archived') {
                                          return <PopupMenuEntry<String>>[
                                            const PopupMenuItem(
                                              value: 'restore',
                                              child: Text('Restore'),
                                            ),
                                            const PopupMenuDivider(),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Delete'),
                                            ),
                                          ];
                                        }
                                        final items = <PopupMenuEntry<String>>[
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'assign',
                                            child: Text('Assign'),
                                          ),
                                        ];
                                        if (isOverdue &&
                                            task.status != 'completed') {
                                          items.add(
                                            const PopupMenuItem(
                                              value: 'escalate',
                                              child: Text('Escalate (SMS)'),
                                            ),
                                          );
                                        }
                                        items.addAll([
                                          const PopupMenuItem(
                                            value: 'archive',
                                            child: Text('Archive'),
                                          ),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ]);
                                        return items;
                                      },
                                    ),
                                  ],
                                ),
                                if (task.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    task.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                // Badges row
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (task.type != null &&
                                        task.type!.isNotEmpty)
                                      _buildBadge(
                                        label: task.type!,
                                        icon: Icons.category,
                                        color: const Color(0xFF2688d4),
                                      ),
                                    if (task.difficulty != null &&
                                        task.difficulty!.isNotEmpty)
                                      _buildBadge(
                                        label: task.difficulty!,
                                        icon: _difficultyIcon(task.difficulty!),
                                        color: _difficultyColor(
                                          task.difficulty!,
                                        ),
                                      ),
                                    if (task.isLate)
                                      _buildBadge(
                                        label: 'Late',
                                        icon: Icons.schedule,
                                        color: Colors.orange.shade700,
                                      ),
                                    if (task.assignedToMultiple.isNotEmpty)
                                      _buildBadge(
                                        label:
                                            '${task.assignedToMultiple.length} assigned',
                                        icon: Icons.people,
                                        color: Colors.blueGrey,
                                      ),
                                  ],
                                ),
                                // Checklist progress
                                if (task.checklist.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildChecklistProgress(task),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }(),
        ),
      ],
    );

    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const maxDesktopWidth = 1280.0;
          final maxWidth = constraints.hasBoundedWidth
              ? (constraints.maxWidth < maxDesktopWidth
                    ? constraints.maxWidth
                    : maxDesktopWidth)
              : maxDesktopWidth;

          final centered = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: body,
            ),
          );

          if (constraints.hasBoundedHeight && constraints.hasBoundedWidth) {
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: centered,
            );
          }

          return centered;
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Task Management'),
        backgroundColor: brandColor,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _sortBy = value);
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'dueDate',
                child: Text('Sort by Due Date'),
              ),
              const PopupMenuItem(
                value: 'difficulty',
                child: Text('Sort by Difficulty'),
              ),
              const PopupMenuItem(
                value: 'status',
                child: Text('Sort by Status'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Tooltip(
                  message: 'Sort tasks',
                  child: Icon(Icons.sort, color: Colors.white),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _addTask,
              icon: const Icon(Icons.add),
              label: const Text('Create Task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: brandColor,
              ),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _AvailabilityInfo {
  final double distanceMeters;
  final int activeTasksCount;
  final int overdueTasksCount;
  final String workloadStatus;

  const _AvailabilityInfo({
    required this.distanceMeters,
    required this.activeTasksCount,
    required this.overdueTasksCount,
    required this.workloadStatus,
  });
}
