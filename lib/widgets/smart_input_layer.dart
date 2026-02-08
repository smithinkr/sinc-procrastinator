import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import 'package:procrastinator/widgets/custom_text_controller.dart';
import '../models/task_model.dart';
import 'package:procrastinator/utils/logger.dart';
import '../services/sync_service.dart';
import 'dart:ui'; // 🔥 This enables the BackdropFilter and ImageFilter
//import 'package:firebase_auth/firebase_auth.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';

class SmartInputLayer extends StatefulWidget {
  final List<Task> allTasks;
  final Function(dynamic, bool) onTaskCreated;
  final bool isVisible;
  final bool isAiLoading;
  final bool isDeletionPending; // 👈 ADD THIS
  final Function(DragUpdateDetails) onProxyItemDrag;
  
  const SmartInputLayer({
    super.key, 
    required this.allTasks,
    required this.onTaskCreated,
    this.isVisible = false,
    required this.isAiLoading,
    required this.isDeletionPending, // 👈 ADD THIS
    required this.onProxyItemDrag, // 🔥 Add this
  });

  

  @override
  State<SmartInputLayer> createState() => SmartInputLayerState();
}

class SmartInputLayerState extends State<SmartInputLayer> with TickerProviderStateMixin {
  final CustomTextController _textController = CustomTextController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder(); 
  final FocusNode _focusNode = FocusNode();
  final ScrollController _hudScrollController = ScrollController(); // 🔥 Dedicated HUD Controller
 
  
  
  File? _recordedFile;
  bool _isListening = false;
  bool _isInputActive = false;
  bool _showHint = true;
  
  

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHint = false);
    });

   

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant SmartInputLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      activateInputFromWidget();
    }
  }

  // The definitive widget-to-app transition logic
  void activateInputFromWidget() {
    if (!mounted) return;
    
    setState(() {
      _isInputActive = true;
      _showHint = false;
    });

    // Aggressive Polling: Checks for focus every 250ms
    Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted || !_isInputActive || _focusNode.hasFocus) {
        timer.cancel();
        return;
      }

      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
      
      if (timer.tick >= 4) timer.cancel();
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _speech.stop();
    _textController.dispose();
    _pulseController.dispose();
    _focusNode.dispose();
    _hudScrollController.dispose(); // Clean up
    super.dispose();
  }

  // --- Voice Logic (Unchanged) ---
 Future<void> _startListening() async {
  if (!mounted) return;
  final settings = Provider.of<SettingsService>(context, listen: false);
  
  FocusScope.of(context).unfocus();

  // 1. Check current status
  var status = await Permission.microphone.status;

  if (!status.isGranted) {
    // 2. This triggers the system dialog, which pauses the Flutter lifecycle
    status = await Permission.microphone.request();

    // 3. THE FIX: If the user just dealt with the permission dialog,
    // we must force the UI to NOT be in listening mode, even if they were holding the button.
    if (mounted) setState(() => _isListening = false);

    // If they denied it, or just granted it for the first time, 
    // stop here so they can start a fresh recording on the next tap.
    return; 
  }

  // 4. Actual Recording Logic (Only runs if permission was ALREADY granted)
  if (settings.isAiEnabled) {
    final directory = await getTemporaryDirectory();
    if (!mounted) return; 
    
    final String path = '${directory.path}/ai_input_${DateTime.now().millisecondsSinceEpoch}.m4a';
    
    await _audioRecorder.start(const RecordConfig(), path: path);
    if (mounted) setState(() => _isListening = true);
  } else {
    bool available = await _speech.initialize();
    if (available && mounted) {
      setState(() => _isListening = true);
      _speech.listen(onResult: (val) {
        if (mounted) {
          setState(() {
            _textController.text = val.recognizedWords;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: _textController.text.length),
            );
          });
        }
      });
    }
  }
}

  void _stopListening() async {
    if (!mounted) return;
    final settings = Provider.of<SettingsService>(context, listen: false);
    if (mounted) setState(() => _isListening = false);
    FocusScope.of(context).unfocus();
    if (settings.isAiEnabled) {
      final path = await _audioRecorder.stop();
      if (path != null && mounted) {
        _recordedFile = File(path);
        widget.onTaskCreated(_recordedFile!, true);
        _textController.clear();
      }
    } else {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted && _textController.text.isNotEmpty) {
        widget.onTaskCreated(_textController.text, false);
        _textController.clear();
      }
    }
  }

  void _submitTask() {
  final String text = _textController.text.trim();
  final settings = Provider.of<SettingsService>(context, listen: false);
  
  // 1. THE DEADBOLT (Security Guard)
  // Check widget.isAiLoading to prevent duplicate triggers
  if (text.isEmpty || widget.isAiLoading) return;
  _focusNode.unfocus();
  SystemChannels.textInput.invokeMethod('TextInput.hide');

  // 2. TRIGGER THE AI IMMEDIATELY
  // We do this while the text and widget are still fully "active"
  L.d("📡 S.INC: Handing baton to AI for: $text");
  widget.onTaskCreated(text, settings.isAiEnabled);

  // 3. UI CLEANUP (With a small delay)
  // We wait 100ms to ensure the async 'onTaskCreated' is firmly in the background
  Future.delayed(const Duration(milliseconds: 100), () {
    if (!mounted) return;

    // Disconnect the system focus to stop Autofill loops
    _focusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    
    setState(() {
      _textController.clear();
      _isInputActive = false;
    });
  });
}

  void _activateInputMode() {
    setState(() {
      _isInputActive = true;
      _showHint = false;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

void _closeInputMode() {
    setState(() {
      // We force the input to inactive regardless of text 
      // if we are closing the mode/moving away.
      _isInputActive = false;
    });

    // 1. Remove focus from the current node
    _focusNode.unfocus();

    // 2. Force the FocusScope to a 'neutral' node (The Vacuum Fix)
    FocusScope.of(context).requestFocus(FocusNode());

    // 3. Send a direct command to the Android/iOS system to hide the tray
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // Capture keyboard height to push the UI up
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final todayTasks = _getTodayTasks(widget.allTasks);
    final settings = Provider.of<SettingsService>(context); 
    final bool isKeyboardOpen = keyboardHeight > 0;

  

    return Stack(
      children: [

 // --- Combined Watermark Dashboard & Slogan ---
if (settings.isHudEnabled)
  AnimatedPositioned(
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
    top: MediaQuery.of(context).size.height * 0.20,
    left: 0, right: 0,
    child: AnimatedOpacity(
      opacity: _isInputActive ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Stack( // 👈 START HUD STACK
        alignment: Alignment.center,
        children: [
          
          // 1. THE BACKGROUND GROUP (Tasks + Gap + Slogan)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            opacity: widget.isDeletionPending ? 0.25 : 1.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // TASK AT-A-GLANCE
                SizedBox(
  height: MediaQuery.of(context).size.height * 0.35,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (todayTasks.isNotEmpty) ...[
        // 1. HUD HEADER
        Text(
          "TODAY",
          style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w300, letterSpacing: 5.0,
            color: isDarkMode ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 20),

        // 🔥 THE MASTER FIX: Wrap the task list in IgnorePointer
        // This makes the text "physically transparent" to all gestures.
        IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...todayTasks.take(3).map((task) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
                child: Text(
                  task.title.toLowerCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w200, letterSpacing: 1.2,
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.25),
                  ),
                ),
              )),
              
              if (todayTasks.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    "you have more, click calendar button",
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.normal,
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ] else const SizedBox(height: 50),
    ],
  ),
),
                
              ],
            ),
          ),

          // 2. 🔥 THE LIMBO BANNER (Floating Center)
          if (widget.isDeletionPending)
  ClipRRect(
    borderRadius: BorderRadius.circular(32),
    child: BackdropFilter(
      // 👈 Increase blur to 16 for better separation from the background tasks
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), 
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          // 👈 Darker, more opaque glass makes the Amber text "pop"
          color: isDarkMode 
              ? Colors.black.withValues(alpha: 0.65) 
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.4), 
            width: 1.5
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 👈 Increased icon size for urgency
            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 42),
            const SizedBox(height: 16),
            const Text(
              "APP EUTHANIZATION ACTIVE",
              style: TextStyle(
                color: Colors.amber, 
                fontWeight: FontWeight.w900, // 👈 Extra Bold for readability
                fontSize: 13, 
                letterSpacing: 2.5
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Your tasks' funeral is scheduled at midnight UTC. \nAI Intelligence turned off. \nYou crushed Dev's heart today. We could've talked this out",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.black87, 
                fontSize: 13, 
                height: 1.5,
                fontWeight: FontWeight.w400
              ),
            ),
            const SizedBox(height: 28),
            
            // --- THE REFINED "SOLID STATE" BUTTON ---
            ElevatedButton(
           // --- REPLACE YOUR BUTTON'S onPressed WITH THIS ---
onPressed: () async {
  HapticFeedback.heavyImpact(); 
  
  try {
    // 🛡️ S.INC SHIELD: Service call
    await SyncService().abortAccountDeletion();
    
    // ✅ THE 2026 STANDARD: Check 'context.mounted' directly 
    // to bridge the async gap for the SnackBar below.
    if (!context.mounted) return;

    L.d("🟢 S.INC: Restore Successful.");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Account Restored! Welcome back."),
        behavior: SnackBarBehavior.floating,
      ),
    );

  } catch (e) {
    L.d("🚨 S.INC Restore Failed: $e");
    
    // ✅ Apply the same guard here in the catch block
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Restore failed. Check connection."),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
},
              style: ElevatedButton.styleFrom(
                // 👈 SOLID background for 100% visibility
                backgroundColor: Colors.amber, 
                foregroundColor: Colors.black, // High contrast black text
                elevation: 4,
                shadowColor: Colors.amber.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                minimumSize: const Size(double.infinity, 54),
              ),
              child: const Text(
                "ABORT ERASURE", 
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)
                      ),
            ),
                    ],
                  ),
                ),
              ),
            ),
        ], // 👈 END STACK CHILDREN
      ), // 👈 END STACK
    ),
  ),

// 3. BACKGROUND DIMMER (Outside the HUD)
if (_isInputActive)
  Positioned.fill(
    child: GestureDetector(
      onTap: _closeInputMode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isDarkMode ? Colors.black54 : Colors.black26,
      ),
    ),
  ),
        // --- 4. THE UI STACK (Inside build method) ---
// ✨ THE INTELLIGENCE SWITCH (Island 1)
         AnimatedPositioned(
  duration: const Duration(milliseconds: 200), // Slightly longer for a 'layered' feel
  curve: Curves.easeOutCubic,
            // 🔥 Position 0 keeps it out of the way of your swipe cards when hidden
            bottom: _isInputActive ? (isKeyboardOpen ? keyboardHeight + 200 : 335) : 0,
            left: 24, 
            child: IgnorePointer(
          ignoring: !_isInputActive || widget.isDeletionPending,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isInputActive ? (widget.isDeletionPending ? 0.3 : 1.0) : 0.0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
    // ⚡ THE DIRECT WIRE: Tell the global settings to flip
    settings.toggleAiFeatures(!settings.isAiEnabled); 
    HapticFeedback.heavyImpact();
    L.d("🎚️ S.INC: UI Toggle synced with Global Settings -> ${!settings.isAiEnabled}");
  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      // 🔥 THE 60FPS SECRET:
// When the keyboard is moving (isKeyboardOpen), we drop the blur to 4.
// It still looks glassy, but saves the GPU 60% of the math work.
filter: ImageFilter.blur(
  sigmaX: isKeyboardOpen ? 4 : 12, 
  sigmaY: isKeyboardOpen ? 4 : 12
),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: settings.isAiEnabled 
                              ? Colors.indigo.withValues(alpha: 0.3) 
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: settings.isAiEnabled ? Colors.indigo.withValues(alpha: 0.5) : Colors.white10,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              settings.isAiEnabled ? Icons.toggle_on : Icons.toggle_off_outlined, 
                              size: 18, 
                              color: settings.isAiEnabled ? Colors.indigoAccent : Colors.white38
                            ),
                            const SizedBox(width: 10),
                            Text(
                              settings.isAiEnabled ? "AI ON" : "AI OFF",
                              style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, 
                                color: Colors.white, 
                                letterSpacing: 2.0
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),
         ),
       

        // 📥 THE INPUT BOX (Island 2)
        AnimatedPositioned(
  // 🔥 THE FLUID SECRET: 
  // 150ms is shorter than the keyboard's own 300ms rise.
  // This creates a 'Trailing Elastic' feel without feeling laggy.
  duration: const Duration(milliseconds: 150), 
  
  // easeOutCubic starts fast and slows down gently at the end.
  // This makes the box 'settle' into position.
  curve: Curves.easeOutCubic,
            // 🔥 Moving to bottom 0 ensures no "ghost touches" in the middle of the screen
            bottom: _isInputActive ? (isKeyboardOpen ? keyboardHeight + 20 : 150) : 0,
            left: 24, right: 24,
            child: IgnorePointer( // 🔥 MOVE THE GUARD HERE
    ignoring: !_isInputActive,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _isInputActive ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.all(20),
                height: 150,
                decoration: BoxDecoration(
                  color: isDarkMode 
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.9) 
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: settings.isAiEnabled ? Colors.indigo.withValues(alpha: 0.3) : Colors.white10,
                    width: settings.isAiEnabled ? 2.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: settings.isAiEnabled ? Colors.indigo.withValues(alpha: 0.15) : Colors.black12, 
                      blurRadius: 40, offset: const Offset(0, 15)
                    )
                  ],
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  enableSuggestions: true, 
                  autocorrect: true, 
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(fontSize: 18, color: isDarkMode ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: "What do you need to do?",
                    hintStyle: const TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(
                        settings.isAiEnabled ? Icons.auto_awesome : Icons.send_rounded, 
                        color: Colors.indigo
                      ),
                      onPressed: _submitTask,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Orb UI
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          bottom: (_isInputActive && !_isListening) ? -200 : 100,
          left: 0, right: 0,
          child: Column(
            children: [
              if (_showHint)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text("Hold for voice", style: TextStyle(color: Colors.white38)),
                ),
              if (_isListening)
                 const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      Icon(Icons.graphic_eq, color: Colors.purpleAccent, size: 28),
                      Text("Listening...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              GestureDetector(
                onLongPressStart: (_) => _startListening(),
                onLongPressEnd: (_) => _stopListening(),
                onTap: _activateInputMode,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isListening ? _pulseAnimation.value : 1.0,
                      child: Container(
                        width: 140, height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isListening 
                              ? const LinearGradient(colors: [Colors.cyanAccent, Colors.purpleAccent])
                              : null,
                          color: _isListening ? null : Colors.white.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                              color: _isListening ? Colors.purpleAccent.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.12),
                              blurRadius: _isListening ? 40 : 20,
                            )
                          ],
                        ),
                        child: Center(
                          child: _isListening 
                            ? const Icon(Icons.mic, color: Colors.white, size: 50)
                            : Text(
                                "create", 
                                style: TextStyle(
                                  fontWeight: FontWeight.w700, 
                                  fontSize: 16, 
                                  letterSpacing: 1.5, 
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shadows: [
                                    Shadow(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      offset: const Offset(0.5, 0.5),
                                      blurRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  List<Task> _getTodayTasks(List<Task> allTasks) {
    final now = DateTime.now();
    return allTasks.where((task) {
      if (task.isCompleted) return false;
      
      // Check exactDate safely
      if (task.exactDate != null) {
        return task.exactDate!.year == now.year &&
               task.exactDate!.month == now.month &&
               task.exactDate!.day == now.day;
      }
      
      // Fallback to checking the string
      return task.dueDate.toLowerCase().contains('today');
    }).toList();
  }
}