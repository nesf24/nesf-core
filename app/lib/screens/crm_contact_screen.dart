import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'crm_screen.dart' show crmStages, crmCategories, crmStageColor;

/// One contact: their details, the log of every interaction, and contributions
/// pledged or received.
class CrmContactScreen extends StatefulWidget {
  const CrmContactScreen({super.key, required this.contactId});
  final int contactId;

  @override
  State<CrmContactScreen> createState() => _CrmContactScreenState();
}

class _CrmContactScreenState extends State<CrmContactScreen> {
  Map<String, dynamic>? _contact;
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
      final data = await context.read<Api>().get('/crm/contacts/${widget.contactId}')
          as Map<String, dynamic>;
      if (mounted) setState(() { _contact = data; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  List get _interactions => (_contact?['interactions'] as List?) ?? const [];
  List get _contributions => (_contact?['contributions'] as List?) ?? const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact == null ? 'Contact' : '${_contact!['name']}'),
        actions: [
          if (_contact?['phone'] != null) ...[
            IconButton(
              tooltip: 'Call',
              icon: const Icon(Icons.phone_rounded),
              onPressed: () => _launch('tel:${_contact!['phone']}'),
            ),
            IconButton(
              tooltip: 'WhatsApp',
              icon: const Icon(Icons.chat_rounded),
              onPressed: () => _launch(
                  'https://wa.me/${'${_contact!['whatsapp'] ?? _contact!['phone']}'.replaceAll(RegExp(r'[^\d]'), '')}'),
            ),
          ],
        ],
      ),
      floatingActionButton: _contact == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _logInteraction,
              backgroundColor: NesfColors.green,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Log interaction'),
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
                      _header(),
                      const SectionTitle('Details'),
                      NesfCard(
                        child: Column(
                          children: [
                            DetailRow('Category', _categoryLabel()),
                            if (_contact!['organisation'] != null)
                              DetailRow('Organisation', '${_contact!['organisation']}'),
                            if (_contact!['designation'] != null)
                              DetailRow('Designation', '${_contact!['designation']}'),
                            if (_contact!['phone'] != null)
                              DetailRow('Phone', '${_contact!['phone']}'),
                            if (_contact!['email'] != null)
                              DetailRow('Email', '${_contact!['email']}'),
                            if (_contact!['district'] != null)
                              DetailRow('District', '${_contact!['district']}'),
                            if (_contact!['source'] != null)
                              DetailRow('Source', '${_contact!['source']}'),
                            if (_contact!['owner_name'] != null)
                              DetailRow('Managed by', '${_contact!['owner_name']}'),
                            DetailRow('Last contacted', fmtDate(_contact!['last_contacted_at'])),
                          ],
                        ),
                      ),
                      if (_contact!['notes'] != null) ...[
                        const SectionTitle('Notes'),
                        NesfCard(
                          child: Text('${_contact!['notes']}',
                              style: const TextStyle(
                                  fontSize: 13, height: 1.45, color: NesfColors.body)),
                        ),
                      ],
                      SectionTitle('Contributions (${_contributions.length})',
                          action: TextButton.icon(
                            onPressed: _addContribution,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Record'),
                          )),
                      if (_contributions.isEmpty)
                        const NesfCard(
                          child: Text('No contributions recorded yet.',
                              style: TextStyle(fontSize: 13, color: NesfColors.muted)),
                        )
                      else
                        ..._contributions.map(_contributionTile),
                      SectionTitle('Interaction history (${_interactions.length})'),
                      if (_interactions.isEmpty)
                        const NesfCard(
                          child: Text('No interactions logged yet.',
                              style: TextStyle(fontSize: 13, color: NesfColors.muted)),
                        )
                      else
                        ..._interactions.map(_interactionTile),
                    ],
                  ),
                ),
    );
  }

  String _categoryLabel() {
    for (final c in crmCategories) {
      if (c.value == '${_contact!['category']}') return c.label;
    }
    return '${_contact!['category']}';
  }

  Widget _header() {
    final received = num.tryParse('${_contact!['received_paise']}') ?? 0;
    final pledged = num.tryParse('${_contact!['pledged_paise']}') ?? 0;
    final stage = '${_contact!['stage']}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NesfColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: crmStageColor(stage).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _contact!['kind'] == 'organisation'
                      ? Icons.corporate_fare_rounded
                      : Icons.person_rounded,
                  color: crmStageColor(stage),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_contact!['name']}',
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                    if (_contact!['organisation'] != null)
                      Text('${_contact!['organisation']}',
                          style: const TextStyle(fontSize: 12.5, color: NesfColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // The stage is the one field staff change constantly, so it is
          // editable inline rather than behind an edit form.
          Align(
            alignment: Alignment.centerLeft,
            child: Text('PIPELINE STAGE',
                style: TextStyle(
                    fontSize: 10, letterSpacing: 0.7,
                    fontWeight: FontWeight.w700, color: NesfColors.muted)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in crmStages)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(s.label, style: const TextStyle(fontSize: 12)),
                      selected: stage == s.value,
                      showCheckmark: false,
                      selectedColor: crmStageColor(s.value),
                      labelStyle: TextStyle(
                          color: stage == s.value ? Colors.white : NesfColors.body),
                      onSelected: (_) => _setStage(s.value),
                    ),
                  ),
              ],
            ),
          ),
          if (received > 0 || pledged > 0) ...[
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(fmtMoney(received),
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: NesfColors.approved)),
                      const Text('Received',
                          style: TextStyle(fontSize: 11, color: NesfColors.muted)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(fmtMoney(pledged),
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: NesfColors.pending)),
                      const Text('Pledged',
                          style: TextStyle(fontSize: 11, color: NesfColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _interactionTile(dynamic raw) {
    final i = raw as Map<String, dynamic>;
    final icon = switch ('${i['kind']}') {
      'call' => Icons.phone_rounded,
      'meeting' => Icons.groups_rounded,
      'email' => Icons.email_outlined,
      'whatsapp' => Icons.chat_rounded,
      'visit' => Icons.directions_walk_rounded,
      'event' => Icons.event_rounded,
      _ => Icons.notes_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: NesfColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${i['kind']}'.replaceFirst('${i['kind']}'[0], '${i['kind']}'[0].toUpperCase()),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(fmtDateShort(i['happened_at']),
                    style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
              ],
            ),
            const SizedBox(height: 7),
            Text('${i['summary']}',
                style: const TextStyle(fontSize: 13, height: 1.4, color: NesfColors.body)),
            if (i['outcome'] != null) ...[
              const SizedBox(height: 5),
              Text('Outcome: ${i['outcome']}',
                  style: const TextStyle(fontSize: 12, color: NesfColors.muted, height: 1.35)),
            ],
            if (i['by_name'] != null) ...[
              const SizedBox(height: 7),
              Text('Logged by ${i['by_name']}',
                  style: const TextStyle(fontSize: 10.5, color: NesfColors.muted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contributionTile(dynamic raw) {
    final c = raw as Map<String, dynamic>;
    final isReceived = c['status'] == 'received';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        child: Row(
          children: [
            Icon(
              isReceived ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 19,
              color: isReceived ? NesfColors.approved : NesfColors.pending,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmtMoney(c['amount_paise'], decimals: true),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  Text(
                    [
                      isReceived ? 'Received' : 'Pledged',
                      '${c['kind']}'.toUpperCase(),
                      if (c['received_on'] != null) fmtDateShort(c['received_on']),
                      if (c['project_name'] != null) '${c['project_name']}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11, color: NesfColors.muted),
                  ),
                  if (c['reference'] != null)
                    Text('Ref ${c['reference']}',
                        style: const TextStyle(fontSize: 10.5, color: NesfColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open $url', error: true);
    }
  }

  /// Changing the stage goes through the update endpoint, which needs the whole
  /// contact body — so the existing values are resent unchanged.
  Future<void> _setStage(String stage) async {
    if (stage == '${_contact!['stage']}') return;
    try {
      await context.read<Api>().put('/crm/contacts/${widget.contactId}', {
        'kind': _contact!['kind'],
        'category': _contact!['category'],
        'name': _contact!['name'],
        'organisation': _contact!['organisation'],
        'designation': _contact!['designation'],
        'email': _contact!['email'],
        'phone': _contact!['phone'],
        'whatsapp': _contact!['whatsapp'],
        'address': _contact!['address'],
        'district': _contact!['district'],
        'state': _contact!['state'],
        'pincode': _contact!['pincode'],
        'website': _contact!['website'],
        'stage': stage,
        'source': _contact!['source'],
        'notes': _contact!['notes'],
        'owner_id': _contact!['owner_id'],
        'next_action': _contact!['next_action'],
        'next_action_on': _contact!['next_action_on'],
      });
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _logInteraction() async {
    final summary = TextEditingController();
    final outcome = TextEditingController();
    final nextAction = TextEditingController();
    var kind = 'call';
    DateTime? nextOn;
    String? newStage;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Log an interaction',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'call', child: Text('Phone call')),
                    DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                    DropdownMenuItem(value: 'visit', child: Text('Visit')),
                    DropdownMenuItem(value: 'email', child: Text('Email')),
                    DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                    DropdownMenuItem(value: 'event', child: Text('At an event')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setSheetState(() => kind = v ?? 'call'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: summary,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'What was discussed?', alignLabelWithHint: true),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: outcome,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Outcome (optional)'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: newStage,
                  decoration: const InputDecoration(labelText: 'Move to stage (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Leave unchanged')),
                    for (final s in crmStages)
                      DropdownMenuItem(value: s.value, child: Text(s.label)),
                  ],
                  onChanged: (v) => setSheetState(() => newStage = v),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nextAction,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Next action (optional)'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: nextOn ?? now.add(const Duration(days: 7)),
                      firstDate: now.subtract(const Duration(days: 7)),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked != null) setSheetState(() => nextOn = picked);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Follow up on',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
                    ),
                    child: Text(
                      nextOn == null ? 'Not set' : fmtDate(apiDate(nextOn!)),
                      style: TextStyle(
                          fontSize: 13.5,
                          color: nextOn == null ? NesfColors.muted : NesfColors.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () {
                    if (summary.text.trim().length < 3) {
                      showSnack(context, 'Please summarise the interaction.', error: true);
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;

    try {
      await context.read<Api>().post('/crm/contacts/${widget.contactId}/interactions', {
        'kind': kind,
        'summary': summary.text.trim(),
        if (outcome.text.trim().isNotEmpty) 'outcome': outcome.text.trim(),
        if (nextAction.text.trim().isNotEmpty) 'next_action': nextAction.text.trim(),
        if (nextOn != null) 'next_action_on': apiDate(nextOn!),
        if (newStage != null) 'stage': newStage,
      });
      if (!mounted) return;
      showSnack(context, 'Interaction logged.');
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _addContribution() async {
    final amount = TextEditingController();
    final reference = TextEditingController();
    var kind = 'bank';
    var status = 'received';
    final receivedOn = DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Record a contribution',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹ '),
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'received', label: Text('Received')),
                    ButtonSegment(value: 'pledged', label: Text('Pledged')),
                  ],
                  selected: {status},
                  onSelectionChanged: (s) => setSheetState(() => status = s.first),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const [
                    DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'in_kind', child: Text('In kind')),
                  ],
                  onChanged: (v) => setSheetState(() => kind = v ?? 'bank'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                      labelText: 'Reference / transaction no. (optional)'),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () {
                    if ((num.tryParse(amount.text) ?? 0) <= 0) {
                      showSnack(context, 'Enter the amount.', error: true);
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;

    try {
      await context.read<Api>().post('/crm/contacts/${widget.contactId}/contributions', {
        'amount': num.tryParse(amount.text) ?? 0,
        'kind': kind,
        'status': status,
        if (status == 'received') 'received_on': apiDate(receivedOn),
        if (reference.text.trim().isNotEmpty) 'reference': reference.text.trim(),
      });
      if (!mounted) return;
      showSnack(context, 'Contribution recorded.');
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }
}
