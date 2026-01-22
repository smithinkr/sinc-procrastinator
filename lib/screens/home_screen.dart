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
    int _aiCooldownSeconds = 0;
    Timer? _cooldownTimer;
    Timer? _deleteDebounceTimer;
    

    double _drawerDragOffset = 0.0;
    final double _maxDrawerWidth = 140.0;
    String _selectedCategory = 'All';
    String? _currentUid; // Track the current user ID

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
        if (user?.uid != _currentUid) {
      _currentUid = user?.uid; 
      if (mounted) {
        L.d("☁️ S.INC: Identity Changed to ${user?.email}. Refreshing Ledger...");
        _loadData(); 
      }
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
      _cooldownTimer?.cancel();
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

    }

    /// Helper to refresh the UI safely
    void _updateUI(List<Task> tasks) {
      if (!mounted) return;
      setState(() {
        _tasks.clear();
        _tasks.addAll(tasks);
      });
    }
    

Widget _buildModalRow(IconData icon, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

    

   // 1. Add this variable at the top of your _HomeScreenState class
bool _isSyncing = false;

void _saveData({SettingsService? settings, ScaffoldMessengerState? messenger}) async {
  if (_isSyncing) return;

  // 1. CAPTURE & RECONCILE
  final effectiveSettings = settings ?? (mounted ? Provider.of<SettingsService>(context, listen: false) : null);
  
  if (effectiveSettings == null) {
    L.d("⚠️ S.INC: Save aborted - Widget unmounted before capture.");
    return;
  }

  _isSyncing = true; 

  try {
    final List<Task> taskSnapshot = List.from(_tasks); 
    final currentUser = FirebaseAuth.instance.currentUser;

    // 2. LOCAL VAULT (Prioritized)
    await StorageService.saveTasks(taskSnapshot);
    
    // 3. CLOUD SYNC (Silent Handshake)
    if (currentUser != null) {
      try {
        await SyncService().syncTasksToCloud(taskSnapshot);
        // 🔥 NO setState here. No SnackBar here. 
        // This prevents the "jerk" and breaks the infinite loop.
        L.d("☁️ S.INC: Cloud Ledger Updated Silently.");
      } catch (e) {
        L.d("🚨 S.INC Cloud Error: $e");
        // We only show feedback on ACTUAL errors
        if (mounted) {
          messenger?.showSnackBar(
            const SnackBar(content: Text("Sync delayed - saved locally")),
          );
        }
      }
    }

    // 4. BACKGROUND HUD RECONCILIATION
    _updateBackgroundHUD(taskSnapshot, effectiveSettings);

  } finally {
    _isSyncing = false;
  }
}

// Private helper to handle non-UI background tasks
void _updateBackgroundHUD(List<Task> tasks, SettingsService settings) async {
  try {
    final urgentTasks = _getUrgentTasks(tasks).where((t) => !t.isCompleted).toList();
    String widgetContent = urgentTasks.isEmpty 
        ? "List clear. Take a breath." 
        : urgentTasks.take(3).map((t) => "• ${t.title.toLowerCase()}").join("\n");

    await HomeWidget.saveWidgetData<String>('headline_description', widgetContent);
    await HomeWidget.updateWidget(
      name: 'ProcrastinatorWidgetProvider',
      androidName: 'ProcrastinatorWidgetProvider',
      qualifiedAndroidName: 'com.sinc.procrastinator.ProcrastinatorWidgetProvider',
    );
    
    await NotificationService().updateNotifications(
      allTasks: tasks,
      briefHour: settings.briefHour, 
      briefMinute: settings.briefMinute,
    );
  } catch (e) {
    L.d("🚨 S.INC HUD Error: $e");
  }
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
          // 🔥 Ensure no fixed height or ConstrainedBox wraps this
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20, right: 20, top: 10,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // 🔥 HUGS CONTENT
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  height: 5, width: 40,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
              ),
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

                      // --- FIX: Define newTask here so it's in scope ---
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

                      final Task newTask = Task(
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

   Future<void> _addTask(dynamic input, bool useAi) async {
  // 1. INPUT VALIDATION
  if (input is String && input.trim().isEmpty) return;
  
  // 2. BUSY & COOLDOWN GUARD
  // Blocks if AI is currently thinking OR if we are in the 60s penalty window
  if (_isAiLoading || _aiCooldownSeconds > 0) {
    L.d("🛡️ S.INC: System is Busy or Cooling. Request blocked.");
    HapticFeedback.vibrate(); // A standard "alert" vibration
    return;
  }

  final settings = Provider.of<SettingsService>(context, listen: false);
  final currentUser = FirebaseAuth.instance.currentUser;

  // 3. PRIMARY INTERPRETER (Local Truth)
  // We run this immediately so we have a fallback ready instantly
  Task localTruth = (input is String) 
      ? NaturalLanguageParser.parse(input) 
      : NaturalLanguageParser.parse("Voice Task");
L.d("🔍 S.INC Audit: User: ${currentUser?.email}, AI Enabled: ${settings.isAiEnabled}");
  // 4. THE HARD GATE: LOGGED-IN & ENABLED CHECK
  if (currentUser == null || !settings.isAiEnabled) {
    L.d("🚶 S.INC: AI Bypassed. Manual handling engaged.");
    setState(() {
      _isAiLoading = false;
      _previewTask = localTruth.copyWith(
        dueDate: localTruth.dueDate.isEmpty ? "Go Ahead, Ignore me" : localTruth.dueDate
      );
    });
    return;
  }

  // 5. THE AI BATON PASS
  setState(() {
    _isAiLoading = true;
    _aiCooldownSeconds = 0; // Reset timer for new attempt
  });

  try {
    L.d("📡 S.INC: Requesting AI enrichment...");
    
    // Call the service with localTruth context so AI knows what we've already found
    final Task aiTask = await GeminiService.analyzeTask(
      input,
      settings.aiCreativity,
      preParsedTask: localTruth,
    );

    if (!mounted) return;

    setState(() {
      _isAiLoading = false;

      // --- RECONCILIATION: LOCAL TRUTH PRIORITIZATION ---
      
      // Use Local Due Date if found, otherwise use AI smart-guess (e.g., "End of Jan")
      final String finalDueDate = localTruth.dueDate.isNotEmpty 
          ? localTruth.dueDate 
          : (aiTask.dueDate.isNotEmpty ? aiTask.dueDate : "Go Ahead, Ignore me");

      // Use Local Priority if it's High/Low, otherwise accept AI's category logic
      final String finalPriority = (localTruth.priority != 'Medium') 
          ? localTruth.priority 
          : aiTask.priority;

      // Final merge: AI provides the subtasks/category, Local provides the specific dates
      _previewTask = aiTask.copyWith(
        priority: finalPriority,
        dueDate: finalDueDate,
        exactDate: localTruth.exactDate ?? aiTask.exactDate,
        hasSpecificTime: localTruth.hasSpecificTime || aiTask.hasSpecificTime,
      );
      
      L.d("✅ S.INC: AI Handover Successful. Data reconciled.");
    });

  } catch (e) {
    if (!mounted) return;
    setState(() => _isAiLoading = false);
    
    L.d("🚨 AI CRITICAL ERROR: $e");

    // TRIGGER VISUAL FEEDBACK (The Cooldown Bridge)
    if (e.toString().contains("AI_BUSY_RETRY_LATER")) {
      _startVisualCooldown(60); 
      L.d("⏳ S.INC: Visual Cooldown Triggered.");
    }
    
    HapticFeedback.heavyImpact();
    
    // EMERGENCY FALLBACK: Revert to Local Truth so user progress is never lost
    setState(() {
      _previewTask = localTruth.copyWith(
        dueDate: localTruth.dueDate.isEmpty ? "Go Ahead, Ignore me" : localTruth.dueDate,
      );
    });
  }
}


    void _confirmTask() {
    if (_previewTask == null) return;
    final settings = Provider.of<SettingsService>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);

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
    _saveData(settings: settings, messenger: messenger); 
    
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
    void _startVisualCooldown(int seconds) {
  _cooldownTimer?.cancel();
  setState(() => _aiCooldownSeconds = seconds);
  
  _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (_aiCooldownSeconds > 0) {
      setState(() => _aiCooldownSeconds--);
    } else {
      timer.cancel();
    }
  });
}

   void _deleteTask(String id) {
  // 1. CAPTURE ASSETS
  // We grab these before the UI potentially changes or unmounts
  final settings = Provider.of<SettingsService>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);

  // 2. OPTIMISTIC UI UPDATE
  // This happens instantly. No "jerk" or waiting for the cloud.
  setState(() {
    _tasks.removeWhere((t) => t.id == id);
    _expandedTask = null; // Close the modal if it was open
  });

  // 3. PHYSICAL FEEDBACK
  HapticFeedback.lightImpact(); 

  // 4. DEBOUNCED PERSISTENCE
  // We wait 1.5 seconds before syncing. If you delete another task
  // during this window, the timer resets. This prevents "Rapid Fire" crashes.
  _deleteDebounceTimer?.cancel();
  _deleteDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
    if (mounted) {
      _saveData(settings: settings, messenger: messenger);
      L.d("🗑️ S.INC: Cloud Ledger reconciled after batch deletion.");
    }
  });

  L.d("🗑️ S.INC: Task $id removed from local UI. Sync queued...");
}

    void _toggleSubtask(String taskId, String subtaskId) {
      final settings = Provider.of<SettingsService>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
      setState(() {
        final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex != -1) {
          final subIndex = _tasks[taskIndex].subtasks.indexWhere((s) => s.id == subtaskId);
          if (subIndex != -1) {
            _tasks[taskIndex].subtasks[subIndex].isCompleted = !_tasks[taskIndex].subtasks[subIndex].isCompleted;
            _saveData(settings: settings, messenger: messenger);
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
    // --- 1. THE UNIFIED ENGINE (Surgical Handshake) ---

    
    void _showGlobalIdentityModal(BuildContext context, SettingsService settings) {
  final user = FirebaseAuth.instance.currentUser;

  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7), 
    builder: (context) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: settings.isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // BRANDING HEADER
              Text("S.INC CLOUD GATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.grey[500])),
              const SizedBox(height: 24),

              if (user == null) ...[
                // --- REQUIREMENT 3.1: NOT LOGGED IN ---
                const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text("Data is Local Only", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Text(
                  "Log in to never lose your data and unlock AI features.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.5),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    await SyncService().signInWithGoogle();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.login, size: 16),
                  label: const Text("LOG IN TO UNLOCK"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ] else ...[
                // --- REQUIREMENT 3.2: LOGGED IN ---
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.indigo,
                      child: Text((user.displayName ?? "U")[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.displayName ?? "S.INC Member", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(user.email ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                
                // SYNC STATUS
                _buildModalRow(Icons.sync, "Status", "Cloud Secured"),
                _buildModalRow(Icons.history, "Last Sync", "Just now"),
                
                const SizedBox(height: 24),

                // BETA ACCESS BUTTON (Hides automatically when approved)
                

                // STATUS INDICATOR
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: settings.isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("AI STATUS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text(
                        settings.isBetaApproved ? "ACCEPTED" : "PENDING REVIEW",
                        style: TextStyle(
                          fontSize: 9, 
                          fontWeight: FontWeight.bold, 
                          color: settings.isBetaApproved ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                TextButton(
                  onPressed: () async {
                    await SyncService().signOut();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("LOG OUT", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
    

  // Helper widget for the modal buttons

    // --- SMART IDENTITY HELPERS ---

    Widget _buildSyncProfileButton(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final isDark = settings.isDarkMode;
    final themeColor = _getThemeColor(settings.themeColor);
    
    // Use current Firebase user directly (Provider will trigger a rebuild on changes)
    final user = FirebaseAuth.instance.currentUser;
    final bool isLoggedIn = user != null;
    
    // Get initial or cloud icon
    final String initial = isLoggedIn 
        ? (user.displayName?.isNotEmpty == true ? user.displayName![0].toUpperCase() : "U") 
        : "!";

    final Color contentColor = isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1E293B);

    return GestureDetector(
      onTap: () => _showGlobalIdentityModal(context, settings), // Unified Modal
      child: Container(
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
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.1) 
                    : Colors.black.withValues(alpha: 0.05),
                border: Border.all(
                  // THEME RING: Glows with the theme color only when logged in
                  color: isLoggedIn 
                      ? themeColor.withValues(alpha: 0.8) 
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
                        color: contentColor,
                      ),
                    )
                  : Icon(
                      Icons.cloud_off, 
                      size: 20, 
                      color: contentColor.withValues(alpha: 0.5),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
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

              // --- HEADER ROW (S.INC HUD) ---
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
            // This is your Cloud Sync / Identity Button
            _buildSyncProfileButton(context), 
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
    onTaskCreated: (input, useAi) => _addTask(input, useAi),
    isVisible: false,
    isAiLoading: _isAiLoading, 
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

             // 1. Dark background overlay (Scrim)
if (_previewTask != null || _expandedTask != null)
  Positioned.fill(
    child: GestureDetector(
      onTap: () => setState(() {
        _previewTask = null;
        _expandedTask = null;
      }),
      child: Container(color: Colors.black54), // Dim the background
    ),
  ),

              // 2. The Task Modal (Preview or Expanded)
if (_previewTask != null || _expandedTask != null)
  Align(
    alignment: Alignment.bottomCenter, // 🔥 This forces it to the bottom
    child: TaskDetailModal(
      task: _previewTask ?? _expandedTask!,
      isPreview: _previewTask != null,
      onClose: () => setState(() {
        _previewTask = null;
        _expandedTask = null;
      }),
      onConfirm: _confirmTask,
      onToggle: () => _toggleTask((_previewTask ?? _expandedTask!).id),
      onDelete: () => _deleteTask((_previewTask ?? _expandedTask!).id),
      onSubtaskToggle: (sid) => _toggleSubtask((_previewTask ?? _expandedTask!).id, sid),
      onUpdate: (updatedTask) => _updateTaskContent(updatedTask),
    ),
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
