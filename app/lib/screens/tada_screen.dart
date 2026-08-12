import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/documents.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TadaScreen extends StatefulWidget {
  const TadaScreen({super.key});

  @override
  State<TadaScreen> createState() => _TadaScreenState();
}

class _TadaScreenState extends State<TadaScreen> {
  List _claims = const [];
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
      final data = await context.read<Api>().get('/tada', {'scope': 'mine'}) as List;
      if (mounted) setState(() { _claims = data; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TA / DA claims')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/tada/new');
          if (mounted) _load();
        },
        backgroundColor: NesfColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New claim'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _claims.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No claims yet',
                      message: 'Raise a travelling and daily allowance claim for a journey '
                          'made on Foundation duty.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        children: _claims.map(_tile).toList(),
                      ),
                    ),
    );
  }

  Widget _tile(dynamic raw) {
    final c = raw as Map<String, dynamic>;
    final issued = c['status'] == 'approved' || c['status'] == 'paid';
    // A reduced sanction is the figure that matters, so show it when it differs.
    final sanctioned = c['sanctioned_paise'];
    final reduced = sanctioned != null && sanctioned != c['total_paise'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        onTap: () => _detail(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fmtMoney(c['net_payable_paise']),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        reduced
                            ? 'Sanctioned ${fmtMoney(sanctioned)} of ${fmtMoney(c['total_paise'])}'
                            : 'Claimed ${fmtMoney(c['total_paise'])}',
                        style: const TextStyle(fontSize: 11.5, color: NesfColors.muted),
                      ),
                    ],
                  ),
                ),
                StatusChip('${c['status']}'),
              ],
            ),
            const Divider(height: 18),
            Text('${c['purpose']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.35)),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 13, color: NesfColors.muted),
                const SizedBox(width: 5),
                Text(fmtRange(c['from_date'], c['to_date']),
                    style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
                if (c['claim_no'] != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${c['claim_no']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
                  ),
                ],
              ],
            ),
            if (issued) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: Text('File No. ${c['file_no'] ?? '—'}',
                        style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openBill(c),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Bill'),
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

  Future<void> _openBill(Map<String, dynamic> c) async {
    try {
      await context.read<DocumentService>().openPdf(
        '/tada/${c['id']}/bill.pdf',
        'NESF-TADA-${c['emp_code']}-${c['from_date']}.pdf',
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _detail(Map<String, dynamic> claim) async {
    Map<String, dynamic>? full;
    try {
      full = await context.read<Api>().get('/tada/${claim['id']}') as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
      return;
    }
    if (!mounted) return;

    final legs = (full['legs'] as List?) ?? const [];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${full!['claim_no'] ?? 'TA/DA claim'}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                StatusChip('${full['status']}'),
              ],
            ),
            const SizedBox(height: 14),
            DetailRow('Purpose', '${full['purpose']}'),
            DetailRow('Journey', fmtRange(full['from_date'], full['to_date'])),
            if (full['project_name'] != null) DetailRow('Project', '${full['project_name']}'),
            const SectionTitle('Journey legs'),
            for (final leg in legs) _legRow(leg as Map<String, dynamic>),
            const SectionTitle('Amounts'),
            DetailRow('Fare', fmtMoney(full['fare_paise'], decimals: true)),
            DetailRow('Daily allowance', fmtMoney(full['da_paise'], decimals: true)),
            DetailRow('Lodging', fmtMoney(full['lodging_paise'], decimals: true)),
            DetailRow('Other', fmtMoney(full['other_paise'], decimals: true)),
            const Divider(height: 20),
            DetailRow('Gross claimed', fmtMoney(full['total_paise'], decimals: true), bold: true),
            if ((full['advance_paise'] as num? ?? 0) > 0)
              DetailRow('Less advance', '(-) ${fmtMoney(full['advance_paise'], decimals: true)}'),
            if (full['sanctioned_paise'] != null)
              DetailRow('Sanctioned', fmtMoney(full['sanctioned_paise'], decimals: true),
                  bold: true),
            DetailRow('Net payable', fmtMoney(full['net_payable_paise'], decimals: true),
                bold: true, valueColor: NesfColors.green),
            if (full['review_remark'] != null) ...[
              const SectionTitle('Reporting officer'),
              Text('${full['review_remark']}',
                  style: const TextStyle(fontSize: 13, color: NesfColors.body, height: 1.4)),
            ],
            if (full['approve_remark'] != null) ...[
              const SectionTitle('Approving authority'),
              Text('${full['approve_remark']}',
                  style: const TextStyle(fontSize: 13, color: NesfColors.body, height: 1.4)),
            ],
            if (full['payment_ref'] != null) ...[
              const SectionTitle('Payment'),
              DetailRow('Reference', '${full['payment_ref']}'),
              DetailRow('Paid on', fmtDate(full['paid_at'])),
            ],
            const SizedBox(height: 20),
            if (full['status'] == 'approved' || full['status'] == 'paid')
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openBill(full!);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download sanction bill'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legRow(Map<String, dynamic> leg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: NesfColors.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${leg['from_place']} → ${leg['to_place']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text(fmtMoney(
                    (leg['fare_paise'] as num? ?? 0) +
                        (leg['da_paise'] as num? ?? 0) +
                        (leg['lodging_paise'] as num? ?? 0) +
                        (leg['other_paise'] as num? ?? 0),
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              fmtDateShort(leg['travel_date']),
              '${leg['mode']}'.replaceAll('_', ' '),
              if ((num.tryParse('${leg['distance_km']}') ?? 0) > 0) '${leg['distance_km']} km',
              if ((num.tryParse('${leg['da_days']}') ?? 0) > 0) 'DA ${leg['da_days']} day(s)',
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: NesfColors.muted),
          ),
        ],
      ),
    );
  }
}
