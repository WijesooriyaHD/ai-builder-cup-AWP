import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'meditation_state.dart';
import 'widgets/meditation_widgets.dart';

/// Body-scan meditations: choose a session, then progress sequentially through
/// each body region with gentle cues.
class BodyScanScreen extends StatefulWidget {
  const BodyScanScreen({super.key});

  @override
  State<BodyScanScreen> createState() => _BodyScanScreenState();
}

class _BodyScanScreenState extends State<BodyScanScreen> {
  BodyScanSession? _active;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Body Scan'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: _active == null
          ? _buildPicker(context)
          : _BodyScanSession(
              session: _active!,
              onExit: () => setState(() => _active = null),
            ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: MeditationCatalog.bodyScans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final s = MeditationCatalog.bodyScans[i];
        return MeditationListCard(
          emoji: '💆',
          title: s.title,
          subtitle: s.description,
          trailing: '${s.durationMinutes} min',
          onTap: () => setState(() => _active = s),
        );
      },
    );
  }
}

class _BodyScanSession extends StatefulWidget {
  final BodyScanSession session;
  final VoidCallback onExit;
  const _BodyScanSession({required this.session, required this.onExit});

  @override
  State<_BodyScanSession> createState() => _BodyScanSessionState();
}

class _BodyScanSessionState extends State<_BodyScanSession> {
  Timer? _timer;
  int _index = 0;
  bool _completed = false;
  late final int _secondsPerRegion;

  List<String> get _regions => MeditationCatalog.bodyRegions;

  @override
  void initState() {
    super.initState();
    // Spread the session duration evenly across the regions.
    final total = widget.session.durationMinutes * 60;
    _secondsPerRegion = (total / _regions.length).ceil().clamp(3, 600);
    _startRegionTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRegionTimer() {
    _timer?.cancel();
    HapticFeedback.selectionClick();
    _timer = Timer(Duration(seconds: _secondsPerRegion), _advance);
  }

  void _advance() {
    if (_index >= _regions.length - 1) {
      _finish();
    } else {
      setState(() => _index++);
      _startRegionTimer();
    }
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    await context.read<MeditationState>().completeSession(
          type: SessionType.bodyScan,
          title: widget.session.title,
          minutes: widget.session.durationMinutes,
        );
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: const [
            Text('💆', style: TextStyle(fontSize: 44)),
            SizedBox(height: 8),
            Text('Scan complete'),
          ],
        ),
        content: const Text(
          'You moved awareness through your whole body. Notice how you feel.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onExit();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final region = _regions[_index];
    final progress = (_index + 1) / _regions.length;

    return Container(
      color: kMeditationDeep,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () {
                    _timer?.cancel();
                    widget.onExit();
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('${_index + 1} / ${_regions.length}',
                      style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Bring gentle awareness to your',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            Text(
              region,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: BodyRegionIndicator(
                    regions: _regions,
                    activeIndex: _index,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation(kMeditationAccent),
                ),
              ),
            ),
            TextButton(
              onPressed: _advance,
              child: Text(
                _index >= _regions.length - 1 ? 'Finish' : 'Next region',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
