import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

// --- Responsive breakpoints --------------------------------------------------
const double _kTablet  = 600;
const double _kDesktop = 960;

// --- Task status -------------------------------------------------------------
enum TaskStatus { upcoming, dueToday, overdue, missed, completed }

extension TaskStatusExt on TaskStatus {
  Color get color => const {
    TaskStatus.upcoming:  Color(0xFF1976D2),
    TaskStatus.dueToday:  Color(0xFF1565C0),
    TaskStatus.overdue:   Color(0xFFE65100),
    TaskStatus.missed:    Color(0xFFC62828),
    TaskStatus.completed: Color(0xFF2E7D32),
  }[this]!;

  Color get bgColor => const {
    TaskStatus.upcoming:  Color(0xFFE3F2FD),
    TaskStatus.dueToday:  Color(0xFFBBDEFB),
    TaskStatus.overdue:   Color(0xFFFFF3E0),
    TaskStatus.missed:    Color(0xFFFFEBEE),
    TaskStatus.completed: Color(0xFFE8F5E9),
  }[this]!;

  IconData get icon => const {
    TaskStatus.upcoming:  Icons.water_drop,
    TaskStatus.dueToday:  Icons.water_drop,
    TaskStatus.overdue:   Icons.warning_amber,
    TaskStatus.missed:    Icons.cancel_outlined,
    TaskStatus.completed: Icons.check_circle,
  }[this]!;

  String get label => const {
    TaskStatus.upcoming:  'Upcoming',
    TaskStatus.dueToday:  'Due Today',
    TaskStatus.overdue:   'Overdue',
    TaskStatus.missed:    'Missed',
    TaskStatus.completed: 'Done',
  }[this]!;
}

// --- Water amount (derived from interval) ------------------------------------
enum WaterAmount { low, medium, high }

WaterAmount _calcWaterAmount(int interval) {
  if (interval <= 3) return WaterAmount.high;
  if (interval <= 7) return WaterAmount.medium;
  return WaterAmount.low;
}

extension WaterAmountExt on WaterAmount {
  String   get label => const {WaterAmount.low: 'Low', WaterAmount.medium: 'Medium', WaterAmount.high: 'High'}[this]!;
  Color    get color => const {WaterAmount.low: Color(0xFF388E3C), WaterAmount.medium: Color(0xFFF57F17), WaterAmount.high: Color(0xFFC62828)}[this]!;
  IconData get icon  => Icons.water_drop;
}

// --- Care task type metadata -------------------------------------------------
extension CareTaskTypeInfo on String {
  String get careLabel => const {
    'fertilize': 'Fertilize',
    'prune':     'Prune',
    'pest_check': 'Pest Check',
  }[this] ?? this;

  IconData get careIcon => const {
    'fertilize': Icons.eco,
    'prune':     Icons.content_cut,
    'pest_check': Icons.bug_report,
  }[this] ?? Icons.task_alt;

  Color get careColor => const {
    'fertilize': Color(0xFF558B2F),
    'prune':     Color(0xFF6A1B9A),
    'pest_check': Color(0xFFBF360C),
  }[this] ?? const Color(0xFF666666);

  int get careDefaultInterval => const {
    'fertilize': 30,
    'prune':     60,
    'pest_check': 14,
  }[this] ?? 30;
}

// --- Month name table --------------------------------------------------------
const _monthNames = ['', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];
const _monthShort = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// --- CalendarScreen ----------------------------------------------------------
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  DateTime?     _selected;
  bool          _isLoading  = true;
  List<dynamic> _plants     = [];
  List<dynamic> _careTasks  = [];
  String?       _activeFilter;            // null=all | 'water' | care task type
  final Set<int> _markingIds        = {};
  final Set<int> _completingCareIds = {};

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _loadWithBackfill();
  }

  /// On first load, run backfill so existing plants get care tasks created.
  Future<void> _loadWithBackfill() async {
    await ApiService.backfillCareTasks();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      ApiService.getMyGarden(),
      ApiService.getCareTasks(),
    ]);
    if (mounted) setState(() {
      _plants    = results[0];
      _careTasks = results[1];
      _isLoading = false;
    });
  }

  // -- Data helpers ------------------------------------------------------------

  // Water task map — entries tagged with _task_kind: 'water'
  Map<DateTime, List<Map<String, dynamic>>> _buildWaterMap() {
    final map   = <DateTime, List<Map<String, dynamic>>>{};
    final first = DateTime(_month.year, _month.month, 1);
    final last  = DateTime(_month.year, _month.month + 1, 0);

    for (final raw in _plants) {
      final p        = Map<String, dynamic>.from(raw as Map);
      // Resolve interval: ground plants use ground_range lower bound if available
      int? interval = p['watering_interval_days'] as int?;
      final plantingType = p['planting_type'] as String?;
      final rec = p['watering_recommended'] as Map<String, dynamic>?;
      if (plantingType == 'ground' && rec != null && rec['ground_range'] != null) {
        try {
          final gndStr = rec['ground_range'] as String;
          interval = int.parse(gndStr.split('-')[0]);
        } catch (_) {}
      }
      if (interval == null || interval <= 0) continue;
      p['_task_kind'] = 'water';

      DateTime start;
      final lwStr = p['last_watered_at'] as String?;
      if (lwStr != null) {
        try { start = DateTime.parse(lwStr); } catch (_) { start = DateTime.now(); }
      } else {
        start = DateTime.now().subtract(Duration(days: interval));
      }

      int n = 1;
      DateTime next = start.add(Duration(days: interval));
      while (DateTime(next.year, next.month, next.day).isBefore(first)) {
        n++; next = start.add(Duration(days: interval * n));
      }
      while (!DateTime(next.year, next.month, next.day).isAfter(last)) {
        final d = DateTime(next.year, next.month, next.day);
        (map[d] ??= []).add(Map<String, dynamic>.from(p));
        n++; next = start.add(Duration(days: interval * n));
      }
    }
    return map;
  }

  // Care task map — entries tagged with _task_kind: 'care'
  Map<DateTime, List<Map<String, dynamic>>> _buildCareMap() {
    final map   = <DateTime, List<Map<String, dynamic>>>{};
    final first = DateTime(_month.year, _month.month, 1);
    final last  = DateTime(_month.year, _month.month + 1, 0);

    for (final raw in _careTasks) {
      final t        = Map<String, dynamic>.from(raw as Map);
      final interval = t['interval_days'] as int?;
      if (interval == null || interval <= 0) continue;
      t['_task_kind'] = 'care';

      DateTime start;
      final ldStr = t['last_done_at'] as String?;
      if (ldStr != null) {
        try { start = DateTime.parse(ldStr); } catch (_) { start = DateTime.now(); }
      } else {
        start = DateTime.now().subtract(Duration(days: interval));
      }

      int n = 1;
      DateTime next = start.add(Duration(days: interval));
      while (DateTime(next.year, next.month, next.day).isBefore(first)) {
        n++; next = start.add(Duration(days: interval * n));
      }
      while (!DateTime(next.year, next.month, next.day).isAfter(last)) {
        final d = DateTime(next.year, next.month, next.day);
        (map[d] ??= []).add(Map<String, dynamic>.from(t));
        n++; next = start.add(Duration(days: interval * n));
      }
    }
    return map;
  }

  // Merge water + care maps, applying active filter
  Map<DateTime, List<Map<String, dynamic>>> _buildCombinedMap(
      Map<DateTime, List<Map<String, dynamic>>> waterMap,
      Map<DateTime, List<Map<String, dynamic>>> careMap) {
    final combined = <DateTime, List<Map<String, dynamic>>>{};

    if (_activeFilter == null || _activeFilter == 'water') {
      for (final e in waterMap.entries) {
        (combined[e.key] ??= []).addAll(e.value);
      }
    }
    if (_activeFilter != 'water') {
      for (final e in careMap.entries) {
        final tasks = _activeFilter == null
            ? e.value
            : e.value.where((t) => t['task_type'] == _activeFilter).toList();
        if (tasks.isNotEmpty) (combined[e.key] ??= []).addAll(tasks);
      }
    }
    return combined;
  }

  TaskStatus _taskStatusForDate(Map<String, dynamic> task, DateTime date) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isWater = (task['_task_kind'] as String?) == 'water';

    final lastStr = isWater
        ? task['last_watered_at'] as String?
        : task['last_done_at'] as String?;

    DateTime? lastNorm;
    if (lastStr != null) {
      try {
        final lw = DateTime.parse(lastStr);
        lastNorm = DateTime(lw.year, lw.month, lw.day);
      } catch (_) {}
    }

    if (lastNorm != null && !lastNorm.isBefore(date)) return TaskStatus.completed;
    if (date.isAfter(today)) return TaskStatus.upcoming;
    if (date == today) {
      final days = isWater
          ? task['days_until_water'] as int?
          : task['days_until_due'] as int?;
      return (days != null && days < 0) ? TaskStatus.overdue : TaskStatus.dueToday;
    }
    return TaskStatus.missed;
  }

  TaskStatus _worstStatus(List<Map<String, dynamic>> tasks, DateTime date) {
    final s = tasks.map((t) => _taskStatusForDate(t, date)).toList();
    if (s.any((x) => x == TaskStatus.missed))      return TaskStatus.missed;
    if (s.any((x) => x == TaskStatus.overdue))     return TaskStatus.overdue;
    if (s.any((x) => x == TaskStatus.dueToday))    return TaskStatus.dueToday;
    if (s.every((x) => x == TaskStatus.completed)) return TaskStatus.completed;
    return TaskStatus.upcoming;
  }

  Map<String, int> _monthlySummary(
      Map<DateTime, List<Map<String, dynamic>>> taskMap) {
    int total = 0, completed = 0, overdue = 0;
    for (final entry in taskMap.entries) {
      for (final t in entry.value) {
        total++;
        final s = _taskStatusForDate(t, entry.key);
        if (s == TaskStatus.completed) completed++;
        if (s == TaskStatus.overdue || s == TaskStatus.missed) overdue++;
      }
    }
    return {'total': total, 'completed': completed,
            'overdue': overdue, 'remaining': total - completed};
  }

  // -- Actions -----------------------------------------------------------------

  Future<void> _markWatered(int id) async {
    if (_markingIds.contains(id)) return;
    if (mounted) setState(() => _markingIds.add(id));
    try {
      await ApiService.markWatered(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _markingIds.remove(id));
    }
  }

  Future<void> _markCareDone(int taskId) async {
    if (_completingCareIds.contains(taskId)) return;
    if (mounted) setState(() => _completingCareIds.add(taskId));
    try {
      await ApiService.completeCareTask(taskId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _completingCareIds.remove(taskId));
    }
  }

  void _showDaySheet(DateTime date, List<Map<String, dynamic>> tasks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        expand: false,
        builder: (_, controller) => _DayDetailSheet(
          date: date,
          tasks: tasks,
          statusFn: _taskStatusForDate,
          markingIds: _markingIds,
          completingCareIds: _completingCareIds,
          onMarkWatered: (id) { Navigator.pop(context); _markWatered(id); },
          onMarkCareDone: (id) { Navigator.pop(context); _markCareDone(id); },
          scrollController: controller,
        ),
      ),
    );
  }

  void _showAddCareTaskDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddCareTaskDialog(
        plants: _plants,
        existingCareTasks: _careTasks,
        onCreated: _load,
      ),
    );
  }

  // -- Shared sub-widgets ------------------------------------------------------

  Widget _buildSummaryCard(Map<String, int> s) => Container(
    margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
    ),
    child: Row(children: [
      _SumStat(Icons.task_alt,        '${s['total']}',     'Total',   const Color(0xFF1565C0)),
      _SumStat(Icons.check_circle,    '${s['completed']}', 'Done',    const Color(0xFF2E7D32)),
      _SumStat(Icons.hourglass_empty, '${s['remaining']}', 'Left',    const Color(0xFF1B5E20)),
      _SumStat(Icons.warning_amber,   '${s['overdue']}',   'Overdue',
          (s['overdue'] ?? 0) > 0 ? const Color(0xFFE65100) : const Color(0xFF9E9E9E),
          highlight: (s['overdue'] ?? 0) > 0),
    ]),
  );

  Widget _buildFilterChips() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(children: [
      _FilterChip(
          label: 'All', icon: Icons.grid_view,
          selected: _activeFilter == null,
          onTap: () => setState(() => _activeFilter = null)),
      const SizedBox(width: 6),
      _FilterChip(
          label: 'Water', icon: Icons.water_drop,
          color: const Color(0xFF1565C0),
          selected: _activeFilter == 'water',
          onTap: () => setState(
              () => _activeFilter = _activeFilter == 'water' ? null : 'water')),
      ...['fertilize', 'prune', 'pest_check'].map((type) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: _FilterChip(
            label: type.careLabel,
            icon: type.careIcon,
            color: type.careColor,
            selected: _activeFilter == type,
            onTap: () => setState(
                () => _activeFilter = _activeFilter == type ? null : type),
          ),
        )),
    ]),
  );

  Widget _buildMonthNav() => ColoredBox(
    color: const Color(0xFF2E7D32),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => setState(() {
            _selected = null;
            _month = DateTime(_month.year, _month.month - 1);
          }),
        ),
        Expanded(
          child: Text('${_monthNames[_month.month]} ${_month.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white),
          onPressed: () => setState(() {
            _selected = null;
            _month = DateTime(_month.year, _month.month + 1);
          }),
        ),
      ]),
    ),
  );

  Widget _buildWeekHeaders() => ColoredBox(
    color: const Color(0xFF388E3C),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .map((d) => Expanded(
                  child: Text(d,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ))
            .toList(),
      ),
    ),
  );

  Widget _buildLegend() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Wrap(spacing: 10, runSpacing: 4, children: [
      _LegendDot(color: const Color(0xFF2E7D32),      label: 'Today'),
      _LegendDot(color: TaskStatus.dueToday.bgColor,  label: 'Due'),
      _LegendDot(color: TaskStatus.overdue.bgColor,   label: 'Overdue'),
      _LegendDot(color: TaskStatus.missed.bgColor,    label: 'Missed'),
      _LegendDot(color: TaskStatus.completed.bgColor, label: 'Done'),
    ]),
  );

  Widget _buildGrid(
      DateTime today,
      Map<DateTime, List<Map<String, dynamic>>> taskMap,
      double availableWidth) {
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth  = DateTime(_month.year, _month.month + 1, 0).day;
    final leading      = firstOfMonth.weekday - 1;

    final cellWidth  = (availableWidth / 7) - 4.0;
    final cellHeight = (cellWidth * 1.6).clamp(54.0, 110.0);
    final aspect     = cellWidth / cellHeight;
    final numSize    = (cellWidth * 0.22).clamp(9.0, 14.0);

    final cells = <Widget>[
      for (int i = 0; i < leading; i++) const SizedBox(),
      for (int d = 1; d <= daysInMonth; d++) _buildCell(
          d, DateTime(_month.year, _month.month, d), today,
          taskMap, cellWidth, numSize),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: aspect,
      children: cells,
    );
  }

  Widget _buildCell(int d, DateTime date, DateTime today,
      Map<DateTime, List<Map<String, dynamic>>> taskMap,
      double cellWidth, double numSize) {
    final isToday = date == today;
    final isSel   = date == _selected;
    final tasks   = taskMap[date] ?? [];
    final isPast  = date.isBefore(today);

    Color cellBg;
    if (isToday) {
      cellBg = const Color(0xFF2E7D32);
    } else if (tasks.isNotEmpty) {
      final ws = _worstStatus(tasks, date);
      cellBg = isSel ? ws.bgColor.withOpacity(0.9) : ws.bgColor;
    } else {
      cellBg = isSel ? const Color(0xFFE8F5E9) : Colors.transparent;
    }

    return GestureDetector(
      onTap: () {
        setState(() => _selected = isSel ? null : date);
        if (tasks.isNotEmpty && MediaQuery.of(context).size.width < _kTablet) {
          _showDaySheet(date, tasks);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: cellBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('$d',
                style: TextStyle(
                  fontSize: numSize,
                  fontWeight: (isToday || isSel) ? FontWeight.bold : FontWeight.normal,
                  color: isToday
                      ? Colors.white
                      : isPast ? Colors.grey.shade400 : Colors.black87,
                )),
            if (tasks.isNotEmpty)
              ..._buildCellChips(tasks, date, isToday, cellWidth),
          ],
        ),
      ),
    );
  }

  IconData _taskIcon(Map<String, dynamic> task) {
    if ((task['_task_kind'] as String?) == 'care') {
      return (task['task_type'] as String? ?? '').careIcon;
    }
    return Icons.water_drop;
  }

  List<Widget> _buildCellChips(List<Map<String, dynamic>> tasks, DateTime date,
      bool isToday, double cellWidth) {
    final iconSize = (cellWidth * 0.18).clamp(7.0, 11.0);
    final fontSize = (cellWidth * 0.13).clamp(6.0, 8.5);
    return [
      for (final t in tasks.take(2)) ...[
        const SizedBox(height: 1),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: isToday
                ? Colors.white24
                : _taskStatusForDate(t, date).color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _taskIcon(t),
              size: iconSize,
              color: isToday ? Colors.white : _taskStatusForDate(t, date).color,
            ),
            const SizedBox(width: 1),
            Expanded(
              child: Text(
                t['plant_name'] as String? ?? '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  color: isToday ? Colors.white : _taskStatusForDate(t, date).color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ],
      if (tasks.length > 2)
        Text('+${tasks.length - 2}',
            style: TextStyle(
                fontSize: (fontSize - 1).clamp(5.5, 8.0),
                color: isToday ? Colors.white70 : Colors.grey.shade600)),
    ];
  }

  // -- Wide side-panel detail --------------------------------------------------

  Widget _buildDayPanel(DateTime date, List<Map<String, dynamic>> tasks) =>
      ListView(padding: EdgeInsets.zero, children: [
        _DayPanelHeader(date: date),
        ...tasks.map((t) {
          if ((t['_task_kind'] as String?) == 'care') {
            return _CareTaskCard(
              task: t,
              date: date,
              status: _taskStatusForDate(t, date),
              isCompleting: _completingCareIds.contains(t['id'] as int? ?? -1),
              onMarkDone: () => _markCareDone(t['id'] as int),
            );
          }
          return _PlantTaskCard(
            plant: t,
            date: date,
            status: _taskStatusForDate(t, date),
            isMarking: _markingIds.contains(t['id'] as int? ?? -1),
            onMarkWatered: () => _markWatered(t['id'] as int),
          );
        }),
        const SizedBox(height: 24),
      ]);

  // -- Responsive layouts ------------------------------------------------------

  Widget _buildNarrow(BoxConstraints c, DateTime today,
      Map<DateTime, List<Map<String, dynamic>>> taskMap,
      Map<String, int> summary) {
    return SingleChildScrollView(
      child: Column(children: [
        _buildSummaryCard(summary),
        _buildFilterChips(),
        _buildMonthNav(),
        _buildWeekHeaders(),
        ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: _buildGrid(today, taskMap, c.maxWidth - 12),
          ),
        ),
        _buildLegend(),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildWide(
      BoxConstraints c,
      DateTime today,
      Map<DateTime, List<Map<String, dynamic>>> taskMap,
      Map<String, int> summary,
      List<Map<String, dynamic>>? selectedTasks,
      bool hasTasks) {
    final calW = c.maxWidth * (c.maxWidth >= _kDesktop ? 0.55 : 0.60);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: calW,
        child: SingleChildScrollView(
          child: Column(children: [
            _buildSummaryCard(summary),
            _buildFilterChips(),
            _buildMonthNav(),
            _buildWeekHeaders(),
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _buildGrid(today, taskMap, calW - 12),
              ),
            ),
            _buildLegend(),
          ]),
        ),
      ),
      const VerticalDivider(width: 1, thickness: 1),
      Expanded(
        child: hasTasks
            ? (selectedTasks != null && selectedTasks.isNotEmpty
                ? _buildDayPanel(_selected!, selectedTasks)
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: Colors.grey, size: 36),
                        SizedBox(height: 8),
                        Text('Tap a day to see tasks',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    )))
            : const _NoSchedules(),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(children: [
          Icon(Icons.calendar_month, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text('Plant Care Calendar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2E7D32),
        onPressed: _showAddCareTaskDialog,
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: const Text('Add Care Task',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : LayoutBuilder(builder: (context, c) {
              final now     = DateTime.now();
              final today   = DateTime(now.year, now.month, now.day);
              final wmap    = _buildWaterMap();
              final cmap    = _buildCareMap();
              final taskMap = _buildCombinedMap(wmap, cmap);
              final summary = _monthlySummary(taskMap);
              final hasTasks  = wmap.isNotEmpty || cmap.isNotEmpty;
              final selTasks  = _selected != null ? taskMap[_selected!] : null;

              if (c.maxWidth >= _kTablet) {
                return _buildWide(c, today, taskMap, summary, selTasks, hasTasks);
              }
              return _buildNarrow(c, today, taskMap, summary);
            }),
    );
  }
}

// --- Monthly summary stat column ---------------------------------------------
class _SumStat extends StatelessWidget {
  final IconData iconData;
  final String value, label;
  final Color iconColor;
  final bool highlight;
  const _SumStat(this.iconData, this.value, this.label, this.iconColor,
      {this.highlight = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(iconData, color: iconColor, size: 22),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: highlight
                      ? const Color(0xFFE65100)
                      : const Color(0xFF1B5E20))),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      );
}

// --- Day panel header --------------------------------------------------------
class _DayPanelHeader extends StatelessWidget {
  final DateTime date;
  const _DayPanelHeader({required this.date});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(children: [
          const Icon(Icons.event, size: 18, color: Color(0xFF1B5E20)),
          const SizedBox(width: 8),
          Text('${_monthNames[date.month]} ${date.day}, ${date.year}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1B5E20))),
        ]),
      );
}

// --- Plant task card ---------------------------------------------------------
class _PlantTaskCard extends StatelessWidget {
  final Map<String, dynamic> plant;
  final DateTime date;
  final TaskStatus status;
  final bool isMarking;
  final VoidCallback onMarkWatered;

  const _PlantTaskCard({
    required this.plant,
    required this.date,
    required this.status,
    required this.isMarking,
    required this.onMarkWatered,
  });

  @override
  Widget build(BuildContext context) {
    final name     = plant['plant_name']      as String? ?? '-';
    final sci      = plant['scientific_name'] as String? ?? '';
    final interval = plant['watering_interval_days'] as int? ?? 7;
    final wa       = _calcWaterAmount(interval);
    final lwStr    = plant['last_watered_at'] as String?;
    final imgPath  = plant['image_path'] as String?;
    final isDone     = status == TaskStatus.completed;
    final isUpcoming = status == TaskStatus.upcoming;

    String lastLabel = 'Never', nextLabel = '-';
    if (lwStr != null) {
      try {
        final lw   = DateTime.parse(lwStr);
        final next = lw.add(Duration(days: interval));
        lastLabel = '${lw.day} ${_monthShort[lw.month]} ${lw.year}';
        nextLabel = '${next.day} ${_monthShort[next.month]} ${next.year}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color.withOpacity(0.3)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: status.bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200),
              clipBehavior: Clip.antiAlias,
              child: imgPath != null && File(imgPath).existsSync()
                  ? Image.file(File(imgPath), fit: BoxFit.cover)
                  : const Icon(Icons.local_florist, color: Color(0xFF388E3C), size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (sci.isNotEmpty)
                  Text(sci,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
              ]),
            ),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: status.color, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(status.icon, size: 11, color: Colors.white),
                const SizedBox(width: 4),
                Text(status.label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
        ),

        // Info grid
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(spacing: 16, runSpacing: 8, children: [
            _InfoChip(label: 'Task',         value: 'Water Plant', icon: Icons.water_drop),
            _InfoChip(label: 'Amount',       value: wa.label,      icon: wa.icon, color: wa.color),
            _InfoChip(label: 'Last watered', value: lastLabel,     icon: Icons.history),
            _InfoChip(label: 'Next due',     value: nextLabel,     icon: Icons.schedule),
          ]),
        ),

        // Action row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: isDone
              ? const Row(children: [
                  Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 18),
                  SizedBox(width: 6),
                  Text('Watered',
                      style: TextStyle(
                          color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                ])
              : isUpcoming
                  ? Row(children: [
                      Icon(Icons.event_available,
                          color: Colors.blue.shade300, size: 16),
                      const SizedBox(width: 6),
                      Text('Scheduled — water on this day',
                          style: TextStyle(
                              color: Colors.blue.shade400, fontSize: 12)),
                    ])
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: isMarking ? null : onMarkWatered,
                        icon: isMarking
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(isMarking ? 'Saving...' : 'Mark Watered'),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// --- Info chip (label + value) -----------------------------------------------
class _InfoChip extends StatelessWidget {
  final String label, value;
  final IconData? icon;
  final Color? color;
  const _InfoChip({required this.label, required this.value, this.icon, this.color});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color ?? Colors.grey.shade600),
            const SizedBox(width: 3),
          ],
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.black87)),
        ]),
      ]);
}

// --- Bottom sheet (mobile day detail) ----------------------------------------
class _DayDetailSheet extends StatelessWidget {
  final DateTime date;
  final List<Map<String, dynamic>> tasks;
  final TaskStatus Function(Map<String, dynamic>, DateTime) statusFn;
  final Set<int> markingIds;
  final Set<int> completingCareIds;
  final void Function(int) onMarkWatered;
  final void Function(int) onMarkCareDone;
  final ScrollController? scrollController;

  const _DayDetailSheet({
    required this.date,
    required this.tasks,
    required this.statusFn,
    required this.markingIds,
    required this.completingCareIds,
    required this.onMarkWatered,
    required this.onMarkCareDone,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1F8F1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            const Icon(Icons.event, color: Color(0xFF1B5E20)),
            const SizedBox(width: 8),
            Text('${_monthNames[date.month]} ${date.day}, ${date.year}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1B5E20))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            children: [
              ...tasks.map((t) {
                if ((t['_task_kind'] as String?) == 'care') {
                  return _CareTaskCard(
                    task: t,
                    date: date,
                    status: statusFn(t, date),
                    isCompleting: completingCareIds.contains(t['id'] as int? ?? -1),
                    onMarkDone: () => onMarkCareDone(t['id'] as int),
                  );
                }
                return _PlantTaskCard(
                  plant: t,
                  date: date,
                  status: statusFn(t, date),
                  isMarking: markingIds.contains(t['id'] as int? ?? -1),
                  onMarkWatered: () => onMarkWatered(t['id'] as int),
                );
              }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ]),
    );
  }
}

// --- Legend dot --------------------------------------------------------------
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.grey.shade300)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]);
}

// --- Empty state -------------------------------------------------------------
class _NoSchedules extends StatelessWidget {
  const _NoSchedules();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 52, color: Color(0xFF1565C0)),
              SizedBox(height: 12),
              Text('No care schedules yet.',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32))),
              SizedBox(height: 6),
              Text('Tap "+ Add Care Task" to schedule\nfertilizing, pruning, pest checks and more.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      );
}

// --- Care task card ----------------------------------------------------------
class _CareTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final DateTime date;
  final TaskStatus status;
  final bool isCompleting;
  final VoidCallback onMarkDone;

  const _CareTaskCard({
    required this.task,
    required this.date,
    required this.status,
    required this.isCompleting,
    required this.onMarkDone,
  });

  @override
  Widget build(BuildContext context) {
    final name      = task['plant_name']      as String? ?? '-';
    final sci       = task['scientific_name'] as String? ?? '';
    final taskType  = task['task_type']       as String? ?? '';
    final interval  = task['interval_days']   as int? ?? 30;
    final imgPath   = task['image_path']      as String?;
    final ldStr     = task['last_done_at']    as String?;
    final source    = task['schedule_source'] as String?;
    final isDone     = status == TaskStatus.completed;
    final isUpcoming = status == TaskStatus.upcoming;
    final typeColor = taskType.careColor;
    final typeIcon  = taskType.careIcon;
    final typeLabel = taskType.careLabel;

    String lastLabel = 'Never', nextLabel = '-';
    if (ldStr != null) {
      try {
        final ld   = DateTime.parse(ldStr);
        final next = ld.add(Duration(days: interval));
        lastLabel = '${ld.day} ${_monthShort[ld.month]} ${ld.year}';
        nextLabel = '${next.day} ${_monthShort[next.month]} ${next.year}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withOpacity(0.3)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: status.bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200),
              clipBehavior: Clip.antiAlias,
              child: imgPath != null && File(imgPath).existsSync()
                  ? Image.file(File(imgPath), fit: BoxFit.cover)
                  : Icon(typeIcon, color: typeColor, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (sci.isNotEmpty)
                  Text(sci,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: status.color, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(status.icon, size: 11, color: Colors.white),
                const SizedBox(width: 4),
                Text(status.label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
        ),
        // Info grid
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(spacing: 16, runSpacing: 8, children: [
            _InfoChip(label: 'Task',      value: typeLabel,           icon: typeIcon,       color: typeColor),
            _InfoChip(label: 'Frequency', value: 'Every $interval days', icon: Icons.repeat),
            _InfoChip(label: 'Last done', value: lastLabel,           icon: Icons.history),
            _InfoChip(label: 'Next due',  value: nextLabel,           icon: Icons.schedule),
            if (source != null) _ScheduleSourceBadge(source: source),
          ]),
        ),
        // Action row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: isDone
              ? Row(children: [
                  Icon(Icons.check_circle, color: typeColor, size: 18),
                  const SizedBox(width: 6),
                  Text('Completed',
                      style: TextStyle(color: typeColor, fontWeight: FontWeight.w600)),
                ])
              : isUpcoming
                  ? Row(children: [
                      Icon(Icons.event_available, color: Colors.blue.shade300, size: 16),
                      const SizedBox(width: 6),
                      Text('Scheduled — do on this day',
                          style: TextStyle(color: Colors.blue.shade400, fontSize: 12)),
                    ])
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: typeColor,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: isCompleting ? null : onMarkDone,
                        icon: isCompleting
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(isCompleting ? 'Saving...' : 'Mark Done'),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// --- Filter chip -------------------------------------------------------------
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF2E7D32);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : Colors.grey.shade300),
          boxShadow: selected
              ? [BoxShadow(color: c.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: selected ? Colors.white : c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.black87,
              )),
        ]),
      ),
    );
  }
}

// --- Schedule source badge ---------------------------------------------------
class _ScheduleSourceBadge extends StatelessWidget {
  final String source;
  const _ScheduleSourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (source) {
      'species_specific' => ('Species Specific', const Color(0xFF1B5E20), Icons.verified),
      'ai_estimated'     => ('AI Estimated',     const Color(0xFF1565C0), Icons.auto_awesome),
      _                  => ('General Rule',     const Color(0xFF757575), Icons.tune),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// --- Add care task dialog ----------------------------------------------------
class _AddCareTaskDialog extends StatefulWidget {
  final List<dynamic> plants;
  final List<dynamic> existingCareTasks;
  final VoidCallback onCreated;

  const _AddCareTaskDialog({
    required this.plants,
    required this.existingCareTasks,
    required this.onCreated,
  });

  @override
  State<_AddCareTaskDialog> createState() => _AddCareTaskDialogState();
}

class _AddCareTaskDialogState extends State<_AddCareTaskDialog> {
  int?   _selectedPlantId;
  String _selectedType = 'fertilize';
  bool   _isSaving     = false;
  String? _errorMsg;

  /// Task types that already exist for the currently selected plant.
  Set<String> _existingTypes() {
    if (_selectedPlantId == null) return {};
    return widget.existingCareTasks
        .where((t) => t['plant_id'] == _selectedPlantId)
        .map((t) => t['task_type'] as String)
        .toSet();
  }

  bool _currentTypeExists() => _existingTypes().contains(_selectedType);

  /// When plant changes, auto-select the first task type not yet scheduled.
  void _onPlantChanged(int? plantId) {
    final existing = widget.existingCareTasks
        .where((t) => t['plant_id'] == plantId)
        .map((t) => t['task_type'] as String)
        .toSet();
    const types = ['fertilize', 'prune', 'pest_check'];
    final available = types.firstWhere((t) => !existing.contains(t), orElse: () => 'fertilize');
    setState(() {
      _selectedPlantId = plantId;
      _selectedType    = available;
      _errorMsg        = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const types = ['fertilize', 'prune', 'pest_check'];
    final existing   = _existingTypes();
    final allTaken   = existing.length >= types.length;

    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.add_task, color: Color(0xFF2E7D32)),
        SizedBox(width: 8),
        Text('Add Care Task'),
      ]),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('Plant', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: _selectedPlantId,
            hint: const Text('Select a plant'),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: widget.plants.map<DropdownMenuItem<int>>((raw) {
              final p = raw as Map<String, dynamic>;
              return DropdownMenuItem(
                value: p['id'] as int,
                child: Text(
                  p['garden_name'] as String? ?? p['plant_name'] as String? ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _onPlantChanged,
          ),
          const SizedBox(height: 16),
          const Text('Task Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          if (_selectedPlantId != null && allTaken)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All care tasks are already scheduled for this plant.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ]),
            )
          else
            Wrap(
              spacing: 8, runSpacing: 8,
              children: types.map((type) {
                final isExisting = existing.contains(type);
                final selected   = _selectedType == type && !isExisting;
                final c          = isExisting ? Colors.grey.shade400 : type.careColor;
                return GestureDetector(
                  onTap: isExisting ? null : () => setState(() {
                    _selectedType = type;
                    _errorMsg     = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isExisting
                          ? Colors.grey.shade100
                          : selected ? c : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isExisting ? Colors.grey.shade300
                              : selected ? c : Colors.grey.shade300),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        isExisting ? Icons.check_circle : type.careIcon,
                        size: 16,
                        color: isExisting ? Colors.grey.shade400
                            : selected ? Colors.white : c,
                      ),
                      const SizedBox(width: 6),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(type.careLabel, style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13,
                          color: isExisting ? Colors.grey.shade400
                              : selected ? Colors.white : Colors.black87,
                        )),
                        Text(
                          isExisting ? 'Already set' : 'Every ${type.careDefaultInterval}d',
                          style: TextStyle(
                            fontSize: 10,
                            color: isExisting ? Colors.grey.shade400
                                : selected ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ]),
                    ]),
                  ),
                );
              }).toList(),
            ),
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_errorMsg!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          onPressed: (_isSaving || _selectedPlantId == null || _currentTypeExists() || allTaken)
              ? null
              : () async {
                  setState(() { _isSaving = true; _errorMsg = null; });
                  final err = await ApiService.createCareTask({
                    'plant_id':  _selectedPlantId,
                    'task_type': _selectedType,
                  });
                  if (!mounted) return;
                  if (err != null) {
                    setState(() { _isSaving = false; _errorMsg = err; });
                  } else {
                    if (context.mounted) Navigator.pop(context);
                    widget.onCreated();
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}
