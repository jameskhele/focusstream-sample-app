import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _MinigameWidgetState extends State<MinigameWidget> with TickerProviderStateMixin {
  Timer? _gameLoopTimer;
  Timer? _animTimer;
  Timer? _patrolTimer;
  late AnimationController _glitchController;
  late AnimationController _wantedPulseController;
  final List<FloatingTextEffect> _floaters = [];
  final List<String> _policeRadioLogs = [
    '[DISPATCH] Safehouse link detected. All squads monitor matrix traffic.',
    '[SYSTEM] Operational matrix initialized.'
  ];

  static const _projectId = 'focusstream';
  static const _environmentId = 'development';

  // Game/Grid States
  bool _isPlaying = false;
  String _activeHeistName = '';
  int _activeHeistPayout = 0;
  int _activeHeistHeatRisk = 0;

  int _gridSize = 6;
  List<int> _playerPos = [0, 5];
  List<int> _vaultPos = [5, 0];
  List<List<int>> _firewalls = []; // [[x, y, dx, dy, isChaser]]
  List<List<int>> _credits = []; // [[x, y]]
  List<List<int>> _decoysOnGrid = []; // [[x, y]]

  int _currentRunCredits = 0;
  bool _flashRed = false;
  final FocusNode _keyboardFocusNode = FocusNode();

  // SDK/Workspace Mappings
  DartStreamClient get _client => widget.session.client!;
  DartStreamSession get _sdkSession => widget.session.sdkSession!;

  int get _cash => widget.workspace.gameScore;
  int get _heat => widget.workspace.gameCores;
  int get _rep => widget.workspace.tycoonPrestige;
  int get _jammers => widget.workspace.tycoonSeniors;
  int get _decoys => widget.workspace.tycoonAiPilots;
  int get _heistsCompleted => widget.workspace.tycoonServers;
  int get _clickMult => widget.workspace.gameMultiplier;

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
    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    _wantedPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _startGameLoop();
    _startAnimationLoop();
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    _animTimer?.cancel();
    _patrolTimer?.cancel();
    _glitchController.dispose();
    _wantedPulseController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _startGameLoop() {
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      // Heat dissipation based on Jammers owned
      if (_heat > 0 && Random().nextDouble() > 0.6) {
        final cooldownChance = 0.15 * (_jammers + 1);
        if (Random().nextDouble() < cooldownChance) {
          final newHeat = max(0, _heat - 1);
          final updated = widget.workspace.copyWith(gameCores: newHeat);
          widget.onWorkspaceChanged(updated);
          _addRadioLog('[VPN] Jammer shielded your IP. Heat level cooled down.');
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

  void _addRadioLog(String log) {
    setState(() {
      _policeRadioLogs.insert(0, log);
      if (_policeRadioLogs.length > 5) {
        _policeRadioLogs.removeLast();
      }
    });
  }

  // Initiate Matrix Hacking Session
  void _startHeist(String name, int payout, int heatRisk) {
    if (_heat >= 5) {
      _addRadioLog('[WARNING] High Wanted level! Wipe heat trace first.');
      return;
    }

    _keyboardFocusNode.requestFocus();

    setState(() {
      _isPlaying = true;
      _activeHeistName = name;
      _activeHeistPayout = payout;
      _activeHeistHeatRisk = heatRisk;
      _currentRunCredits = 0;

      // Grid sizing based on heist difficulty
      if (name == 'ATM Hack') {
        _gridSize = 5;
      } else if (name == 'Armored Van') {
        _gridSize = 6;
      } else if (name == 'Giga-Bank Heist') {
        _gridSize = 7;
      } else {
        _gridSize = 8; // Military Vault
      }

      _playerPos = [0, _gridSize - 1];
      _vaultPos = [_gridSize - 1, 0];

      // Generate credits and decoys
      _credits.clear();
      _decoysOnGrid.clear();
      _firewalls.clear();

      final rand = Random();
      final targetCredits = name == 'ATM Hack' ? 2 : name == 'Armored Van' ? 3 : name == 'Giga-Bank Heist' ? 4 : 5;

      while (_credits.length < targetCredits) {
        int cx = rand.nextInt(_gridSize);
        int cy = rand.nextInt(_gridSize);
        if ((cx == _playerPos[0] && cy == _playerPos[1]) || (cx == _vaultPos[0] && cy == _vaultPos[1])) continue;
        if (!_credits.any((c) => c[0] == cx && c[1] == cy)) {
          _credits.add([cx, cy]);
        }
      }

      // Add decoy key chance
      if (rand.nextDouble() > 0.4) {
        int dx = rand.nextInt(_gridSize);
        int dy = rand.nextInt(_gridSize);
        if ((dx != _playerPos[0] || dy != _playerPos[1]) && (dx != _vaultPos[0] || dy != _vaultPos[1])) {
          _decoysOnGrid.add([dx, dy]);
        }
      }

      // Spawning firewalls
      // Format: [x, y, dx, dy, isChaser]
      int firewallCount = name == 'ATM Hack' ? 1 : name == 'Armored Van' ? 2 : name == 'Giga-Bank Heist' ? 3 : 4;
      for (int i = 0; i < firewallCount; i++) {
        int fx = rand.nextInt(_gridSize - 2) + 1;
        int fy = rand.nextInt(_gridSize - 2) + 1;
        bool isChaser = false;
        
        // Homing chase AI configurations
        if (name == 'Giga-Bank Heist' && i == 0) isChaser = true;
        if (name == 'Military Vault' && i < 2) isChaser = true;

        _firewalls.add([fx, fy, rand.nextBool() ? 1 : -1, rand.nextBool() ? 1 : -1, isChaser ? 1 : 0]);
      }
    });

    _addRadioLog('[CONNECT] Matrix connected. Bypassing $_activeHeistName firewall...');
    _trackEvent('heist.started', {'type': name, 'grid_size': _gridSize});

    // Start firewall movement loop
    _patrolTimer?.cancel();
    final easyHack = _isFeatureEnabled('easy-hack-mode');
    final intervalMs = easyHack ? 1100 : 700;

    _patrolTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      _moveFirewalls();
    });
  }

  void _moveFirewalls() {
    setState(() {
      for (var f in _firewalls) {
        final isChaser = f[4] == 1;
        if (isChaser) {
          // Chase logic - step towards player
          int px = _playerPos[0];
          int py = _playerPos[1];
          int fx = f[0];
          int fy = f[1];

          if (fx < px) f[0]++;
          else if (fx > px) f[0]--;
          else if (fy < py) f[1]++;
          else if (fy > py) f[1]--;
        } else {
          // Standard patrol logic
          int nx = f[0] + f[2];
          int ny = f[1] + f[3];

          if (nx < 0 || nx >= _gridSize) {
            f[2] = -f[2];
            nx = f[0] + f[2];
          }
          if (ny < 0 || ny >= _gridSize) {
            f[3] = -f[3];
            ny = f[1] + f[3];
          }

          f[0] = nx.clamp(0, _gridSize - 1);
          f[1] = ny.clamp(0, _gridSize - 1);
        }
      }
      _checkCollisions();
    });
  }

  void _movePlayer(int dx, int dy) {
    if (!_isPlaying) return;

    setState(() {
      int nx = (_playerPos[0] + dx).clamp(0, _gridSize - 1);
      int ny = (_playerPos[1] + dy).clamp(0, _gridSize - 1);
      _playerPos = [nx, ny];

      // Check credit nodes collection
      for (int i = _credits.length - 1; i >= 0; i--) {
        if (_credits[i][0] == nx && _credits[i][1] == ny) {
          _credits.removeAt(i);
          final doubleLoot = _isFeatureEnabled('double-loot');
          final collected = (doubleLoot ? 200 : 100) * (_clickMult);
          _currentRunCredits += collected;
          _spawnFloater('+$collected KB', const Offset(120, 100));
        }
      }

      // Check decoy pickup
      for (int i = _decoysOnGrid.length - 1; i >= 0; i--) {
        if (_decoysOnGrid[i][0] == nx && _decoysOnGrid[i][1] == ny) {
          _decoysOnGrid.removeAt(i);
          // Directly add virtual decoy to player inventory
          final updated = widget.workspace.copyWith(tycoonAiPilots: _decoys + 1);
          widget.onWorkspaceChanged(updated);
          _addRadioLog('[SOFTWARE] Picked up trace decoy key.');
          _spawnFloater('+1 Decoy', const Offset(120, 100));
        }
      }

      _checkCollisions();

      // Check win condition
      if (_playerPos[0] == _vaultPos[0] && _playerPos[1] == _vaultPos[1]) {
        _completeMissionSuccess();
      }
    });
  }

  void _checkCollisions() {
    for (var f in _firewalls) {
      if (f[0] == _playerPos[0] && f[1] == _playerPos[1]) {
        _triggerFirewallDetection();
        break;
      }
    }
  }

  void _triggerFirewallDetection() {
    _patrolTimer?.cancel();
    setState(() {
      _flashRed = true;
    });

    Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _flashRed = false);
    });

    if (_decoys > 0) {
      // Use Decoy to save run
      final updated = widget.workspace.copyWith(tycoonAiPilots: _decoys - 1);
      widget.onWorkspaceChanged(updated);
      _addRadioLog('[ALERT] Firewall collision! Decoy VPN deployed. Shield active.');
      
      // Relocate player to start, but keep loot
      setState(() {
        _playerPos = [0, _gridSize - 1];
      });

      // Resume patrol timer
      final easyHack = _isFeatureEnabled('easy-hack-mode');
      _patrolTimer = Timer.periodic(Duration(milliseconds: easyHack ? 1100 : 700), (timer) {
        if (!_isPlaying) {
          timer.cancel();
          return;
        }
        _moveFirewalls();
      });
    } else {
      // Busted run
      final finalHeat = min(5, _heat + 1);
      final updated = widget.workspace.copyWith(gameCores: finalHeat);
      widget.onWorkspaceChanged(updated);

      _addRadioLog('[ALARM] Trace detected! Cops tracing location. Heat level increased.');
      _trackEvent('heist.busted', {'heist_target': _activeHeistName, 'final_heat': finalHeat});

      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _completeMissionSuccess() {
    _patrolTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });

    // Payout calc
    final basePayout = _activeHeistPayout * (1 + _rep);
    final totalReward = basePayout + _currentRunCredits;
    final finalHeat = min(5, _heat + _activeHeistHeatRisk);

    final updated = widget.workspace.copyWith(
      gameScore: _cash + totalReward,
      gameCores: finalHeat,
      tycoonServers: _heistsCompleted + 1,
    );
    widget.onWorkspaceChanged(updated);

    _addRadioLog('[SUCCESS] Completed $_activeHeistName. Earned \$$totalReward cash.');
    _spawnFloater('+$totalReward KB', const Offset(150.0, 80.0));
    _trackEvent('heist.completed', {'type': _activeHeistName, 'earnings': totalReward});
  }

  // Upgrades and Prestige Reset commands
  void _buyJammer() {
    final cost = 400 * (_jammers + 1);
    if (_cash >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: _cash - cost,
        tycoonSeniors: _jammers + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addRadioLog('[UPGRADE] Installed Server Signal Jammer.');
      _trackEvent('heist.upgrade.bought', {'item': 'jammer', 'cost': cost});
    }
  }

  void _buyDecoy() {
    final cost = 1200 * (_decoys + 1);
    if (_cash >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: _cash - cost,
        tycoonAiPilots: _decoys + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addRadioLog('[UPGRADE] Downloaded VPN decrypter key.');
      _trackEvent('heist.upgrade.bought', {'item': 'decoy', 'cost': cost});
    }
  }

  void _buyCpuRig() {
    final cost = 300 * _clickMult;
    if (_cash >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: _cash - cost,
        gameMultiplier: _clickMult + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addRadioLog('[UPGRADE] Matrix node Overclocker updated.');
      _trackEvent('heist.upgrade.bought', {'item': 'overclocker', 'cost': cost});
    }
  }

  void _clearHeat() {
    final cost = 1500 * _heat;
    if (_cash >= cost && _heat > 0) {
      final updated = widget.workspace.copyWith(
        gameScore: _cash - cost,
        gameCores: 0,
      );
      widget.onWorkspaceChanged(updated);
      _addRadioLog('[DATABASE] Security nodes wiped. Heat cleared.');
      _trackEvent('heist.heat.wiped', {'cost': cost});
    }
  }

  void _escapePrestige() {
    final prestigeLevel = _rep + 1;
    final updated = widget.workspace.copyWith(
      gameScore: 100,
      gameCores: 0,
      tycoonSeniors: 0,
      tycoonAiPilots: 0,
      tycoonServers: 0,
      tycoonPrestige: prestigeLevel,
      gameMultiplier: 1,
    );
    widget.onWorkspaceChanged(updated);
    _addRadioLog('[SYSTEM] Safehouse relocated. Global multiplier increased.');
    _trackEvent('heist.prestige', {'prestige': prestigeLevel});
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
    final militaryResponse = _isFeatureEnabled('game-military-response');

    final jammerCost = 400 * (_jammers + 1);
    final decoyCost = 1200 * (_decoys + 1);
    final rigCost = 300 * _clickMult;
    final bribeCost = 1500 * _heat;

    return Focus(
      focusNode: _keyboardFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.keyW) {
            _movePlayer(0, -1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.keyS) {
            _movePlayer(0, 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.keyA) {
            _movePlayer(-1, 0);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.keyD) {
            _movePlayer(1, 0);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        color: const Color(0xFF070913),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: _heat >= 4 ? const Color(0xFFF43F5E) : const Color(0xFF00F5FF),
            width: _heat >= 4 ? 2.5 : 1.5,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C0E20), Color(0xFF05060A)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Stack(
              children: [
                // Layout Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header HUD
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.grid_3x3,
                              color: _heat >= 4 ? const Color(0xFFF43F5E) : const Color(0xFF00F5FF),
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GRAND THEFT CYBER: MATRIX BYPASS',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Text(
                                  'STEAL CORES. INFILTRATE SECURITY PORTS.',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Cops Wanted Stars
                        Row(
                          children: List.generate(5, (index) {
                            final isActive = index < _heat;
                            final pulse = _heat >= 4 && _wantedPulseController.value > 0.5;
                            return Icon(
                              Icons.star,
                              color: isActive
                                  ? (pulse ? const Color(0xFFF43F5E) : const Color(0xFFEAB308))
                                  : const Color(0xFF1E293B),
                              size: 20,
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Game Stats row
                    Row(
                      children: [
                        Expanded(child: _statHudBlock('Safehouse Assets', '\$$_cash', const Color(0xFF10B981))),
                        const SizedBox(width: 8),
                        Expanded(child: _statHudBlock('Rep Multiplier', 'x${(_rep + 1)}', const Color(0xFF00F5FF))),
                        const SizedBox(width: 8),
                        Expanded(child: _statHudBlock('Heist Database', '$_heistsCompleted completed', const Color(0xFFA855F7))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Playfield / Grid Canvas Panel
                    Container(
                      height: 280,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _flashRed ? const Color(0xFFF43F5E) : const Color(0xFF1E293B),
                          width: _flashRed ? 3.0 : 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            // Matrix grid background styling
                            Opacity(
                              opacity: 0.15,
                              child: GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 16,
                                ),
                                itemCount: 256,
                                itemBuilder: (context, index) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFF00F5FF).withOpacity(0.1)),
                                    ),
                                  );
                                },
                              ),
                            ),
                            // Scanning horizontal laser line
                            AnimatedBuilder(
                              animation: _glitchController,
                              builder: (context, child) {
                                return Positioned(
                                  left: 0,
                                  right: 0,
                                  top: _glitchController.value * 280,
                                  child: Container(
                                    height: 1.5,
                                    color: const Color(0xFF00F5FF).withOpacity(0.5),
                                  ),
                                );
                              },
                            ),

                            // Dynamic Game View
                            if (!_isPlaying)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0C0E20).withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.security, color: Color(0xFF00F5FF), size: 42),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'FIREWALL MATRIX BLOCKED',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontSize: 13,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Select an active contract below to hack network ports.',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: () => _startHeist('ATM Hack', 150, 0),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00F5FF),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text('QUICK HACK (ATM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _gridSize,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6,
                                  ),
                                  itemCount: _gridSize * _gridSize,
                                  itemBuilder: (context, index) {
                                    final x = index % _gridSize;
                                    final y = index ~/ _gridSize;

                                    final isPlayer = _playerPos[0] == x && _playerPos[1] == y;
                                    final isVault = _vaultPos[0] == x && _vaultPos[1] == y;
                                    
                                    final isFirewall = _firewalls.any((f) => f[0] == x && f[1] == y);
                                    final isChasingFirewall = _firewalls.any((f) => f[0] == x && f[1] == y && f[4] == 1);
                                    
                                    final isCredit = _credits.any((c) => c[0] == x && c[1] == y);
                                    final isDecoy = _decoysOnGrid.any((d) => d[0] == x && d[1] == y);

                                    // Render cell styles
                                    Color cellBorder = const Color(0xFF1E293B);
                                    Color cellBg = const Color(0xFF05060A);
                                    Widget cellChild = const SizedBox();

                                    if (isPlayer) {
                                      cellBorder = const Color(0xFF00F5FF);
                                      cellBg = const Color(0xFF0A2233);
                                      cellChild = const Icon(Icons.person_pin, color: Color(0xFF00F5FF), size: 18);
                                    } else if (isVault) {
                                      cellBorder = const Color(0xFFEAB308);
                                      cellBg = const Color(0xFF2B2207);
                                      cellChild = const Icon(Icons.lock_open, color: Color(0xFFEAB308), size: 18);
                                    } else if (isFirewall) {
                                      cellBorder = const Color(0xFFF43F5E);
                                      cellBg = const Color(0xFF330A12);
                                      cellChild = Icon(
                                        isChasingFirewall ? Icons.radar : Icons.dangerous,
                                        color: const Color(0xFFF43F5E),
                                        size: 18,
                                      );
                                    } else if (isCredit) {
                                      cellBorder = const Color(0xFF10B981);
                                      cellBg = const Color(0xFF092B1C);
                                      cellChild = const Icon(Icons.monetization_on, color: Color(0xFF10B981), size: 18);
                                    } else if (isDecoy) {
                                      cellBorder = const Color(0xFFEC4899);
                                      cellBg = const Color(0xFF2E0922);
                                      cellChild = const Icon(Icons.vpn_key, color: Color(0xFFEC4899), size: 16);
                                    }

                                    return InkWell(
                                      onTap: () {
                                        // Allow tap-to-move to adjacent cells
                                        int dx = (x - _playerPos[0]).abs();
                                        int dy = (y - _playerPos[1]).abs();
                                        if ((dx == 1 && dy == 0) || (dx == 0 && dy == 1)) {
                                          _movePlayer(x - _playerPos[0], y - _playerPos[1]);
                                        }
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: cellBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: cellBorder, width: isPlayer || isVault || isFirewall ? 2.0 : 1.0),
                                          boxShadow: isPlayer
                                              ? [const BoxShadow(color: Color(0xFF00F5FF), blurRadius: 4)]
                                              : isVault
                                                  ? [const BoxShadow(color: Color(0xFFEAB308), blurRadius: 4)]
                                                  : isFirewall
                                                      ? [const BoxShadow(color: Color(0xFFF43F5E), blurRadius: 4)]
                                                      : null,
                                        ),
                                        child: Center(child: cellChild),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Directional Controller (for mobile or mouse clicks)
                    if (_isPlaying) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Control Node:',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          _directionButton(Icons.arrow_back, () => _movePlayer(-1, 0)),
                          const SizedBox(width: 6),
                          _directionButton(Icons.arrow_upward, () => _movePlayer(0, -1)),
                          const SizedBox(width: 6),
                          _directionButton(Icons.arrow_downward, () => _movePlayer(0, 1)),
                          const SizedBox(width: 6),
                          _directionButton(Icons.arrow_forward, () => _movePlayer(1, 0)),
                          const SizedBox(width: 16),
                          Text(
                            'Loot collected: \$$_currentRunCredits',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Terminal Radio Log screen
                    Container(
                      height: 72,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF04060C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _policeRadioLogs.length,
                        itemBuilder: (context, index) {
                          final text = _policeRadioLogs[index];
                          Color logColor = const Color(0xFF38BDF8);
                          if (text.contains('[ALERT]') || text.contains('[WARNING]') || text.contains('[ALARM]')) {
                            logColor = const Color(0xFFF43F5E);
                          } else if (text.contains('[SUCCESS]')) {
                            logColor = const Color(0xFF10B981);
                          } else if (text.contains('[UPGRADE]')) {
                            logColor = const Color(0xFFA855F7);
                          }

                          return Text(
                            text,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontFamily: 'CourierNew',
                              fontWeight: FontWeight.w600,
                              color: logColor,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mission Contract Targets
                    const Text(
                      'AVAILABLE TARGET CONTRACTS:',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _missionContractCard('ATM Port', '\$150', 'Risk: None', () => _startHeist('ATM Port', 150, 0)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _missionContractCard('Armored Van', '\$800', 'Risk: 1 Star', () => _startHeist('Armored Van', 800, 1)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _missionContractCard('Giga-Bank Heist', '\$4000', 'Risk: 2 Stars', () => _startHeist('Giga-Bank Heist', 4000, 2)),
                        ),
                        if (militaryResponse) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _missionContractCard('Military Vault', '\$15000', 'Risk: 3 Stars', () => _startHeist('Military Vault', 15000, 3)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Shop and upgrades
                    const Text(
                      'NETRUNNER BLACK MARKET:',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _shopItemCard('Signal Jammer', '\$$jammerCost', 'Cools Heat', _cash >= jammerCost ? _buyJammer : null, Icons.cell_tower),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _shopItemCard('Decoy Key', '\$$decoyCost', 'Saves Hack', _cash >= decoyCost ? _buyDecoy : null, Icons.vpn_lock),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _shopItemCard('Node Rig', '\$$rigCost', 'x$_clickMult speed', _cash >= rigCost ? _buyCpuRig : null, Icons.hardware),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Action buttons (Wipe Heat, Reset Safehouse)
                    Row(
                      children: [
                        if (_heat > 0)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _cash >= bribeCost ? _clearHeat : null,
                              icon: const Icon(Icons.security, size: 14),
                              label: Text('Wipe Security Trace (\$$bribeCost)', style: const TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF43F5E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        if (_cash >= 50000) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _escapePrestige,
                              icon: const Icon(Icons.rocket_launch, size: 14),
                              label: const Text('Relocate Safehouse (Prestige)', style: TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFA855F7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                // Floating numbers popup animations
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
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black),
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
      ),
    );
  }

  Widget _statHudBlock(String title, String val, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1122),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            val,
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

  Widget _directionButton(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        color: const Color(0xFF00F5FF),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF0F1122),
          side: const BorderSide(color: Color(0xFF1E293B)),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _missionContractCard(String title, String payout, String risk, VoidCallback onTap) {
    return InkWell(
      onTap: _isPlaying ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _isPlaying ? const Color(0xFF0A0C14) : const Color(0xFF0F1122),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _isPlaying ? const Color(0xFF1E293B) : const Color(0xFF00F5FF).withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(payout, style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(risk, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 8)),
          ],
        ),
      ),
    );
  }

  Widget _shopItemCard(String title, String cost, String effect, VoidCallback? onTap, IconData icon) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isEnabled ? const Color(0xFF13172E) : const Color(0xFF0A0C14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? const Color(0xFFA855F7).withOpacity(0.6) : const Color(0xFF1E293B),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: isEnabled ? const Color(0xFFA855F7) : const Color(0xFF94A3B8)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: isEnabled ? Colors.white : const Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(cost, style: const TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
            Text(effect, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 7.5)),
          ],
        ),
      ),
    );
  }
}
