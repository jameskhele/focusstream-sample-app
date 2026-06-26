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
  final List<String> _terminalLogs = [
    '[SYSTEM] Focus Grid Core initialized...',
    '[SYSTEM] Start hiring Developers to automate Byte production!'
  ];
  
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

  int get _autoMiningRate {
    final doubleBoost = _isFeatureEnabled('game-double-multiplier');
    final multiplier = doubleBoost ? 2 : 1;
    final prestigeBonus = 1 + (widget.workspace.tycoonPrestige * 0.5);

    // Calculate rates per tier
    final juniorRate = widget.workspace.gameCores * 1;
    final seniorRate = widget.workspace.tycoonSeniors * 8;
    final aiPilotRate = widget.workspace.tycoonAiPilots * 50;
    final serverRate = widget.workspace.tycoonServers * 300;

    return ((juniorRate + seniorRate + aiPilotRate + serverRate) * multiplier * prestigeBonus).floor();
  }

  void _startAutoMining() {
    _autoMineTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final rate = _autoMiningRate;
      if (rate > 0) {
        final updated = widget.workspace.copyWith(
          gameScore: widget.workspace.gameScore + rate,
        );
        widget.onWorkspaceChanged(updated);

        // Spawn floaters randomly
        final rand = Random();
        _spawnFloater(
          '+$rate KB',
          Offset(80.0 + rand.nextInt(150), 180.0 + rand.nextInt(60)),
        );

        if (rand.nextDouble() > 0.8) {
          _addLog('[AUTO] Server clusters synced. +$rate KB.');
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

  void _spawnFloater(String text, Offset localPos) {
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
    final clickValue = widget.workspace.gameMultiplier * (doubleBoost ? 2 : 1) * (1 + widget.workspace.tycoonPrestige);
    
    final updated = widget.workspace.copyWith(
      gameScore: widget.workspace.gameScore + clickValue,
    );
    widget.onWorkspaceChanged(updated);

    _spawnFloater('+$clickValue KB', details.localPosition);
    _addLog('[HACK] Core Node #$index optimized. +$clickValue KB.');

    _trackEvent('tycoon.click', {
      'node_index': index,
      'value': clickValue,
      'new_score': updated.gameScore,
    });
  }

  // Hiring operations
  void _hireJunior() {
    final cost = 100 + (widget.workspace.gameCores * 15);
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        gameCores: widget.workspace.gameCores + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addLog('[HIRE] Hired Junior Dev. Auto yield increased.');
      _trackEvent('tycoon.hired.developer', {'tier': 'junior', 'cost': cost});
    }
  }

  void _hireSenior() {
    final cost = 800 + (widget.workspace.tycoonSeniors * 120);
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        tycoonSeniors: widget.workspace.tycoonSeniors + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addLog('[HIRE] Hired Senior Dev. Output optimized.');
      _trackEvent('tycoon.hired.developer', {'tier': 'senior', 'cost': cost});
    }
  }

  void _hireAiPilot() {
    final cost = 5000 + (widget.workspace.tycoonAiPilots * 800);
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        tycoonAiPilots: widget.workspace.tycoonAiPilots + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addLog('[UPGRADE] AI Co-Pilot integrated into repo.');
      _trackEvent('tycoon.hired.developer', {'tier': 'ai_pilot', 'cost': cost});
    }
  }

  void _hireServer() {
    final cost = 30000 + (widget.workspace.tycoonServers * 5000);
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        tycoonServers: widget.workspace.tycoonServers + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addLog('[SYSTEM] Kubernetes Cluster spawned.');
      _trackEvent('tycoon.hired.developer', {'tier': 'server', 'cost': cost});
    }
  }

  void _buyClickUpgrade() {
    final cost = 200 * widget.workspace.gameMultiplier;
    if (widget.workspace.gameScore >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: widget.workspace.gameScore - cost,
        gameMultiplier: widget.workspace.gameMultiplier + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addLog('[SHOP] Click strength upgraded.');
      _trackEvent('tycoon.research.completed', {'upgrade': 'click_strength', 'cost': cost});
    }
  }

  void _raiseSeriesA() {
    final prestigeLevel = widget.workspace.tycoonPrestige + 1;
    final updated = widget.workspace.copyWith(
      gameScore: 0,
      gameCores: 0,
      tycoonSeniors: 0,
      tycoonAiPilots: 0,
      tycoonServers: 0,
      tycoonPrestige: prestigeLevel,
      gameMultiplier: 1 + (prestigeLevel * 2),
    );
    widget.onWorkspaceChanged(updated);
    _addLog('[SERIES-A] Raised Funding Round! Prestige Level $prestigeLevel.');
    _trackEvent('tycoon.series_a.raised', {'prestige': prestigeLevel});
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
    final quantumServersUnlocked = _isFeatureEnabled('quantum-servers');

    // Costs
    final juniorCost = 100 + (widget.workspace.gameCores * 15);
    final seniorCost = 800 + (widget.workspace.tycoonSeniors * 120);
    final aiCost = 5000 + (widget.workspace.tycoonAiPilots * 800);
    final serverCost = 30000 + (widget.workspace.tycoonServers * 5000);
    final multCost = 200 * widget.workspace.gameMultiplier;

    final prestigeAvailable = widget.workspace.gameScore >= 50000;

    return Card(
      color: const Color(0xFF0F111E),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: doubleBoost ? const Color(0xFFEC4899) : const Color(0xFF312E81),
          width: doubleBoost ? 2.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1122), Color(0xFF070913)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Stack(
            children: [
              // Main Tycoon Layout
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.rocket_launch, color: Color(0xFFEC4899), size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SAAS STARTUP TYCOON',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                'BUILD AUTOMATION & PRESTIGE FOR SERIOUS YIELDS',
                                style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (doubleBoost)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFF59E0B)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('GLOBAL BOOST ×2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Stat Cards Grid
                  Row(
                    children: [
                      Expanded(
                        child: _tycoonStatCard(
                          'SaaS Revenue',
                          '${widget.workspace.gameScore} KB',
                          const Color(0xFF10B981),
                          Icons.attach_money,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _tycoonStatCard(
                          'Auto Yield',
                          '+$_autoMiningRate KB/s',
                          const Color(0xFF6366F1),
                          Icons.loop,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _tycoonStatCard(
                          'Funding Multiplier',
                          '×${1 + widget.workspace.tycoonPrestige}',
                          const Color(0xFFEC4899),
                          Icons.stars,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Central Sever Core (Hack Node)
                  const Text('Optimize Central Server Cluster:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
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
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        return InkWell(
                          onTapDown: (details) => _clickNode(index, details),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1C2E),
                              border: Border.all(color: const Color(0xFF312E81)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Icon(Icons.flash_on, color: Color(0xFFEC4899), size: 16),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Cyber Logging Console
                  Container(
                    height: 64,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _terminalLogs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _terminalLogs[index],
                          style: const TextStyle(fontSize: 9, fontFamily: 'Courier', color: Color(0xFFEC4899)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Developer Upgrades Shop (Hire Devs)
                  const Text('Hire Developers to Automate:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _hireDevCard(
                          'Junior Dev',
                          '${widget.workspace.gameCores} hired',
                          '+1 KB/s',
                          juniorCost,
                          widget.workspace.gameScore >= juniorCost ? _hireJunior : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _hireDevCard(
                          'Senior Dev',
                          '${widget.workspace.tycoonSeniors} hired',
                          '+8 KB/s',
                          seniorCost,
                          widget.workspace.gameScore >= seniorCost ? _hireSenior : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _hireDevCard(
                          'AI Co-Pilot',
                          '${widget.workspace.tycoonAiPilots} active',
                          '+50 KB/s',
                          aiCost,
                          widget.workspace.gameScore >= aiCost ? _hireAiPilot : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _hireDevCard(
                          quantumServersUnlocked ? 'Quantum Cluster' : 'Cloud Server',
                          '${widget.workspace.tycoonServers} built',
                          quantumServersUnlocked ? '+1200 KB/s' : '+300 KB/s',
                          serverCost,
                          widget.workspace.gameScore >= serverCost ? _hireServer : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Upgrades Shop
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.workspace.gameScore >= multCost ? _buyClickUpgrade : null,
                          icon: const Icon(Icons.touch_app, size: 14),
                          label: Text('Click Boost ($multCost KB)', style: const TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF59E0B),
                            side: BorderSide(color: widget.workspace.gameScore >= multCost ? const Color(0xFFF59E0B) : const Color(0xFF1F2937)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (prestigeUnlocked || prestigeAvailable) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: prestigeAvailable ? _raiseSeriesA : null,
                            icon: const Icon(Icons.currency_exchange, size: 14),
                            label: const Text('Raise Series-A Funding', style: TextStyle(fontSize: 11)),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFEC4899),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              // Pop float numbers overlays
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEC4899),
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black),
                            Shadow(blurRadius: 8, color: Color(0xFFF43F5E)),
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

  Widget _tycoonStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF17192C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E344F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
              Icon(icon, size: 12, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }

  Widget _hireDevCard(String name, String status, String rate, int cost, VoidCallback? onTap) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isEnabled ? const Color(0xFF181B34) : const Color(0xFF10121C),
          border: Border.all(
            color: isEnabled ? const Color.fromRGBO(236, 72, 153, 0.5) : const Color(0xFF1E2937),
            width: isEnabled ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEnabled ? Colors.white : Colors.grey)),
                Text(rate, style: const TextStyle(fontSize: 8, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(status, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isEnabled ? const Color.fromRGBO(236, 72, 153, 0.15) : const Color(0xFF1E2937),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$cost KB',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isEnabled ? const Color(0xFFEC4899) : Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
