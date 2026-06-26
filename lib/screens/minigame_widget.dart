import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:dartstream_client/dartstream_client.dart';
import '../models/workspace_data.dart';
import '../state/session.dart';

// Game Entity Definitions
class GameParticle {
  double x, y;
  double vx, vy;
  double life; // 1.0 down to 0.0
  final Color color;

  GameParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
  });

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    life -= dt * 2.0; // disappear quickly
  }
}

class LaserGate {
  double x;
  final double gapTop;
  final double gapHeight;
  final double width;
  bool scored = false;

  LaserGate({
    required this.x,
    required this.gapTop,
    required this.gapHeight,
    required this.width,
  });
}

class CyberShard {
  double x;
  double y;
  bool collected = false;
  double angle = 0.0;

  CyberShard({
    required this.x,
    required this.y,
  });
}

class SentryDrone {
  double x;
  double y;
  double speed;
  int direction; // 1 or -1

  SentryDrone({
    required this.x,
    required this.y,
    required this.speed,
    required this.direction,
  });
}

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
  late Ticker _gameTicker;
  Timer? _gameLoopTimer;
  Timer? _animTimer;
  
  late AnimationController _glitchController;
  late AnimationController _wantedPulseController;
  final List<FloatingTextEffect> _floaters = [];
  final List<String> _policeRadioLogs = [
    '[DISPATCH] Safehouse node detected. Keep sentinel scans active.',
    '[SYSTEM] Cyber Ball gravity core online.'
  ];

  static const _projectId = 'focusstream';
  static const _environmentId = 'development';

  // Game Engine & State
  bool _isPlaying = false;
  bool _gameOver = false;
  int _score = 0;
  double _timeElapsed = 0.0;

  // Ball physics
  double _ballY = 150.0;
  double _ballVelocityY = 0.0;
  static const double _ballX = 70.0;
  static const double _ballRadius = 11.0;
  
  double _invincibilityTimer = 0.0; // Shield flash time on decoy hit
  int _runShardsCollected = 0;

  // Entities
  final List<LaserGate> _gates = [];
  final List<CyberShard> _shards = [];
  final List<SentryDrone> _drones = [];
  final List<GameParticle> _particles = [];

  double _spawnTimer = 0.0;
  final FocusNode _keyboardFocusNode = FocusNode();
  final Random _rand = Random();

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

    // Initialize 60fps ticker loop for physics
    _gameTicker = createTicker(_onGameTick);

    _startGameLoop();
    _startAnimationLoop();
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    _animTimer?.cancel();
    _gameTicker.dispose();
    _glitchController.dispose();
    _wantedPulseController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _startGameLoop() {
    _gameLoopTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // Heat dissipation based on Jammers owned
      if (_heat > 0 && _rand.nextDouble() > 0.6) {
        final cooldownChance = 0.15 * (_jammers + 1);
        if (_rand.nextDouble() < cooldownChance) {
          final newHeat = max(0, _heat - 1);
          final updated = widget.workspace.copyWith(gameCores: newHeat);
          widget.onWorkspaceChanged(updated);
          _addRadioLog('[VPN] Heat signature cooled down. Jammers active.');
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

  // Action input triggers jump
  void _triggerJump() {
    if (!_isPlaying) {
      _startGame();
      return;
    }
    if (_gameOver) {
      _startGame();
      return;
    }

    setState(() {
      // Jump speed boosted by click overclock multiplier
      _ballVelocityY = -230.0 - (_clickMult * 5.0);
      
      // Emit neon trail particles
      for (int i = 0; i < 5; i++) {
        _particles.add(
          GameParticle(
            x: _ballX,
            y: _ballY,
            vx: -50.0 - _rand.nextDouble() * 50.0,
            vy: -20.0 + _rand.nextDouble() * 40.0,
            life: 1.0,
            color: const Color(0xFF00F5FF),
          ),
        );
      }
    });
  }

  void _startGame() {
    _keyboardFocusNode.requestFocus();
    setState(() {
      _isPlaying = true;
      _gameOver = false;
      _score = 0;
      _runShardsCollected = 0;
      _ballY = 140.0;
      _ballVelocityY = 0.0;
      _timeElapsed = 0.0;
      _invincibilityTimer = 0.0;

      _gates.clear();
      _shards.clear();
      _drones.clear();
      _particles.clear();
      _spawnTimer = 0.0;
    });

    _addRadioLog('[CONNECT] Security tunnel initialized. Evade incoming lasers.');
    _trackEvent('game.started', {'mult': _clickMult});
    _gameTicker.start();
  }

  // Core physics tick loop running at 60fps
  void _onGameTick(Duration elapsed) {
    if (!_isPlaying || _gameOver) return;

    // Fixed timestep dt (roughly 16ms)
    final dt = 0.0166;
    _timeElapsed += dt;

    setState(() {
      // 1. Gravity Math
      final easyHack = _isFeatureEnabled('easy-hack-mode');
      final gravity = easyHack ? 380.0 : 540.0;
      _ballVelocityY += gravity * dt;
      _ballY += _ballVelocityY * dt;

      // Invincibility check
      if (_invincibilityTimer > 0.0) {
        _invincibilityTimer -= dt;
      }

      // Check boundaries
      if (_ballY < 0) {
        _ballY = 0;
        _ballVelocityY = 0;
      }
      if (_ballY > 280) {
        _triggerCollision();
      }

      // 2. Obstacles spawn & move
      _spawnTimer += dt;
      final spawnInterval = easyHack ? 2.5 : 1.8;
      if (_spawnTimer >= spawnInterval) {
        _spawnTimer = 0.0;
        _spawnEntities();
      }

      // Move gates
      final scrollSpeed = easyHack ? 110.0 : 160.0;
      for (int i = _gates.length - 1; i >= 0; i--) {
        final gate = _gates[i];
        gate.x -= scrollSpeed * dt;

        // Score pass gate
        if (!gate.scored && gate.x + gate.width < _ballX) {
          gate.scored = true;
          _score++;
          _spawnFloater('+1', const Offset(_ballX, 60.0));
          if (_score % 10 == 0) {
            _addRadioLog('[SYSTEM] Firewalls bypassed: $_score');
            _trackEvent('game.checkpoint', {'score': _score});
          }
        }
        if (gate.x < -100) _gates.removeAt(i);
      }

      // Move shards & rotate
      for (int i = _shards.length - 1; i >= 0; i--) {
        final shard = _shards[i];
        shard.x -= scrollSpeed * dt;
        shard.angle += dt * 3.0;

        // Collision check with ball
        final dx = shard.x - _ballX;
        final dy = shard.y - _ballY;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < (_ballRadius + 10.0)) {
          _collectShard(shard);
          _shards.removeAt(i);
          continue;
        }
        if (shard.x < -50) _shards.removeAt(i);
      }

      // Move military drone hazards
      final militaryResponse = _isFeatureEnabled('game-military-response');
      if (militaryResponse) {
        for (int i = _drones.length - 1; i >= 0; i--) {
          final drone = _drones[i];
          drone.x -= (scrollSpeed + drone.speed) * dt;

          // Drone collision check
          final dx = drone.x - _ballX;
          final dy = drone.y - _ballY;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist < (_ballRadius + 9.0)) {
            _triggerCollision();
          }
          if (drone.x < -50) _drones.removeAt(i);
        }
      }

      // Particle physics
      for (int i = _particles.length - 1; i >= 0; i--) {
        final p = _particles[i];
        p.update(dt);
        if (p.life <= 0) _particles.removeAt(i);
      }

      // Collision checks with laser walls
      for (final gate in _gates) {
        // A gate is two rectangles: top and bottom
        final hitTop = _ballX + _ballRadius > gate.x &&
            _ballX - _ballRadius < gate.x + gate.width &&
            _ballY - _ballRadius < gate.gapTop;
        final hitBottom = _ballX + _ballRadius > gate.x &&
            _ballX - _ballRadius < gate.x + gate.width &&
            _ballY + _ballRadius > gate.gapTop + gate.gapHeight;

        if (hitTop || hitBottom) {
          _triggerCollision();
          break;
        }
      }
    });
  }

  void _spawnEntities() {
    final easyHack = _isFeatureEnabled('easy-hack-mode');
    final gapHeight = easyHack ? 100.0 : 80.0;
    
    // Choose gap position between 30 and 170
    final gapTop = 30.0 + _rand.nextDouble() * 110.0;
    
    _gates.add(
      LaserGate(
        x: 360.0,
        gapTop: gapTop,
        gapHeight: gapHeight,
        width: 38.0,
      ),
    );

    // Spawn shard inside the gap
    _shards.add(
      CyberShard(
        x: 360.0 + 19.0, // center of gate
        y: gapTop + (gapHeight / 2.0),
      ),
    );

    // Military response drone spawning
    final militaryResponse = _isFeatureEnabled('game-military-response');
    if (militaryResponse && _rand.nextDouble() > 0.4) {
      _drones.add(
        SentryDrone(
          x: 380.0,
          y: 20.0 + _rand.nextDouble() * 240.0,
          speed: 40.0 + _rand.nextDouble() * 50.0,
          direction: -1,
        ),
      );
    }
  }

  void _collectShard(CyberShard shard) {
    final doubleLoot = _isFeatureEnabled('double-loot');
    final shardReward = (doubleLoot ? 200 : 100) * (_clickMult);
    
    _runShardsCollected++;
    
    final updated = widget.workspace.copyWith(
      gameScore: _cash + shardReward,
    );
    widget.onWorkspaceChanged(updated);

    _spawnFloater('+\$$shardReward', Offset(_ballX, _ballY - 10.0));
    _addRadioLog('[DATABASE] Decrypted code shard: +\$$shardReward cash');

    // Create green explosion particles
    for (int i = 0; i < 8; i++) {
      _particles.add(
        GameParticle(
          x: shard.x,
          y: shard.y,
          vx: -60.0 + _rand.nextDouble() * 120.0,
          vy: -60.0 + _rand.nextDouble() * 120.0,
          life: 1.0,
          color: const Color(0xFF10B981),
        ),
      );
    }
  }

  void _triggerCollision() {
    if (_invincibilityTimer > 0.0) return; // Immune

    if (_decoys > 0) {
      // Consume decoy shield
      final updated = widget.workspace.copyWith(
        tycoonAiPilots: _decoys - 1,
      );
      widget.onWorkspaceChanged(updated);

      _invincibilityTimer = 1.8; // invincibility seconds
      _addRadioLog('[ALERT] Firewall crash! Decoy trace diverted security.');
      _spawnFloater('VPN SHIELDED', Offset(_ballX, _ballY - 20.0));

      // Emit flash particles
      for (int i = 0; i < 15; i++) {
        _particles.add(
          GameParticle(
            x: _ballX,
            y: _ballY,
            vx: -100.0 + _rand.nextDouble() * 200.0,
            vy: -100.0 + _rand.nextDouble() * 200.0,
            life: 1.2,
            color: const Color(0xFFEC4899),
          ),
        );
      }
    } else {
      // Game Over
      _gameTicker.stop();
      setState(() {
        _gameOver = true;
      });

      // Increase heat wanted level
      final finalHeat = min(5, _heat + 1);
      final updated = widget.workspace.copyWith(
        gameCores: finalHeat,
        tycoonServers: _heistsCompleted + 1,
      );
      widget.onWorkspaceChanged(updated);

      _addRadioLog('[ALARM] BUSTED! Gravity hack crashed. Score: $_score. Heat levels critical.');
      _trackEvent('game.over', {'score': _score, 'shards': _runShardsCollected, 'heat_increase': 1});
    }
  }

  // Netrunner Market Operations
  void _buyJammer() {
    final cost = 400 * (_jammers + 1);
    if (_cash >= cost) {
      final updated = widget.workspace.copyWith(
        gameScore: _cash - cost,
        tycoonSeniors: _jammers + 1,
      );
      widget.onWorkspaceChanged(updated);
      _addRadioLog('[UPGRADE] Installed hardware Signal Jammer.');
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
      _addRadioLog('[UPGRADE] Loaded VPN Decoy software shield.');
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
      _addRadioLog('[UPGRADE] Gravity core engine overclocked.');
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
      _addRadioLog('[VPN] Clear server records. Heat trace reset.');
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
    _addRadioLog('[PRESTIGE] Node relocated. Network multiplier upgraded to x$prestigeLevel.');
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
          if (event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.keyW ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _triggerJump();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        color: const Color(0xFF060810),
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
              colors: [Color(0xFF0B0D1E), Color(0xFF040508)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Stack(
              children: [
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
                              Icons.rocket_launch,
                              color: _heat >= 4 ? const Color(0xFFF43F5E) : const Color(0xFF00F5FF),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CYBER BOUNCE: GRAVITY HACKER',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Text(
                                  'TAP TO IMPULSE. BYPASS FIREWALL GATES.',
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
                        // Stars Heat Tracker
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

                    // Stats Dashboard
                    Row(
                      children: [
                        Expanded(child: _statHudBlock('Safehouse Cash', '\$$_cash', const Color(0xFF10B981))),
                        const SizedBox(width: 8),
                        Expanded(child: _statHudBlock('Jump Boost', 'x$_clickMult speed', const Color(0xFF00F5FF))),
                        const SizedBox(width: 8),
                        Expanded(child: _statHudBlock('Decoy VPNs', '$_decoys shield keys', const Color(0xFFEC4899))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Game Canvas (Clickable target)
                    GestureDetector(
                      onTap: _triggerJump,
                      child: Container(
                        height: 280,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _gameOver ? const Color(0xFFF43F5E) : const Color(0xFF1E293B),
                            width: _gameOver ? 2.5 : 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              CustomPaint(
                                painter: CyberGamePainter(
                                  ballY: _ballY,
                                  ballRadius: _ballRadius,
                                  gates: _gates,
                                  shards: _shards,
                                  drones: _drones,
                                  particles: _particles,
                                  invincible: _invincibilityTimer > 0.0,
                                  time: _timeElapsed,
                                  militaryEnabled: militaryResponse,
                                ),
                                child: Container(),
                              ),

                              // HUD / Instructions inside canvas
                              if (!_isPlaying)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0C0E20).withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.touch_app, color: Color(0xFF00F5FF), size: 40),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'GRAVITY SYSTEM OFFLINE',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Tap screen or press Space to jump.',
                                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                        ),
                                        const SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: _startGame,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF00F5FF),
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: const Text('INITIALIZE HACK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              if (_gameOver)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1F0A10).withOpacity(0.95),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFF43F5E)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.report_problem, color: Color(0xFFF43F5E), size: 42),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'CONNECTION INTERRUPTED',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Firewalls Bypassed: $_score',
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: _startGame,
                                          icon: const Icon(Icons.refresh, size: 14),
                                          label: const Text('RETRY HACK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFF43F5E),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Floating scores HUD (Top left)
                              if (_isPlaying && !_gameOver)
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'SCORE: $_score',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontFamily: 'Courier',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Log radio dispatch screen
                    Container(
                      height: 76,
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
                          } else if (text.contains('[DATABASE]') || text.contains('[SUCCESS]')) {
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

                    // Upgrades shop catalog
                    const Text(
                      'BLACK MARKET NETRUNNER SHOP:',
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
                          child: _shopItemCard('VPN Decoy Shield', '\$$decoyCost', 'Saves Crashes', _cash >= decoyCost ? _buyDecoy : null, Icons.vpn_lock),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _shopItemCard('Node Overclock', '\$$rigCost', 'Boost speed', _cash >= rigCost ? _buyCpuRig : null, Icons.speed),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Action buttons (Bribe / Prestige)
                    Row(
                      children: [
                        if (_heat > 0)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _cash >= bribeCost ? _clearHeat : null,
                              icon: const Icon(Icons.gavel, size: 14),
                              label: Text('Bribe Security Core (\$$bribeCost)', style: const TextStyle(fontSize: 11)),
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
                              icon: const Icon(Icons.vpn_key_sharp, size: 14),
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

                // Floating points text
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

// Custom Painter for 60fps neon physics game
class CyberGamePainter extends CustomPainter {
  final double ballY;
  final double ballRadius;
  final List<LaserGate> gates;
  final List<CyberShard> shards;
  final List<SentryDrone> drones;
  final List<GameParticle> particles;
  final bool invincible;
  final double time;
  final bool militaryEnabled;

  CyberGamePainter({
    required this.ballY,
    required this.ballRadius,
    required this.gates,
    required this.shards,
    required this.drones,
    required this.particles,
    required this.invincible,
    required this.time,
    required this.militaryEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Grid Background
    final gridPaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.04)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 24) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += 24) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // Laser lines scrolling indicator
    final laserIndicatorY = (time * 50.0) % size.height;
    canvas.drawLine(
      Offset(0, laserIndicatorY),
      Offset(size.width, laserIndicatorY),
      Paint()..color = const Color(0xFF00F5FF).withOpacity(0.06)..strokeWidth = 1.5,
    );

    // 2. Render Laser Gates
    final gateFillPaint = Paint()..color = const Color(0xFF0A1E3F);
    final gateOutlinePaint = Paint()
      ..color = const Color(0xFF00F5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final dangerLaserPaint = Paint()
      ..color = const Color(0xFFF43F5E)
      ..strokeWidth = 1.5;

    for (final gate in gates) {
      // Top wall
      final topRect = Rect.fromLTWH(gate.x, 0, gate.width, gate.gapTop);
      canvas.drawRect(topRect, gateFillPaint);
      canvas.drawRect(topRect, gateOutlinePaint);

      // Bottom wall
      final bottomRect = Rect.fromLTWH(gate.x, gate.gapTop + gate.gapHeight, gate.width, size.height - (gate.gapTop + gate.gapHeight));
      canvas.drawRect(bottomRect, gateFillPaint);
      canvas.drawRect(bottomRect, gateOutlinePaint);

      // Draw red laser beams between the gaps!
      canvas.drawLine(
        Offset(gate.x, gate.gapTop),
        Offset(gate.x, gate.gapTop + gate.gapHeight),
        dangerLaserPaint,
      );
      canvas.drawLine(
        Offset(gate.x + gate.width, gate.gapTop),
        Offset(gate.x + gate.width, gate.gapTop + gate.gapHeight),
        dangerLaserPaint,
      );
    }

    // 3. Render Shards (Diamonds)
    final shardPaint = Paint()..color = const Color(0xFF10B981);
    for (final shard in shards) {
      canvas.save();
      canvas.translate(shard.x, shard.y);
      canvas.rotate(shard.angle);

      final path = Path()
        ..moveTo(0, -7)
        ..lineTo(5, 0)
        ..lineTo(0, 7)
        ..lineTo(-5, 0)
        ..close();

      canvas.drawPath(path, shardPaint);
      
      // outer neon glow ring
      canvas.drawCircle(Offset.zero, 11, Paint()
        ..color = const Color(0xFF10B981).withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);

      canvas.restore();
    }

    // 4. Render Military Drones
    if (militaryEnabled) {
      final dronePaint = Paint()..color = const Color(0xFFEF4444);
      final droneShieldPaint = Paint()
        ..color = const Color(0xFFEF4444).withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      for (final drone in drones) {
        canvas.drawCircle(Offset(drone.x, drone.y), 6.5, dronePaint);
        // glowing warning rings
        canvas.drawCircle(Offset(drone.x, drone.y), 11.0, droneShieldPaint);
      }
    }

    // 5. Render Particle Sparks
    for (final p in particles) {
      final particlePaint = Paint()..color = p.color.withOpacity(p.life.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(p.x, p.y), 2.0 * p.life, particlePaint);
    }

    // 6. Render Cyber Ball (Player)
    final double _ballX = 70.0;
    if (!invincible || (time * 10.0).toInt() % 2 == 0) {
      final ballPaint = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE0F7FA), Color(0xFF00F5FF)],
        ).createShader(Rect.fromCircle(center: Offset(_ballX, ballY), radius: ballRadius));

      final glowPaint = Paint()
        ..color = const Color(0xFF00F5FF).withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);

      // outer glow
      canvas.drawCircle(Offset(_ballX, ballY), ballRadius + 4.0, glowPaint);
      // solid core
      canvas.drawCircle(Offset(_ballX, ballY), ballRadius, ballPaint);

      // Direction indicator pip
      canvas.drawCircle(
        Offset(_ballX + 4.0, ballY - 2.0),
        2.0,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CyberGamePainter oldDelegate) {
    return oldDelegate.ballY != ballY ||
        oldDelegate.gates.length != gates.length ||
        oldDelegate.particles.length != particles.length ||
        oldDelegate.time != time;
  }
}
