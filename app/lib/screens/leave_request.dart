import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/auth.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Leave request screen with a form to apply for leave and a list of
/// pending/approved/rejected applications.
class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  List _types = const [];
  List _leaves = const [];
  int? _typeId;
  DateTime? _from;
  DateTime? _to;
  bool _halfDay = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = context.read<Api>();
      final results = await Future.wait([
        api.get('/leaves/types'),
        api.get('/leaves', {'scope': 'mine'}),
      ]);
      if (!mounted) return;
      setState(() {
        _types = results[0] as List;
        _leaves = results[1] as List;
        _typeId = _types.isNotEmpty ? _types.first['id'] as int : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Map<String, dynamic>? get _selectedType {
    for (final t in _types) {
      if (t['id'] == _typeId) return t as Map<String, dynamic>;
    }
    return null;
  }

  /// Estimate working days between chosen dates, excluding Sundays.
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
      firstDate: DateTime(now.year, now.month - 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
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
      });
      if (!mounted) return;
      showSnack(context, 'Leave application submitted to your reporting officer.');
      setState(() {
        _reason.clear();
        _from = null;
        _to = null;
        _halfDay = false;
        _busy = false;
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, e.message, error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthService>().employee;

    // Skip leave management for admin/director users
    if (me?.isAdmin ?? false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leave')),
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
                  'Leave management is not required for administrators.',
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
      appBar: AppBar(title: const Text('Leave')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _types.isEmpty
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                    children: [
                      const SectionTitle('Submit a request', padTop: false),
                      Form(
                        key: _formKey,
                        child: NesfCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
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
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                      child: _dateField('From', _from, () => _pickDate(isFrom: true))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: _dateField('To', _to, () => _pickDate(isFrom: false))),
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
                                      const Icon(Icons.info_outline_rounded,
                                          size: 17, color: NesfColors.green),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          'Approximately $_estimatedDays working day(s) will be debited. '
                                          'Sundays are not counted.',
                                          style: const TextStyle(
                                              fontSize: 12, color: NesfColors.green, height: 1.35),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _reason,
                                maxLines: 3,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  labelText: 'Reason for leave',
                                  alignLabelWithHint: true,
                                ),
                                validator: (v) => (v == null || v.trim().length < 5)
                                    ? 'Please give a reason of at least 5 characters'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 20, height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.2, color: Colors.white))
                                    : const Text('Submit application'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SectionTitle('Your applications'),
                      if (_leaves.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: EmptyState(
                            icon: Icons.event_busy_rounded,
                            title: 'No applications yet',
                            message: 'Once you apply for leave, your applications will appear here.',
                          ),
                        )
                      else
                        ..._leaves.map(_leaveCard),
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

  Widget _leaveCard(dynamic raw) {
    final l = raw as Map<String, dynamic>;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l['leave_type_name']}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip('${l['status']}'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 13, color: NesfColors.muted),
                const SizedBox(width: 5),
                Text(
                  '${fmtRange(l['from_date'], l['to_date'])} · ${l['days']} day(s)',
                  style: const TextStyle(fontSize: 12, color: NesfColors.body),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${l['reason']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: NesfColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
