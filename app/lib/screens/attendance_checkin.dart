import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/attendance.dart';
import '../services/auth.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Quick attendance check-in screen. A simplified, focused interface for marking
/// arrival or departure, captured as a selfie with GPS location.
class AttendanceCheckInScreen extends StatefulWidget {
  const AttendanceCheckInScreen({super.key});

  @override
  State<AttendanceCheckInScreen> createState() => _AttendanceCheckInScreenState();
}

class _AttendanceCheckInScreenState extends State<AttendanceCheckInScreen> {
  Map<String, dynamic>? _today;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = context.read<Api>();
      final today = await api.get('/attendance/today') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _today = today;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  bool get _canCheckIn => _today?['can_check_in'] == true;
  bool get _canCheckOut => _today?['can_check_out'] == true;

  Future<void> _capture({required bool checkIn}) async {
    final service = context.read<AttendanceService>();
    final messenger = ScaffoldMessenger.of(context);

    // Ask for work mode on check-in
    String? mode;
    if (checkIn) {
      mode = await _askWorkMode();
      if (mode == null) return;
    }

    setState(() => _busy = true);
    try {
      final capture = await service.capture();

      // Check if location is available
      if (!capture.hasLocation && mounted) {
        final proceed = await _confirmNoLocation();
        if (proceed != true) {
          setState(() => _busy = false);
          return;
        }
      }

      // Submit to API
      final result = checkIn
          ? await service.checkIn(capture, workMode: mode)
          : await service.checkOut(capture);

      if (!mounted) return;

      // Show success
      final warning = result['offsite_warning'] as String?;
      setState(() {
        _successMessage = warning ??
            (checkIn
                ? 'Checked in at ${fmtTime(result['check_in_at'])}.'
                : 'Checked out at ${fmtTime(result['check_out_at'])}. '
                    'Time worked: ${fmtDuration(result['minutes_worked'])}.');
        _busy = false;
      });

      // Reload today's data
      await _load();

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_successMessage!),
          backgroundColor: warning != null ? NesfColors.pending : NesfColors.greenDark,
          duration: Duration(seconds: warning != null ? 6 : 4),
        ));
    } on CaptureException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: NesfColors.rejected,
          duration: const Duration(seconds: 6),
          action: e.canOpenSettings
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: service.openLocationSettings,
                )
              : null,
        ));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, e.message, error: true);
      }
    }
  }

  Future<String?> _askWorkMode() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Where are you working today?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final m in const [
              (value: 'office', label: 'At the office', icon: Icons.business_rounded),
              (value: 'field', label: 'Field duty', icon: Icons.directions_bike_rounded),
              (value: 'wfh', label: 'Work from home', icon: Icons.home_work_outlined),
            ])
              ListTile(
                leading: Icon(m.icon, color: NesfColors.green),
                title: Text(m.label),
                onTap: () => Navigator.pop(context, m.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmNoLocation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location unavailable'),
        content: const Text(
          'Your location could not be read, so this check-in will be recorded '
          'without a geo-tag. The office may ask you to confirm where you were.\n\n'
          'Continue anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthService>().employee;

    // Skip attendance for admin/director users
    if (me?.isAdmin ?? false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check In / Out')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48, color: NesfColors.muted),
                const SizedBox(height: 16),
                const Text(
                  'Not available',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: NesfColors.ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Attendance tracking is not required for administrators.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: NesfColors.muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Check In / Out')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _today == null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _statusCard(),
                      const SectionTitle('Quick action'),
                      _actionButtons(),
                      if (_successMessage != null) ...[
                        const SectionTitle('Confirmation'),
                        NesfCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 24, color: NesfColors.approved),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: NesfColors.approved,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _statusCard() {
    final record = _today?['attendance'] as Map<String, dynamic>?;
    final base = _today?['base'] as Map<String, dynamic>?;

    return NesfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            fmtDate(_today?['date']),
            style: const TextStyle(fontSize: 13, color: NesfColors.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('In', fmtTime(record?['check_in_at']), Icons.login_rounded)),
              Expanded(
                  child: _stat('Out', fmtTime(record?['check_out_at']), Icons.logout_rounded)),
              Expanded(
                  child: _stat('Worked', fmtDuration(record?['minutes_worked']), Icons.timer_outlined)),
            ],
          ),
          if (record?['check_in_offsite'] == true) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_off_outlined, size: 17, color: NesfColors.pending),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Recorded as off-site check-in',
                    style: TextStyle(fontSize: 12, color: NesfColors.pending, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          if (base?['lat'] != null) ...[
            const SizedBox(height: 10),
            Text(
              'Base: ${base!['label'] ?? 'Office'} · on-site within '
              '${_today?['geofence_radius_m'] ?? 300} m',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: NesfColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: NesfColors.green),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: NesfColors.muted)),
      ],
    );
  }

  Widget _actionButtons() {
    if (!(_canCheckIn || _canCheckOut)) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: NesfColors.approvedBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: NesfColors.approved),
            SizedBox(width: 8),
            Text('Attendance complete for today',
                style: TextStyle(
                    color: NesfColors.approved, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return NesfCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (_canCheckIn)
            FilledButton.icon(
              onPressed: _busy ? null : () => _capture(checkIn: true),
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.photo_camera_rounded),
              label: Text(_busy ? 'Capturing…' : 'Check In (Selfie + Location)'),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : () => _capture(checkIn: false),
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.logout_rounded),
              label: Text(_busy ? 'Capturing…' : 'Check Out (Selfie + Location)'),
            ),
          if (_canCheckIn && _canCheckOut) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _capture(checkIn: false),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Check Out instead'),
            ),
          ],
        ],
      ),
    );
  }
}
