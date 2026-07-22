// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Alert history (History tab)
//  Returns CONTENT only (no Scaffold) — LumiMainNav/NavBarPage provides the
//  gradient + bar, matching every other tab page.
//  See docs/superpowers/specs/2026-07-22-sos-history-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../database/alert_history_db.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_widgets.dart';

const _triggerIcons = {
  'SOS button': Icons.warning_amber_rounded,
  'Shake to SOS': Icons.vibration,
  'Check-in timer': Icons.timer_outlined,
  'Silent SOS trigger': Icons.volume_down,
};

class AlertHistoryPage extends StatefulWidget {
  const AlertHistoryPage({super.key});

  @override
  State<AlertHistoryPage> createState() => _AlertHistoryPageState();
}

class _AlertHistoryPageState extends State<AlertHistoryPage> {
  final _db = AlertHistoryDb();
  late Future<List<AlertHistoryEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _db.getEntries();
  }

  Future<void> _refresh() async {
    final future = _db.getEntries();
    setState(() {
      _entriesFuture = future;
    });
    await future;
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiColors.surface,
        title: Text('Clear alert history', style: LumiText.display(18)),
        content: Text("This can't be undone.",
            style: LumiText.body(14, color: LumiColors.textSub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: LumiText.body(14, color: LumiColors.textSub))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Clear',
                  style: LumiText.body(14,
                      weight: FontWeight.w700, color: LumiColors.accent))),
        ],
      ),
    );
    if (ok == true) {
      await _db.clear();
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text('History', style: LumiText.display(24)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: LumiColors.textSub),
                  onPressed: _confirmClear,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Every alert Lumi has sent, on this device.',
                style: LumiText.body(13, color: LumiColors.textSub)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: LumiColors.accent,
              child: FutureBuilder<List<AlertHistoryEntry>>(
                future: _entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: LumiColors.accent));
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return ListView(
                      // Scrollable even when empty, so pull-to-refresh
                      // still works with nothing on screen.
                      children: [
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: Text('No alerts yet',
                                style: LumiText.body(13,
                                    color: LumiColors.textSub)),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 11),
                    itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final AlertHistoryEntry entry;

  String _formatTimestamp(DateTime t) {
    final now = DateTime.now();
    final isToday =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $ampm';
    if (isToday) return 'Today $time';
    return '${t.month}/${t.day}/${t.year} $time';
  }

  @override
  Widget build(BuildContext context) {
    final sent = entry.outcome == 'Sent';
    return LumiCard(
      child: Row(
        children: [
          Icon(_triggerIcons[entry.trigger] ?? Icons.notifications_outlined,
              color: LumiColors.blue, size: 22),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.trigger,
                    style: LumiText.body(14.5, weight: FontWeight.w700)),
                Text(_formatTimestamp(entry.timestamp),
                    style: LumiText.body(12, color: LumiColors.textSub)),
                if (entry.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(entry.detail!,
                      style: LumiText.body(11.5, color: LumiColors.textSub)),
                ],
              ],
            ),
          ),
          LumiStatusPill(
              label: entry.outcome,
              color: sent ? LumiColors.green : LumiColors.accent),
        ],
      ),
    );
  }
}
