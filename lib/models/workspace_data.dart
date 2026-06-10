class TaskItem {
  final String id;
  final String title;
  final String description;
  final String status; // 'todo', 'in_progress', 'done'
  final String createdAt;

  TaskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? 'todo',
      createdAt: json['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'createdAt': createdAt,
    };
  }

  TaskItem copyWith({
    String? title,
    String? description,
    String? status,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

class WorkspaceData {
  final List<TaskItem> tasks;
  final int completedCount;
  final int focusSessions;
  final int lifetimeFocusMinutes;
  final String themeName;

  const WorkspaceData({
    required this.tasks,
    required this.completedCount,
    required this.focusSessions,
    required this.lifetimeFocusMinutes,
    required this.themeName,
  });

  factory WorkspaceData.empty() {
    return const WorkspaceData(
      tasks: [],
      completedCount: 0,
      focusSessions: 0,
      lifetimeFocusMinutes: 0,
      themeName: 'Default Blue',
    );
  }

  factory WorkspaceData.fromJson(Map<String, dynamic> json) {
    final tasksList = json['tasks'] as List? ?? [];
    return WorkspaceData(
      tasks: tasksList.map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e))).toList(),
      completedCount: json['completedCount'] ?? 0,
      focusSessions: json['focusSessions'] ?? 0,
      lifetimeFocusMinutes: json['lifetimeFocusMinutes'] ?? 0,
      themeName: json['themeName'] ?? 'Default Blue',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tasks': tasks.map((e) => e.toJson()).toList(),
      'completedCount': completedCount,
      'focusSessions': focusSessions,
      'lifetimeFocusMinutes': lifetimeFocusMinutes,
      'themeName': themeName,
    };
  }

  WorkspaceData copyWith({
    List<TaskItem>? tasks,
    int? completedCount,
    int? focusSessions,
    int? lifetimeFocusMinutes,
    String? themeName,
  }) {
    return WorkspaceData(
      tasks: tasks ?? this.tasks,
      completedCount: completedCount ?? this.completedCount,
      focusSessions: focusSessions ?? this.focusSessions,
      lifetimeFocusMinutes: lifetimeFocusMinutes ?? this.lifetimeFocusMinutes,
      themeName: themeName ?? this.themeName,
    );
  }
}
