import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

const crmStages = [
  (value: 'new', label: 'New'),
  (value: 'contacted', label: 'Contacted'),
  (value: 'interested', label: 'Interested'),
  (value: 'proposal_sent', label: 'Proposal sent'),
  (value: 'committed', label: 'Committed'),
  (value: 'donated', label: 'Donated'),
  (value: 'declined', label: 'Declined'),
  (value: 'dormant', label: 'Dormant'),
];

const crmCategories = [
  (value: 'donor', label: 'Individual donor'),
  (value: 'sponsor', label: 'Sponsor'),
  (value: 'csr', label: 'CSR / corporate'),
  (value: 'partner', label: 'Partner NGO'),
  (value: 'government', label: 'Government'),
  (value: 'school', label: 'School'),
  (value: 'club', label: 'Club / academy'),
  (value: 'athlete_family', label: 'Athlete family'),
  (value: 'media', label: 'Media'),
  (value: 'vendor', label: 'Vendor'),
  (value: 'other', label: 'Other'),
];

String crmStageLabel(String? value) {
  for (final s in crmStages) {
    if (s.value == value) return s.label;
  }
  return value ?? '—';
}

/// Colour ramp across the pipeline, so a glance at a list conveys momentum.
Color crmStageColor(String? stage) => switch (stage) {
      'donated' => NesfColors.approved,
      'committed' => const Color(0xFF2E7D32),
      'proposal_sent' => NesfColors.info,
      'interested' => const Color(0xFF6A1B9A),
      'contacted' => NesfColors.pending,
      'declined' => NesfColors.rejected,
      'dormant' => NesfColors.muted,
      _ => NesfColors.body,
    };

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  List _contacts = const [];
  List _pipeline = const [];
  bool _loading = true;
  bool _dueOnly = false;
  String? _stage;
  String _query = '';
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
        api.get('/crm/contacts', {
          if (_stage != null) 'stage': _stage,
          if (_query.trim().isNotEmpty) 'q': _query.trim(),
          if (_dueOnly) 'due': 'true',
        }),
        api.get('/crm/pipeline'),
      ]);
      if (!mounted) return;
      setState(() {
        _contacts = results[0] as List;
        _pipeline = results[1] as List;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts & donors'),
        actions: [
          IconButton(
            tooltip: _dueOnly ? 'Show all' : 'Follow-ups due',
            icon: Icon(_dueOnly ? Icons.filter_alt_off_rounded : Icons.notifications_active_outlined),
            onPressed: () {
              setState(() => _dueOnly = !_dueOnly);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newContact,
        backgroundColor: NesfColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add contact'),
      ),
      body: Column(
        children: [
          _searchBar(),
          if (_pipeline.isNotEmpty) _pipelineStrip(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _contacts.isEmpty
                        ? EmptyState(
                            icon: Icons.handshake_outlined,
                            title: _dueOnly ? 'No follow-ups due' : 'No contacts yet',
                            message: _dueOnly
                                ? 'Contacts with a follow-up date on or before today appear here.'
                                : 'Add donors, sponsors, CSR contacts, schools and partners '
                                    'to keep the Foundation\'s relationships in one place.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                              children: _contacts.map(_tile).toList(),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          TextField(
            onSubmitted: (v) {
              setState(() => _query = v);
              _load();
            },
            decoration: InputDecoration(
              hintText: 'Search by name, organisation, phone or email',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        setState(() => _query = '');
                        _load();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _stageChip(null, 'All'),
                for (final s in crmStages) _stageChip(s.value, s.label),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageChip(String? value, String label) {
    final selected = _stage == value;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        showCheckmark: false,
        selectedColor: NesfColors.green,
        labelStyle: TextStyle(color: selected ? Colors.white : NesfColors.body),
        onSelected: (_) {
          setState(() => _stage = selected ? null : value);
          _load();
        },
      ),
    );
  }

  /// Horizontal funnel: contact counts and money received per stage.
  Widget _pipelineStrip() {
    final active = _pipeline.where((p) => (p['contacts'] as int? ?? 0) > 0).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    final received = _pipeline.fold<num>(
        0, (sum, p) => sum + (num.tryParse('${p['received_paise']}') ?? 0));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (received > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  const Icon(Icons.volunteer_activism_rounded,
                      size: 15, color: NesfColors.approved),
                  const SizedBox(width: 6),
                  Text('${fmtMoney(received)} received to date',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: NesfColors.approved)),
                ],
              ),
            ),
          SizedBox(
            height: 26,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in active)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: crmStageColor('${p['stage']}').withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${crmStageLabel('${p['stage']}')} ${p['contacts']}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: crmStageColor('${p['stage']}'),
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

  Widget _tile(dynamic raw) {
    final c = raw as Map<String, dynamic>;
    final due = () {
      final d = DateTime.tryParse('${c['next_action_on']}');
      if (d == null) return false;
      final now = DateTime.now();
      return !d.isAfter(DateTime(now.year, now.month, now.day));
    }();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        onTap: () async {
          await context.push('/crm/${c['id']}');
          if (mounted) _load();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  c['kind'] == 'organisation'
                      ? Icons.corporate_fare_rounded
                      : Icons.person_rounded,
                  size: 18,
                  color: NesfColors.green,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('${c['name']}',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: crmStageColor('${c['stage']}').withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    crmStageLabel('${c['stage']}'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: crmStageColor('${c['stage']}'),
                    ),
                  ),
                ),
              ],
            ),
            if (c['organisation'] != null) ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 27),
                child: Text(
                  '${c['designation'] != null ? '${c['designation']}, ' : ''}${c['organisation']}',
                  style: const TextStyle(fontSize: 11.5, color: NesfColors.muted),
                ),
              ),
            ],
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                if (c['phone'] != null) _meta(Icons.phone_rounded, '${c['phone']}'),
                if ((num.tryParse('${c['received_paise']}') ?? 0) > 0)
                  _meta(Icons.currency_rupee_rounded,
                      fmtMoney(c['received_paise']), color: NesfColors.approved),
                if (c['interaction_count'] != null &&
                    (c['interaction_count'] as int? ?? 0) > 0)
                  _meta(Icons.forum_outlined, '${c['interaction_count']} interaction(s)'),
              ],
            ),
            if (c['next_action'] != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: due ? NesfColors.rejectedBg : NesfColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      due ? Icons.notification_important_rounded : Icons.event_note_rounded,
                      size: 14,
                      color: due ? NesfColors.rejected : NesfColors.muted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${c['next_action']} · ${fmtDateShort(c['next_action_on'])}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: due ? NesfColors.rejected : NesfColors.body,
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

  Widget _meta(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? NesfColors.muted),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 11.5,
                color: color ?? NesfColors.muted,
                fontWeight: color != null ? FontWeight.w600 : FontWeight.w400)),
      ],
    );
  }

  Future<void> _newContact() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _ContactForm(),
    );
    if (saved == true && mounted) _load();
  }
}

/// Add-contact sheet. Kept in this file because it is only reachable from here.
class _ContactForm extends StatefulWidget {
  const _ContactForm();

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _district = TextEditingController();
  final _notes = TextEditingController();
  final _nextAction = TextEditingController();

  String _kind = 'person';
  String _category = 'donor';
  String _stage = 'new';
  DateTime? _nextActionOn;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _org, _designation, _phone, _email, _district, _notes, _nextAction]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Api>().post('/crm/contacts', {
        'kind': _kind,
        'category': _category,
        'name': _name.text.trim(),
        if (_org.text.trim().isNotEmpty) 'organisation': _org.text.trim(),
        if (_designation.text.trim().isNotEmpty) 'designation': _designation.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'stage': _stage,
        if (_nextAction.text.trim().isNotEmpty) 'next_action': _nextAction.text.trim(),
        if (_nextActionOn != null) 'next_action_on': apiDate(_nextActionOn!),
      });
      if (!mounted) return;
      showSnack(context, 'Contact added.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => Form(
          key: _formKey,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              const Text('Add contact',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'person', label: Text('Person'), icon: Icon(Icons.person_rounded, size: 17)),
                  ButtonSegment(value: 'organisation', label: Text('Organisation'), icon: Icon(Icons.corporate_fare_rounded, size: 17)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: _kind == 'person' ? 'Full name' : 'Contact person / name'),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _org,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Organisation (optional)'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _designation,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Designation (optional)'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in crmCategories)
                    DropdownMenuItem(value: c.value, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'donor'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _stage,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Stage'),
                items: [
                  for (final s in crmStages)
                    DropdownMenuItem(value: s.value, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _stage = v ?? 'new'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _district,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'District', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  return value.contains('@') ? null : 'Enter a valid email';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Notes (optional)', alignLabelWithHint: true),
              ),
              const SectionTitle('Next follow-up'),
              TextFormField(
                controller: _nextAction,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'What needs doing next?', isDense: true),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _nextActionOn ?? now,
                    firstDate: now.subtract(const Duration(days: 30)),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked != null) setState(() => _nextActionOn = picked);
                },
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Follow up on',
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
                  ),
                  child: Text(
                    _nextActionOn == null ? 'Not set' : fmtDate(apiDate(_nextActionOn!)),
                    style: TextStyle(
                        fontSize: 13.5,
                        color: _nextActionOn == null ? NesfColors.muted : NesfColors.ink),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Text('Save contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
