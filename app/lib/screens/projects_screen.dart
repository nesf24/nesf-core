import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/auth.dart';
import '../services/documents.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Projects with their approved-activity rollups, plus the staff member's own
/// activity reports.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List _projects = const [];
  List _activities = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = context.read<Api>();
      final results = await Future.wait([
        api.get('/projects'),
        api.get('/projects/activities/list', {'scope': 'mine'}),
      ]);
      if (!mounted) return;
      setState(() {
        _projects = results[0] as List;
        _activities = results[1] as List;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthService>().employee;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects & activities'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: NesfColors.accent,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Projects (${_projects.length})'),
            Tab(text: 'My activities (${_activities.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/activities/new');
          if (mounted) _load();
        },
        backgroundColor: NesfColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Report activity'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _projectList(me),
                    _activityList(),
                  ],
                ),
    );
  }

  Widget _projectList(Employee? me) {
    if (_projects.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No projects yet',
        message: 'Projects are set up by programme managers. Activities you report '
            'can then be linked to them.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: _projects.map((p) => _projectCard(p as Map<String, dynamic>, me)).toList(),
      ),
    );
  }

  Widget _projectCard(Map<String, dynamic> p, Employee? me) {
    final budget = num.tryParse('${p['budget_paise']}') ?? 0;
    final spent = num.tryParse('${p['expenditure_paise']}') ?? 0;
    final ratio = budget == 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0).toDouble();
    final overspent = budget > 0 && spent > budget;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NesfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${p['name']}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                StatusChip('${p['status']}', compact: true),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              [
                '${p['code']}',
                if (p['sport'] != null) '${p['sport']}',
                if (p['district'] != null) '${p['district']}',
              ].join(' · '),
              style: const TextStyle(fontSize: 11.5, color: NesfColors.muted),
            ),
            if (p['funder'] != null) ...[
              const SizedBox(height: 5),
              Text('Supported by ${p['funder']}',
                  style: const TextStyle(fontSize: 11.5, color: NesfColors.body)),
            ],
            const Divider(height: 18),
            Row(
              children: [
                Expanded(child: _stat('${p['activity_count']}', 'Activities')),
                Expanded(child: _stat('${p['participants']}', 'Participants')),
                Expanded(child: _stat('${p['beneficiaries']}', 'Beneficiaries')),
              ],
            ),
            if (budget > 0) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fmtMoney(spent)} of ${fmtMoney(budget)} used',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: overspent ? NesfColors.rejected : NesfColors.body,
                      ),
                    ),
                  ),
                  Text('${(ratio * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: NesfColors.greenLight,
                  valueColor: AlwaysStoppedAnimation(
                      overspent ? NesfColors.rejected : NesfColors.green),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await context.push('/activities/new', extra: p);
                      if (mounted) _load();
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Activity'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                // The consolidated project report is a management document, so
                // only reviewers and above can pull it.
                if (me?.isReviewer ?? false) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _projectReport(p),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('Report'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        textStyle: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10.5, color: NesfColors.muted)),
      ],
    );
  }

  Future<void> _projectReport(Map<String, dynamic> p) async {
    try {
      await context.read<DocumentService>()
          .openPdf('/projects/${p['id']}/report.pdf', 'NESF-Project-${p['code']}.pdf');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Widget _activityList() {
    if (_activities.isEmpty) {
      return const EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No activity reports',
        message: 'Report a coaching session, tournament or workshop you conducted. '
            'Once approved it becomes part of the project record.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: _activities.map((a) => _activityCard(a as Map<String, dynamic>)).toList(),
      ),
    );
  }

  Widget _activityCard(Map<String, dynamic> a) {
    final approved = a['status'] == 'approved';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NesfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${a['title']}',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                StatusChip('${a['status']}', compact: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                fmtDate(a['activity_date']),
                if (a['venue'] != null) '${a['venue']}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: NesfColors.body),
            ),
            if (a['project_name'] != null) ...[
              const SizedBox(height: 4),
              Text('${a['project_name']}',
                  style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
            ],
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill(Icons.groups_rounded, '${a['participants_total'] ?? 0} participants'),
                if ((num.tryParse('${a['beneficiaries']}') ?? 0) > 0)
                  _pill(Icons.volunteer_activism_outlined, '${a['beneficiaries']} beneficiaries'),
                if ((num.tryParse('${a['expenditure_paise']}') ?? 0) > 0)
                  _pill(Icons.currency_rupee_rounded, fmtMoney(a['expenditure_paise'])),
              ],
            ),
            if (approved) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: Text('File No. ${a['file_no'] ?? '—'}',
                        style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await context.read<DocumentService>().openPdf(
                          '/projects/activities/${a['id']}/report.pdf',
                          'NESF-Activity-${a['id']}-${a['activity_date']}.pdf',
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: NesfColors.greenLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: NesfColors.green),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 11, color: NesfColors.green)),
        ],
      ),
    );
  }
}
