import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/auth.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// One inbox covering all four submission types. A manager sees their reportees'
/// items to recommend; the authority sees everything still open to approve.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  bool _loading = true;
  String? _error;

  List _leaves = const [];
  List _reports = const [];
  List _tada = const [];
  List _activities = const [];

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
        api.get('/leaves', {'scope': 'inbox'}),
        api.get('/reports', {'scope': 'inbox'}),
        api.get('/tada', {'scope': 'inbox'}),
        api.get('/projects/activities/list', {'scope': 'inbox'}),
      ]);
      if (!mounted) return;
      setState(() {
        _leaves = results[0] as List;
        _reports = results[1] as List;
        _tada = results[2] as List;
        _activities = results[3] as List;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  int get _total => _leaves.length + _reports.length + _tada.length + _activities.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approvals'),
        actions: [
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$_total pending',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _total == 0
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        children: const [
                          SizedBox(height: 90),
                          EmptyState(
                            icon: Icons.check_circle_outline_rounded,
                            title: 'Nothing awaiting you',
                            message: 'Leave applications, reports, TA/DA claims and activity '
                                'reports needing your decision will appear here.',
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        children: [
                          if (_leaves.isNotEmpty) ...[
                            SectionTitle('Leave applications (${_leaves.length})', padTop: false),
                            ..._leaves.map((l) => _card(
                                  kind: 'leaves',
                                  row: l as Map<String, dynamic>,
                                  title: '${l['leave_type_name']}',
                                  subtitle:
                                      '${fmtRange(l['from_date'], l['to_date'])} · ${l['days']} day(s)',
                                  body: '${l['reason']}',
                                  icon: Icons.event_busy_rounded,
                                )),
                          ],
                          if (_reports.isNotEmpty) ...[
                            SectionTitle('Work reports (${_reports.length})'),
                            ..._reports.map((r) => _card(
                                  kind: 'reports',
                                  row: r as Map<String, dynamic>,
                                  title: '${r['title']}',
                                  subtitle: fmtRange(r['period_start'], r['period_end']),
                                  body: '${r['summary']}',
                                  icon: Icons.description_outlined,
                                )),
                          ],
                          if (_tada.isNotEmpty) ...[
                            SectionTitle('TA/DA claims (${_tada.length})'),
                            ..._tada.map((c) => _card(
                                  kind: 'tada',
                                  row: c as Map<String, dynamic>,
                                  title: fmtMoney(c['total_paise']),
                                  subtitle:
                                      '${fmtRange(c['from_date'], c['to_date'])} · ${c['claim_no'] ?? ''}',
                                  body: '${c['purpose']}',
                                  icon: Icons.receipt_long_rounded,
                                )),
                          ],
                          if (_activities.isNotEmpty) ...[
                            SectionTitle('Activity reports (${_activities.length})'),
                            ..._activities.map((a) => _card(
                                  kind: 'activities',
                                  row: a as Map<String, dynamic>,
                                  title: '${a['title']}',
                                  subtitle:
                                      '${fmtDate(a['activity_date'])} · ${a['participants_total'] ?? 0} participants',
                                  body: '${a['description']}',
                                  icon: Icons.emoji_events_outlined,
                                )),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _card({
    required String kind,
    required Map<String, dynamic> row,
    required String title,
    required String subtitle,
    required String body,
    required IconData icon,
  }) {
    final me = context.read<AuthService>().employee!;
    // A submission at 'submitted' needs the manager's recommendation; at
    // 'reviewed' it is waiting on the authority. An authority may also approve
    // straight from 'submitted'.
    final needsReview = row['status'] == 'submitted';
    final canApprove = me.isApprover;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: NesfColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${row['full_name']}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip('${row['status']}', compact: true),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${row['designation'] ?? 'Staff'} · ${row['emp_code']}',
              style: const TextStyle(fontSize: 11, color: NesfColors.muted),
            ),
            const Divider(height: 18),
            Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12.5, color: NesfColors.body)),
            const SizedBox(height: 7),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: NesfColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(kind, row, approve: false, review: needsReview),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NesfColors.rejected,
                      side: const BorderSide(color: NesfColors.rejected),
                      minimumSize: const Size(0, 42),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => _decide(
                      kind, row,
                      approve: true,
                      // A manager can only recommend; the authority approves.
                      review: needsReview && !canApprove,
                    ),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    child: Text(needsReview && !canApprove ? 'Recommend' : 'Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Collects a remark and posts either the review or the approval decision.
  Future<void> _decide(
    String kind,
    Map<String, dynamic> row, {
    required bool approve,
    required bool review,
  }) async {
    final isTada = kind == 'tada';
    final remark = TextEditingController();
    final sanctioned = TextEditingController(
      text: isTada ? ((row['total_paise'] as num? ?? 0) / 100).toStringAsFixed(0) : '',
    );

    final action = review
        ? (approve ? 'Recommend' : 'Reject')
        : (approve ? 'Approve' : 'Reject');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action submission'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${row['full_name']} — ${review ? 'your recommendation goes to the approving authority' : 'this decision is final and will be printed on the document'}.',
                style: const TextStyle(fontSize: 13, color: NesfColors.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              // Only the authority sets the sanctioned amount, and only on
              // approval — a reduced sanction changes what is paid out.
              if (isTada && approve && !review) ...[
                TextField(
                  controller: sanctioned,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount sanctioned (₹)',
                    helperText: 'Claimed ${fmtMoney(row['total_paise'])}',
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: remark,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: approve ? 'Remark (optional)' : 'Reason for rejection',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!approve && remark.text.trim().isEmpty) {
                showSnack(context, 'Please give a reason for rejecting.', error: true);
                return;
              }
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: approve ? NesfColors.green : NesfColors.rejected,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Activities live under the projects router.
    final base = kind == 'activities' ? '/projects/activities' : '/$kind';
    final path = '$base/${row['id']}/${review ? 'review' : 'approve'}';
    final body = <String, dynamic>{
      'decision': review ? (approve ? 'forwarded' : 'rejected') : (approve ? 'approved' : 'rejected'),
      if (remark.text.trim().isNotEmpty) 'remark': remark.text.trim(),
      if (isTada && approve && !review && sanctioned.text.trim().isNotEmpty)
        'sanctioned': num.tryParse(sanctioned.text.trim()),
    };

    try {
      await context.read<Api>().put(path, body);
      if (!mounted) return;
      showSnack(context, review
          ? (approve ? 'Recommended and forwarded to the authority.' : 'Rejected.')
          : (approve ? 'Approved. The signed document is now available.' : 'Rejected.'));
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }
}
