import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Submit or edit a periodic work report. Passing [existing] switches the screen
/// into edit mode; the API only permits edits while a report is still a draft or
/// awaiting review.
class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _achievements = TextEditingController();
  final _challenges = TextEditingController();
  final _nextPlan = TextEditingController();

  String _period = 'monthly';
  DateTime? _start;
  DateTime? _end;
  int? _projectId;
  List _projects = const [];
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = '${e['title'] ?? ''}';
      _summary.text = '${e['summary'] ?? ''}';
      _achievements.text = '${e['achievements'] ?? ''}';
      _challenges.text = '${e['challenges'] ?? ''}';
      _nextPlan.text = '${e['next_plan'] ?? ''}';
      _period = '${e['period'] ?? 'monthly'}';
      _start = DateTime.tryParse('${e['period_start']}');
      _end = DateTime.tryParse('${e['period_end']}');
      _projectId = e['project_id'] as int?;
    } else {
      _applyPeriodDefaults();
    }
    _loadProjects();
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _achievements.dispose();
    _challenges.dispose();
    _nextPlan.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final data = await context.read<Api>().get('/projects', {'status': 'active'}) as List;
      if (mounted) setState(() => _projects = data);
    } on ApiException {
      // Project linkage is optional; the form stays usable without the list.
    }
  }

  /// Pre-fills the period to the obvious span for the chosen frequency — the
  /// last complete month, this week, or today.
  void _applyPeriodDefaults() {
    final now = DateTime.now();
    switch (_period) {
      case 'daily':
        _start = DateTime(now.year, now.month, now.day);
        _end = _start;
      case 'weekly':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        _start = DateTime(monday.year, monday.month, monday.day);
        _end = _start!.add(const Duration(days: 6));
      case 'quarterly':
        final q = ((now.month - 1) ~/ 3) * 3 + 1;
        _start = DateTime(now.year, q, 1);
        _end = DateTime(now.year, q + 3, 0);
      default:
        _start = DateTime(now.year, now.month, 1);
        _end = DateTime(now.year, now.month + 1, 0);
    }
  }

  Future<void> _pick({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end == null || _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start == null || _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Future<void> _submit({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null) {
      showSnack(context, 'Please choose the reporting period.', error: true);
      return;
    }

    setState(() => _busy = true);
    final body = {
      'period': _period,
      'period_start': apiDate(_start!),
      'period_end': apiDate(_end!),
      if (_projectId != null) 'project_id': _projectId,
      'title': _title.text.trim(),
      'summary': _summary.text.trim(),
      if (_achievements.text.trim().isNotEmpty) 'achievements': _achievements.text.trim(),
      if (_challenges.text.trim().isNotEmpty) 'challenges': _challenges.text.trim(),
      if (_nextPlan.text.trim().isNotEmpty) 'next_plan': _nextPlan.text.trim(),
      'status': asDraft ? 'draft' : 'submitted',
    };

    try {
      final api = context.read<Api>();
      if (_isEdit) {
        await api.put('/reports/${widget.existing!['id']}', body);
      } else {
        await api.post('/reports', body);
      }
      if (!mounted) return;
      showSnack(context, asDraft
          ? 'Saved as a draft.'
          : 'Report submitted to your reporting officer.');
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit report' : 'Submit work report')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Reporting frequency'),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
              ],
              onChanged: (v) => setState(() {
                _period = v ?? 'monthly';
                if (!_isEdit) _applyPeriodDefaults();
              }),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _dateField('Period from', _start, () => _pick(isStart: true))),
                const SizedBox(width: 12),
                Expanded(child: _dateField('Period to', _end, () => _pick(isStart: false))),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: _projectId,
              decoration: const InputDecoration(labelText: 'Project / programme (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('General / not project-specific')),
                for (final p in _projects)
                  DropdownMenuItem(
                    value: p['id'] as int,
                    child: Text('${p['name']}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SectionTitle('The report'),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Subject'),
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Give the report a subject' : null,
            ),
            const SizedBox(height: 14),
            _bigField(_summary, 'Summary of work done', minLines: 5,
                validator: (v) => (v == null || v.trim().length < 20)
                    ? 'Please write at least 20 characters'
                    : null),
            const SizedBox(height: 14),
            _bigField(_achievements, 'Key achievements (optional)'),
            const SizedBox(height: 14),
            _bigField(_challenges, 'Challenges faced (optional)'),
            const SizedBox(height: 14),
            _bigField(_nextPlan, 'Plan for the next period (optional)'),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: _busy ? null : () => _submit(asDraft: false),
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Text('Submit for review'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(asDraft: true),
              child: const Text('Save as draft'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigField(
    TextEditingController controller,
    String label, {
    int minLines = 3,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines + 4,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      validator: validator,
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
              fontSize: 13.5, color: value == null ? NesfColors.muted : NesfColors.ink),
        ),
      ),
    );
  }
}
