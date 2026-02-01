  import 'dart:convert';
  import 'package:uuid/uuid.dart';
  import '../models/task_model.dart';
  import 'natural_language_parser.dart'; 
  import 'dart:io';
  import '../utils/logger.dart'; // This connects the 'L' to its definition
  import 'package:firebase_ai/firebase_ai.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';

  
  

  class GeminiService {
    static Future<int> _fetchDailyLimit() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();

      if (doc.exists && doc.data() != null) {
        // Fetch the cloud-controlled limit
        return doc.data()!['daily_token_limit'] as int;
      }
      return 50000; // Fallback default
    } catch (e) {
      L.d("🚨 S.INC Config Error: $e");
      return 50000; // Safety fallback
    }
  }
   static final GenerativeModel _model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.0-flash',
    // 🔥 YOUR SYSTEM INSTRUCTIONS GO HERE:
    systemInstruction: Content.system(
      "You are the S.INC Master Architect. "
      "CRITICAL RULE: If the user asks for recommendations, places, books, or facts, "
      "DO NOT give generic process steps (e.g., '1. Research', '2. Filter'). "
      "Instead, provide the ACTUAL items as subtasks (e.g. restaurant names such as, "
      "'1. Brindavan Vegetarian hotel', '2. Paragon Biryani'). "
      "Each subtask must be a specific, actionable choice the user can check off. "
      "Maintain the 8-10 step limit by selecting only the best recommendations."
    ),
  );

  static String? _lastRequestHash;
  static int _globalRequestCounter = 0;
  static DateTime? _lastRequestTime;


  static Future<Task> analyzeTask(
  dynamic input, 
  double creativity, {
  Task? preParsedTask, 
  required bool isBetaApproved,
}) async {
  final int currentId = ++_globalRequestCounter;
  final now = DateTime.now();
  final String currentRequestHash = input.toString() + creativity.toString();
  final user = FirebaseAuth.instance.currentUser; // 🔥 Need this for the wallet

 
  // 1. ROUTING & BETA GATE (The S.Inc Logic)
  // If it's a voice file, we strictly check for Beta status.
  if (input is File && !isBetaApproved) {
    L.d("🛡️ S.INC: Voice-to-AI blocked (Non-Beta). Triggering UI Fallback.");
    throw Exception("VOICE_BETA_REQUIRED");
  }

  // If it's text but they aren't Beta approved, we still block it 
  // because the AI generates the subtasks/roadmaps (the premium feature).
  if (input is String && !isBetaApproved) {
     L.d("🛡️ S.INC: Text-to-Roadmap blocked (Non-Beta).");
     throw Exception("BETA_ACCESS_REQUIRED");
  }

  L.d("📡 [AI CALL #$currentId]: Triggered | Input: ${input is File ? 'Audio' : 'Text'}");

  // 2. THE GHOST GUARD (Keep this to protect your Blaze budget!)
  if (_lastRequestHash == currentRequestHash && 
      _lastRequestTime != null && 
      now.difference(_lastRequestTime!).inSeconds < 5) {
    L.d("🛡️ S.INC: Duplicate request detected.");
    throw Exception("DUPLICATE_REQUEST_IGNORED");
  }
// --- 🔥 NEW: THE PRE-FLIGHT BUDGET AUDIT ---
  if (user != null) {
    // A. Fetch Global Limit from the app_config collection
    final int maxTokens = await _fetchDailyLimit(); 
    
    // B. Check User's Current usage
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    int currentUsage = userDoc.data()?['tokens_used'] ?? 0;

    if (currentUsage >= maxTokens) {
      L.d("🛡️ S.INC: Budget Exhausted ($currentUsage/$maxTokens). Request Denied.");
      throw Exception("DAILY_LIMIT_REACHED");
    }
  }
    _lastRequestHash = currentRequestHash;
    _lastRequestTime = now;

    dynamic sanitizedInput = input;
    if (input is String) {
      sanitizedInput = input.length > 1000 ? input.substring(0, 1000) : input;
      sanitizedInput = sanitizedInput.replaceAll(RegExp(r'ignore (all )?previous instructions', caseSensitive: false), '[REDACTED]');
    }

   
    try {
  L.d("📡 [TEST #$currentId]: Sending via Firebase Secure Proxy...");
// 🔥 FIX: DEFINING THE CONTENT LIST
      final String promptText = _buildSecureTaskPrompt(sanitizedInput.toString(), creativity, preParsedTask: preParsedTask);
      final List<Content> content = [];

      if (sanitizedInput is File) {
        final bytes = await sanitizedInput.readAsBytes();
        content.add(Content.multi([
          InlineDataPart('audio/aac', bytes), // This is correct for the Developer backend
          TextPart(promptText),
        ]));
      } else {
        content.add(Content.text(promptText));
      }
  // 1. THE CALL
  // We use the 'content' list we built in the previous step
  final response = await _model.generateContent(
        content,
        generationConfig: GenerationConfig(
          temperature: creativity,
          responseMimeType: "application/json",
        ),
    // Safety settings can be set here if not already set in the model instance
    safetySettings: [
  // S.INC: 3 arguments for the compiler, but 'null' for the backend
  SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high, null),
  SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.high, null),
  SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high, null),
  SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high, null),
],
  ).timeout(const Duration(seconds: 20)); // Increased slightly for audio files

  // 6. THE ACCOUNTANT (Upgraded to Bulletproof 'Set')
   // 📊 6. THE ACCOUNTANT (Strict Update Logic)
if (response.usageMetadata != null && user != null) {
  int totalUsed = response.usageMetadata!.totalTokenCount ?? 0;
  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  
  try {
    // 🛡️ S.INC SHIELD: No more 'merge'. We only update existing ledgers.
    await userRef.update({
      'tokens_used': FieldValue.increment(totalUsed),
      'last_active': FieldValue.serverTimestamp(),
    });
    
    L.d("📊 S.INC: Wallet updated. Deducted $totalUsed tokens via strict update.");
  } catch (e) {
    // This catches [cloud_firestore/not-found] errors
    L.d("🚨 S.INC ACCOUNTANT ERROR: Profile document missing. Tokens not recorded: $e");
    
    // STRATEGIC CHOICE: We don't 'throw' here. 
    // We let the user see their AI roadmap even if the bank update failed.
  }
}

    // 2. THE RESPONSE
    final String? rawText = response.text;
    L.d("✅ [TEST #$currentId]: Success.");

    if (rawText == null || rawText.isEmpty) throw Exception("EMPTY_AI_RESPONSE");
    
    // 🔥 THE S.INC DEBUG TAP
    L.d("🤖 [AI RAW OUTPUT]:\n$rawText"); 
    return _parseAiResponse(rawText, input is String ? input : "Audio Task");

  } catch (e) {
    L.d("🛠️ [TEST #$currentId]: Request aborted with error: $e");
    
    // 3. THE 429 "IP PENALTY" REPLACEMENT
    if (e.toString().contains('resource-exhausted') || e.toString().contains('429')) {
      _lastRequestTime = DateTime.now().add(const Duration(seconds: 60));
      L.d("🚨 S.INC: RATE_LIMIT detected. Penalty Lock engaged.");
      throw Exception("AI_BUSY_RETRY_LATER");
    }
    
    // Catch the specific Daily Limit exception if thrown from our pre-flight check
    if (e.toString().contains("DAILY_LIMIT_REACHED")) {
      rethrow; 
    }
    
    rethrow;
  }
}

  // --- HELPERS (Marked STATIC to allow access from analyzeTask) ---
  static String _buildSecureTaskPrompt(String input, double creativity, {Task? preParsedTask}) {
    final now = DateTime.now(); // FIX: Added missing 'now' definition
 final String sanitized = _sanitizeForSecurity(input);
  // 🔥 THE HANDSHAKE: Capture the actual digital value from the King (Parser)
  final String localIsoDate = preParsedTask?.exactDate?.toIso8601String() ?? "NULL";
  final bool localHasTime = preParsedTask?.hasSpecificTime ?? false;

  // 1. DEPTH SCALE
  // Instead of limiting steps, we define the "Depth" of the logic.
  String depthInstruction = creativity <= 0.4 
      ? "Provide 5-8 essential, high-level milestones." 
      : "Provide 8-10 granular, sequential steps. Be exhaustive.";

  return """
    
    [GOAL]
    Take the user's input and expand it into a comprehensive project blueprint or
    Extract specific recommendations and format them as an actionable checklist.

    [FEW-SHOT EXAMPLE]
    User: "Best books on history"
    AI: {
      "title": "History Reading List",
      "subtasks": [
        {"title": "Sapiens by Yuval Noah Harari", "notes": "A brief history of humankind."},
        {"title": "Guns, Germs, and Steel", "notes": "Why some civilizations thrived."}
      ]
    }
    
    [PHASE 1: ROADMAP GENERATION]
    - Identify the sequence required to complete this goal.
    - GOVERNANCE: $depthInstruction
    - For professional/educational goals (e.g., "Data Analytics Course"), provide a syllabus-style roadmap.
    - Each subtask must be a JSON object: {"title": "Step Name", "notes": "Context or Tip"}.

    [PHASE 2: CATEGORY & PRIORITY]
    - Assign "Work", "Personal", "Shopping", or "General".

    [PHASE 2: DATE GOVERNANCE (THE LAW)]
    - Today's Date: ${now.year}-${now.month}-${now.day}
    - LOCAL TRUTH: $localIsoDate (Specific Time: $localHasTime)
    
    - RULE 1: If LOCAL TRUTH is not "NULL", you MUST use it. Copy $localIsoDate exactly into "exactDate".
    - RULE 2: If LOCAL TRUTH is "NULL", only generate an "exactDate" if the user explicitly mentions a time or date (e.g., "end of the month", "at 5pm"). 
    - RULE 3: If no date/time is mentioned, "exactDate" MUST be null. NEVER hallucinate a date.
    - RULE 4: All "exactDate" values must be valid ISO8601 strings.

    [USER INPUT]
    "$sanitized"

    [STRICT JSON OUTPUT]
    Return ONLY raw JSON.
    {
      "title": "Refined Name",
      "priority": "High/Medium/Low",
      "category": "Work/Personal/Shopping/General",
      "dueDate": "Preserve local or suggest (only if the user input appears to have one)",
      "exactDate": "ISO8601 string or null",
      "hasSpecificTime": true/false,
      "subtasks": []
    }
  """;
}

  static Task _parseAiResponse(String rawText, String originalInput) {
    // 🔥 THE S.INC BLACK BOX LOG
  try {
    // 1. SECURE EXTRACTION (Handles markdown fences if AI ignores instructions)
    final int start = rawText.indexOf('{');
    final int end = rawText.lastIndexOf('}');
    if (start == -1) throw const FormatException("Invalid JSON");
    final json = jsonDecode(rawText.substring(start, end + 1));

    // 2. ROBUST SUBTASK MAPPING
    List<SubTask> subtasks = [];
    if (json['subtasks'] != null && json['subtasks'] is List) {
      for (var t in json['subtasks']) {
        String title = "";
        if (t is Map) {
          title = t['title']?.toString() ?? t['task']?.toString() ?? "Step";
        } else {
          title = t.toString();
        }
        
        subtasks.add(SubTask(
          id: const Uuid().v4(), 
          title: title, 
          isCompleted: false
        ));
      }
    }

    // 3. DATE RECONCILIATION
    DateTime? exact;
if (json['exactDate'] != null && json['exactDate'] != "null" && json['exactDate'] != "NULL") {
  exact = DateTime.tryParse(json['exactDate'].toString());
}

    return Task(
      id: const Uuid().v4(),
      title: json['title'] ?? originalInput,
      priority: json['priority'] ?? 'Medium',
      category: json['category'] ?? 'General',
      dueDate: json['dueDate'] ?? "",
      exactDate: exact,
      hasSpecificTime: json['hasSpecificTime'] ?? false,
      isCompleted: false,
      subtasks: subtasks,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isAiGenerated: true,
    );
  } catch (e) {
    L.d("🚨 S.INC PARSE ERROR: $e");
    // This is the safety net if the AI response is truly broken
    return NaturalLanguageParser.parse(originalInput);
  }
}


  // --- LAYER 3: SECURITY SHIELD ---
  // This remains essential to prevent "Prompt Injection" attacks.
  static String _sanitizeForSecurity(String input) {
    String sanitized = input;

    // 1. Remove common injection markers to protect the Master Architect persona
    final List<String> forbiddenPatterns = [
      "you are now", "acting as", "new rules", 
      "forget everything", "stop being", "payload"
    ];

    for (var pattern in forbiddenPatterns) {
      sanitized = sanitized.replaceAll(RegExp(pattern, caseSensitive: false), '[SECURE]');
    }

    // 2. The "Markdown Fence" Guard
    // Prevents users from trying to close your JSON string early by replacing double quotes
    sanitized = sanitized.replaceAll('"', "'"); 
    
    return sanitized;
  }
}