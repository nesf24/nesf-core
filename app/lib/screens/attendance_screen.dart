import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/attendance.dart';
import '../services/auth.dart';
import '../services/documents.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Map<String, dynamic>? _today;
  List _history = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = context.read<Api>();
      final results = await Future.wait([
        api.get('/attendance/today'),
        api.get('/attendance/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _today = results[0] as Map<String, dynamic>;
        _history = results[1] as List;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  bool get _canCheckIn => _today?['can_check_in'] == true;
  bool get _canCheckOut => _today?['can_check_out'] == true;

  Future<void> _punch({required bool checkIn}) async {
    final service = context.read<AttendanceService>();
    final messenger = ScaffoldMessenger.of(context);

    // Ask for the work mode up front on check-in, so someone heading to the
    // field is not mis-marked just because they happen to start near the office.
    String? mode;
    if (checkIn) {
      mode = await _askWorkMode();
      if (mode == null) return;
    }

    setState(() => _busy = true);
    try {
      final capture = await service.capture();

      if (!capture.hasLocation && mounted) {
        // The photo is taken; ask rather than silently filing a location-less
        // punch, since the office relies on the geo-tag.
        final proceed = await _confirmNoLocation();
        if (proceed != true) {
          setState(() => _busy = false);
          return;
        }
      }

      final result = checkIn
          ? await service.checkIn(capture, workMode: mode)
          : await service.checkOut(capture);

      if (!mounted) return;
      await _load();

      final warning = result['offsite_warning'] as String?;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(warning ??
              (checkIn
                  ? 'Checked in at ${fmtTime(result['check_in_at'])}.'
                  : 'Checked out at ${fmtTime(result['check_out_at'])}. '
                      'Time worked: ${fmtDuration(result['minutes_worked'])}.')),
          backgroundColor: warning != null ? NesfColors.pending : NesfColors.greenDark,
          duration: Duration(seconds: warning != null ? 6 : 4),
        ));
    } on CaptureException catch (e) {
      if (!mounted) return;
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
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
          'Your location could not be read, so this punch will be recorded '
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          if (me?.isReviewer ?? false)
            IconButton(
              tooltip: 'Monthly register (PDF)',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _downloadMuster,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _today == null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _punchPanel(),
                      if (!(me?.hasBaseLocation ?? true)) _baseLocationPrompt(me!.id),
                      const SectionTitle('Last 30 days'),
                      if (_history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: EmptyState(
                            icon: Icons.fingerprint_rounded,
                            title: 'No attendance yet',
                            message: 'Your check-ins will be listed here once you start marking attendance.',
                          ),
                        )
                      else
                        ..._history.map(_historyTile),
                    ],
                  ),
                ),
    );
  }

  Widget _punchPanel() {
    final record = _today?['attendance'] as Map<String, dynamic>?;
    final base = _today?['base'] as Map<String, dynamic>?;
    final radius = _today?['geofence_radius_m'];

    return NesfCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            fmtDate(_today?['date']),
            style: const TextStyle(fontSize: 13, color: NesfColors.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _bigStat('In', fmtTime(record?['check_in_at']), Icons.login_rounded)),
              Expanded(child: _bigStat('Out', fmtTime(record?['check_out_at']), Icons.logout_rounded)),
              Expanded(child: _bigStat('Worked', fmtDuration(record?['minutes_worked']), Icons.timer_outlined)),
            ],
          ),
          if (record?['check_in_place'] != null || record?['check_in_distance'] != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  record?['check_in_offsite'] == true
                      ? Icons.location_off_outlined
                      : Icons.location_on_outlined,
                  size: 17,
                  color: record?['check_in_offsite'] == true
                      ? NesfColors.pending
                      : NesfColors.approved,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationSummary(record),
                    style: const TextStyle(fontSize: 12, color: NesfColors.body, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (_canCheckIn || _canCheckOut)
            FilledButton.icon(
              onPressed: _busy ? null : () => _punch(checkIn: _canCheckIn),
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_canCheckIn ? Icons.photo_camera_rounded : Icons.logout_rounded),
              label: Text(_busy
                  ? 'Please wait…'
                  : _canCheckIn
                      ? 'Take selfie & check in'
                      : 'Take selfie & check out'),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              width: double.infinity,
              decoration: BoxDecoration(
                color: NesfColors.approvedBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, size: 19, color: NesfColors.approved),
                  SizedBox(width: 9),
                  Text('Attendance complete for today',
                      style: TextStyle(
                          color: NesfColors.approved,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (base?['lat'] != null) ...[
            const SizedBox(height: 10),
            Text(
              'Base: ${base!['label'] ?? 'Office'} · on-site within ${radius ?? 300} m',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: NesfColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  String _locationSummary(Map<String, dynamic>? record) {
    final parts = <String>[];
    if (record?['check_in_place'] != null) parts.add('${record!['check_in_place']}');
    final distance = num.tryParse('${record?['check_in_distance']}');
    if (distance != null) {
      parts.add(distance < 1000
          ? '${distance.round()} m from base'
          : '${(distance / 1000).toStringAsFixed(1)} km from base');
    }
    if (record?['check_in_offsite'] == true) parts.add('recorded as off-site');
    return parts.isEmpty ? 'Location recorded' : parts.join(' · ');
  }

  Widget _bigStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 19, color: NesfColors.green),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
      ],
    );
  }

  /// Without a base location the server cannot judge whether a punch is on-site,
  /// so prompt once to set it.
  Widget _baseLocationPrompt(int employeeId) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: NesfColors.infoBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NesfColors.info.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.my_location_rounded, size: 20, color: NesfColors.info),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Set your base location so on-site and field check-ins can be told apart.',
                style: TextStyle(fontSize: 12.5, color: NesfColors.info, height: 1.35),
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await context.read<AttendanceService>()
                      .setBaseHere(employeeId, label: 'My base');
                  if (!mounted) return;
                  await context.read<AuthService>().refresh();
                  if (mounted) showSnack(context, 'Base location saved.');
                } on CaptureException catch (e) {
                  if (mounted) showSnack(context, e.message, error: true);
                } on ApiException catch (e) {
                  if (mounted) showSnack(context, e.message, error: true);
                }
              },
              child: const Text('Set here'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(dynamic raw) {
    final a = raw as Map<String, dynamic>;
    final mode = '${a['work_mode']}';
    final (icon, colour) = switch (mode) {
      'field' => (Icons.directions_bike_rounded, NesfColors.info),
      'wfh' => (Icons.home_work_outlined, NesfColors.green),
      _ => (Icons.business_rounded, NesfColors.muted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: NesfColors.greenLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '${a['work_date']}'.split('-').last,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: NesfColors.green),
                  ),
                  Text(
                    fmtDateShort(a['work_date']).split(' ').last,
                    style: const TextStyle(fontSize: 9.5, color: NesfColors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: colour),
                      const SizedBox(width: 5),
                      Text(
                        '${fmtTime(a['check_in_at'])} – ${a['check_out_at'] == null ? 'not checked out' : fmtTime(a['check_out_at'])}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (a['check_in_place'] != null) '${a['check_in_place']}',
                      if (a['check_in_offsite'] == true) 'off-site',
                      fmtDuration(a['minutes_worked']),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: NesfColors.muted),
                  ),
                ],
              ),
            ),
            if (a['check_in_selfie'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: PrivateImage(
                  storageKey: a['check_in_selfie'] as String?,
                  width: 38,
                  height: 38,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadMuster() async {
    final now = DateTime.now();
    try {
      await context.read<DocumentService>().openPdf(
        '/attendance/muster.pdf',
        'NESF-Attendance-${now.year}-${now.month.toString().padLeft(2, '0')}.pdf',
        query: {'year': now.year, 'month': now.month},
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }
}
