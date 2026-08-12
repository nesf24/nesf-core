import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LeaveApplyScreen extends StatefulWidget {
  const LeaveApplyScreen({super.key});

  @override
  State<LeaveApplyScreen> createState() => _LeaveApplyScreenState();
}

class _LeaveApplyScreenState extends State<LeaveApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();

  List _types = const [];
  List _staff = const [];
  int? _typeId;
  DateTime? _from;
  DateTime? _to;
  bool _halfDay = false;
  int? _handoverId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _address.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<Api>();
      final results = await Future.wait([
        api.get('/leaves/types'),
        api.get('/employees'),
      ]);
      if (!mounted) return;
      setState(() {
        _types = results[0] as List;
        _staff = results[1] as List;
        _typeId = _types.isNotEmpty ? _types.first['id'] as int : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, e.message, error: true);
        setState(() => _loading = false);
      }
    }
  }

  Map<String, dynamic>? get _selectedType {
    for (final t in _types) {
      if (t['id'] == _typeId) return t as Map<String, dynamic>;
    }
    return null;
  }

  /// Working days between the chosen dates, excluding Sundays. The server is the
  /// authority (it also excludes declared holidays); this is a live estimate so
  /// the user sees roughly what will be debited before submitting.
  num get _estimatedDays {
    if (_from == null || _to == null) return 0;
    var days = 0;
    for (var d = _from!; !d.isAfter(_to!); d = d.add(const Duration(days: 1))) {
      if (d.weekday != DateTime.sunday) days++;
    }
    if (_halfDay && days == 1) return 0.5;
    return days;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom ? (_from ?? now) : (_to ?? _from ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // Backdated applications are allowed (sick leave is often filed on
      // return), but only within the current and previous month.
      firstDate: DateTime(now.year, now.month - 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // Keep the range valid when the start moves past the end.
        if (_to == null || _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (_from == null || _from!.isAfter(picked)) _from = picked;
      }
      if (_from != _to) _halfDay = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_from == null || _to == null) {
      showSnack(context, 'Please choose the leave dates.', error: true);
      return;
    }

    final available = num.tryParse('${_selectedType?['available']}') ?? 0;
    if (_estimatedDays > available) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Balance exceeded'),
          content: Text(
            'You are applying for $_estimatedDays day(s) but only $available day(s) of '
            '${_selectedType?['name']} remain. The application can still be submitted, '
            'but the authority may reject it or treat the excess as leave without pay.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit anyway')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await context.read<Api>().post('/leaves', {
        'leave_type_id': _typeId,
        'from_date': apiDate(_from!),
        'to_date': apiDate(_to!),
        'is_half_day': _halfDay,
        'reason': _reason.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address_on_leave': _address.text.trim(),
        if (_contact.text.trim().isNotEmpty) 'contact_on_leave': _contact.text.trim(),
        if (_handoverId != null) 'handover_to_id': _handoverId,
      });
      if (!mounted) return;
      showSnack(context, 'Application submitted to your reporting officer.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _typeId,
                    decoration: const InputDecoration(labelText: 'Type of leave'),
                    items: [
                      for (final t in _types)
                        DropdownMenuItem(
                          value: t['id'] as int,
                          child: Text(
                            '${t['name']}'
                            '${(num.tryParse('${t['annual_quota']}') ?? 0) > 0 ? '  (${t['available']} left)' : ''}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _typeId = v),
                    validator: (v) => v == null ? 'Choose a leave type' : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _dateField('From', _from, () => _pickDate(isFrom: true))),
                      const SizedBox(width: 12),
                      Expanded(child: _dateField('To', _to, () => _pickDate(isFrom: false))),
                    ],
                  ),
                  if (_from != null && _from == _to) ...[
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      value: _halfDay,
                      onChanged: (v) => setState(() => _halfDay = v ?? false),
                      title: const Text('Half day', style: TextStyle(fontSize: 14)),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ],
                  if (_from != null && _to != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NesfColors.greenLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 17, color: NesfColors.green),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Approximately $_estimatedDays working day(s) will be debited. '
                              'Sundays and declared holidays are not counted.',
                              style: const TextStyle(
                                  fontSize: 12, color: NesfColors.green, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SectionTitle('Reason'),
                  TextFormField(
                    controller: _reason,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Why do you need this leave?',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? 'Please give a reason of at least 5 characters'
                        : null,
                  ),
                  const SectionTitle('While you are away'),
                  DropdownButtonFormField<int?>(
                    initialValue: _handoverId,
                    decoration: const InputDecoration(
                      labelText: 'Hand over duties to (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Not applicable')),
                      for (final s in _staff)
                        DropdownMenuItem(
                          value: s['id'] as int,
                          child: Text('${s['full_name']}${s['designation'] != null ? ' · ${s['designation']}' : ''}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _handoverId = v),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Address during leave (optional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _contact,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact number during leave (optional)',
                    ),
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Text('Submit application'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your application goes to your reporting officer for recommendation, '
                    'then to the approving authority. You will be able to download the '
                    'signed approval letter once it is sanctioned.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: NesfColors.muted, height: 1.45),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value == null ? 'Select' : fmtDate(apiDate(value)),
          style: TextStyle(
            fontSize: 14,
            color: value == null ? NesfColors.muted : NesfColors.ink,
          ),
        ),
      ),
    );
  }
}
