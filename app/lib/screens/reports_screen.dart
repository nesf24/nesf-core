import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/documents.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List _reports = const [];
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
      final data = await context.read<Api>().get('/reports', {'scope': 'mine'}) as List;
      if (mounted) setState(() { _reports = data; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My reports')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/reports/new');
          if (mounted) _load();
        },
        backgroundColor: NesfColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New report'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _reports.isEmpty
                  ? const EmptyState(
                      icon: Icons.description_outlined,
                      title: 'No reports submitted',
                      message: 'Submit your daily, weekly or monthly work report for '
                          'your reporting officer to review.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        children: _reports.map(_tile).toList(),
                      ),
                    ),
    );
  }

  Widget _tile(dynamic raw) {
    final r = raw as Map<String, dynamic>;
    final approved = r['status'] == 'approved';
    final editable = r['status'] == 'draft' || r['status'] == 'submitted';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        onTap: editable
            ? () async {
                await context.push('/reports/new', extra: r);
                if (mounted) _load();
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${r['title']}',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                StatusChip('${r['status']}'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: NesfColors.greenLight,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${r['period']}'.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9.5, fontWeight: FontWeight.w700, color: NesfColors.green),
                  ),
                ),
                const SizedBox(width: 8),
                Text(fmtRange(r['period_start'], r['period_end']),
                    style: const TextStyle(fontSize: 12, color: NesfColors.body)),
              ],
            ),
            if (r['project_name'] != null) ...[
              const SizedBox(height: 5),
              Text('Project: ${r['project_name']}',
                  style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
            ],
            const SizedBox(height: 6),
            Text(
              '${r['summary']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: NesfColors.muted, height: 1.35),
            ),
            if (r['review_remark'] != null || r['approve_remark'] != null) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: NesfColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${r['approve_remark'] ?? r['review_remark']}',
                  style: const TextStyle(
                      fontSize: 11.5, color: NesfColors.body, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            if (approved) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: Text('File No. ${r['file_no'] ?? '—'}',
                        style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await context.read<DocumentService>().openPdf(
                          '/reports/${r['id']}/report.pdf',
                          'NESF-Report-${r['emp_code']}-${r['period_start']}.pdf',
                        );
                      } on ApiException catch (e) {
                        if (mounted) showSnack(context, e.message, error: true);
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ] else if (editable) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.edit_outlined, size: 13, color: NesfColors.muted),
                  SizedBox(width: 5),
                  Text('Tap to edit', style: TextStyle(fontSize: 11, color: NesfColors.muted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
