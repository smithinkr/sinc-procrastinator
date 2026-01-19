import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:procrastinator/utils/logger.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/gemini_service.dart';
import '../models/task_model.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'settings_page.dart';
import '../widgets/task_card.dart';
import '../widgets/task_detail_modal.dart';
import '../widgets/calendar_modal.dart';
import '../widgets/smart_input_layer.dart';
import '../widgets/category_ribbons.dart';
import '../services/natural_language_parser.dart';
import 'package:home_widget/home_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/sync_service.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
StreamSubscription<User?>? _authListener;
  static const List<Color> _darkPalette = [
    Color(0xFF2C3E50), Color(0xFF3E3D32), Color(0xFF4A2328),
    Color(0xFF1E3A3A), Color(0xFF3B2F45), Color(0xFF42382F),
  ];

  static const List<Color> _lightPalette = [
    Color(0xFFE3F2FD), Color(0xFFF1F8E9), Color(0xFFFFF3E0),
    Color(0xFFF3E5F5), Color(0xFFE0F7FA), Color(0xFFFCE4EC),
  ];
  

  final PageController _pageController = PageController(initialPage: 1);
  final GlobalKey<SmartInputLayerState> _smartInputKey = GlobalKey<SmartInputLayerState>();
  
  bool _isAiLoading = false;
  bool _isListExpanded = false;
  final List<Task> _tasks = [];

  double _drawerDragOffset = 0.0;
  final double _maxDrawerWidth = 140.0;
  String _selectedCategory = 'All';

  Task? _expandedTask;
  Task? _previewTask;

  // --- LOGIC METHODS ---

List<Task> _getUrgentTasks(List<Task> allTasks) {
  final now = DateTime.now();
  // We set the threshold to the very END of the 3rd day (23:59)
  final todayStart = DateTime(now.year, now.month, now.day);
  final urgencyThreshold = todayStart.add(const Duration(days: 3, hours: 23, minutes: 59));

  return allTasks.where((task) {
    // 1. Filter out completed tasks first
    if (task.isCompleted) return false;

    // 2. Priority Check (Case-insensitive & Trimmed)
    final String p = task.priority.trim().toLowerCase();
    bool isHighPriority = p == 'high' || p == 'urgent' || p == 'now';

    // 3. Date Check
    bool isExpiringSoon = false;
    if (task.exactDate != null) {
      // Inclusive check: Is the task date before our 3-day buffer ends?
      isExpiringSoon = task.exactDate!.isBefore(urgencyThreshold);
    } else {
      // String Fallback for Natural Language Parser
      final String dueLower = task.dueDate.toLowerCase();
      isExpiringSoon = dueLower.contains('today') || 
                       dueLower.contains('tomorrow') || 
                       dueLower.contains('tonight');
    }

    return isHighPriority || isExpiringSoon;
  }).toList();
}

@override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Detects when the app comes back from the background
    if (state == AppLifecycleState.resumed) {
      L.d("🔄 S.INC: App Resumed. Synchronizing data...");
      _loadData(); 
    }
  }
 @override
  void initState() {
    super.initState();
    
    // START AUDITORS
    WidgetsBinding.instance.addObserver(this); // Lifecycle Auditor
    
    // AUTH AUDITOR: Immediately refreshes tasks when user logs in/out
    _authListener = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        L.d("☁️ S.INC: Auth State Changed. Refreshing Ledger...");
        _loadData(); 
      }
    });

    // YOUR EXISTING CODE
    
    HomeWidget.setAppGroupId('group.com.sinc.procrastinator');
    _checkWidgetLaunch();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService().requestPermissions();
    });

    _pageController.addListener(_handlePageScroll);
  }

  void _handlePageScroll() {
    if (!mounted) return;
    double page = _pageController.page ?? 1.0;
    if (page > 0.9 && page < 1.1) {
      if (_selectedCategory != 'All' || _drawerDragOffset > 0) {
        setState(() {
          _selectedCategory = 'All'; 
          _drawerDragOffset = 0.0; 
        });
      }
    }
  }

  void _checkWidgetLaunch() {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetClick);
    HomeWidget.widgetClicked.listen(_handleWidgetClick);
  }

  void _handleWidgetClick(Uri? uri) {
    if (uri == null) return;
    if (uri.host == 'create') {
      setState(() => _selectedCategory = 'All');
      if (_pageController.hasClients) {
        _pageController.animateToPage(1, 
          duration: const Duration(milliseconds: 300), 
          curve: Curves.easeOutCubic
        ).then((_) {
          _smartInputKey.currentState?.activateInputFromWidget();
        });
      }
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    // STOP AUDITORS
    WidgetsBinding.instance.removeObserver(this); // Stop Lifecycle Auditor
    _authListener?.cancel(); // Stop Auth Auditor
    
    // YOUR EXISTING CODE
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    List<Task> mergedTasks = [];

    // 1. PHASE ONE: Load from the local "Hardware Vault"
    // We show this immediately so the user doesn't see a blank screen.
    try {
      final localTasks = await StorageService.loadTasks();
      if (localTasks.isNotEmpty) {
        mergedTasks = localTasks;
        _updateUI(mergedTasks); 
      }
    } catch (e) {
      L.d("🚨 LOCAL LOAD ERROR: $e");
    }

    // 2. PHASE TWO: Handshake with Firebase
    try {
      await SyncService().getUserId(); 
      final cloudTasks = await SyncService().fetchTasksFromCloud();
      
      if (cloudTasks.isNotEmpty) {
        // SMART MERGE: We only add tasks from the cloud that aren't already here.
        // This prevents the cloud from "deleting" newer local tasks.
        final localIds = mergedTasks.map((t) => t.id).toSet();
        final newFromCloud = cloudTasks.where((t) => !localIds.contains(t.id)).toList();

        if (newFromCloud.isNotEmpty) {
          mergedTasks.addAll(newFromCloud);
          
          // Sort by date (assuming your Task model has a createdAt or similar)
          mergedTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // 3. SECURE THE MERGE: Save the updated list back to the local vault
          // Because of our 'compute' update in StorageService, this won't freeze the UI.
          await StorageService.saveTasks(mergedTasks);
          _updateUI(mergedTasks);
        }
      }
    } catch (e) {
      // If the user is offline, we just fail silently. The local tasks are already visible.
      L.d("🚨 CLOUD SYNC ERROR: $e");
    }
    // Inside _loadData() at the very end
_updateUI(mergedTasks);
_saveData(); // This pushes the freshly loaded cloud tasks to the widget
  }

  /// Helper to refresh the UI safely
  void _updateUI(List<Task> tasks) {
    if (!mounted) return;
    setState(() {
      _tasks.clear();
      _tasks.addAll(tasks);
    });
  }

  void _saveData() async {
  // 1. CAPTURE STATE (Do this first to avoid 'context' errors later)
  final settings = Provider.of<SettingsService>(context, listen: false);
  final List<Task> taskSnapshot = List.from(_tasks); 
  final currentUser = FirebaseAuth.instance.currentUser;

  // 2. LOCAL VAULT (Non-blocking)
  StorageService.saveTasks(taskSnapshot);
  
  // 3. IMMEDIATE CLOUD SYNC (The 'Right of Passage')
  // We trigger this immediately. If logged in, it syncs; if not, it skips safely.
  // 3. IMMEDIATE CLOUD SYNC
if (currentUser != null) {
  SyncService().syncTasksToCloud(taskSnapshot).then((_) {
    if (mounted) {
      setState(() {}); 
      L.d("☁️ S.INC: Cloud Handshake Successful.");
    }
  }).catchError((e) {
    L.d("🚨 Cloud Sync Error: $e");
    return null; // The fix is here
  });
}

  // 4. WIDGET RECONCILIATION
  final urgentTasks = _getUrgentTasks(taskSnapshot).where((t) => !t.isCompleted).toList();
  String widgetContent = urgentTasks.isEmpty 
      ? "List clear. Take a breath." 
      : urgentTasks.take(3).map((t) => "• ${t.title.toLowerCase()}").join("\n");

  try {
    await HomeWidget.saveWidgetData<String>('headline_description', widgetContent);
    await HomeWidget.saveWidgetData<String>('app_id', 'com.sinc.procrastinator');
    await HomeWidget.updateWidget(
      name: 'ProcrastinatorWidgetProvider',
      androidName: 'ProcrastinatorWidgetProvider',
      qualifiedAndroidName: 'com.sinc.procrastinator.ProcrastinatorWidgetProvider',
    );
    L.d("✅ S.INC: Widget HUD Updated.");
  } catch (e) {
    L.d("🚨 Widget Sync Error: $e");
  }

  // 5. NOTIFICATIONS (Background)
  // 5. NOTIFICATIONS
NotificationService().updateNotifications(
  allTasks: taskSnapshot,
  briefHour: settings.briefHour, 
  briefMinute: settings.briefMinute,
).catchError((e) {
  L.d("🚨 Notification Error: $e");
  return null; // And the fix is here
});
}

  // --- UI HELPERS ---

  Color _getCardColor(int index, bool isDark) {
    return isDark 
        ? _darkPalette[index % _darkPalette.length].withValues(alpha: 0.9) 
        : _lightPalette[index % _lightPalette.length];
  }

  Color _getBandColor(Color base, bool isDark) {
    return isDark 
        ? HSLColor.fromColor(base).withLightness(0.35).toColor() 
        : HSLColor.fromColor(base).withLightness(0.92).toColor();
  }

  List<Color> _getGradient(String theme, bool isDark) {
    Color top = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color bottom;
    switch (theme) {
      case 'emerald': bottom = isDark ? const Color(0xFF064E3B) : const Color(0xFF047857); break;
      case 'rose':    bottom = isDark ? const Color(0xFF881337) : const Color(0xFFBE123C); break;
      case 'cyan':    bottom = isDark ? const Color(0xFF164E63) : const Color(0xFF0E7490); break;
      default:        bottom = isDark ? const Color(0xFF312E81) : const Color(0xFF4338CA); break;
    }
    return [top, bottom];
  }

  void _showCalendar() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusScope.of(context).requestFocus(FocusNode());
    
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => CalendarModal(
        tasks: _tasks, 
        onClose: () {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          FocusScope.of(context).requestFocus(FocusNode());
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showAddTaskModal(BuildContext context) {
    final TextEditingController taskController = TextEditingController();
    String selectedCategory = 'General';
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          String dateText = selectedDate == null ? "Set Date" : "${selectedDate!.day}/${selectedDate!.month}";
          String timeText = selectedTime == null ? "Set Time" : selectedTime!.format(context);

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 20, right: 20, top: 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("New Task", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(
                  controller: taskController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "What needs doing?",
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['General', 'Work', 'Personal', 'Shopping'].map((cat) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: selectedCategory == cat,
                          onSelected: (bool selected) { if (selected) setModalState(() => selectedCategory = cat); },
                          selectedColor: Colors.black,
                          labelStyle: TextStyle(color: selectedCategory == cat ? Colors.white : Colors.black),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context, initialDate: DateTime.now(),
                          firstDate: DateTime.now(), lastDate: DateTime(2030),
                        );
                        if (date != null) setModalState(() => selectedDate = date);
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(dateText),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: selectedDate == null ? null : () async {
                        final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                        if (time != null) setModalState(() => selectedTime = time);
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(timeText),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        if (taskController.text.isEmpty) return;
                        DateTime? finalExactDate;
                        bool hasTime = false;
                        String displayDate = "";

                        if (selectedDate != null) {
                          if (selectedTime != null) {
                            finalExactDate = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, selectedTime!.hour, selectedTime!.minute);
                            hasTime = true;
                            displayDate = "${selectedDate!.day}/${selectedDate!.month} ${selectedTime!.format(context)}";
                          } else {
                            finalExactDate = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day);
                            displayDate = "${selectedDate!.day}/${selectedDate!.month}";
                          }
                        }

                        final newTask = Task(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: taskController.text,
                          category: selectedCategory,
                          subtasks: [],
                          createdAt: DateTime.now().millisecondsSinceEpoch,
                          dueDate: displayDate.isEmpty ? "Go Ahead, Ignore me" : displayDate,
                          exactDate: finalExactDate,
                          hasSpecificTime: hasTime,
                        );

                        setState(() => _previewTask = newTask);
                        Navigator.pop(context);
                        _confirmTask();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("Add"),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _toggleDrawer(bool open) {
    setState(() => _drawerDragOffset = open ? _maxDrawerWidth : 0.0);
  }

  Future<void> _addTask(dynamic input) async {
    if (input is String && input.trim().isEmpty) return;
    final settings = Provider.of<SettingsService>(context, listen: false);

    Task localTruth = (input is String) 
        ? NaturalLanguageParser.parse(input) 
        : NaturalLanguageParser.parse("Voice Task");

    if (!settings.isAiEnabled) {
      setState(() {
        _previewTask = localTruth.copyWith(
          dueDate: localTruth.dueDate.isEmpty ? "Go Ahead, Ignore me" : localTruth.dueDate
        );
      });
      return;
    }

    setState(() => _isAiLoading = true);

    try {
      final Task aiTask = await GeminiService.analyzeTask(
        input, 
  settings.aiCreativity, // Now only pass creativity and input
  preParsedTask: localTruth, 
      ).timeout(const Duration(seconds: 10)); 

      if (!mounted) return;

      setState(() {
        _isAiLoading = false;
        String mergedPriority = (localTruth.priority != 'Medium') ? localTruth.priority : aiTask.priority;
        if (mergedPriority.toLowerCase() == 'high') mergedPriority = 'High';

        String finalDueDate = "";
        if (localTruth.dueDate.isNotEmpty) {
          finalDueDate = localTruth.dueDate;
        } else if (aiTask.dueDate.isNotEmpty) {
          finalDueDate = aiTask.dueDate;
        } else {
          finalDueDate = "Go Ahead, Ignore me";
        }

        _previewTask = aiTask.copyWith(
          priority: mergedPriority,
          dueDate: finalDueDate,
          exactDate: (localTruth.exactDate != null) ? localTruth.exactDate : aiTask.exactDate,
          hasSpecificTime: (localTruth.exactDate != null) ? localTruth.hasSpecificTime : aiTask.hasSpecificTime,
        ); 
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAiLoading = false);
      L.d("🚨 AI CRITICAL ERROR: $e");
      HapticFeedback.vibrate();
      setState(() {
        _previewTask = localTruth.copyWith(
          dueDate: localTruth.dueDate.isEmpty ? "Go Ahead, Ignore me" : localTruth.dueDate
        );
      });
    }
  }

  void _confirmTask() {
  if (_previewTask == null) return;

  // 1. UI UPDATE FIRST (Instant Gratification)
  setState(() {
    _tasks.insert(0, _previewTask!);
    _previewTask = null;
    
    // Page transition feels smoother if triggered here
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        0, 
        duration: const Duration(milliseconds: 500), 
        curve: Curves.easeInOut
      );
    }
  });

  // 2. BACKGROUND RECONCILIATION
  // We call this OUTSIDE setState because it's an async process
  _saveData(); 
  
  // 3. HAPTIC FEEDBACK (The S.Inc Touch)
  HapticFeedback.mediumImpact(); 
}

  void _toggleTask(String id) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index != -1) {
        _tasks[index].isCompleted = !_tasks[index].isCompleted;
        _saveData(); 
        if (_expandedTask?.id == id) _expandedTask = _tasks[index]; 
      }
    });
  }

  void _deleteTask(String id) {
    setState(() {
      _tasks.removeWhere((t) => t.id == id);
      _expandedTask = null;
      _saveData(); 
    });
  }

  void _toggleSubtask(String taskId, String subtaskId) {
    setState(() {
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex != -1) {
        final subIndex = _tasks[taskIndex].subtasks.indexWhere((s) => s.id == subtaskId);
        if (subIndex != -1) {
          _tasks[taskIndex].subtasks[subIndex].isCompleted = !_tasks[taskIndex].subtasks[subIndex].isCompleted;
          _saveData();
        }
      }
    });
  }

  void _updateTaskContent(Task updatedTask) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
      if (index != -1) {
        _tasks[index] = updatedTask;
        _saveData();
        _expandedTask = updatedTask; 
      }
    });
  }
  void _showProfilePeek(BuildContext context, User user) {
  // 1. Access settings and theme info
  final settings = Provider.of<SettingsService>(context, listen: false);
  final Color themeColor = _getThemeColor(settings.themeColor);
  final bool isDark = settings.isDarkMode;

  // 2. Format the Sync Timestamp
  final String syncTime = SyncService.lastSyncedAt != null 
      ? "${SyncService.lastSyncedAt!.hour}:${SyncService.lastSyncedAt!.minute.toString().padLeft(2, '0')}"
      : "Never";

  // 3. Extract the initial from email
  final String initial = (user.email != null && user.email!.isNotEmpty) 
      ? user.email![0].toUpperCase() 
      : "S";

  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (context) => Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          // Background adapts to Dark Mode
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 15),
            )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // THEMED INITIAL CIRCLE
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [themeColor, themeColor.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.3), 
                      blurRadius: 15, 
                      offset: const Offset(0, 8)
                    )
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 40, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // USER IDENTITY
              Text(
                user.displayName ?? "Task Master",
                style: TextStyle(
                  fontSize: 22, 
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.white : Colors.black87
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.email ?? "",
                style: TextStyle(
                  fontSize: 13, 
                  color: isDark ? Colors.white54 : Colors.black45
                ),
              ),
              
              const SizedBox(height: 24),
              
              // THEMED LAST SYNCED BADGE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: themeColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done, color: themeColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      "Last Synced: $syncTime",
                      style: TextStyle(
                        color: themeColor, 
                        fontWeight: FontWeight.bold, 
                        fontSize: 12
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 10),
              
              // ACTION BUTTONS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPeekAction(
                    Icons.settings_outlined, 
                    "Settings", 
                    () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
                    },
                    isDark: isDark,
                    themeColor: themeColor,
                  ),
                  _buildPeekAction(
                    Icons.logout, 
                    "Sign Out", 
                    () async {
                      await SyncService().signOut();
                      if (context.mounted) Navigator.pop(context);
                    }, 
                    isDestructive: true,
                    isDark: isDark,
                    themeColor: themeColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Helper widget for the modal buttons
Widget _buildPeekAction(IconData icon, String label, VoidCallback onTap, 
    {bool isDestructive = false, required bool isDark, required Color themeColor}) {
  final Color actionColor = isDestructive ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black87);
  
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Icon(icon, color: actionColor, size: 24),
          const SizedBox(height: 4),
          Text(
            label, 
            style: TextStyle(
              fontSize: 12, 
              fontWeight: FontWeight.bold, 
              color: actionColor
            )
          ),
        ],
      ),
    ),
  );
}
  // --- SMART IDENTITY HELPERS ---

  Widget _buildSyncProfileButton(BuildContext context) {
  final settings = Provider.of<SettingsService>(context);
  final Color themeColor = _getThemeColor(settings.themeColor);
  final bool isDark = settings.isDarkMode;

  // 1. DYNAMIC CONTRAST: Ensures visibility in Light & Dark modes
  final Color contentColor = isDark 
      ? Colors.white.withValues(alpha: 0.9) 
      : const Color(0xFF1E293B); // Deep Charcoal

  return StreamBuilder<User?>(
    stream: FirebaseAuth.instance.userChanges(),
    builder: (context, snapshot) {
      final user = snapshot.data;
      final bool isLoggedIn = user != null;
      
      String initial = isLoggedIn ? (user.email?[0].toUpperCase() ?? "S") : "!";

      return GestureDetector(
        onTap: () => isLoggedIn ? _showProfilePeek(context, user) : _handleLogin(context),
        child: Container(
          // 2. OUTER SHADOW: Essential for depth on Glassmorphism
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 3. ADAPTIVE GLASS: Milky in Light, Inky in Dark
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.1) 
                      : Colors.black.withValues(alpha: 0.05),
                  border: Border.all(
                    // 4. RIGHT OF PASSAGE: Themed ring only when logged in
                    color: isLoggedIn 
                        ? themeColor.withValues(alpha: 0.6) 
                        : contentColor.withValues(alpha: 0.2), 
                    width: 2.0,
                  ),
                ),
                child: Center(
                  child: isLoggedIn 
                    ? Text(
                        initial,
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold, 
                          color: contentColor, // Matches global button text
                        ),
                      )
                    : Icon(
                        Icons.cloud_off, 
                        size: 20, 
                        color: contentColor.withValues(alpha: 0.5), // Matches global icons
                      ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

  void _handleLogin(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connecting to Google...")));
    
    final user = await SyncService().signInWithGoogle();
    
    // THE FIX: Check if the screen is still visible before showing the next message
    if (!context.mounted) return;

    if (user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Welcome, ${user.displayName}!"))
      );
      _saveData();
    }
  }

  // --- MAIN BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final Color themeColor = _getThemeColor(settings.themeColor);
  

    final activeTasks = _tasks.where((t) {
      if (t.isCompleted) return false;
      if (_selectedCategory == 'Urgent') {
        final isHigh = t.priority == 'High';
        final isSoon = t.exactDate != null && t.exactDate!.isBefore(DateTime.now().add(const Duration(days: 2)));
        return isHigh || isSoon;
      }
      return _selectedCategory == 'All' || t.category == _selectedCategory;
    }).toList();

    final completedTasks = _tasks.where((t) => t.isCompleted).toList();
    String cardTitle = _selectedCategory == 'All' ? "My Tasks" : _selectedCategory;

    final double screenHeight = MediaQuery.of(context).size.height;
    final double systemBottomPadding = MediaQuery.of(context).padding.bottom;
    final double topGap = screenHeight * 0.10;
    final double bottomGap = math.max(screenHeight * 0.05, systemBottomPadding + 10);

    return PopScope(
      canPop: _previewTask == null, 
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _previewTask != null) setState(() => _previewTask = null);
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false, 
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: _getGradient(settings.themeColor, settings.isDarkMode),
                  stops: const [0.3, 1.0], 
                ),
              ),
            ),

            PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(), 
              children: [
                Stack(
                  children: [
                    Positioned.fill(
                      top: topGap, bottom: bottomGap,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: _maxDrawerWidth + 60,
                          child: CategoryRibbons(
                            width: _drawerDragOffset,
                            selectedCategory: _selectedCategory,
                            onCategoryTap: (category) {
                              setState(() {
                                _selectedCategory = category == "All Tasks" ? "All" : category;
                                _drawerDragOffset = (_selectedCategory == 'All') ? 0.0 : _maxDrawerWidth;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(_drawerDragOffset, 0),
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          if (details.delta.dx > 0 && _pageController.position.pixels <= 5) {
                            setState(() => _drawerDragOffset = (_drawerDragOffset + details.delta.dx).clamp(0.0, _maxDrawerWidth));
                          } else if (details.delta.dx < 0) {
                            if (_drawerDragOffset > 0) {
                              setState(() => _drawerDragOffset = (_drawerDragOffset + details.delta.dx).clamp(0.0, _maxDrawerWidth));
                            } else {
                              _pageController.position.jumpTo(_pageController.offset - details.delta.dx);
                            }
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (_drawerDragOffset > 0) {
                            _toggleDrawer(_drawerDragOffset > _maxDrawerWidth / 2 || details.primaryVelocity! > 300);
                          } else {
                            final double sw = MediaQuery.of(context).size.width;
                            _pageController.animateToPage(
                              (_pageController.offset > sw * 0.25 || details.primaryVelocity! < -300) ? 1 : 0,
                              duration: const Duration(milliseconds: 300), curve: Curves.easeOut
                            );
                          }
                        },
                        child: _buildGlassSection(context, cardTitle, activeTasks, settings, false, topGap, bottomGap),
                      ),
                    ),
                  ],
                ),
                const SizedBox.shrink(), 
                _buildGlassSection(context, "Completed", completedTasks, settings, true, topGap, bottomGap),
              ],
            ),

            // --- HEADER ROW (NOW WITH SMART BUTTON) ---
            Positioned(
              top: 60, left: 20, right: 20, 
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isAiLoading ? 0.0 : 1.0, 
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildHeaderButton(Icons.tune, "Procrastinator", () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
                    }, settings.isDarkMode, themeColor),
                    Row(
                      children: [
                        _buildSyncProfileButton(context), // <--- THE UPDATED BUTTON
                        const SizedBox(width: 12),
                        _buildIconButton(Icons.calendar_today, _showCalendar, themeColor),
                      ],
                    )
                  ],
                ),
              ),
            ),

            if (!_isAiLoading && _previewTask == null)
              ListenableBuilder(
                listenable: _pageController,
                builder: (context, child) {
                  double page = _pageController.hasClients ? (_pageController.page ?? 1.0) : 1.0;
                  bool isCentered = (page > 0.9 && page < 1.1);
                  return IgnorePointer(
                    ignoring: !isCentered,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: isCentered ? 1.0 : 0.0,
                      child: SmartInputLayer(
  key: _smartInputKey, 
  allTasks: _tasks, // <--- THE FIX: Add this line here
  onTaskCreated: (input) => _addTask(input),
  isVisible: false, 
),
                    ),
                  );
                },
              ),

            if (_isAiLoading && settings.isAiEnabled)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3), 
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: settings.isDarkMode ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: Colors.indigo),
                              const SizedBox(height: 20),
                              Text("Working AI Magic...", style: TextStyle(fontWeight: FontWeight.bold, color: settings.isDarkMode ? Colors.white : Colors.black87)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            if (_previewTask != null)
              TaskDetailModal(
                task: _previewTask!, isPreview: true,
                onClose: () => setState(() => _previewTask = null),
                onConfirm: _confirmTask, onToggle: () {}, onDelete: () {}, onSubtaskToggle: (s) {},
              ),

            if (_expandedTask != null)
              TaskDetailModal(
                task: _expandedTask!,
                onClose: () => setState(() => _expandedTask = null),
                onToggle: () => _toggleTask(_expandedTask!.id),
                onDelete: () => _deleteTask(_expandedTask!.id),
                onSubtaskToggle: (sid) => _toggleSubtask(_expandedTask!.id, sid),
                onUpdate: (updatedTask) => _updateTaskContent(updatedTask),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassSection(BuildContext context, String title, List<Task> tasks, SettingsService settings, bool isDone, double top, double bottom) {
    const int visibleLimit = 4;
    int itemCount = (_isListExpanded || isDone) ? tasks.length : (tasks.length > visibleLimit ? visibleLimit : tasks.length);

    final List<Task> allUrgent = _getUrgentTasks(_tasks); 
    final List<Task> finalUrgentList = _selectedCategory == 'All' ? allUrgent : allUrgent.where((t) => t.category == _selectedCategory).toList();
    final bool isDark = settings.isDarkMode;
    final Color themeColor = _getThemeColor(settings.themeColor);

    return RepaintBoundary(
      child: Container(
        alignment: Alignment.topCenter,
        margin: EdgeInsets.only(top: top, bottom: bottom, left: 16, right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18), blurRadius: 40, offset: const Offset(0, 15), spreadRadius: -5)
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: isDark ? const Color(0xFF1E293B) : Colors.white)),
              Positioned.fill(child: ColoredBox(color: themeColor.withValues(alpha: isDark ? 0.18 : 0.10))),
              Column(
                children: [
                  const SizedBox(height: 50),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B))),
                        if (!isDone) 
                          IconButton(
                            icon: Icon(_isListExpanded ? Icons.expand_less : Icons.add, color: Colors.indigo),
                            onPressed: _isListExpanded ? () => setState(() => _isListExpanded = false) : () => _showAddTaskModal(context),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)),
                            child: Text("${tasks.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          )
                      ],
                    ),
                  ),
                  if (!isDone && finalUrgentList.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt, color: Colors.orange, size: 18),
                          const SizedBox(width: 4),
                          Text("URGENT", style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1)),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: finalUrgentList.length,
                        itemBuilder: (context, index) {
                          final task = finalUrgentList[index];
                          return GestureDetector(
                            onTap: () => setState(() => _expandedTask = task),
                            child: Container(
                              width: 170, margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                                  const SizedBox(height: 4),
                                  Text(task.dueDate, style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(indent: 24, endIndent: 24),
                  ],
                  Expanded(
                    child: tasks.isEmpty 
                      ? Center(child: Text(isDone ? "No completed tasks" : "Empty", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), 
                          physics: const BouncingScrollPhysics(),
                          itemCount: itemCount,
                          itemBuilder: (c, i) {
                            final task = tasks[i];
                            bool isPile = !_isListExpanded && !isDone && i == visibleLimit - 1 && tasks.length > visibleLimit;
                            if (isPile) return _buildStackPile(task, settings, tasks.length - visibleLimit + 1);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16), 
                              child: VisualTaskCard(
                                task: task, themeColor: settings.themeColor,
                                overrideColor: _getCardColor(i, isDark), 
                                overrideBandColor: _getBandColor(_getCardColor(i, isDark), isDark),
                                onToggle: () => _toggleTask(task.id),
                                onDelete: () => _deleteTask(task.id),
                                onTap: () => setState(() => _expandedTask = task),
                                onLongPress: () {}, 
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStackPile(Task task, SettingsService settings, int remainingCount) {
    final bool isDark = settings.isDarkMode;
    Widget buildGenericCard(double scale, double offset) {
      return Transform.translate(
        offset: Offset(0, offset),
        child: Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            widthFactor: scale, 
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.1)),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _isListExpanded = true),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20), height: 140, 
        child: Stack(
          children: [
            buildGenericCard(0.85, 30),
            buildGenericCard(0.92, 15),
            buildGenericCard(1.0, 0),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers, size: 24, color: isDark ? Colors.white70 : Colors.indigo),
                  const SizedBox(height: 8),
                  Text("+$remainingCount More Tasks", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                  Text("Tap to expand", style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

 // --- UPDATED: Themed Icon Button (Calendar) ---
 Widget _buildIconButton(IconData icon, VoidCallback onTap, Color themeColor) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color contentColor = isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1E293B);

  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44, // FORCED SYNC: Matches Login Button
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 12, offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            // Removed padding: Center handles the alignment
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
              border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 2.0),
            ),
            child: Center(child: Icon(icon, size: 22, color: contentColor)), 
          ),
        ),
      ),
    ),
  );
}

  Color _getThemeColor(String theme) {
    switch (theme.toLowerCase()) {
      case 'emerald': return const Color(0xFF047857);
      case 'rose':    return const Color(0xFFBE123C);
      case 'cyan':    return const Color(0xFF0E7490);
      default:        return const Color(0xFF4338CA); 
    }
  }
  // --- UPDATED: Themed Header Button (Settings/Title) ---
  Widget _buildHeaderButton(IconData icon, String label, VoidCallback onTap, bool isDark, Color themeColor) {
  final Color contentColor = isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1E293B);

  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44, // FORCED SYNC: Matches Login Button height
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 15, offset: const Offset(0, 5),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16), // Adjusted for 44 height
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 2.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: contentColor), 
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15, // Slightly smaller for 44 height
                    color: contentColor, letterSpacing: 0.5,
                  )
                )
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
