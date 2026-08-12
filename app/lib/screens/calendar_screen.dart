import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Month calendar combining three sources: the signed-in user's own attendance
/// marks, everyone's approved leave, and declared holidays — so staff can see
/// who is away before picking their own dates.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  Map<String, dynamic>? _leave;
  Map<String, dynamic>? _attendance;
  bool _loading = true;
  String? _error;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = now.day;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<Api>();
      final query = {'year': _month.year, 'month': _month.month};
      final results = await Future.wait([
        api.get('/leaves/calendar', query),
        api.get('/attendance/calendar', query),
      ]);
      if (!mounted) return;
      setState(() {
        _leave = results[0] as Map<String, dynamic>;
        _attendance = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _selectedDay = null;
    });
    _load();
  }

  String _key(int day) =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// Own attendance state for a day, from the attendance grid.
  String? _myMark(int day) {
    final rows = (_attendance?['rows'] as List?) ?? const [];
    if (rows.isEmpty) return null;
    final marks = (rows.first as Map<String, dynamic>)['marks'] as Map<String, dynamic>?;
    return marks?['$day'] as String?;
  }

  List _leaveOn(int day) => (_leave?['by_date'] as Map<String, dynamic>?)?[_key(day)] as List? ?? const [];

  Map<String, dynamic>? _holidayOn(int day) {
    final holidays = (_leave?['holidays'] as List?) ?? const [];
    for (final h in holidays) {
      if ('${(h as Map)['holiday_on']}' == _key(day)) return h.cast<String, dynamic>();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Apply for leave',
            icon: const Icon(Icons.event_busy_rounded),
            onPressed: () => context.push('/leaves/apply'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _monthHeader(),
                    const SizedBox(height: 14),
                    _grid(),
                    const SizedBox(height: 8),
                    _legend(),
                    if (_selectedDay != null) _dayDetail(_selectedDay!),
                  ],
                ),
    );
  }

  Widget _monthHeader() {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
                   'August', 'September', 'October', 'November', 'December'];
    return Row(
      children: [
        IconButton(
          onPressed: () => _shift(-1),
          icon: const Icon(Icons.chevron_left_rounded),
          style: IconButton.styleFrom(backgroundColor: Colors.white),
        ),
        Expanded(
          child: Text(
            '${names[_month.month - 1]} ${_month.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: () => _shift(1),
          icon: const Icon(Icons.chevron_right_rounded),
          style: IconButton.styleFrom(backgroundColor: Colors.white),
        ),
      ],
    );
  }

  Widget _grid() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday-first grid, matching how the office reads a week.
    final leadingBlanks = DateTime(_month.year, _month.month, 1).weekday - 1;
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NesfColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: NesfColors.muted)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(r * 7 + c - leadingBlanks + 1, daysInMonth)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 46);

    final holiday = _holidayOn(day);
    final leaves = _leaveOn(day);
    final mark = _myMark(day);
    final selected = _selectedDay == day;
    final today = DateTime.now();
    final isToday = today.year == _month.year && today.month == _month.month && today.day == day;

    // Priority: own leave, then own attendance, then holiday, then others' leave.
    Color? bg;
    Color fg = NesfColors.ink;
    if (mark == 'leave') {
      bg = NesfColors.pendingBg;
      fg = NesfColors.pending;
    } else if (mark == 'present' || mark == 'field' || mark == 'wfh') {
      bg = NesfColors.approvedBg;
      fg = NesfColors.approved;
    } else if (holiday != null) {
      bg = NesfColors.infoBg;
      fg = NesfColors.info;
    } else if (mark == 'absent') {
      bg = NesfColors.rejectedBg;
      fg = NesfColors.rejected;
    } else if (mark == 'weekly_off') {
      fg = NesfColors.muted;
    }

    return InkWell(
      onTap: () => setState(() => _selectedDay = day),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: selected ? NesfColors.green : bg,
          borderRadius: BorderRadius.circular(9),
          border: isToday && !selected
              ? Border.all(color: NesfColors.green, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isToday || selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : fg,
              ),
            ),
            // A row of dots showing how many people are away that day.
            if (leaves.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < (leaves.length > 3 ? 3 : leaves.length); i++)
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? Colors.white70 : NesfColors.pending,
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

  Widget _legend() {
    final items = [
      (NesfColors.approvedBg, NesfColors.approved, 'Present'),
      (NesfColors.pendingBg, NesfColors.pending, 'On leave'),
      (NesfColors.infoBg, NesfColors.info, 'Holiday'),
      (NesfColors.rejectedBg, NesfColors.rejected, 'Absent'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (bg, fg, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 11, height: 11,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: fg.withValues(alpha: 0.5))),
              ),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
            ],
          ),
      ],
    );
  }

  Widget _dayDetail(int day) {
    final holiday = _holidayOn(day);
    final leaves = _leaveOn(day);
    final mark = _myMark(day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(fmtDate(_key(day))),
        if (holiday != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NesfCard(
              child: Row(
                children: [
                  const Icon(Icons.celebration_outlined, size: 19, color: NesfColors.info),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text('${holiday['name']}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  ),
                  const Text('Holiday', style: TextStyle(fontSize: 11.5, color: NesfColors.info)),
                ],
              ),
            ),
          ),
        if (mark != null && mark != 'future')
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NesfCard(
              child: Row(
                children: [
                  const Icon(Icons.fingerprint_rounded, size: 19, color: NesfColors.green),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text('Your attendance: ${_markLabel(mark)}',
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
          ),
        if (leaves.isEmpty && holiday == null && (mark == null || mark == 'future'))
          const NesfCard(
            child: Row(
              children: [
                Icon(Icons.event_available_outlined, size: 19, color: NesfColors.muted),
                SizedBox(width: 11),
                Text('Nothing recorded for this day',
                    style: TextStyle(fontSize: 13.5, color: NesfColors.muted)),
              ],
            ),
          ),
        for (final l in leaves)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NesfCard(
              child: Row(
                children: [
                  Avatar(
                    initials: _initials('${(l as Map)['full_name']}'),
                    photoKey: l['photo_url'] as String?,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l['full_name']}',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text(
                          '${l['leave_type_name']}${l['designation'] != null ? ' · ${l['designation']}' : ''}',
                          style: const TextStyle(fontSize: 11.5, color: NesfColors.muted),
                        ),
                      ],
                    ),
                  ),
                  StatusChip('${l['status']}', compact: true),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _markLabel(String mark) => switch (mark) {
        'present' => 'Present at the office',
        'field' => 'Field duty',
        'wfh' => 'Worked from home',
        'leave' => 'On leave',
        'holiday' => 'Holiday',
        'weekly_off' => 'Weekly off',
        'absent' => 'Not marked',
        _ => mark,
      };

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
