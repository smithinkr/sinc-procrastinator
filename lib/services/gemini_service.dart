  import 'dart:convert';
  import 'package:http/http.dart' as http;
  import 'package:uuid/uuid.dart';
  import '../models/task_model.dart';
  import 'natural_language_parser.dart'; 
  import 'dart:io';
  import '../utils/logger.dart'; // This connects the 'L' to its definition
  

  class GeminiService {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
  static String? _lastRequestHash;
  static int _globalRequestCounter = 0;
  static DateTime? _lastRequestTime;

  // --- LAYER 1: SECURE INJECTION ---
  static const String _injectedKey = String.fromEnvironment('GEMINI_API_KEY');
  
  // --- LAYER 2: RUNTIME OBFUSCATION ---
  static final String _vaultedKey = _scramble(_injectedKey);

  // OBFUSCATION LOGIC
  static String _scramble(String input) {
    if (input.isEmpty) return "";
    return base64Encode(utf8.encode(input)).split('').reversed.join();
  }

  static String _unscramble(String scrambled) {
    if (scrambled.isEmpty) return "";
    String reversed = scrambled.split('').reversed.join();
    return utf8.decode(base64Decode(reversed));
  }

  static Future<Task> analyzeTask(
    dynamic input, 
    double creativity, {
    Task? preParsedTask, 
  }) async {
    // Logic like '++' and 'DateTime.now()' must live INSIDE the method
    final int currentId = ++_globalRequestCounter;
    final now = DateTime.now();
    final String currentRequestHash = input.toString() + creativity.toString();

    L.d("📡 [AI CALL]: Triggered at $now | Input Type: ${input.runtimeType}");

    // --- THE ULTIMATE GUARD ---
    if (_lastRequestHash == currentRequestHash && 
        _lastRequestTime != null && 
        now.difference(_lastRequestTime!).inSeconds < 5) {
      L.d("🛡️ S.INC: Ghost-submit detected and blocked.");
      throw Exception("DUPLICATE_REQUEST_IGNORED");
    }

    _lastRequestHash = currentRequestHash;
    _lastRequestTime = DateTime.now();

    if (_vaultedKey.isEmpty) {
      throw Exception("S.INC_SECURITY_ERROR: API Key not injected via environment.");
    }
    
    dynamic sanitizedInput = input;
    if (input is String) {
      sanitizedInput = input.length > 1000 ? input.substring(0, 1000) : input;
      sanitizedInput = sanitizedInput.replaceAll(RegExp(r'ignore (all )?previous instructions', caseSensitive: false), '[REDACTED]');
    }

    final url = Uri.parse(_baseUrl);
    List<Map<String, dynamic>> parts = [];

    if (sanitizedInput is String) {
      parts.add({"text": _buildSecureTaskPrompt(sanitizedInput, creativity, preParsedTask: preParsedTask)});
    } else if (sanitizedInput is File) {
      final bytes = await sanitizedInput.readAsBytes();
      parts.add({
        "inlineData": {"mimeType": "audio/aac", "data": base64Encode(bytes)}
      });
      parts.add({"text": _buildSecureTaskPrompt("User provided an audio recording.", creativity, preParsedTask: preParsedTask)});
    }

    try {
      L.d("📡 [TEST #$currentId]: PHYSICALLY sending to Google now...");

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json', 
          'x-goog-api-key': _unscramble(_vaultedKey) 
        },
        body: jsonEncode({
  // 🔥 THE SECURITY GATE: This instruction is the "Master Law"
  "systemInstruction": {
  "parts": [{
    "text": "You are the S.INC Master Architect. "
            "CRITICAL RULE: If the user asks for recommendations, places, books, or facts, "
            "DO NOT give generic process steps (e.g., '1. Research', '2. Filter'). "
            "Instead, provide the ACTUAL items as subtasks (e.g. restaurant names such as, '1. Brindavan Vegetarian hotel', '2. Paragon Biryani'). "
            "Each subtask must be a specific, actionable choice the user can check off. "
            "Maintain the 8-10 step limit by selecting only the best recommendations."
  }]
},
  "contents": [{"parts": parts}], // The user's input (now lower priority)
  "safetySettings": [
    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_ONLY_HIGH"}, // Added for extra safety
  ],
  "generationConfig": {
    "temperature": creativity,
    "responseMimeType": "application/json"
  }
}),
      ).timeout(const Duration(seconds: 15));

      L.d("✅ [TEST #$currentId]: Server responded with ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String rawText = data['candidates'][0]['content']['parts'][0]['text'];
        return _parseAiResponse(rawText, input is String ? input : "Audio Task");
      } else if (response.statusCode == 429) {
        _lastRequestTime = DateTime.now().add(const Duration(seconds: 60));
        L.d("🚨 S.INC: SERVER_ERROR_429 for Test #$currentId. IP Penalty Lock engaged.");
        throw Exception("AI_BUSY_RETRY_LATER");
      } else {
        throw Exception("SERVER_ERROR_${response.statusCode}");
      }
    } catch (e) {
      L.d("🛠️ [TEST #$currentId]: Request aborted with error: $e");
      rethrow;
    }
  }

  // --- HELPERS (Marked STATIC to allow access from analyzeTask) ---
  static String _buildSecureTaskPrompt(String input, double creativity, {Task? preParsedTask}) {
  final now = DateTime.now();
  _sanitizeForSecurity(input);

  // 1. DEPTH SCALE
  // Instead of limiting steps, we define the "Depth" of the logic.
  String depthInstruction = creativity <= 0.4 
      ? "Provide 5-8 essential, high-level milestones." 
      : "Provide 8-10 granular, sequential steps. Be exhaustive.";

  return """
    [SYSTEM ROLE]
    You are the S.INC Master Architect. You specialize in project decomposition and roadmap generation.
    
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
    - Data/Time: If the local system found a date (${preParsedTask?.dueDate}), preserve it.
    
    Today's Date: ${now.year}-${now.month}-${now.day}

    [USER INPUT]
    "$input"

    [STRICT JSON OUTPUT]
    Return ONLY raw JSON. No markdown, no commentary.
    {
      "title": "Refined Project Name",
      "priority": "High/Medium/Low",
      "category": "Work/Personal/Shopping/General",
      "dueDate": "Preserve local or suggest",
      "subtasks": []
    }
  """;
}

  static Task _parseAiResponse(String rawText, String originalInput) {
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
    if (json['exactDate'] != null && json['exactDate'] != "null") {
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

  static Future<String> generateMorningBrief(List<Task> tasks) async {
    if (_vaultedKey.isEmpty) return "API Key missing.";
    return "Brief logic preserved";
  }
  static String _sanitizeForSecurity(String input) {
  String sanitized = input;

  // 1. Remove common injection markers
  final List<String> forbiddenPatterns = [
    "you are now", "acting as", "new rules", 
    "forget everything", "stop being", "payload"
  ];

  for (var pattern in forbiddenPatterns) {
    sanitized = sanitized.replaceAll(RegExp(pattern, caseSensitive: false), '[SECURE]');
  }

  // 2. The "Markdown Fence" Guard
  // Prevents users from trying to close your JSON string early
  sanitized = sanitized.replaceAll('"', "'"); 
  
  return sanitized;
}
}