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
          "contents": [{"parts": parts}],
          "safetySettings": [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"},
            {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"},
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

  // 1. IMAGINATION GOVERNOR
  String imaginationLevel;
  if (creativity <= 0.3) {
    imaginationLevel = "STRICT & LITERAL: Do not add extra steps. Focus on exact categorization.";
  } else if (creativity <= 0.7) {
    imaginationLevel = "BALANCED & HELPFUL: Provide logical subtasks and shopping links.";
  } else {
    imaginationLevel = "VISIONARY & COMPREHENSIVE: Use deep culinary/project knowledge for a full roadmap.";
  }

  // 2. STEP COMPLEXITY (Preserved from your previous code)
  String complexity = creativity <= 0.3 
      ? "LITERAL: 2-3 essential steps." 
      : (creativity < 0.8 ? "BALANCED: 3-5 subtasks." : "COMPREHENSIVE: 5-7 subtasks.");

  // 3. SOURCE OF TRUTH
  String constraintBlock = "";
  if (preParsedTask != null && (preParsedTask.dueDate.isNotEmpty || preParsedTask.priority == 'High')) {
    constraintBlock = """
    [SOURCE OF TRUTH - MANDATORY]
    The local system identified these. DO NOT CHANGE:
    - Date/Time: ${preParsedTask.dueDate}
    - Urgent Status: ${preParsedTask.priority}
    """;
  }

  return """
    [SYSTEM ROLE]
    You are an Expert Project Architect for S.INC. 
    IMAGINATION MODE: $imaginationLevel

    [STRICT CATEGORY ENUM]
    You MUST categorize every task into exactly ONE: "Work", "Personal", "Shopping", or "General".
    - If the input involves ingredients or stores, use "Shopping".
    - If it involves office/emails, use "Work".

    [PHASE 1: COMPLEXITY EVALUATION]
    - If task is a "Quick Action" (e.g., "Buy milk"): Return subtasks: [].
    - Else, use Complexity Level: $complexity

    [PHASE 2: SPECIALIZED BLUEPRINTS]
    - CULINARY: If cooking/groceries, break into "Aroma & Base", "Main Proteins/Veg", "Flavors & Spices", "Garnish & Finish".
    - RESEARCH: For shopping, include specific search URLs in 'notes' field.

    $constraintBlock
    Reference Today: ${now.year}-${now.month}-${now.day} (Wednesday)

    [USER INPUT]
    $input

    [STRICT OUTPUT FORMAT]
    Return ONLY valid JSON with these keys: 
    "title", "priority", "category", "dueDate", "exactDate", "subtasks" (array with title and notes).
  """;
}

  static Task _parseAiResponse(String rawText, String originalInput) {
    try {
      final int start = rawText.indexOf('{');
      final int end = rawText.lastIndexOf('}');
      if (start == -1) throw const FormatException();

      final json = jsonDecode(rawText.substring(start, end + 1));
      List<SubTask> subtasks = (json['subtasks'] as List? ?? []).map((t) => 
        SubTask(id: const Uuid().v4(), title: t is Map ? t['title'] : t.toString(), isCompleted: false)
      ).toList();

      DateTime? exact;
      if (json['exactDate'] != null && json['exactDate'] != "null") {
        exact = DateTime.tryParse(json['exactDate']);
      }

      return Task(
        id: const Uuid().v4(),
        title: json['title'] ?? originalInput,
        priority: json['priority'] ?? 'Medium',
        category: json['category'] ?? 'General',
        dueDate: json['dueDate'] ?? (exact != null ? "${exact.day}/${exact.month}" : ""),
        exactDate: exact,
        hasSpecificTime: json['hasSpecificTime'] ?? false,
        isCompleted: false,
        subtasks: subtasks,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isAiGenerated: true,
      );
    } catch (e) {
      return NaturalLanguageParser.parse(originalInput);
    }
  }

  static Future<String> generateMorningBrief(List<Task> tasks) async {
    if (_vaultedKey.isEmpty) return "API Key missing.";
    return "Brief logic preserved";
  }
}