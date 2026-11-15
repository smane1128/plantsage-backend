import 'package:flutter/material.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────
class DiseaseHistoryScreen extends StatefulWidget {
  const DiseaseHistoryScreen({super.key});

  @override
  State<DiseaseHistoryScreen> createState() => _DiseaseHistoryScreenState();
}

class _DiseaseHistoryScreenState extends State<DiseaseHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  String _filterStatus = 'all';
  String _sortBy       = 'newest';
  String _searchQuery  = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getDiseaseHistory();
    if (mounted) {
      setState(() {
        _history     = List<Map<String, dynamic>>.from(data);
        _isLoading   = false;
      });
    }
  }

  Future<void> _deleteScan(Map<String, dynamic> scan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text(
            'Delete this health record for "${scan['plant_name'] ?? 'this plant'}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final err = await ApiService.deleteDiagnoseScan(scan['id'] as int);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    } else {
      setState(() => _history.removeWhere((s) => s['id'] == scan['id']));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Record deleted'),
        backgroundColor: Color(0xFF546E7A),
      ));
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> scan, String newStatus) async {
    final err = await ApiService.updateDiseaseStatus(scan['id'] as int, newStatus);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newStatus == 'resolved'
            ? 'Marked as resolved — plant health updated'
            : 'Status updated to Recovering'),
        backgroundColor: const Color(0xFF2E7D32),
      ));
      _load();
    }
  }

  // ── Derived lists ──────────────────────────────────────────
  int _count(String status) =>
      _history.where((s) => s['status'] == status).length;

  List<Map<String, dynamic>> get _filtered {
    var list = _history.where((s) {
      if (_filterStatus != 'all' && s['status'] != _filterStatus) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name    = (s['plant_name']   ?? '').toString().toLowerCase();
        final disease = (s['disease_name'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !disease.contains(q)) return false;
      }
      return true;
    }).toList();

    switch (_sortBy) {
      case 'newest':
        list.sort((a, b) => (b['scan_date'] ?? '').compareTo(a['scan_date'] ?? ''));
        break;
      case 'oldest':
        list.sort((a, b) => (a['scan_date'] ?? '').compareTo(b['scan_date'] ?? ''));
        break;
      case 'severity':
        const ord = {'severe': 0, 'moderate': 1, 'mild': 2, 'none': 3};
        list.sort((a, b) {
          final sa = ord[(a['severity'] ?? 'none').toString().toLowerCase()] ?? 3;
          final sb = ord[(b['severity'] ?? 'none').toString().toLowerCase()] ?? 3;
          return sa.compareTo(sb);
        });
        break;
      case 'plant':
        list.sort((a, b) =>
            (a['plant_name'] ?? 'zzz').toString()
                .compareTo((b['plant_name'] ?? 'zzz').toString()));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isWide  = screenW > 720;
    final hPad    = isWide ? screenW * 0.08 : 14.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.health_and_safety_outlined, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text('Plant Health History',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : _history.isEmpty
              ? _EmptyHistory(onScan: () => Navigator.pop(context))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF2E7D32),
                  child: CustomScrollView(slivers: [
                    // ── Stats header ──────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                        child: _StatsHeader(
                          total:      _history.length,
                          active:     _count('active'),
                          recovering: _count('recovering'),
                          resolved:   _count('resolved'),
                        ),
                      ),
                    ),
                    // ── Search bar ────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'Search by plant or disease…',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF2E7D32), size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── Filter + sort row ─────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 0),
                        child: Row(children: [
                          Expanded(
                            child: _FilterBar(
                              selected: _filterStatus,
                              onSelect: (v) => setState(() => _filterStatus = v),
                              counts: {
                                'all':        _history.length,
                                'active':     _count('active'),
                                'recovering': _count('recovering'),
                                'resolved':   _count('resolved'),
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          _SortButton(
                            current: _sortBy,
                            onChange: (v) => setState(() => _sortBy = v),
                          ),
                        ]),
                      ),
                    ),
                    // ── Result count ──────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 2),
                        child: Text(
                          '${_filtered.length} record${_filtered.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ),
                    ),
                    // ── Cards ─────────────────────────────────────────────
                    _filtered.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                                  const SizedBox(height: 10),
                                  const Text('No matching records.',
                                      style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 20),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => _DiseaseCard(
                                  scan: _filtered[i],
                                  onUpdateStatus: _updateStatus,
                                  onDelete: _deleteScan,
                                ),
                                childCount: _filtered.length,
                              ),
                            ),
                          ),
                  ]),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stats header
// ─────────────────────────────────────────────────────────────
class _StatsHeader extends StatelessWidget {
  final int total, active, recovering, resolved;
  const _StatsHeader(
      {required this.total,
      required this.active,
      required this.recovering,
      required this.resolved});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF2E7D32).withOpacity(0.28),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        Expanded(child: _StatTile(label: 'Total\nDiagnoses', value: total, color: Colors.white, icon: Icons.biotech)),
        _vd(),
        Expanded(child: _StatTile(label: 'Active', value: active, color: const Color(0xFFEF9A9A), icon: Icons.warning_amber_rounded)),
        _vd(),
        Expanded(child: _StatTile(label: 'Recovering', value: recovering, color: const Color(0xFFFFCC80), icon: Icons.healing)),
        _vd(),
        Expanded(child: _StatTile(label: 'Resolved', value: resolved, color: const Color(0xFFA5D6A7), icon: Icons.check_circle)),
      ]),
    );
  }

  Widget _vd() => Container(
      width: 1, height: 40,
      color: Colors.white.withOpacity(0.2),
      margin: const EdgeInsets.symmetric(horizontal: 2));
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _StatTile({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, size: 16, color: color.withOpacity(0.7)),
        const SizedBox(height: 4),
        Text('$value',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color, height: 1.1)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), height: 1.2)),
      ]);
}

// ─────────────────────────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  final Map<String, int> counts;
  const _FilterBar({required this.selected, required this.onSelect, required this.counts});

  @override
  Widget build(BuildContext context) {
    final filters = <(String, String)>[
      ('all', 'All'),
      ('active', 'Active'),
      ('recovering', 'Recovering'),
      ('resolved', 'Resolved'),
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.map((f) {
          final isSel  = selected == f.$1;
          final count  = counts[f.$1] ?? 0;
          final clr    = _statusColor(f.$1);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onSelect(f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSel ? clr : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSel ? clr : Colors.grey.shade300, width: 1),
                ),
                child: Text('${f.$2} ($count)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSel ? Colors.white : Colors.grey.shade600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':     return const Color(0xFFB71C1C);
      case 'recovering': return const Color(0xFFE65100);
      case 'resolved':   return const Color(0xFF2E7D32);
      default:           return const Color(0xFF546E7A);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Sort button
// ─────────────────────────────────────────────────────────────
class _SortButton extends StatelessWidget {
  final String current;
  final void Function(String) onChange;
  const _SortButton({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: current,
      onSelected: onChange,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'newest', child: Text('Newest First')),
        PopupMenuItem(value: 'oldest', child: Text('Oldest First')),
        PopupMenuItem(value: 'severity', child: Text('By Severity')),
        PopupMenuItem(value: 'plant', child: Text('By Plant Name')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sort, size: 16, color: Color(0xFF2E7D32)),
          const SizedBox(width: 4),
          Text(_label(current),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
        ]),
      ),
    );
  }

  String _label(String v) {
    switch (v) {
      case 'newest':   return 'Newest';
      case 'oldest':   return 'Oldest';
      case 'severity': return 'Severity';
      case 'plant':    return 'Plant';
      default:         return 'Sort';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Disease card
// ─────────────────────────────────────────────────────────────
class _DiseaseCard extends StatefulWidget {
  final Map<String, dynamic> scan;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStatus;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  const _DiseaseCard({required this.scan, required this.onUpdateStatus, required this.onDelete});

  @override
  State<_DiseaseCard> createState() => _DiseaseCardState();
}

class _DiseaseCardState extends State<_DiseaseCard> {
  bool _expanded   = false;
  bool _showTreat  = false;
  bool _showTimeline = false;

  // ── Static helpers ──────────────────────────────────────────
  static Color _sevColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'mild':     return const Color(0xFFF9A825);
      case 'moderate': return const Color(0xFFE65100);
      case 'severe':   return const Color(0xFFB71C1C);
      default:         return Colors.grey;
    }
  }

  static Color _statusColor(String? s) {
    switch (s) {
      case 'active':     return const Color(0xFFB71C1C);
      case 'recovering': return const Color(0xFFE65100);
      case 'resolved':   return const Color(0xFF2E7D32);
      default:           return const Color(0xFF546E7A);
    }
  }

  static IconData _statusIcon(String? s) {
    switch (s) {
      case 'active':     return Icons.warning_amber_rounded;
      case 'recovering': return Icons.healing;
      case 'resolved':   return Icons.check_circle;
      default:           return Icons.help_outline;
    }
  }

  /// Turns "None" / null / ambiguous names into readable labels
  static String _friendlyDiseaseName(
      String? raw, String? description, String? status) {
    final r = (raw ?? '').trim();
    if (r.isEmpty || r.toLowerCase() == 'none') {
      // Try to infer from description
      final d = (description ?? '').toLowerCase();
      if (d.contains('heat') || d.contains('sun scorch') || d.contains('burn'))
        return 'Heat Stress';
      if (d.contains('overwater') || d.contains('root rot') || d.contains('excess water'))
        return 'Overwatering Stress';
      if (d.contains('underwater') || d.contains('drought') || d.contains('dehydrat'))
        return 'Drought Stress';
      if (d.contains('nutrient') || d.contains('deficien') || d.contains('yellowing'))
        return 'Nutrient Deficiency';
      if (d.contains('environment') || d.contains('climate') || d.contains('unsuitable'))
        return 'Environmental Stress';
      if (d.contains('pest') || d.contains('insect') || d.contains('mite'))
        return 'Pest Infestation';
      if (d.contains('fungal') || d.contains('mold') || d.contains('blight'))
        return 'Fungal Infection';
      if (status == 'resolved') return 'Healthy Plant';
      return 'Unknown Condition';
    }
    // Normalise casing
    final lower = r.toLowerCase();
    if (lower.contains('heat') || lower.contains('scorch')) return 'Heat Stress';
    if (lower.contains('environment') || lower.contains('unsuitable climate'))
      return 'Environmental Stress';
    return r;
  }

  String _formatDate(String? rawDate, {bool compact = false}) {
    if (rawDate == null) return '';
    final dt = DateTime.tryParse(rawDate);
    if (dt == null) return rawDate;
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    if (compact) return '${dt.day} ${m[dt.month - 1]}';
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Parse the treatment field — Map from the API (backend already parsed it)
  Map<String, dynamic> _treatmentMap() {
    final t = widget.scan['treatment'];
    if (t == null) return {};
    if (t is Map<String, dynamic>) return t;
    // Defensive: if somehow still a string, wrap it
    if (t is String && t.isNotEmpty) return {'treatment_notes': t};
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final scan        = widget.scan;

    // ── Healthy scan — dedicated card ──────────────────────────
    final isHealthy = scan['is_healthy'] == true ||
        ((scan['disease_name'] == null ||
              (scan['disease_name'] as String).toLowerCase() == 'none') &&
            scan['status'] == 'resolved' &&
            (scan['severity'] == null ||
                (scan['severity'] as String? ?? '').toLowerCase() == 'none'));
    if (isHealthy) {
      final plantName = scan['plant_name'] as String?;
      final sciName   = scan['scientific_name'] as String?;
      final dateStr   = _formatDate(scan['scan_date'] as String?);
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.25), width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: const Color(0xFF2E7D32).withOpacity(0.10), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('✅ Healthy Plant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B5E20))),
                const SizedBox(height: 2),
                const Text('No disease detected',
                    style: TextStyle(fontSize: 12, color: Color(0xFF388E3C))),
                if (plantName != null && plantName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.local_florist, size: 12, color: Color(0xFF66BB6A)),
                    const SizedBox(width: 3),
                    Flexible(child: Text(
                      sciName != null && sciName.isNotEmpty ? '$plantName  ·  $sciName' : plantName,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF388E3C), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 11, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ]),
              ])),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                tooltip: 'Delete record',
                onPressed: () => widget.onDelete(scan),
              ),
            ]),
          ),
        ]),
      );
    }

    // ── Disease / pest scan ────────────────────────────────────
    final rawDisease  = scan['disease_name']      as String?;
    final desc        = scan['description']       as String?;
    final severity    = scan['severity']          as String?;
    final plantName   = scan['plant_name']        as String?;
    final sciName     = scan['scientific_name']   as String?;
    final notes       = scan['follow_up_notes']   as String?;
    final status      = scan['status']            as String? ?? 'active';
    final plantHealth = scan['plant_health_status'] as String?;
    final dateStr     = _formatDate(scan['scan_date']    as String?);
    final updatedStr  = _formatDate(scan['updated_date'] as String?, compact: true);
    final resolvedStr = _formatDate(scan['resolved_at']  as String?, compact: true);

    final disease   = _friendlyDiseaseName(rawDisease, desc, status);
    final sevColor  = _sevColor(severity);
    final statusClr = _statusColor(status);
    final statusIc  = _statusIcon(status);
    final treatMap  = _treatmentMap();
    final isActive  = status == 'active' || status == 'recovering';
    // Determine if treatment has any real content
    final hasTreat  = treatMap.isNotEmpty &&
        !treatMap.containsKey('treatment_notes');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusClr.withOpacity(0.20), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Status accent bar ──────────────────────────────────
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: statusClr,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14)),
          ),
        ),

        // ── Summary row ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Status icon circle
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: statusClr.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(statusIc, color: statusClr, size: 22),
            ),
            const SizedBox(width: 10),

            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Disease name
              Text(disease,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B5E20))),
              const SizedBox(height: 2),

              // Plant name + scientific name
              if (plantName != null && plantName.isNotEmpty)
                Row(children: [
                  const Icon(Icons.local_florist, size: 12, color: Color(0xFF66BB6A)),
                  const SizedBox(width: 3),
                  Flexible(child: Text(
                    sciName != null && sciName.isNotEmpty
                        ? '$plantName  ·  $sciName'
                        : plantName,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF388E3C), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
              const SizedBox(height: 5),

              // Badges row
              Wrap(spacing: 5, runSpacing: 3, children: [
                _Badge(label: '${status[0].toUpperCase()}${status.substring(1)}',
                    color: statusClr, icon: statusIc),
                if (severity != null && severity.isNotEmpty && severity.toLowerCase() != 'none')
                  _Badge(label: severity, color: sevColor, icon: Icons.bar_chart),
                _Badge(label: dateStr, color: Colors.grey.shade500,
                    icon: Icons.access_time, subtle: true),
              ]),

              // Description snippet — shown ONCE here, not repeated in expanded panel
              if (desc != null && desc.isNotEmpty) ...[  
                const SizedBox(height: 5),
                Text(
                  desc.length > 110 ? '${desc.substring(0, 110)}…' : desc,
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.black54, height: 1.4),
                ),
              ],

              // Linked plant garden health status
              if (plantHealth != null && plantHealth.isNotEmpty) ...[  
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _healthColor(plantHealth).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _healthColor(plantHealth).withOpacity(0.30)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.yard, size: 12, color: _healthColor(plantHealth)),
                    const SizedBox(width: 4),
                    Text('Garden Status: ${plantHealth[0].toUpperCase()}${plantHealth.substring(1)}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _healthColor(plantHealth))),
                  ]),
                ),
              ],
            ])),
          ]),
        ),

        // ── Quick action buttons ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            _QuickBtn(
              icon: Icons.medical_services_outlined,
              label: 'Treatment',
              active: _showTreat,
              onTap: () => setState(() {
                _showTreat = !_showTreat;
                if (_showTreat) _showTimeline = false;
                _expanded = _showTreat;
              }),
            ),
            const SizedBox(width: 6),
            _QuickBtn(
              icon: Icons.timeline,
              label: 'Timeline',
              active: _showTimeline,
              onTap: () => setState(() {
                _showTimeline = !_showTimeline;
                if (_showTimeline) _showTreat = false;
                _expanded = _showTimeline;
              }),
            ),
            const Spacer(),
            if (isActive && status != 'recovering')
              _QuickBtn(
                icon: Icons.healing,
                label: 'Recovering',
                onTap: () => widget.onUpdateStatus(widget.scan, 'recovering'),
                color: const Color(0xFFE65100),
              ),
            if (isActive) ...[  
              const SizedBox(width: 6),
              _QuickBtn(
                icon: Icons.check_circle_outline,
                label: 'Resolved',
                onTap: () => widget.onUpdateStatus(widget.scan, 'resolved'),
                color: const Color(0xFF2E7D32),
              ),
            ],
            const SizedBox(width: 6),
            _QuickBtn(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: () => widget.onDelete(widget.scan),
              color: Colors.grey.shade500,
            ),
          ]),
        ),

        // ── Expanded: Treatment plan ───────────────────────────
        if (_showTreat && _expanded) ...[  
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Treatment plan — NO duplicate description here
              if (hasTreat) ...[  
                _SectionLabel(
                    icon: Icons.medical_services_outlined,
                    label: 'Treatment Plan'),
                const SizedBox(height: 8),
                _TreatmentBlock(treatMap: treatMap),
              ] else if (treatMap.containsKey('treatment_notes')) ...[  
                _SectionLabel(icon: Icons.medical_services_outlined, label: 'Treatment'),
                const SizedBox(height: 6),
                Text(treatMap['treatment_notes'].toString(),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87, height: 1.5)),
              ] else ...[
                const Text('No treatment plan recorded.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],

              if (notes != null && notes.isNotEmpty) ...[  
                const SizedBox(height: 10),
                _SectionLabel(icon: Icons.edit_note, label: 'Follow-up Notes'),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF3F8F3),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: const Color(0xFF2E7D32).withOpacity(0.20))),
                  child: Text(notes,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54, height: 1.5)),
                ),
              ],
            ]),
          ),
        ],

        // ── Expanded: Timeline ─────────────────────────────────
        if (_showTimeline && _expanded) ...[  
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: _Timeline(
              scanDate:     scan['scan_date']    as String?,
              updatedDate:  scan['updated_date'] as String?,
              resolvedDate: scan['resolved_at']  as String?,
              status:       status,
              updatedStr:   updatedStr,
              resolvedStr:  resolvedStr,
              statusColor:  statusClr,
            ),
          ),
        ],
      ]),
    );
  }

  Color _healthColor(String? s) {
    switch (s) {
      case 'healthy':    return const Color(0xFF2E7D32);
      case 'sick':       return const Color(0xFFB71C1C);
      case 'recovering': return const Color(0xFFE65100);
      default:           return Colors.grey;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Timeline widget
// ─────────────────────────────────────────────────────────────
class _Timeline extends StatelessWidget {
  final String? scanDate, updatedDate, resolvedDate, status;
  final String updatedStr, resolvedStr;
  final Color statusColor;

  const _Timeline({
    required this.scanDate,
    required this.updatedDate,
    required this.resolvedDate,
    required this.status,
    required this.updatedStr,
    required this.resolvedStr,
    required this.statusColor,
  });

  String _fmt(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final events = <(String, String, Color, IconData)>[];
    if (scanDate != null)
      events.add((_fmt(scanDate), 'Disease Detected', const Color(0xFFB71C1C), Icons.bug_report_outlined));
    if (updatedDate != null && status == 'recovering')
      events.add((_fmt(updatedDate), 'Treatment Started / Recovering', const Color(0xFFE65100), Icons.healing));
    if (resolvedDate != null)
      events.add((_fmt(resolvedDate), 'Marked Resolved', const Color(0xFF2E7D32), Icons.check_circle));

    if (events.isEmpty)
      return const Text('No timeline data.', style: TextStyle(color: Colors.grey));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(icon: Icons.timeline, label: 'Disease Timeline'),
        const SizedBox(height: 10),
        ...List.generate(events.length, (i) {
          final ev      = events[i];
          final isLast  = i == events.length - 1;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 28,
              child: Column(children: [
                Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                        color: ev.$3.withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(ev.$4, size: 14, color: ev.$3)),
                if (!isLast)
                  Container(width: 2, height: 32, color: Colors.grey.shade200),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ev.$2,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ev.$3)),
                  const SizedBox(height: 2),
                  Text(ev.$1,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ),
            ),
          ]);
        }),
        // Current status pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Text(
            'Current Status: ${status![0].toUpperCase()}${status!.substring(1)}',
            style: TextStyle(
                fontSize: 12, color: statusColor, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Treatment block — renders structured treatment map
// ─────────────────────────────────────────────────────────────
class _TreatmentBlock extends StatelessWidget {
  final Map<String, dynamic> treatMap;
  const _TreatmentBlock({required this.treatMap});

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];

    // immediate_actions
    final immediate = _asList(treatMap['immediate_actions']);
    if (immediate.isNotEmpty) {
      widgets.add(_TreatSection(
        icon: Icons.flash_on,
        color: const Color(0xFFB71C1C),
        title: 'Immediate Actions',
        items: immediate,
        bullets: 'check',
      ));
    }

    // products
    final products = _asList(treatMap['products']);
    if (products.isNotEmpty && !(products.length == 1 && products[0].isEmpty)) {
      widgets.add(_TreatSection(
        icon: Icons.science_outlined,
        color: const Color(0xFF1565C0),
        title: 'Recommended Products',
        items: products.isEmpty ? ['None required'] : products,
        bullets: 'dot',
      ));
    } else {
      widgets.add(_TreatSection(
        icon: Icons.science_outlined,
        color: const Color(0xFF1565C0),
        title: 'Recommended Products',
        items: const ['None required'],
        bullets: 'none',
      ));
    }

    // application
    final app = (treatMap['application'] ?? '').toString().trim();
    if (app.isNotEmpty && app.toLowerCase() != 'n/a') {
      widgets.add(_TreatSection(
        icon: Icons.auto_fix_high,
        color: const Color(0xFFE65100),
        title: 'Application Method',
        items: [app],
        bullets: 'none',
      ));
    }

    // recovery_time
    final rec = (treatMap['recovery_time'] ?? '').toString().trim();
    if (rec.isNotEmpty && rec.toLowerCase() != 'n/a') {
      widgets.add(_TreatSection(
        icon: Icons.timer_outlined,
        color: const Color(0xFF2E7D32),
        title: 'Expected Recovery Time',
        items: [rec],
        bullets: 'none',
      ));
    }

    // Catch-all for any other keys (e.g. generic "Treatment" key)
    for (final e in treatMap.entries) {
      final k = e.key.toString();
      if (['immediate_actions', 'products', 'application', 'recovery_time']
          .contains(k)) continue;
      final items = e.value is List
          ? (e.value as List).map((x) => x.toString()).toList()
          : [e.value.toString()];
      widgets.add(_TreatSection(
        icon: Icons.arrow_right,
        color: const Color(0xFF424242),
        title: k,
        items: items,
        bullets: items.length > 1 ? 'dot' : 'none',
      ));
    }

    return Column(children: widgets);
  }

  List<String> _asList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    final s = v.toString().trim();
    return s.isEmpty ? [] : [s];
  }
}

class _TreatSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;
  final String bullets; // 'check' | 'dot' | 'none'
  const _TreatSection(
      {required this.icon,
      required this.color,
      required this.title,
      required this.items,
      required this.bullets});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.18), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 6),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (bullets == 'check')
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 6),
                    child: Icon(Icons.check, size: 13, color: color),
                  )
                else if (bullets == 'dot')
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 8, left: 2),
                    child: Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ),
                Expanded(child: Text(item,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87, height: 1.5))),
              ]),
            )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Quick action button
// ─────────────────────────────────────────────────────────────
class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;
  const _QuickBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final clr = color ?? const Color(0xFF546E7A);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? clr.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? clr.withOpacity(0.5) : Colors.grey.shade300,
              width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? clr : Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? clr : Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Badge
// ─────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool subtle;
  const _Badge(
      {required this.label,
      required this.color,
      required this.icon,
      this.subtle = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: subtle ? Colors.grey.shade100 : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: subtle ? Colors.grey.shade300 : color.withOpacity(0.35),
              width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: subtle ? Colors.grey : color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: subtle ? Colors.grey.shade600 : color,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1B5E20))),
      ]);
}

// ─────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────
class _EmptyHistory extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyHistory({required this.onScan});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.health_and_safety_outlined,
                size: 52, color: Color(0xFF2E7D32)),
          ),
          const SizedBox(height: 20),
          const Text('No Disease Records Found',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
          const SizedBox(height: 8),
          const Text('Your garden looks healthy!',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Start Disease Scan'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: onScan,
          ),
        ]),
      );
}
