import 'dart:convert';
import 'package:uuid/uuid.dart';

class Task {
  final String id;
  String title;
  String description;
  bool isCompleted;
  String priority;
  String category;
  final int createdAt;
  bool isAiGenerated;
  List<SubTask> subtasks;
  String dueDate;      
  DateTime? exactDate; 
  bool hasSpecificTime; 

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.priority = 'Medium',
    this.category = 'General',
    required this.createdAt,
    this.isAiGenerated = false,
    this.subtasks = const [],
    this.dueDate = '',
    this.exactDate,
    this.hasSpecificTime = false,
  });

  // --- CLOUD SYNC METHOD ---
  // Converts the Task object into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'priority': priority,
      'category': category,
      'createdAt': createdAt,
      'isAiGenerated': isAiGenerated,
      'subtasks': subtasks.map((e) => e.toMap()).toList(),
      'dueDate': dueDate,
      'exactDate': exactDate?.millisecondsSinceEpoch,
      'hasSpecificTime': hasSpecificTime,
    };
  }

  // --- LOCAL STORAGE METHOD ---
  // Points to toMap() to keep data consistent between local and cloud
  Map<String, dynamic> toJson() => toMap();

  factory Task.fromJson(Map<String, dynamic> json) {
    var subtasksData = json['subtasks'];
    List<dynamic> parsedSubtasks = [];

    if (subtasksData is String) {
      try {
        parsedSubtasks = jsonDecode(subtasksData);
      } catch (e) {
        parsedSubtasks = [];
      }
    } else if (subtasksData is List) {
      parsedSubtasks = subtasksData;
    }

    return Task(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      isCompleted: json['isCompleted'] ?? false, 
      priority: json['priority'] ?? 'Medium',
      category: json['category'] ?? 'General',
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      isAiGenerated: json['isAiGenerated'] ?? false,
      subtasks: parsedSubtasks
          .map((e) => SubTask.fromJson(e))
          .toList(),
      dueDate: json['dueDate'] ?? '',
      exactDate: json['exactDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['exactDate']) 
          : null,
      hasSpecificTime: json['hasSpecificTime'] ?? false,
    );
  }

  // --- EQUALITY CHECK ---
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isCompleted == other.isCompleted &&
          exactDate == other.exactDate &&
          title == other.title &&
          priority == other.priority &&
          category == other.category &&
          subtasks.length == other.subtasks.length;

  @override
  int get hashCode => 
    id.hashCode ^ 
    isCompleted.hashCode ^ 
    exactDate.hashCode ^ 
    priority.hashCode ^ 
    category.hashCode;

  Task copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    String? priority,
    String? category,
    int? createdAt,
    bool? isAiGenerated,
    List<SubTask>? subtasks,
    String? dueDate,
    DateTime? exactDate,
    bool? hasSpecificTime,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      subtasks: subtasks ?? this.subtasks,
      dueDate: dueDate ?? this.dueDate,
      exactDate: exactDate ?? this.exactDate,
      hasSpecificTime: hasSpecificTime ?? this.hasSpecificTime,
    );
  }
}

class SubTask {
  final String id;
  String title;
  bool isCompleted;

  SubTask({required this.id, required this.title, this.isCompleted = false});

  // --- CLOUD & LOCAL STORAGE METHODS ---
  Map<String, dynamic> toMap() {
    return {
      'id': id, 
      'title': title, 
      'isCompleted': isCompleted
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory SubTask.fromJson(Map<String, dynamic> json) {
    return SubTask(
      id: json['id'] ?? const Uuid().v4(), 
      title: json['title'] ?? '',
      isCompleted: json['isCompleted'] ?? false,
    );
  }

  // --- EQUALITY CHECK ---
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isCompleted == other.isCompleted;

  @override
  int get hashCode => id.hashCode ^ isCompleted.hashCode;

  SubTask copyWith({
    String? id,
    String? title,
    bool? isCompleted,
  }) {
    return SubTask(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}