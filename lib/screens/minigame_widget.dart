import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartstream_client/dartstream_client.dart';
import '../models/workspace_data.dart';
import '../state/session.dart';

class MinigameWidget extends StatefulWidget {
  final Session session;
  final WorkspaceData workspace;
  final Function(WorkspaceData updated) onWorkspaceChanged;
  final List<dynamic> featureFlags;

  const MinigameWidget({
    super.key,
    required this.session,
    required this.workspace,
    required this.onWorkspaceChanged,
    required this.featureFlags,
  });

  @override
  State<MinigameWidget> createState() => _MinigameWidgetState();
}

class _MinigameWidgetState extends State<MinigameWidget> {
  Timer? _autoMineTimer;
  static const _projectId = 'focusstream';
  static const _environmentId = 'development';

  DartStreamClient get _client => widget.session.client!;
  DartStreamSession get _sdkSession => widget.session.sdkSession!;

  bool _isFeatureEnabled(String flagKey) {
    for (final f in widget.featureFlags) {
      if (f is Map) {
        final key = f['key'] ?? f['flag_key'] ?? f['flagKey'];
        if (key == flagKey) {
          final enabled = f['enabled'] ?? f['value'] ?? false;
          return enabled == true || enabled == 'true';
        }
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _startAutoMining();
  }

  @override
  void dispose() {
    _autoMineTimer?.cancel();
    super.dispose();
  }

  void _startAutoMining() {
    _autoMineTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (widget.workspace.gameCores > 0) {
        final doubleBoost = _isFeatureEnabled('game-double-multiplier');
        final bytesAdded = widget.workspace.gameCores * (doubleBoost ? 2 : 1);
        
        final updated = widget.workspace.copyWith(
          gameScore: widget.workspace.gameScore + bytesAdded,
        );
        widget.onWorkspaceChanged(updated);
      }
    });
  }

  void _clickNode(int index) {
    final doubleBoost = _isFeatureEnabled('game-double-multiplier');
    final clickValue = widget.workspace.gameMultiplier * (doubleBoost ? 2 : 1);
    
    final updated = widget.workspace.copyWith(
      gameScore: widget.workspace.gameScore + clickValue,
    );
    widget.onWorkspaceChanged(updated);

    // Stream telemetry event
    _trackEvent('minigame.node.clicked', {
      'node_index': index,
      'points_earned': clickValue,
      'current_score': updated.gameScore,
    });
  }

  void _buyCore() {
    final cost = 50 * (widget.workspace.gameCores + 1);
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        gameCores: widget.workspace.gameCores + 1,
      );
      widget.onWorkspaceChanged(updated);
      _trackEvent('minigame.upgrade.bought', {
        'upgrade_type': 'ai_core',
        'cost': cost,
        'new_cores': updated.gameCores,
      });
    }
  }

  void _buyMultiplier() {
    final cost = 100 * widget.workspace.gameMultiplier;
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        gameMultiplier: widget.workspace.gameMultiplier + 1,
      );
      widget.onWorkspaceChanged(updated);
      _trackEvent('minigame.upgrade.bought', {
        'upgrade_type': 'compiler_multiplier',
        'cost': cost,
        'new_multiplier': updated.gameMultiplier,
      });
    }
  }

  void _prestigeReset() {
    final updated = widget.workspace.copyWith(
      gameScore: 0,
      gameCores: 0,
      gameMultiplier: widget.workspace.gameMultiplier + 5,
    );
    widget.onWorkspaceChanged(updated);
    _trackEvent('minigame.prestige', {
      'new_multiplier': updated.gameMultiplier,
    });
  }

  Future<void> _trackEvent(String eventType, Map<String, dynamic> payload) async {
    try {
      await _client.reactive.trackEvent(
        _sdkSession,
        eventType: eventType,
        payload: {
          ...payload,
          'projectId': _projectId,
          'environmentId': _environmentId,
        },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final doubleBoost = _isFeatureEnabled('game-double-multiplier');
    final prestigeUnlocked = _isFeatureEnabled('game-prestige-mode');
    
    final coreCost = 50 * (widget.workspace.gameCores + 1);
    final multCost = 100 * widget.workspace.gameMultiplier;

    return Card(
      color: const Color(0xFF151824),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: doubleBoost ? const Color(0xFF8B5CF6) : const Color(0xFF312E81),
          width: doubleBoost ? 2.0 : 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.grid_view_rounded, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Text(
                      'Focus Grid: Cyber Miner',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: doubleBoost ? Colors.white : const Color(0xFFC7D2FE),
                      ),
                    ),
                  ],
                ),
                if (doubleBoost)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'BOOSTED ×2',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Score Dashboard
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F111A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statColumn('Focus Bytes', '${widget.workspace.gameScore} KB', const Color(0xFF10B981)),
                  _statColumn('Auto Rate', '+${widget.workspace.gameCores * (doubleBoost ? 2 : 1)} KB/s', const Color(0xFF6366F1)),
                  _statColumn('Click Mult', '×${widget.workspace.gameMultiplier * (doubleBoost ? 2 : 1)}', const Color(0xFFF59E0B)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Interactive Clicker Grid
            const Text(
              'Optimize Nodes to Mine Bytes:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: 18,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () => _clickNode(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2130),
                      border: Border.all(color: const Color(0xFF312E81)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Icon(Icons.bolt, size: 16, color: Color(0xFF6366F1)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Upgrade Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.workspace.gameScore >= coreCost ? _buyCore : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: widget.workspace.gameScore >= coreCost ? const Color(0xFF6366F1) : const Color(0xFF1E2130)),
                    ),
                    child: Column(
                      children: [
                        const Text('Buy AI Core', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('$coreCost KB', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.workspace.gameScore >= multCost ? _buyMultiplier : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: widget.workspace.gameScore >= multCost ? const Color(0xFFF59E0B) : const Color(0xFF1E2130)),
                    ),
                    child: Column(
                      children: [
                        const Text('Compiler Upgrade', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('$multCost KB', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Gated Prestige Button
            if (prestigeUnlocked) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _prestigeReset,
                icon: const Icon(Icons.star, size: 16),
                label: const Text('Cyber Prestige (+5 Mult)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEC4899),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color, fontFamily: 'Courier'),
        ),
      ],
    );
  }
}
