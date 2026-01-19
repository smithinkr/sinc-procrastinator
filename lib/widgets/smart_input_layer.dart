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

class SmartInputLayer extends StatefulWidget {
  final List<Task> allTasks;
  final Function(dynamic) onTaskCreated;
  final bool isVisible;
  const SmartInputLayer({
    super.key, 
    required this.allTasks,
    required this.onTaskCreated,
    this.isVisible = false,
  });

  

  @override
  State<SmartInputLayer> createState() => SmartInputLayerState();
}

class SmartInputLayerState extends State<SmartInputLayer> with TickerProviderStateMixin {
  final CustomTextController _textController = CustomTextController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder(); 
  final FocusNode _focusNode = FocusNode();
  
  File? _recordedFile;
  bool _isListening = false;
  bool _isInputActive = false;
  bool _showHint = true;
  bool _showSlogan = true; // S.INC Brand state

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHint = false);
    });

    Timer(const Duration(seconds: 4), () {
    if (mounted) setState(() => _showSlogan = false);
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
        widget.onTaskCreated(_recordedFile!);
        _textController.clear();
      }
    } else {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted && _textController.text.isNotEmpty) {
        widget.onTaskCreated(_textController.text);
        _textController.clear();
      }
    }
  }

  void _submitTask() {
    if (_textController.text.trim().isNotEmpty) {
      widget.onTaskCreated(_textController.text);
      _textController.clear();
      if (mounted) {
        setState(() => _isInputActive = false);
        FocusScope.of(context).unfocus();
      }
    }
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
    if (_textController.text.isEmpty) {
      setState(() => _isInputActive = false);
    }
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // Capture keyboard height to push the UI up
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final todayTasks = _getTodayTasks(widget.allTasks);
    final settings = Provider.of<SettingsService>(context); 

  

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
      child: Column(
        children: [
          // 1. TASK AT-A-GLANCE (Scrollable Container)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.30, 
            child: GestureDetector(
              onHorizontalDragStart: (_) {}, // Pass horizontal swipes to PageView
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    if (todayTasks.isNotEmpty) ...[
                      Text(
                        "TODAY",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 5.0,
                          color: isDarkMode 
                              ? Colors.white.withValues(alpha: 0.2) 
                              : Colors.black.withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ...todayTasks.map((task) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 40),
                        child: Text(
                          task.title.toLowerCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w200,
                            color: isDarkMode 
                                ? Colors.white.withValues(alpha: 0.4) 
                                : Colors.black.withValues(alpha: 0.25),
                            letterSpacing: 1.2,
                          ),
                        ),
                      )),
                    ] else
                       const SizedBox(height: 50), 
                  ],
                ),
              ),
            ),
          ),

          // 2. THE GAP (Now correctly inside the children list)
          AnimatedOpacity(
            opacity: (_showSlogan && !_isInputActive) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 800),
            child: const SizedBox(height: 40),
          ),

          // 3. THE SLOGAN (Now correctly inside the children list)
          AnimatedOpacity(
            opacity: (_showSlogan && !_isInputActive) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 800), // Smooth fade out
            child: _showSlogan 
              ? Text(
                  "let's procrastinate in style",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    color: isDarkMode 
                        ? Colors.white.withValues(alpha: 0.2) 
                        : Colors.black.withValues(alpha: 0.12),
                    letterSpacing: 2.5,
                  ),
                )
              : const SizedBox.shrink(),
          ),
        ], // <--- FIXED: Closes the children list
      ), // <--- FIXED: Closes the Column
    ),
  ),
        // Background Dimmer
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

        

        // Polished Input Box (now keyboard-aware)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          // When keyboard is up, we move the box higher to maintain visibility
          bottom: _isInputActive ? (keyboardHeight > 0 ? keyboardHeight + 20 : 150) : 300,
          left: 24, right: 24,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _isInputActive ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_isInputActive,
              child: Container(
                padding: const EdgeInsets.all(20),
                height: 150,
                decoration: BoxDecoration(
                  color: isDarkMode 
    ? const Color(0xFF1E1E1E).withValues(alpha: 0.9) 
    : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: isDarkMode ? Colors.white10 : Colors.black12),
                  boxShadow: [
                    BoxShadow(
                      color: isDarkMode ? Colors.black45 : Colors.black12, 
                      blurRadius: 40, 
                      offset: const Offset(0, 15)
                    )
                  ],
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(fontSize: 18, color: isDarkMode ? Colors.white : Colors.black87),
                  decoration: const InputDecoration(
                    hintText: "What do you need to do?",
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _submitTask(),
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