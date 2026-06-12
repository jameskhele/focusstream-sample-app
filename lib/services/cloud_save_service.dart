import 'package:flutter/foundation.dart';
import 'package:dartstream_client/dartstream_client.dart';
import '../models/workspace_data.dart';

class CloudSaveService {
  static const String slotKey = 'focusstream';
  static const String projectId = 'focusstream';
  static const String environmentId = 'development';

  final DartStreamClient client;
  final DartStreamSession session;

  CloudSaveService(this.client, this.session);

  Future<WorkspaceData?> loadWorkspace({
    required String userId,
    required String tenantId,
  }) async {
    debugPrint('CloudSaveService.loadWorkspace slotKey=$slotKey');
    final snapshot = await client.experience.loadCloudSave(
      session,
      scope: const DartStreamScope(
        projectId: projectId,
        environmentId: environmentId,
      ),
      slotKey: slotKey,
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
    return null;
  }

  Future<void> saveWorkspace({
    required String userId,
    required String tenantId,
    required WorkspaceData workspace,
  }) async {
    debugPrint('CloudSaveService.saveWorkspace slotKey=$slotKey');
    final resp = await client.experience.saveCloudSave(
      session,
      scope: const DartStreamScope(
        projectId: projectId,
        environmentId: environmentId,
      ),
      slotKey: slotKey,
      payload: workspace.toJson(),
    );
    debugPrint('CloudSaveService.saveWorkspace response status: $resp');
  }
}
