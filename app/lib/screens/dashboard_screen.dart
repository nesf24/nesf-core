import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/auth.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await context.read<Api>().get('/dashboard') as Map<String, dynamic>;
      if (mounted) setState(() { _data = data; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final me = auth.employee;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_greeting(), style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(
              me?.fullName ?? 'NESF Core',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      if (me?.mustChangePassword ?? false) _passwordNotice(),
                      _attendanceCard(),
                      const SectionTitle('Quick actions'),
                      _quickActions(),
                      if (_hasPending) ...[
                        const SectionTitle('Awaiting a decision'),
                        _pendingCard(),
                      ],
                      const SectionTitle('Your leave balance'),
                      _leaveBalance(),
                      if (_crmDue.isNotEmpty) ...[
                        SectionTitle('Follow-ups due',
                            action: TextButton(
                              onPressed: () => context.push('/crm'),
                              child: const Text('All contacts'),
                            )),
                        ..._crmDue.map(_crmTile),
                      ],
                      const SectionTitle('The office today'),
                      _orgToday(),
                    ],
                  ),
                ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _passwordNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: NesfColors.pendingBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NesfColors.pending.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.key_outlined, size: 20, color: NesfColors.pending),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'You are still using the password issued by the office. Please change it.',
                style: TextStyle(fontSize: 12.5, color: NesfColors.pending, height: 1.35),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/profile'),
              style: TextButton.styleFrom(foregroundColor: NesfColors.pending),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  /// The check-in card: the single most-used control in the app, so it sits at
  /// the top and shows today's state at a glance.
  Widget _attendanceCard() {
    final att = _data?['attendance'] as Map<String, dynamic>?;
    final record = att?['record'] as Map<String, dynamic>?;
    final canIn = att?['can_check_in'] == true;
    final canOut = att?['can_check_out'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [NesfColors.green, NesfColors.greenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                fmtDate(_data?['date']),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const Spacer(),
              if (record?['work_mode'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _modeLabel('${record!['work_mode']}'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _punchStat('Checked in', fmtTime(record?['check_in_at'])),
              ),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(
                child: _punchStat('Checked out', fmtTime(record?['check_out_at'])),
              ),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(
                child: _punchStat('Worked', fmtDuration(record?['minutes_worked'])),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/attendance'),
              icon: Icon(canIn
                  ? Icons.photo_camera_rounded
                  : canOut
                      ? Icons.logout_rounded
                      : Icons.check_circle_rounded),
              label: Text(canIn
                  ? 'Check in with photo'
                  : canOut
                      ? 'Check out'
                      : 'Attendance marked for today'),
              style: FilledButton.styleFrom(
                backgroundColor: canIn || canOut ? NesfColors.accent : Colors.white24,
                foregroundColor: canIn || canOut ? NesfColors.ink : Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _punchStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _modeLabel(String mode) => switch (mode) {
        'field' => 'FIELD DUTY',
        'wfh' => 'WORK FROM HOME',
        _ => 'OFFICE',
      };

  Widget _quickActions() {
    final actions = [
      (icon: Icons.event_busy_rounded, label: 'Apply for leave', path: '/leaves/apply'),
      (icon: Icons.description_outlined, label: 'Submit report', path: '/reports/new'),
      (icon: Icons.receipt_long_rounded, label: 'TA/DA claim', path: '/tada/new'),
      (icon: Icons.emoji_events_outlined, label: 'Activity report', path: '/activities/new'),
      (icon: Icons.folder_open_rounded, label: 'Projects', path: '/projects'),
      (icon: Icons.handshake_outlined, label: 'CRM', path: '/crm'),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final a in actions)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => context.push(a.path),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: NesfColors.line),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(a.icon, size: 25, color: NesfColors.green),
                    const SizedBox(height: 8),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.25, color: NesfColors.body),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool get _hasPending {
    final p = _data?['my_pending'] as Map<String, dynamic>?;
    if (p == null) return false;
    return p.values.any((v) => (int.tryParse('$v') ?? 0) > 0);
  }

  Widget _pendingCard() {
    final p = _data?['my_pending'] as Map<String, dynamic>? ?? {};
    final items = [
      (label: 'Leave applications', count: p['leaves'], path: '/leaves'),
      (label: 'Work reports', count: p['reports'], path: '/reports'),
      (label: 'TA/DA claims', count: p['tada'], path: '/tada'),
      (label: 'Activity reports', count: p['activities'], path: '/projects'),
    ].where((i) => (int.tryParse('${i.count}') ?? 0) > 0);

    return NesfCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final i in items)
            ListTile(
              dense: true,
              leading: const Icon(Icons.hourglass_top_rounded,
                  size: 19, color: NesfColors.pending),
              title: Text(i.label, style: const TextStyle(fontSize: 13.5)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${i.count}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: NesfColors.pending)),
                  const Icon(Icons.chevron_right_rounded, color: NesfColors.muted),
                ],
              ),
              onTap: () => context.push(i.path),
            ),
        ],
      ),
    );
  }

  Widget _leaveBalance() {
    final balances = (_data?['leave_balance'] as List?) ?? [];
    // Zero-quota types (compensatory off, leave without pay) would only add
    // noise to a balance summary.
    final shown = balances.where((b) => (num.tryParse('${b['annual_quota']}') ?? 0) > 0).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final b = shown[i] as Map<String, dynamic>;
          final available = num.tryParse('${b['available']}') ?? 0;
          final quota = num.tryParse('${b['annual_quota']}') ?? 0;
          return Container(
            width: 118,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: NesfColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${b['name']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: NesfColors.muted, height: 1.25),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _trimNum(available),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: available <= 0 ? NesfColors.rejected : NesfColors.green,
                      ),
                    ),
                    Text(' / ${_trimNum(quota)}',
                        style: const TextStyle(fontSize: 12, color: NesfColors.muted)),
                  ],
                ),
                const Text('days left', style: TextStyle(fontSize: 10.5, color: NesfColors.muted)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 12.0 -> "12", 1.5 -> "1.5".
  String _trimNum(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  List _get(String key) => (_data?[key] as List?) ?? const [];
  List get _crmDue => _get('crm_due');

  Widget _crmTile(dynamic raw) {
    final c = raw as Map<String, dynamic>;
    final overdue = () {
      final d = DateTime.tryParse('${c['next_action_on']}');
      if (d == null) return false;
      final today = DateTime.now();
      return d.isBefore(DateTime(today.year, today.month, today.day));
    }();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        onTap: () => context.push('/crm/${c['id']}'),
        child: Row(
          children: [
            Icon(
              overdue ? Icons.notification_important_rounded : Icons.event_note_rounded,
              size: 20,
              color: overdue ? NesfColors.rejected : NesfColors.green,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['name']}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (c['organisation'] != null)
                    Text('${c['organisation']}',
                        style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
                  const SizedBox(height: 3),
                  Text(
                    '${c['next_action'] ?? 'Follow up'} · ${fmtDateShort(c['next_action_on'])}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: overdue ? NesfColors.rejected : NesfColors.body,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: NesfColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _orgToday() {
    final o = _data?['org_today'] as Map<String, dynamic>? ?? {};
    final stats = [
      (label: 'Checked in', value: o['checked_in'], icon: Icons.how_to_reg_rounded, color: NesfColors.approved),
      (label: 'On field duty', value: o['field_duty'], icon: Icons.directions_bike_rounded, color: NesfColors.info),
      (label: 'On leave', value: o['on_leave'], icon: Icons.beach_access_rounded, color: NesfColors.pending),
      (label: 'Total staff', value: o['staff_total'], icon: Icons.groups_rounded, color: NesfColors.muted),
    ];

    return NesfCard(
      child: Row(
        children: [
          for (final s in stats)
            Expanded(
              child: Column(
                children: [
                  Icon(s.icon, size: 21, color: s.color),
                  const SizedBox(height: 7),
                  Text('${s.value ?? 0}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    s.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10.5, color: NesfColors.muted, height: 1.2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
