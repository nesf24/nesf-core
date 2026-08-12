import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Report a project activity — a coaching session, tournament or workshop —
/// with participation counts, expenditure and photo evidence.
class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key, this.project});

  /// Pre-selects the project when opened from a project card.
  final Map<String, dynamic>? project;

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _venue = TextEditingController();
  final _district = TextEditingController();
  final _male = TextEditingController(text: '0');
  final _female = TextEditingController(text: '0');
  final _other = TextEditingController(text: '0');
  final _beneficiaries = TextEditingController(text: '0');
  final _description = TextEditingController();
  final _outcome = TextEditingController();
  final _challenges = TextEditingController();
  final _expenditure = TextEditingController();

  DateTime? _date;
  DateTime? _endDate;
  int? _projectId;
  List _projects = const [];
  bool _busy = false;

  /// Photos chosen before the activity exists; uploaded after it is created,
  /// since the upload endpoint needs an activity id.
  final List<({Uint8List bytes, String name, String mime})> _photos = [];

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _projectId = widget.project?['id'] as int?;
    _district.text = '${widget.project?['district'] ?? ''}';
    _loadProjects();
  }

  @override
  void dispose() {
    for (final c in [_title, _venue, _district, _male, _female, _other,
                     _beneficiaries, _description, _outcome, _challenges, _expenditure]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final data = await context.read<Api>().get('/projects', {'status': 'active'}) as List;
      if (mounted) setState(() => _projects = data);
    } on ApiException {
      // Linking to a project is optional.
    }
  }

  int get _participants =>
      (int.tryParse(_male.text) ?? 0) +
      (int.tryParse(_female.text) ?? 0) +
      (int.tryParse(_other.text) ?? 0);

  Future<void> _addPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _photos.add((
          bytes: bytes,
          name: picked.name.isEmpty ? 'photo.jpg' : picked.name,
          mime: picked.mimeType ?? 'image/jpeg',
        )));
  }

  Future<void> _submit({required bool asDraft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      showSnack(context, 'Choose the date of the activity.', error: true);
      return;
    }
    if (_participants == 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No participants recorded'),
          content: const Text(
            'Participation numbers appear in the project report and the Foundation\'s '
            'impact figures. Submit with zero participants?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final api = context.read<Api>();
      final created = await api.post('/projects/activities', {
        if (_projectId != null) 'project_id': _projectId,
        'title': _title.text.trim(),
        'activity_date': apiDate(_date!),
        if (_endDate != null) 'end_date': apiDate(_endDate!),
        if (_venue.text.trim().isNotEmpty) 'venue': _venue.text.trim(),
        if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
        'participants_male': int.tryParse(_male.text) ?? 0,
        'participants_female': int.tryParse(_female.text) ?? 0,
        'participants_other': int.tryParse(_other.text) ?? 0,
        'beneficiaries': int.tryParse(_beneficiaries.text) ?? 0,
        'description': _description.text.trim(),
        if (_outcome.text.trim().isNotEmpty) 'outcome': _outcome.text.trim(),
        if (_challenges.text.trim().isNotEmpty) 'challenges': _challenges.text.trim(),
        'expenditure': num.tryParse(_expenditure.text) ?? 0,
        'status': asDraft ? 'draft' : 'submitted',
      }) as Map<String, dynamic>;

      // Photos are uploaded one by one against the new activity. A failure here
      // must not lose the report itself, so it is reported but not fatal.
      var failed = 0;
      for (final photo in _photos) {
        try {
          await api.upload(
            '/projects/activities/${created['id']}/photos',
            field: 'photo',
            filename: photo.name,
            bytes: photo.bytes,
            contentType: photo.mime,
          );
        } on ApiException {
          failed++;
        }
      }

      if (!mounted) return;
      showSnack(context, failed > 0
          ? 'Activity submitted, but $failed photo(s) could not be uploaded.'
          : asDraft ? 'Saved as a draft.' : 'Activity report submitted for review.',
          error: failed > 0);
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
      appBar: AppBar(title: const Text('Report an activity')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          children: [
            DropdownButtonFormField<int?>(
              initialValue: _projectId,
              decoration: const InputDecoration(labelText: 'Project / programme'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not linked to a project')),
                for (final p in _projects)
                  DropdownMenuItem(
                    value: p['id'] as int,
                    child: Text('${p['name']}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title of the activity'),
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Give the activity a title' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _dateField('Date', _date, (d) => setState(() => _date = d))),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateField('End date (optional)', _endDate,
                      (d) => setState(() => _endDate = d)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _venue,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Venue'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _district,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'District'),
            ),

            SectionTitle('Participation ($_participants total)'),
            Row(
              children: [
                Expanded(child: _countField(_male, 'Male')),
                const SizedBox(width: 10),
                Expanded(child: _countField(_female, 'Female')),
                const SizedBox(width: 10),
                Expanded(child: _countField(_other, 'Other')),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _beneficiaries,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Indirect beneficiaries',
                helperText: 'People reached beyond the direct participants',
              ),
            ),

            const SectionTitle('What happened'),
            TextFormField(
              controller: _description,
              minLines: 5,
              maxLines: 9,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description of the activity',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 20)
                  ? 'Please describe the activity in at least 20 characters'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _outcome,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Outcome & impact (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _challenges,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Challenges (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _expenditure,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Expenditure incurred (₹)',
                prefixText: '₹ ',
              ),
            ),

            SectionTitle('Photographs (${_photos.length})',
                action: TextButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Add'),
                )),
            if (_photos.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: NesfColors.line),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.photo_library_outlined, size: 19, color: NesfColors.muted),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Photos are printed in the approved activity report on '
                        'Foundation letterhead.',
                        style: TextStyle(fontSize: 12, color: NesfColors.muted, height: 1.35),
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final (i, photo) in _photos.indexed)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.memory(photo.bytes, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: InkWell(
                            onTap: () => setState(() => _photos.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                  color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded,
                                  size: 15, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),

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

  Widget _countField(TextEditingController c, String label) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPicked) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 2),
          lastDate: now,
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
        ),
        child: Text(
          value == null ? 'Select' : fmtDateShort(apiDate(value)),
          style: TextStyle(
              fontSize: 13.5, color: value == null ? NesfColors.muted : NesfColors.ink),
        ),
      ),
    );
  }
}
