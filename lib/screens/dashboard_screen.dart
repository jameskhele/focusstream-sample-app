import 'dart:async';
import 'package:flutter/material.dart';
import '../api/dartstream.dart';
import '../models/workspace_data.dart';
import '../services/cloud_save_service.dart';
import '../state/session.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});
  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // DartStream scope configuration
  static const _slotKey = 'focusstream';
  static const _projectId = 'focusstream';
  static const _environmentId = 'production';

  late CloudSaveService _saveService;
  WorkspaceData _workspace = WorkspaceData.empty();
  bool _loading = true;
  Object? _error;

  // Live responses from Dev APIs
  Map<String, dynamic>? _liveProfile;
  List<dynamic> _liveFeatureFlags = const [];
  List<dynamic> _liveInventory = const [];
  List<dynamic> _liveChannels = const [];
  List<dynamic> _liveSessions = const [];
  List<dynamic> _liveDatabase = const [];
  final List<String> _liveLogs = [];

  // Pomodoro Focus Timer state
  Timer? _timer;
  int _secondsRemaining = 25 * 60; // 25 minutes default
  bool _timerRunning = false;
  String _timerMode = 'Focus';

  DartstreamApi get _api => widget.session.api!;
  String get _userId => widget.session.userId!;
  String get _tenantId => widget.session.tenantId!;

  @override
  void initState() {
    super.initState();
    _saveService = CloudSaveService(_api);
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _liveLogs.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  // Fetch all live values from the dev-api servers
  Future<void> _bootstrap() async {
    _log('Initializing FocusStream Workspace...');
    try {
      final results = await Future.wait([
        _saveService.loadWorkspace(userId: _userId, tenantId: _tenantId),
        _api.profile(userId: _userId, tenantId: _tenantId, projectId: _projectId, environmentId: _environmentId),
        _api.featureFlags(tenantId: _tenantId),
        _api.inventory(userId: _userId, tenantId: _tenantId, projectId: _projectId, environmentId: _environmentId),
        _api.streamingChannels(tenantId: _tenantId),
        _api.persistenceList(tenantId: _tenantId, subpath: '/database/'),
      ]);

      final loadedWorkspace = results[0] as WorkspaceData?;
      final profile = results[1] as Map<String, dynamic>;
      final flags = results[2] as Map<String, dynamic>;
      final inventory = results[3] as Map<String, dynamic>;
      final channels = results[4] as List;
      final db = results[5] as List;

      // Extract flags list
      final flagsList = (flags['flags'] is List)
          ? flags['flags'] as List
          : (flags['data'] is List ? flags['data'] as List : const []);

      // Extract inventory list
      final invMap = ((inventory['inventory'] is Map) ? inventory['inventory'] : inventory) as Map?;
      final items = (invMap?['items'] is List) ? invMap!['items'] as List : const [];

      _log('Workspace successfully loaded.');

      setState(() {
        _workspace = loadedWorkspace ?? WorkspaceData.empty();
        _liveProfile = profile;
        _liveFeatureFlags = flagsList;
        _liveInventory = items;
        _liveChannels = channels;
        _liveDatabase = db;
        _loading = false;
      });
    } catch (e) {
      _log('Workspace load failed: $e');
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  // Auto-saves current workspace layout to Cloud Save snapshots
  Future<void> _triggerCloudSave() async {
    _log('Syncing workspace to DartStream snapshots...');
    try {
      await _saveService.saveWorkspace(
        userId: _userId,
        tenantId: _tenantId,
        workspace: _workspace,
      );
      _log('Sync completed successfully.');
    } catch (e) {
      _log('Sync failed: $e');
    }
  }

  // Logs reactive event
  Future<void> _logReactiveEvent(String eventType, Map<String, dynamic> payload) async {
    _log('Logging reactive event: $eventType');
    try {
      await _api.logEvent(
        tenantId: _tenantId,
        eventType: eventType,
        payload: {
          ...payload,
          'projectId': _projectId,
          'environmentId': _environmentId,
        },
      );
      _log('Logged event: $eventType');
    } catch (e) {
      _log('Log event failed: $e');
    }
  }

  // Pomodoro Timer control
  void _toggleTimer() {
    if (_timerRunning) {
      _timer?.cancel();
      setState(() {
        _timerRunning = false;
      });
      _log('Focus Timer paused.');
    } else {
      setState(() {
        _timerRunning = true;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 0) {
          setState(() {
            _secondsRemaining--;
          });
        } else {
          _timer?.cancel();
          _onTimerComplete();
        }
      });
      _log('Focus Timer started.');
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _timerRunning = false;
      _secondsRemaining = _timerMode == 'Focus' ? 25 * 60 : 5 * 60;
    });
    _log('Focus Timer reset.');
  }

  void _onTimerComplete() {
    setState(() {
      _timerRunning = false;
    });

    if (_timerMode == 'Focus') {
      _log('Pomodoro session completed!');
      _workspace = _workspace.copyWith(
        focusSessions: _workspace.focusSessions + 1,
        lifetimeFocusMinutes: _workspace.lifetimeFocusMinutes + 25,
      );
      _logReactiveEvent('focus.session.completed', {
        'duration_minutes': 25,
        'sessions_completed': _workspace.focusSessions,
      });

      _triggerCloudSave();

      // Switch to break mode
      setState(() {
        _timerMode = 'Break';
        _secondsRemaining = 5 * 60;
      });
    } else {
      _log('Break session completed! Back to focus.');
      setState(() {
        _timerMode = 'Focus';
        _secondsRemaining = 25 * 60;
      });
    }
  }

  // Kanban task CRUD
  void _addTask() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Task to Workspace'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(hintText: 'Task Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(hintText: 'Description'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final t = titleController.text.trim();
                final d = descController.text.trim();
                if (t.isEmpty) return;

                final newItem = TaskItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: t,
                  description: d,
                  status: 'todo',
                  createdAt: DateTime.now().toIso8601String(),
                );

                setState(() {
                  _workspace = _workspace.copyWith(
                    tasks: [..._workspace.tasks, newItem],
                  );
                });

                Navigator.pop(context);
                _log('Task "${newItem.title}" added to Workspace.');
                _logReactiveEvent('task.created', {'taskId': newItem.id, 'title': newItem.title});
                _triggerCloudSave();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _moveTask(TaskItem item, String newStatus) {
    final updatedTasks = _workspace.tasks.map((e) {
      if (e.id == item.id) {
        return e.copyWith(status: newStatus);
      }
      return e;
    }).toList();

    int extraCompleted = 0;
    if (newStatus == 'done' && item.status != 'done') {
      extraCompleted = 1;
      _logReactiveEvent('task.completed', {'taskId': item.id, 'title': item.title});
    }

    setState(() {
      _workspace = _workspace.copyWith(
        tasks: updatedTasks,
        completedCount: _workspace.completedCount + extraCompleted,
      );
    });

    _log('Task "${item.title}" moved to $newStatus.');
    _triggerCloudSave();
  }

  void _deleteTask(TaskItem item) {
    final updatedTasks = _workspace.tasks.where((e) => e.id != item.id).toList();
    setState(() {
      _workspace = _workspace.copyWith(tasks: updatedTasks);
    });
    _log('Task "${item.title}" removed.');
    _triggerCloudSave();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Connection failed: $_error', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _bootstrap, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(),
      body: _body(),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: const Color(0xFF151824),
      title: Row(
        children: [
          const Icon(Icons.blur_on, color: Color(0xFF6366F1)),
          const SizedBox(width: 8),
          const Text('FocusStream Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2130),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '$_projectId/$_environmentId',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Courier'),
            ),
          ),
        ],
      ),
      actions: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              widget.session.email ?? '',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.grey),
          onPressed: () => widget.session.signOut(),
          tooltip: 'Sign Out',
        ),
      ],
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1050;
        final dashboard = _dashboardView();
        final explorer = _apiExplorerView();

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: dashboard),
              const VerticalDivider(width: 1, color: Color(0xFF151824)),
              SizedBox(width: 360, child: explorer),
            ],
          );
        } else {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              dashboard,
              const Divider(height: 32, color: Color(0xFF151824)),
              explorer,
            ],
          );
        }
      },
    );
  }

  Widget _dashboardView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timer + Focus Panel
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _timerWidget()),
              const SizedBox(width: 16),
              Expanded(child: _workspaceStatsWidget()),
            ],
          ),
          const SizedBox(height: 24),
          // Kanban Task Board
          _kanbanBoardWidget(),
        ],
      ),
    );
  }

  Widget _timerWidget() {
    final minutes = (_secondsRemaining / 60).floor().toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_timerMode Timer', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Icon(
                  _timerMode == 'Focus' ? Icons.work : Icons.local_cafe,
                  color: _timerMode == 'Focus' ? const Color(0xFF6366F1) : const Color(0xFF10B981),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '$minutes:$seconds',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, fontFamily: 'Courier'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(_timerRunning ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 40,
                  color: const Color(0xFF6366F1),
                  onPressed: _toggleTimer,
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.replay_circle_filled),
                  iconSize: 40,
                  color: Colors.grey,
                  onPressed: _resetTimer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceStatsWidget() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Workspace Stats', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
            _statLine('Focus Sessions', _workspace.focusSessions.toString()),
            _statLine('Focus Minutes', '${_workspace.lifetimeFocusMinutes}m'),
            _statLine('Completed Tasks', _workspace.completedCount.toString()),
            _statLine('Sync Slot', _slotKey),
          ],
        ),
      ),
    );
  }

  Widget _statLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _kanbanBoardWidget() {
    final todoList = _workspace.tasks.where((e) => e.status == 'todo').toList();
    final progressList = _workspace.tasks.where((e) => e.status == 'in_progress').toList();
    final doneList = _workspace.tasks.where((e) => e.status == 'done').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Tasks Kanban Board', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            FilledButton.icon(
              onPressed: _addTask,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Task'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _kanbanColumn('To Do', todoList, 'todo')),
            const SizedBox(width: 12),
            Expanded(child: _kanbanColumn('In Progress', progressList, 'in_progress')),
            const SizedBox(width: 12),
            Expanded(child: _kanbanColumn('Completed', doneList, 'done')),
          ],
        ),
      ],
    );
  }

  Widget _kanbanColumn(String title, List<TaskItem> list, String columnStatus) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151824),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title (${list.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Container(
              height: 80,
              alignment: Alignment.center,
              child: const Text('No tasks', style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          else
            ...list.map((item) => _taskCard(item)),
        ],
      ),
    );
  }

  Widget _taskCard(TaskItem item) {
    return Card(
      color: const Color(0xFF1E2130),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(item.description, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  onPressed: () => _deleteTask(item),
                ),
                Row(
                  children: [
                    if (item.status != 'todo')
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 16),
                        onPressed: () {
                          final prev = item.status == 'done' ? 'in_progress' : 'todo';
                          _moveTask(item, prev);
                        },
                      ),
                    if (item.status != 'done')
                      IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF6366F1)),
                        onPressed: () {
                          final next = item.status == 'todo' ? 'in_progress' : 'done';
                          _moveTask(item, next);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _apiExplorerView() {
    return Container(
      color: const Color(0xFF151824),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Live API Explorer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _explorerSection('Workspace Logs', _logsListWidget()),
                _explorerSection('Feature Flags (${_liveFeatureFlags.length})', _flagsWidget()),
                _explorerSection('Inventory (${_liveInventory.length})', _inventoryWidget()),
                _explorerSection('Streaming Channels (${_liveChannels.length})', _channelsWidget()),
                _explorerSection('Persistence Entries (${_liveDatabase.length})', _databaseWidget()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _explorerSection(String title, Widget child) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      childrenPadding: const EdgeInsets.all(8),
      children: [child],
    );
  }

  Widget _logsListWidget() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _liveLogs.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              _liveLogs[index],
              style: const TextStyle(fontSize: 10, fontFamily: 'Courier', color: Color(0xFF10B981)),
            ),
          );
        },
      ),
    );
  }

  Widget _flagsWidget() {
    if (_liveFeatureFlags.isEmpty) return const Text('No active flags', style: TextStyle(fontSize: 12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _liveFeatureFlags.map((f) => Text('• ${f.toString()}', style: const TextStyle(fontSize: 11))).toList(),
    );
  }

  Widget _inventoryWidget() {
    if (_liveInventory.isEmpty) return const Text('Inventory empty', style: TextStyle(fontSize: 12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _liveInventory.map((item) {
        if (item is Map) {
          final id = item['itemId'] ?? item['id'] ?? '?';
          final qty = item['quantity'] ?? 1;
          return Text('• $id (×$qty)', style: const TextStyle(fontSize: 11));
        }
        return Text('• ${item.toString()}', style: const TextStyle(fontSize: 11));
      }).toList(),
    );
  }

  Widget _channelsWidget() {
    if (_liveChannels.isEmpty) return const Text('No streaming channels found', style: TextStyle(fontSize: 12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _liveChannels.map((c) => Text('• ${c.toString()}', style: const TextStyle(fontSize: 11))).toList(),
    );
  }

  Widget _databaseWidget() {
    if (_liveDatabase.isEmpty) return const Text('Database collection empty', style: TextStyle(fontSize: 12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _liveDatabase.map((d) => Text('• ${d.toString()}', style: const TextStyle(fontSize: 11))).toList(),
    );
  }
}
