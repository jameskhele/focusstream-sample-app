import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dartstream_client/dartstream_client.dart';
import '../models/workspace_data.dart';
import '../state/session.dart';

class FloatingTextEffect {
  final Key id;
  final String text;
  final Offset position;
  double opacity;
  double offsetY;

  FloatingTextEffect({
    required this.id,
    required this.text,
    required this.position,
    this.opacity = 1.0,
    this.offsetY = 0.0,
  });
}

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

class _MinigameWidgetState extends State<MinigameWidget> with SingleTickerProviderStateMixin {
  Timer? _autoMineTimer;
  Timer? _animTimer;
  late AnimationController _pulseController;
  final List<FloatingTextEffect> _floaters = [];
  final List<String> _terminalLogs = ['[SYSTEM] Focus Grid Core initialized...', '[SYSTEM] Awaiting node optimization...'];
  
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _startAutoMining();
    _startAnimationLoop();
  }

  @override
  void dispose() {
    _autoMineTimer?.cancel();
    _animTimer?.cancel();
    _pulseController.dispose();
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

        // Spawn auto-mine floaters randomly in grid area
        final rand = Random();
        _spawnFloater(
          '+$bytesAdded KB',
          Offset(80.0 + rand.nextInt(150), 180.0 + rand.nextInt(60)),
          isAuto: true,
        );

        if (rand.nextDouble() > 0.6) {
          _addLog('[AUTO] AI Core optimized block. +$bytesAdded Focus Bytes.');
        }
      }
    });
  }

  void _startAnimationLoop() {
    _animTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_floaters.isEmpty) return;
      setState(() {
        for (var i = _floaters.length - 1; i >= 0; i--) {
          final f = _floaters[i];
          f.opacity -= 0.05;
          f.offsetY -= 2.0;
          if (f.opacity <= 0.0) {
            _floaters.removeAt(i);
          }
        }
      });
    });
  }

  void _spawnFloater(String text, Offset localPos, {bool isAuto = false}) {
    setState(() {
      _floaters.add(
        FloatingTextEffect(
          id: UniqueKey(),
          text: text,
          position: localPos,
        ),
      );
    });
  }

  void _addLog(String log) {
    setState(() {
      _terminalLogs.insert(0, log);
      if (_terminalLogs.length > 5) {
        _terminalLogs.removeLast();
      }
    });
  }

  void _clickNode(int index, TapDownDetails details) {
    final doubleBoost = _isFeatureEnabled('game-double-multiplier');
    final clickValue = widget.workspace.gameMultiplier * (doubleBoost ? 2 : 1);
    
    final updated = widget.workspace.copyWith(
      gameScore: widget.workspace.gameScore + clickValue,
    );
    widget.onWorkspaceChanged(updated);

    // Spawn satisfying floating number at click position
    _spawnFloater('+$clickValue KB', details.localPosition);
    
    _addLog('[OPTIMIZE] Node #$index synced. +$clickValue KB.');

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
      _addLog('[SHOP] AI Core purchased. Auto rate is now +${updated.gameCores} KB/s.');
      
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
      _addLog('[SHOP] Compiler upgraded. Click multiplier is now ×${updated.gameMultiplier}.');

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
    _addLog('[PRESTIGE] Node network recycled. Multiplier boosted by +5!');
    
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
      color: const Color(0xFF111422),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: doubleBoost ? const Color(0xFF8B5CF6) : const Color(0xFF1E293B),
          width: doubleBoost ? 2.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 12,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF111422),
              doubleBoost ? const Color(0xFF1A1235) : const Color(0xFF0F172A),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Stack(
            children: [
              // Main Layout Column
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title and status badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E38),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.grid_view_rounded, 
                              color: doubleBoost ? const Color(0xFFA78BFA) : const Color(0xFF6366F1), 
                              size: 18
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FOCUS GRID',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'CYBERPRODUCTIVITY MINER',
                                style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (doubleBoost)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C3AED).withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.bolt, color: Colors.white, size: 10),
                              SizedBox(width: 4),
                              Text(
                                'BOOST ×2',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Fancy glowing stats cards
                  Row(
                    children: [
                      Expanded(
                        child: _cyberStatCard(
                          'Focus Bytes',
                          '${widget.workspace.gameScore} KB',
                          const Color(0xFF10B981),
                          Icons.dns,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cyberStatCard(
                          'Auto Rate',
                          '+${widget.workspace.gameCores * (doubleBoost ? 2 : 1)} /s',
                          const Color(0xFF6366F1),
                          Icons.memory,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cyberStatCard(
                          'Multiplier',
                          '×${widget.workspace.gameMultiplier * (doubleBoost ? 2 : 1)}',
                          const Color(0xFFF59E0B),
                          Icons.speed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Auto-miner pulse indicator line
                  if (widget.workspace.gameCores > 0) ...[
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF6366F1),
                                const Color(0xFF10B981).withOpacity(_pulseController.value),
                                const Color(0xFF6366F1),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Live clickable nodes grid
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: 18,
                      itemBuilder: (context, index) {
                        return InkWell(
                          onTapDown: (details) => _clickNode(index, details),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161928),
                              border: Border.all(color: const Color(0xFF2E344F)),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.05),
                                  blurRadius: 4,
                                )
                              ]
                            ),
                            child: Center(
                              child: Icon(
                                Icons.offline_bolt_outlined, 
                                size: 20, 
                                color: doubleBoost ? const Color(0xFF8B5CF6) : const Color(0xFF475569)
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Matrix logs console
                  Container(
                    height: 80,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070913),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _terminalLogs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _terminalLogs[index],
                          style: TextStyle(
                            fontSize: 9, 
                            fontFamily: 'Courier', 
                            color: _terminalLogs[index].contains('[SYSTEM]')
                                ? const Color(0xFF38BDF8)
                                : _terminalLogs[index].contains('[AUTO]')
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF34D399)
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Premium Shop Upgrades
                  Row(
                    children: [
                      Expanded(
                        child: _upgradeButton(
                          'Buy AI Core',
                          '+1 KB/s auto-miner',
                          coreCost,
                          widget.workspace.gameScore >= coreCost ? _buyCore : null,
                          const Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _upgradeButton(
                          'Compiler Boost',
                          '+1 click strength',
                          multCost,
                          widget.workspace.gameScore >= multCost ? _buyMultiplier : null,
                          const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),

                  // Prestige Action
                  if (prestigeUnlocked) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _prestigeReset,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFDB2777), Color(0xFF9D174D)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFDB2777).withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.stars, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'CYBER PRESTIGE RESET (+5 click mult)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Float numbers overlay stack
              ..._floaters.map((f) {
                return Positioned(
                  left: f.position.dx,
                  top: f.position.dy + f.offsetY,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: f.opacity.clamp(0.0, 1.0),
                      child: Text(
                        f.text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF34D399),
                          shadows: [
                            Shadow(
                              blurRadius: 4.0,
                              color: Colors.black,
                              offset: Offset(1.0, 1.0),
                            ),
                            Shadow(
                              blurRadius: 8.0,
                              color: Color(0xFF10B981),
                              offset: Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cyberStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161928),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E344F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Icon(icon, size: 12, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.w900, 
              color: color, 
              fontFamily: 'Courier',
              shadows: [
                Shadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                )
              ]
            ),
          ),
        ],
      ),
    );
  }

  Widget _upgradeButton(String title, String desc, int cost, VoidCallback? onTap, Color color) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isEnabled ? const Color(0xFF1A1F36) : const Color(0xFF121420),
          border: Border.all(
            color: isEnabled ? color.withOpacity(0.5) : const Color(0xFF232535),
            width: isEnabled ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.w900, 
                color: isEnabled ? Colors.white : Colors.grey
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: const TextStyle(fontSize: 8, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: isEnabled ? color.withOpacity(0.2) : const Color(0xFF232535),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$cost KB',
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: FontWeight.w900, 
                  color: isEnabled ? color : Colors.grey
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
