import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/documents.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  List _leaves = const [];
  List _types = const [];
  bool _loading = true;
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
        api.get('/leaves', {'scope': 'mine'}),
        api.get('/leaves/types'),
      ]);
      if (!mounted) return;
      setState(() {
        _leaves = results[0] as List;
        _types = results[1] as List;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My leave')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/leaves/apply');
          if (mounted) _load();
        },
        backgroundColor: NesfColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Apply'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    children: [
                      _balances(),
                      const SectionTitle('Applications'),
                      if (_leaves.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: EmptyState(
                            icon: Icons.event_busy_rounded,
                            title: 'No leave applied for yet',
                            message: 'Tap Apply to submit a leave application to your reporting officer.',
                          ),
                        )
                      else
                        ..._leaves.map(_tile),
                    ],
                  ),
                ),
    );
  }

  Widget _balances() {
    final shown = _types.where((t) => (num.tryParse('${t['annual_quota']}') ?? 0) > 0).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Balance this year', padTop: false),
        NesfCard(
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const Divider(height: 18),
                _balanceRow(shown[i] as Map<String, dynamic>),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _balanceRow(Map<String, dynamic> t) {
    final available = num.tryParse('${t['available']}') ?? 0;
    final quota = num.tryParse('${t['annual_quota']}') ?? 1;
    final used = num.tryParse('${t['used']}') ?? 0;
    final pending = num.tryParse('${t['pending']}') ?? 0;
    final ratio = quota == 0 ? 0.0 : (used / quota).clamp(0.0, 1.0).toDouble();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${t['name']}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  ),
                  Text(
                    '${_n(available)} of ${_n(quota)} left',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: available <= 0 ? NesfColors.rejected : NesfColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: NesfColors.greenLight,
                  valueColor: AlwaysStoppedAnimation(
                    available <= 0 ? NesfColors.rejected : NesfColors.green,
                  ),
                ),
              ),
              if (pending > 0) ...[
                const SizedBox(height: 5),
                Text('${_n(pending)} day(s) awaiting a decision',
                    style: const TextStyle(fontSize: 10.5, color: NesfColors.pending)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _n(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  Widget _tile(dynamic raw) {
    final l = raw as Map<String, dynamic>;
    final approved = l['status'] == 'approved';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        onTap: () => _showDetail(l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l['leave_type_name']}',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip('${l['status']}'),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 14, color: NesfColors.muted),
                const SizedBox(width: 5),
                Text(
                  '${fmtRange(l['from_date'], l['to_date'])} · ${_n(num.tryParse('${l['days']}') ?? 0)} day(s)',
                  style: const TextStyle(fontSize: 12.5, color: NesfColors.body),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${l['reason']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: NesfColors.muted, height: 1.35),
            ),
            if (approved) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'File No. ${l['file_no'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, color: NesfColors.muted),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openLetter(l),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Letter'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openLetter(Map<String, dynamic> l) async {
    try {
      await context.read<DocumentService>().openPdf(
        '/leaves/${l['id']}/letter.pdf',
        'NESF-Leave-${l['emp_code']}-${l['from_date']}.pdf',
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  void _showDetail(Map<String, dynamic> l) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${l['leave_type_name']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                StatusChip('${l['status']}'),
              ],
            ),
            const SizedBox(height: 16),
            DetailRow('Period', fmtRange(l['from_date'], l['to_date']), bold: true),
            DetailRow('Days', '${l['days']}'),
            DetailRow('Applied on', fmtDate(l['created_at'])),
            if (l['handover_name'] != null) DetailRow('Handed over to', '${l['handover_name']}'),
            if (l['address_on_leave'] != null) DetailRow('Address', '${l['address_on_leave']}'),
            if (l['contact_on_leave'] != null) DetailRow('Contact', '${l['contact_on_leave']}'),
            const SectionTitle('Reason'),
            Text('${l['reason']}',
                style: const TextStyle(fontSize: 13.5, height: 1.45, color: NesfColors.body)),
            if (l['reviewed_by_name'] != null) ...[
              const SectionTitle('Reporting officer'),
              DetailRow('Reviewed by', '${l['reviewed_by_name']}'),
              DetailRow('Decision', l['review_decision'] == 'forwarded' ? 'Recommended' : 'Rejected'),
              if (l['review_remark'] != null) DetailRow('Remark', '${l['review_remark']}'),
            ],
            if (l['approved_by_name'] != null) ...[
              const SectionTitle('Approving authority'),
              DetailRow('Decided by', '${l['approved_by_name']}'),
              DetailRow('On', fmtDate(l['approved_at'])),
              if (l['approve_remark'] != null) DetailRow('Remark', '${l['approve_remark']}'),
            ],
            const SizedBox(height: 22),
            if (l['status'] == 'approved')
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openLetter(l);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download approval letter'),
              )
            else if (l['status'] == 'submitted' || l['status'] == 'reviewed')
              OutlinedButton.icon(
                onPressed: () => _cancel(l),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Withdraw application'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NesfColors.rejected,
                  side: const BorderSide(color: NesfColors.rejected),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(Map<String, dynamic> l) async {
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: Text(
            'Your ${l['leave_type_name']} application for ${fmtRange(l['from_date'], l['to_date'])} '
            'will be withdrawn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: NesfColors.rejected),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<Api>().put('/leaves/${l['id']}/cancel');
      if (mounted) {
        showSnack(context, 'Application withdrawn.');
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }
}
