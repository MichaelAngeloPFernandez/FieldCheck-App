// ignore_for_file: deprecated_member_use

import 'package:field_check/main.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();

  static const String _adminEmail = 'perfectomark077@gmail.com';
  static const String _adminPhone = '09945304513';

  final List<(String title, String asset)> _featureSlides = const [
    ('Admin Task Management', 'assets/features/image1.png'),
    ('Geofenced Attendance', 'assets/features/image2.png'),
    ('Reports & Analytics', 'assets/features/image3.png'),
    ('Employee Task List', 'assets/features/image4.png'),
    ('Geofence Management', 'assets/features/image5.png'),
    ('Live Map', 'assets/features/image6.png'),
    ('Attendance History', 'assets/features/image7.png'),
  ];

  final _homeKey = GlobalKey();
  final _aboutKey = GlobalKey();
  final _featuresKey = GlobalKey();
  final _supportKey = GlobalKey();
  final _contactKey = GlobalKey();

  static const Color _brandPrimary = Color(0xFF4DA3FF);
  static const Color _bgBase = Color(0xFF081824);
  static const Color _bgAlt1 = Color(0xFF0A1E2E);
  static const Color _bgAlt2 = Color(0xFF0E2538);
  static const Color _card = Color(0xFF132C42);

  static const Color _lightBgBase = Color(0xFFF7F9FC);
  static const Color _lightBgAlt1 = Color(0xFFFFFFFF);
  static const Color _lightBgAlt2 = Color(0xFFF1F5F9);
  static const Color _lightCard = Color(0xFFFFFFFF);
  static const Color _lightTextPrimary = Color(0xFF1A1A1A);
  static const Color _lightTextSecondary = Color(0xFF4A4A4A);
  static const Color _lightTextMuted = Color(0xFF6B7280);

  static const double _maxWidth = 1160;
  static const double _sectionVPad = 110;

  Future<void> _submitContactForm() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final message = _messageController.text.trim();

    final body = [
      'Name: ${name.isEmpty ? '-' : name}',
      'Email: ${email.isEmpty ? '-' : email}',
      '',
      message.isEmpty ? '(No message provided)' : message,
    ].join('\n');

    final uri = Uri(
      scheme: 'mailto',
      path: _adminEmail,
      queryParameters: {'subject': 'FieldCheck Inquiry', 'body': body},
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void _openGetStartedModal() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? _bgAlt1
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.onSurface.withOpacity(0.10),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose your portal',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Select the portal you want to access. Employees manage attendance and tasks, while administrators manage teams and reports.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.78),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pushNamed('/employee-login');
                        },
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Employee Login'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pushNamed('/admin-login');
                        },
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Admin Login'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _adminEmail,
      queryParameters: {'subject': 'FieldCheck Support'},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchPhone() async {
    final uri = Uri(scheme: 'tel', path: _adminPhone);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openSupportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Support'),
          content: const Text(
            'For support, please contact your administrator.\n\n'
            'FieldCheck is designed for organizations to verify attendance via geofencing, '
            'manage tasks, and track on-field activity with accountability.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _pill({required IconData icon, required String label}) {
    final theme = Theme.of(context);
    final isLight = theme.brightness != Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.06)
            : _brandPrimary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.10)
              : _brandPrimary.withOpacity(0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _brandPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: isLight ? _lightTextPrimary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required GlobalKey key,
    required Color background,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _sectionVPad),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _navLink(String label, GlobalKey targetKey) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: () => _scrollTo(targetKey),
      style: TextButton.styleFrom(
        foregroundColor: theme.brightness == Brightness.dark
            ? theme.colorScheme.onSurface.withOpacity(0.92)
            : _lightTextSecondary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      ),
      child: Text(label),
    );
  }

  PreferredSizeWidget _buildTopNav({required bool isCompact}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? _bgAlt1 : _lightBgAlt1;

    return PreferredSize(
      preferredSize: const Size.fromHeight(78),
      child: Material(
        color: bg,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.black.withOpacity(0.08),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _brandPrimary.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: _brandPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'FieldCheck',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: isDark ? null : _lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 18),
                      if (!isCompact) ...[
                        _navLink('Home', _homeKey),
                        _navLink('About', _aboutKey),
                        _navLink('Features', _featuresKey),
                        _navLink('Support', _supportKey),
                        _navLink('Contact', _contactKey),
                      ] else ...[
                        const Spacer(),
                        PopupMenuButton<String>(
                          tooltip: 'Menu',
                          onSelected: (v) {
                            switch (v) {
                              case 'home':
                                _scrollTo(_homeKey);
                                break;
                              case 'about':
                                _scrollTo(_aboutKey);
                                break;
                              case 'features':
                                _scrollTo(_featuresKey);
                                break;
                              case 'support':
                                _scrollTo(_supportKey);
                                break;
                              case 'contact':
                                _scrollTo(_contactKey);
                                break;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'home', child: Text('Home')),
                            PopupMenuItem(value: 'about', child: Text('About')),
                            PopupMenuItem(
                              value: 'features',
                              child: Text('Features'),
                            ),
                            PopupMenuItem(
                              value: 'support',
                              child: Text('Support'),
                            ),
                            PopupMenuItem(
                              value: 'contact',
                              child: Text('Contact'),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.menu),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (!isCompact) ...[
                        OutlinedButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/employee-login',
                                (r) => false,
                              ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? null : _lightTextPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withOpacity(0.22)
                                  : _brandPrimary.withOpacity(0.45),
                            ),
                          ),
                          child: const Text('Employee Login'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/admin-login',
                                (r) => false,
                              ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          child: const Text('Admin Login'),
                        ),
                        const SizedBox(width: 10),
                      ] else ...[
                        OutlinedButton(
                          onPressed: _openGetStartedModal,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          child: const Text('Login'),
                        ),
                        const SizedBox(width: 10),
                      ],
                      IconButton(
                        tooltip: 'Toggle theme',
                        icon: Icon(
                          Theme.of(context).brightness == Brightness.dark
                              ? Icons.light_mode
                              : Icons.dark_mode,
                          color: isDark ? null : _lightTextPrimary,
                        ),
                        onPressed: () => MyApp.of(context)?.toggleTheme(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.of(context).size.width < 980;
    final isMobile = MediaQuery.of(context).size.width < 720;
    final isDark = theme.brightness == Brightness.dark;

    final pageBg = isDark ? _bgBase : _lightBgBase;
    final section1 = isDark ? _bgBase : _lightBgBase;
    final section2 = isDark ? _bgAlt1 : _lightBgAlt1;
    final section3 = isDark ? _bgAlt2 : _lightBgAlt2;
    final cardBg = isDark ? _card : _lightCard;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.08);
    final textPrimary = isDark
        ? theme.colorScheme.onSurface
        : _lightTextPrimary;
    final textSecondary = isDark
        ? theme.colorScheme.onSurface.withOpacity(0.78)
        : _lightTextSecondary;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: _buildTopNav(isCompact: isCompact),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _section(
                  key: _homeKey,
                  background: section1,
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reliable Field Workforce Tracking with Geofenced Attendance and Task Accountability.',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'FieldCheck provides location-based attendance verification, task accountability, and real-time workforce visibility—built for modern field operations.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.55,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                ElevatedButton(
                                  onPressed: _openGetStartedModal,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brandPrimary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('Get Started'),
                                ),
                                OutlinedButton(
                                  onPressed: () => _scrollTo(_featuresKey),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('View Features'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Image.asset(
                                  _featureSlides[1].$2,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Reliable Field Workforce Tracking with Geofenced Attendance and Task Accountability.',
                                    style: theme.textTheme.displaySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          height: 1.08,
                                          color: textPrimary,
                                        ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    'FieldCheck provides location-based attendance verification, task accountability, and real-time workforce visibility—built for modern field operations.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.6,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      ElevatedButton(
                                        onPressed: _openGetStartedModal,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _brandPrimary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                        ),
                                        child: const Text('Get Started'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () =>
                                            _scrollTo(_featuresKey),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                        ),
                                        child: const Text('View Features'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 28),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _pill(
                                        icon: Icons.location_searching,
                                        label: 'Geofence Validation',
                                      ),
                                      _pill(
                                        icon:
                                            Icons.assignment_turned_in_outlined,
                                        label: 'Task Accountability',
                                      ),
                                      _pill(
                                        icon: Icons.insights_outlined,
                                        label: 'Real-Time Visibility',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 26),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: borderColor),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.30),
                                      blurRadius: 34,
                                      offset: const Offset(0, 18),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 10,
                                    child: Image.asset(
                                      _featureSlides[1].$2,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                _section(
                  key: _aboutKey,
                  background: section2,
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Built for accountable field operations',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'FieldCheck combines secure role-based access, geofence validation, and task tracking into a single workflow that keeps teams aligned and management informed.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _pill(
                                  icon: Icons.verified_user_outlined,
                                  label: 'Role-based Access',
                                ),
                                _pill(
                                  icon: Icons.location_on_outlined,
                                  label: 'Geofence Validation',
                                ),
                                _pill(
                                  icon: Icons.task_alt,
                                  label: 'Task Tracking',
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Image.asset(
                                  _featureSlides[4].$2,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: AspectRatio(
                                  aspectRatio: 16 / 10,
                                  child: Image.asset(
                                    _featureSlides[0].$2,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Built for accountable field operations',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'FieldCheck combines secure role-based access, geofence validation, and task tracking into a single workflow that keeps teams aligned and management informed.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.6,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      _pill(
                                        icon: Icons.verified_user_outlined,
                                        label: 'Role-based Access',
                                      ),
                                      _pill(
                                        icon: Icons.location_on_outlined,
                                        label: 'Geofence Validation',
                                      ),
                                      _pill(
                                        icon: Icons.task_alt,
                                        label: 'Task Tracking',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    'No self-registration: accounts are created and managed by administrators to keep compliance and access control consistent.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      height: 1.5,
                                      color: isDark
                                          ? theme.colorScheme.onSurface
                                                .withOpacity(0.72)
                                          : _lightTextMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                _section(
                  key: _featuresKey,
                  background: section3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Features and Functions',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Explore core modules designed for workforce tracking, task accountability, and operational visibility.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        height: 360,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 4,
                          separatorBuilder: (_, _) => const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final slide = _featureSlides[index];

                            final icon = switch (index) {
                              0 => Icons.assignment_outlined,
                              1 => Icons.location_on_outlined,
                              2 => Icons.bar_chart_rounded,
                              _ => Icons.task_alt,
                            };

                            final desc = switch (index) {
                              0 =>
                                'Assign, prioritize, and monitor tasks with deadlines and difficulty filters.',
                              1 =>
                                'Validate check-ins using GPS + geofence rules to ensure reliable attendance records.',
                              2 =>
                                'Review sessions, incomplete check-ins, and analytics for operational insights.',
                              _ =>
                                'Employees can track assigned tasks, status updates, and completion progress.',
                            };

                            return Container(
                              width: 360,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.22),
                                    blurRadius: 24,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: _brandPrimary.withOpacity(
                                              0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Icon(
                                            icon,
                                            color: _brandPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            slide.$1,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                  color: textPrimary,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      desc,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            height: 1.5,
                                            color: textSecondary,
                                          ),
                                    ),
                                    const Spacer(),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Image.asset(
                                          slide.$2,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
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
                ),
                _section(
                  key: _supportKey,
                  background: section2,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 26,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.22),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Need Help?',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'If you can\'t log in or you need an account, contact your administrator. For technical issues, use the support contact details below.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _openSupportDialog,
                              icon: const Icon(Icons.support_agent),
                              label: const Text('Open Support Center'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _section(
                  key: _contactKey,
                  background: section3,
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contact',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Have a question or need access? Send a message and we\'ll route it to the right administrator.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildContactInfo(theme),
                            const SizedBox(height: 18),
                            _buildContactForm(theme, isMobile: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Contact',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Have a question or need access? Send a message and we\'ll route it to the right administrator.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.6,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _buildContactInfo(theme),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: _buildContactForm(theme)),
                          ],
                        ),
                ),
                Container(
                  width: double.infinity,
                  color: section1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _maxWidth),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'FieldCheck',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Geofenced attendance verification for modern field teams.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: isDark
                                                ? theme.colorScheme.onSurface
                                                      .withOpacity(0.72)
                                                : _lightTextMuted,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '  ${DateTime.now().year} FieldCheck. All rights reserved.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: isDark
                                                ? theme.colorScheme.onSurface
                                                      .withOpacity(0.60)
                                                : _lightTextMuted,
                                          ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {},
                                    child: const Text('Privacy Policy'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () {},
                                    child: const Text('Terms of Service'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? _card : _lightCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brandPrimary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.contact_mail, color: _brandPrimary),
              ),
              const SizedBox(width: 12),
              Text(
                'Contact Information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: isDark ? null : _lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Email',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark
                  ? theme.colorScheme.onSurface.withOpacity(0.82)
                  : _lightTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _launchEmail,
            icon: const Icon(Icons.email_outlined),
            label: Text(_adminEmail),
          ),
          const SizedBox(height: 10),
          Text(
            'Phone',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark
                  ? theme.colorScheme.onSurface.withOpacity(0.82)
                  : _lightTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _launchPhone,
            icon: const Icon(Icons.call_outlined),
            label: Text(_adminPhone),
          ),
          const SizedBox(height: 10),
          Text(
            'Support Hours',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark
                  ? theme.colorScheme.onSurface.withOpacity(0.82)
                  : _lightTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mon–Fri, 9:00 AM – 6:00 PM',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? theme.colorScheme.onSurface.withOpacity(0.72)
                  : _lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactForm(ThemeData theme, {bool isMobile = false}) {
    final isDark = theme.brightness == Brightness.dark;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isDark
            ? Colors.white.withOpacity(0.14)
            : Colors.black.withOpacity(0.10),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? _card : _lightCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Send a message',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: isDark ? null : _lightTextPrimary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              filled: true,
              fillColor: isDark
                  ? Colors.black.withOpacity(0.12)
                  : Colors.black.withOpacity(0.04),
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: fieldBorder.copyWith(
                borderSide: const BorderSide(color: _brandPrimary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              filled: true,
              fillColor: isDark
                  ? Colors.black.withOpacity(0.12)
                  : Colors.black.withOpacity(0.04),
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: fieldBorder.copyWith(
                borderSide: const BorderSide(color: _brandPrimary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            maxLines: isMobile ? 5 : 6,
            decoration: InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
              filled: true,
              fillColor: isDark
                  ? Colors.black.withOpacity(0.12)
                  : Colors.black.withOpacity(0.04),
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: fieldBorder.copyWith(
                borderSide: const BorderSide(color: _brandPrimary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitContactForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.send),
              label: const Text('Submit'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Submit opens your email client with a prefilled message (no backend required).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? theme.colorScheme.onSurface.withOpacity(0.62)
                  : _lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}
