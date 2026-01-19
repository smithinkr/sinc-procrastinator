import 'package:uuid/uuid.dart';

class Task {
  String id;
  String title;
  String description;
  String priority; // 'High', 'Medium', 'Low'
  String category; // 'Work', 'Personal', etc.
  String dueDate;
  bool isCompleted;
  List<SubTask> subtasks;
  int createdAt;

  Task({
    String? id,
    required this.title,
    this.description = '',
    this.priority = 'Medium',
    this.category = 'General',
    this.dueDate = '',
    this.isCompleted = false,
    required this.subtasks,
    required this.createdAt,
  }) : id = id ?? const Uuid().v4(); // Auto-generate ID if null
}

class SubTask {
  String id;
  String title;
  bool isCompleted;

  SubTask({
    String? id, 
    required this.title, 
    this.isCompleted = false
  }) : id = id ?? const Uuid().v4();
}