import 'package:flutter/foundation.dart';
import '../api/dartstream.dart';
import '../models/workspace_data.dart';

class CloudSaveService {
  static const String slotKey = 'focusstream';
  static const String projectId = 'focusstream';
  static const String environmentId = 'production';

  final DartstreamApi api;

  CloudSaveService(this.api);

  Future<WorkspaceData?> loadWorkspace({
    required String userId,
    required String tenantId,
  }) async {
    debugPrint(
      'CloudSaveService.loadWorkspace userId=$userId tenantId=$tenantId slotKey=$slotKey',
    );
    try {
      final snapshot = await api.loadSnapshot(
        userId: userId,
        tenantId: tenantId,
        slotKey: slotKey,
        projectId: projectId,
        environmentId: environmentId,
      );

      if (snapshot == null) {
        debugPrint('CloudSaveService.loadWorkspace snapshot=null');
        return null;
      }

      final snapshotData = snapshot['snapshot'];
      if (snapshotData is! Map) {
        debugPrint('CloudSaveService.loadWorkspace snapshotData invalid');
        return null;
      }

      final payload = snapshotData['payload'];
      if (payload is Map) {
        final workspace = WorkspaceData.fromJson(Map<String, dynamic>.from(payload));
        debugPrint('CloudSaveService.loadWorkspace parsedWorkspace: tasksCount=${workspace.tasks.length}');
        return workspace;
      }
    } catch (e) {
      debugPrint('CloudSaveService.loadWorkspace error: $e');
    }
    return null;
  }

  Future<void> saveWorkspace({
    required String userId,
    required String tenantId,
    required WorkspaceData workspace,
  }) async {
    debugPrint(
      'CloudSaveService.saveWorkspace userId=$userId tenantId=$tenantId slotKey=$slotKey',
    );
    try {
      final resp = await api.saveSnapshot(
        userId: userId,
        tenantId: tenantId,
        slotKey: slotKey,
        payload: workspace.toJson(),
        projectId: projectId,
        environmentId: environmentId,
      );
      debugPrint('CloudSaveService.saveWorkspace response status: $resp');
    } catch (e) {
      debugPrint('CloudSaveService.saveWorkspace error: $e');
    }
  }
}
