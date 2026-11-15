import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _green      = Color(0xFF2E7D32);
  static const _greenLight = Color(0xFFF1F8F1);
  static const _greenMid   = Color(0xFFE8F5E9);

  late Future<Map<String, dynamic>> _aboutFuture;

  @override
  void initState() {
    super.initState();
    _aboutFuture = ApiService.getAboutStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenLight,
      appBar: AppBar(
        backgroundColor: _green,
        title: const Text('Settings & About',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _HeaderCard(),
          const SizedBox(height: 16),
          _FeaturesCard(),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _aboutFuture,
            builder: (ctx, snap) {
              final data = snap.data;
              final loading = snap.connectionState == ConnectionState.waiting;
              return _DatabaseCard(data: data, loading: loading);
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _aboutFuture,
            builder: (ctx, snap) {
              final data = snap.data;
              final loading = snap.connectionState == ConnectionState.waiting;
              return _MilestonesCard(data: data, loading: loading);
            },
          ),
          const SizedBox(height: 16),
          _AppInfoCard(),
          const SizedBox(height: 16),
          _DeveloperToolsCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withOpacity(0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          // Logo circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🌿', style: TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'PlantSage v1.0',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your AI Gardening Assistant',
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Features ────────────────────────────────────────────────────────────────
class _FeaturesCard extends StatelessWidget {
  static const _features = [
    ('🔍', 'Plant Identification',  'Snap a photo and get instant AI-powered plant ID'),
    ('🦠', 'Disease Diagnosis',     'Detect diseases and get treatment guidance'),
    ('🌱', 'My Garden',             'Track your personal plant collection'),
    ('💧', 'Watering Calendar',     'Never miss a watering with smart reminders'),
    ('🤖', 'AI Plant Expert',       'Chat with an expert about any plant topic'),
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Features',
      icon: Icons.auto_awesome,
      child: Column(
        children: _features.map((f) => _FeatureRow(f.$1, f.$2, f.$3)).toList(),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  const _FeatureRow(this.emoji, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B5E20))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Color(0xFF43A047), size: 18),
        ],
      ),
    );
  }
}

// ─── Database stats ───────────────────────────────────────────────────────────
class _DatabaseCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  const _DatabaseCard({required this.data, required this.loading});

  @override
  Widget build(BuildContext context) {
    final dbMb   = (data?['db_size_mb']   as num?)?.toStringAsFixed(2) ?? '—';
    final plants = data?['garden_count']   as int?;
    final scans  = data?['scan_count']     as int?;
    final wish   = data?['wishlist_count'] as int?;

    return _SectionCard(
      title: 'Storage & Usage',
      icon: Icons.storage_outlined,
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF2E7D32)),
                ),
              ),
            )
          : Column(
              children: [
                _StatRow(
                  icon: Icons.storage_rounded,
                  label: 'Database Size',
                  value: '$dbMb MB',
                  color: const Color(0xFF1565C0),
                ),
                _Divider(),
                _StatRow(
                  icon: Icons.local_florist,
                  label: 'Plants Stored',
                  value: plants != null ? '$plants' : '—',
                  color: const Color(0xFF2E7D32),
                ),
                _Divider(),
                _StatRow(
                  icon: Icons.image_search_outlined,
                  label: 'Scans Performed',
                  value: scans != null ? '$scans' : '—',
                  color: const Color(0xFF6A1B9A),
                ),
                _Divider(),
                _StatRow(
                  icon: Icons.favorite_border,
                  label: 'Wishlist Plants',
                  value: wish != null ? '$wish' : '—',
                  color: const Color(0xFFC62828),
                ),
              ],
            ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatRow({required this.icon, required this.label,
                  required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF424242))),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: Color(0xFFE8F5E9));
}

// ─── App Info ─────────────────────────────────────────────────────────────────
class _AppInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'App Info',
      icon: Icons.info_outline,
      child: Column(
        children: const [
          _InfoRow(label: 'App Version',    value: '1.0.0'),
          _InfoRow(label: 'AI Model',       value: 'GPT-4o'),
          _InfoRow(label: 'Platform',       value: 'Flutter / Windows'),
          _InfoRow(label: 'Backend',        value: 'FastAPI + SQLite'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF616161)))),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }
}

// ─── Gardening Milestones ────────────────────────────────────────────────────

class _MilestoneData {
  final String emoji;
  final String title;
  final int current;
  final int goal;
  // Whether this milestone has a meaningful progress bar (false = show ✓/□ only)
  final bool showProgress;

  const _MilestoneData({
    required this.emoji,
    required this.title,
    required this.current,
    required this.goal,
    this.showProgress = true,
  });

  bool get unlocked => current >= goal;
  double get progress => goal <= 0 ? 0.0 : (current / goal).clamp(0.0, 1.0);
}

class _MilestonesCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  const _MilestonesCard({required this.data, required this.loading});

  List<_MilestoneData> _buildMilestones(Map<String, dynamic> d) {
    final plants = d['garden_count']           as int? ?? 0;
    final scans  = d['scan_count']             as int? ?? 0;
    final days   = d['days_gardening']         as int? ?? 0;
    final cured  = d['disease_resolved_count'] as int? ?? 0;
    return [
      _MilestoneData(emoji: '🔍', title: 'First Plant Scanned',    current: scans,  goal: 1,   showProgress: false),
      _MilestoneData(emoji: '🌱', title: 'First Plant Added',       current: plants, goal: 1,   showProgress: false),
      _MilestoneData(emoji: '🦠', title: 'First Disease Resolved',  current: cured,  goal: 1,   showProgress: false),
      _MilestoneData(emoji: '📅', title: '30 Days Gardening',       current: days,   goal: 30),
      _MilestoneData(emoji: '🌿', title: '10 Plants Added',         current: plants, goal: 10),
      _MilestoneData(emoji: '🔬', title: '50 Plants Scanned',       current: scans,  goal: 50),
      _MilestoneData(emoji: '💐', title: '100 Plants Added',        current: plants, goal: 100),
      _MilestoneData(emoji: '🏆', title: '365 Days Gardening',      current: days,   goal: 365),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _SectionCard(
        title: 'Gardening Milestones',
        icon: Icons.emoji_events_outlined,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF2E7D32)),
            ),
          ),
        ),
      );
    }

    final d = data ?? {};
    final milestones = _buildMilestones(d);
    final unlocked = milestones.where((m) => m.unlocked).length;
    final total    = milestones.length;

    return _SectionCard(
      title: 'Gardening Milestones',
      icon: Icons.emoji_events_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? unlocked / total : 0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE8F5E9),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF43A047)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$unlocked / $total',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E7D32)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$unlocked of $total achievements unlocked',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          // Milestone rows
          ...milestones.map((m) => _MilestoneRow(m: m)),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final _MilestoneData m;
  const _MilestoneRow({required this.m});

  @override
  Widget build(BuildContext context) {
    final unlocked = m.unlocked;
    final inProgress = !unlocked && m.showProgress && m.current > 0;

    final iconBg    = unlocked ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5);
    final iconColor = unlocked ? const Color(0xFF2E7D32) : Colors.grey.shade400;
    final titleColor = unlocked
        ? const Color(0xFF1B5E20)
        : (inProgress ? const Color(0xFF424242) : Colors.grey.shade500);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status icon circle
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: unlocked
                      ? const Icon(Icons.check_circle, color: Color(0xFF43A047), size: 18)
                      : Icon(Icons.radio_button_unchecked, color: iconColor, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              // Emoji + title
              Text(m.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  m.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: unlocked ? FontWeight.w600 : FontWeight.normal,
                    color: titleColor,
                  ),
                ),
              ),
              // Count badge
              if (unlocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('✓',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32))),
                )
              else if (m.showProgress)
                Text(
                  '${m.current} / ${m.goal}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: inProgress ? const Color(0xFF1565C0) : Colors.grey.shade400,
                  ),
                ),
            ],
          ),
          // Progress bar for in-progress locked milestones
          if (inProgress) ...
            [
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.only(left: 42),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: m.progress,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE3F2FD),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

// ─── Developer Tools ─────────────────────────────────────────────────────────
class _DeveloperToolsCard extends StatefulWidget {
  @override
  State<_DeveloperToolsCard> createState() => _DeveloperToolsCardState();
}

class _DeveloperToolsCardState extends State<_DeveloperToolsCard> {
  bool _resetting = false;

  Future<void> _confirmAndReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Text('⚠️', style: TextStyle(fontSize: 22)),
          SizedBox(width: 8),
          Text('Reset All Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFB71C1C))),
        ]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will permanently remove:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF424242))),
            SizedBox(height: 10),
            _BulletItem('Scan History'),
            _BulletItem('My Garden'),
            _BulletItem('Wishlist'),
            _BulletItem('Disease History'),
            _BulletItem('Watering Records'),
            SizedBox(height: 12),
            Text('A backup will be created automatically before the reset.',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF424242))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB71C1C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);

    final result = await ApiService.resetAllData();

    if (!mounted) return;
    setState(() => _resetting = false);

    final success = result['success'] as bool? ?? false;
    final message = result['message'] as String? ?? '';
    final backup  = result['backup']  as String? ?? '';
    final total   = result['total_rows_deleted'] as int? ?? 0;

    if (success) {
      _showResultDialog(
        title: '✅ Reset Complete',
        titleColor: const Color(0xFF1B5E20),
        body: 'Reset completed successfully.\n\n$total row(s) removed.\n\nBackup saved to:\n$backup',
      );
    } else {
      _showResultDialog(
        title: '❌ Reset Failed',
        titleColor: const Color(0xFFB71C1C),
        body: message,
      );
    }
  }

  void _showResultDialog({required String title, required Color titleColor, required String body}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF2E7D32))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Developer Tools',
      icon: Icons.developer_mode_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reset all user data for testing purposes. The database schema and app settings are preserved.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _resetting ? null : _confirmAndReset,
              icon: _resetting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_sweep_outlined, size: 20),
              label: Text(_resetting ? 'Resetting…' : 'Reset All Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;
  const _BulletItem(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        const Text('•  ', style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.bold)),
        Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF424242))),
      ]),
    );
  }
}

// ─── Shared section card ──────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: const Color(0xFF2E7D32), size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E7D32),
                      letterSpacing: 0.5)),
            ]),
            const Divider(height: 16, color: Color(0xFFE8F5E9)),
            child,
          ],
        ),
      ),
    );
  }
}
