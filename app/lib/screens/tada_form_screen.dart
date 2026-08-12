import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// One journey leg being edited in the form. Amounts are held as typed strings
/// and only converted at submit, so a half-typed number never becomes 0.
class _Leg {
  DateTime? date;
  final from = TextEditingController();
  final to = TextEditingController();
  String mode = 'bus';
  final distance = TextEditingController();
  final fare = TextEditingController();
  final daDays = TextEditingController(text: '0');
  String daArea = 'ordinary';
  final lodging = TextEditingController();
  final other = TextEditingController();
  final otherNote = TextEditingController();
  String? receiptUrl;

  void dispose() {
    from.dispose();
    to.dispose();
    distance.dispose();
    fare.dispose();
    daDays.dispose();
    lodging.dispose();
    other.dispose();
    otherNote.dispose();
  }
}

const _modes = [
  (value: 'bus', label: 'Bus'),
  (value: 'shared', label: 'Shared vehicle'),
  (value: 'train', label: 'Train'),
  (value: 'air', label: 'Air'),
  (value: 'taxi', label: 'Taxi'),
  (value: 'two_wheeler', label: 'Two wheeler'),
  (value: 'own_car', label: 'Own car'),
  (value: 'other', label: 'Other'),
];

class TadaFormScreen extends StatefulWidget {
  const TadaFormScreen({super.key});

  @override
  State<TadaFormScreen> createState() => _TadaFormScreenState();
}

class _TadaFormScreenState extends State<TadaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _purpose = TextEditingController();
  final _advance = TextEditingController();

  final List<_Leg> _legs = [_Leg()];
  int? _projectId;
  List _projects = const [];

  /// Rates from the server, used to price the claim live as it is typed. The
  /// server re-prices authoritatively on submit; this is only a preview.
  Map<String, dynamic> _taRates = const {};
  Map<String, dynamic> _daRates = const {};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _purpose.dispose();
    _advance.dispose();
    for (final leg in _legs) {
      leg.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<Api>();
      final results = await Future.wait([
        api.get('/tada/rates'),
        api.get('/projects', {'status': 'active'}),
      ]);
      if (!mounted) return;
      final rates = results[0] as Map<String, dynamic>;
      setState(() {
        _taRates = {
          for (final r in (rates['ta_rates'] as List? ?? const [])) '${r['mode']}': r,
        };
        _daRates = {
          for (final r in (rates['da_rates'] as List? ?? const [])) '${r['area']}': r,
        };
        _projects = results[1] as List;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, e.message, error: true);
        setState(() => _loading = false);
      }
    }
  }

  bool _isActualFare(String mode) => _taRates[mode]?['actual_fare'] == true;
  num _perKm(String mode) => num.tryParse('${_taRates[mode]?['paise_per_km']}') ?? 0;
  num _daPerDay(String area) => num.tryParse('${_daRates[area]?['da_paise_per_day']}') ?? 0;

  num _legTotal(_Leg leg) {
    final fare = _isActualFare(leg.mode)
        ? (num.tryParse(leg.fare.text) ?? 0) * 100
        : (num.tryParse(leg.distance.text) ?? 0) * _perKm(leg.mode);
    final da = (num.tryParse(leg.daDays.text) ?? 0) * _daPerDay(leg.daArea);
    final lodging = (num.tryParse(leg.lodging.text) ?? 0) * 100;
    final other = (num.tryParse(leg.other.text) ?? 0) * 100;
    return fare + da + lodging + other;
  }

  num get _grossPaise => _legs.fold<num>(0, (sum, leg) => sum + _legTotal(leg));
  num get _netPaise => _grossPaise - (num.tryParse(_advance.text) ?? 0) * 100;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    for (final (i, leg) in _legs.indexed) {
      if (leg.date == null) {
        showSnack(context, 'Choose the travel date for leg ${i + 1}.', error: true);
        return;
      }
    }

    setState(() => _busy = true);
    try {
      await context.read<Api>().post('/tada', {
        'purpose': _purpose.text.trim(),
        if (_projectId != null) 'project_id': _projectId,
        // The claim spans the earliest to the latest leg.
        'from_date': apiDate(_legs.map((l) => l.date!).reduce((a, b) => a.isBefore(b) ? a : b)),
        'to_date': apiDate(_legs.map((l) => l.date!).reduce((a, b) => a.isAfter(b) ? a : b)),
        'advance': num.tryParse(_advance.text) ?? 0,
        'legs': [
          for (final leg in _legs)
            {
              'travel_date': apiDate(leg.date!),
              'from_place': leg.from.text.trim(),
              'to_place': leg.to.text.trim(),
              'mode': leg.mode,
              'distance_km': num.tryParse(leg.distance.text) ?? 0,
              if (_isActualFare(leg.mode)) 'fare': num.tryParse(leg.fare.text) ?? 0,
              'da_days': num.tryParse(leg.daDays.text) ?? 0,
              'da_area': leg.daArea,
              if (leg.lodging.text.trim().isNotEmpty) 'lodging': num.tryParse(leg.lodging.text) ?? 0,
              if (leg.other.text.trim().isNotEmpty) 'other': num.tryParse(leg.other.text) ?? 0,
              if (leg.otherNote.text.trim().isNotEmpty) 'other_note': leg.otherNote.text.trim(),
              if (leg.receiptUrl != null) 'receipt_url': leg.receiptUrl,
            },
        ],
      });
      if (!mounted) return;
      showSnack(context, 'Claim submitted for review.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('New TA/DA claim')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New TA/DA claim')),
      bottomNavigationBar: _totalsBar(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          children: [
            TextFormField(
              controller: _purpose,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Purpose of the journey',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 5)
                  ? 'Describe why the journey was made'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: _projectId,
              decoration: const InputDecoration(labelText: 'Project / programme (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not project-specific')),
                for (final p in _projects)
                  DropdownMenuItem(
                    value: p['id'] as int,
                    child: Text('${p['name']}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            SectionTitle('Journey legs (${_legs.length})',
                action: TextButton.icon(
                  onPressed: () => setState(() => _legs.add(_Leg())),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add leg'),
                )),
            for (final (i, leg) in _legs.indexed) _legCard(i, leg),
            const SectionTitle('Advance'),
            TextFormField(
              controller: _advance,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Advance already drawn (₹)',
                helperText: 'Leave blank if no advance was taken',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NesfColors.greenLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 17, color: NesfColors.green),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Amounts shown are calculated from the Foundation\'s current rates. '
                      'The office re-checks every figure before sanctioning.',
                      style: TextStyle(fontSize: 11.5, color: NesfColors.green, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legCard(int index, _Leg leg) {
    final actualFare = _isActualFare(leg.mode);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NesfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22, height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: NesfColors.green, shape: BoxShape.circle),
                  child: Text('${index + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(fmtMoney(_legTotal(leg)),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (_legs.length > 1)
                  IconButton(
                    onPressed: () => setState(() {
                      _legs.removeAt(index).dispose();
                    }),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 20, color: NesfColors.rejected),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: leg.date ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: now,
                      );
                      if (picked != null) setState(() => leg.date = picked);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
                      ),
                      child: Text(
                        leg.date == null ? 'Select' : fmtDateShort(apiDate(leg.date!)),
                        style: TextStyle(
                          fontSize: 13,
                          color: leg.date == null ? NesfColors.muted : NesfColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: leg.mode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Mode', isDense: true),
                    items: [
                      for (final m in _modes)
                        DropdownMenuItem(
                          value: m.value,
                          child: Text(m.label, style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                    onChanged: (v) => setState(() => leg.mode = v ?? 'bus'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: leg.from,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'From', isDense: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: leg.to,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'To', isDense: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Per-km modes are computed from distance; ticketed modes take the
            // actual fare paid, so only ever show the field that applies.
            if (actualFare)
              TextFormField(
                controller: leg.fare,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Actual fare paid (₹)',
                  isDense: true,
                  prefixText: '₹ ',
                  helperText: 'Attach the ticket or receipt below',
                ),
              )
            else
              TextFormField(
                controller: leg.distance,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Distance (km)',
                  isDense: true,
                  suffixText: 'km',
                  helperText: 'At ${fmtMoney(_perKm(leg.mode), decimals: true)} per km',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: leg.daDays,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'DA days', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: leg.daArea,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Area', isDense: true),
                    items: [
                      for (final a in const [
                        (value: 'ordinary', label: 'Ordinary'),
                        (value: 'state_capital', label: 'State capital'),
                        (value: 'metro', label: 'Metro city'),
                      ])
                        DropdownMenuItem(
                          value: a.value,
                          child: Text(
                            '${a.label} · ${fmtMoney(_daPerDay(a.value))}/day',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => leg.daArea = v ?? 'ordinary'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: leg.lodging,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Lodging (₹)', isDense: true, prefixText: '₹ '),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: leg.other,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Other (₹)', isDense: true, prefixText: '₹ '),
                  ),
                ),
              ],
            ),
            if (leg.other.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: leg.otherNote,
                decoration: const InputDecoration(
                    labelText: 'What was the other expense for?', isDense: true),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _totalsBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: NesfColors.line)),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Net payable',
                    style: TextStyle(fontSize: 11, color: NesfColors.muted)),
                Text(
                  fmtMoney(_netPaise, decimals: true),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _netPaise < 0 ? NesfColors.rejected : NesfColors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Text('Submit claim'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
