import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/seed/seed_ids.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';
import 'package:spendsense/features/receipts/domain/repositories/receipt_scan_repository.dart';

class ReceiptScanException implements Exception {
  const ReceiptScanException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads a receipt photo with Gemini vision and returns structured data.
/// Mirrors HttpAiAssistantRepository: the call goes through the SpendSense
/// API so the Gemini key stays on the server rather than inside the APK.
class HttpReceiptScanRepository implements ReceiptScanRepository {
  HttpReceiptScanRepository({
    required ApiClient client,
    required this.loadCategories,
    required this.loadReceipts,
  }) : _api = client;

  /// Resolved per scan so the model can only ever suggest a category id that
  /// actually exists right now, rather than inventing one.
  final Future<List<Category>> Function() loadCategories;

  /// Used for local duplicate detection — the model never sees these.
  final Future<List<Receipt>> Function() loadReceipts;

  final ApiClient _api;

  @override
  Future<ReceiptScanResult> scan(String imagePath) async {
    final bytes = await _readImage(imagePath);

    final categories = await loadCategories();
    // Savings is reserved for goal contributions — nothing bought at a shop
    // belongs in it, so it never goes on the menu the model picks from.
    final expenseCategories =
        categories.where((c) => c.type != CategoryType.income && c.id != SeedIds.catSavings).toList();
    final categoryLines = expenseCategories.map((c) => '- ${c.id} → ${c.name}').join('\n');
    final allowedIds = expenseCategories.map((c) => c.id).toList();

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt(categoryLines)},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'inlineData': {'mimeType': _mimeTypeFor(imagePath), 'data': base64Encode(bytes)},
            },
            {'text': 'Extract this receipt.'},
          ],
        },
      ],
      // Guaranteed-parseable JSON instead of regex-scraping prose.
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 2048,
        'thinkingConfig': {'thinkingBudget': 512},
        'responseMimeType': 'application/json',
        'responseSchema': _responseSchema(allowedIds),
      },
    });

    final decoded = await _postWithRetry(body);
    final text = _textOf(decoded);
    if (text == null || text.trim().isEmpty) {
      throw const ReceiptScanException("Couldn't read that receipt. Try again with better lighting.");
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      developer.log('Receipt JSON parse failed', error: e, stackTrace: stackTrace, name: 'ReceiptScan');
      throw const ReceiptScanException("Couldn't read that receipt. Please try again.");
    }

    if (json['is_receipt'] == false) {
      throw const ReceiptScanException("That doesn't look like a receipt. Point the camera at a receipt and try again.");
    }

    return _toResult(json, allowedIds, await loadReceipts());
  }

  Future<List<int>> _readImage(String imagePath) async {
    try {
      return await File(imagePath).readAsBytes();
    } catch (e, stackTrace) {
      developer.log('Receipt image read failed', error: e, stackTrace: stackTrace, name: 'ReceiptScan');
      throw const ReceiptScanException("Couldn't open that photo. Please take the picture again.");
    }
  }

  ReceiptScanResult _toResult(Map<String, dynamic> json, List<String> allowedIds, List<Receipt> existingReceipts) {
    final items = <ReceiptItem>[
      for (final raw in (json['items'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>)
          ReceiptItem(
            name: (raw['name'] as String?)?.trim().isNotEmpty == true ? (raw['name'] as String).trim() : 'Item',
            qty: _asInt(raw['qty']) ?? 1,
            price: Money(_asMinorUnits(raw['price']) ?? 0),
          ),
    ];

    final total = Money(_asMinorUnits(json['total']) ?? 0);
    // Receipts often omit an explicit subtotal; fall back to the total so the
    // review screen never shows a nonsensical ₱0.00 subtotal against a real total.
    final subtotal = Money(_asMinorUnits(json['subtotal']) ?? total.minorUnits);
    final date = _parseDate(json['date']);

    final suggested = json['suggested_category_id'] as String?;
    final categoryId = (suggested != null && allowedIds.contains(suggested)) ? suggested : SeedIds.catOther;

    final merchant = (json['merchant'] as String?)?.trim();

    return ReceiptScanResult(
      merchant: merchant?.isNotEmpty == true ? merchant! : 'Unknown merchant',
      date: date,
      items: items,
      subtotal: subtotal,
      tax: Money(_asMinorUnits(json['tax']) ?? 0),
      discount: Money(_asMinorUnits(json['discount']) ?? 0),
      total: total,
      suggestedCategoryId: categoryId,
      confidence: (_asDouble(json['confidence']) ?? 0.0).clamp(0.0, 1.0),
      qualityIssue: _qualityIssueFrom(json['quality_issue']),
      duplicateOfReceiptId: _findDuplicate(merchant, total, date, existingReceipts)?.id,
    );
  }

  static ReceiptQualityIssue _qualityIssueFrom(Object? v) {
    return switch (v) {
      'blurry' => ReceiptQualityIssue.blurry,
      'cropped' => ReceiptQualityIssue.cropped,
      'glare' => ReceiptQualityIssue.glare,
      'too_dark' => ReceiptQualityIssue.tooDark,
      'unreadable' => ReceiptQualityIssue.unreadable,
      _ => ReceiptQualityIssue.none,
    };
  }

  /// Same merchant + same total within a 3-day window is almost always the
  /// user scanning a receipt they already saved.
  Receipt? _findDuplicate(String? merchant, Money total, DateTime date, List<Receipt> existingReceipts) {
    if (merchant == null || merchant.isEmpty || total.minorUnits == 0) return null;
    final needle = merchant.toLowerCase().trim();
    for (final r in existingReceipts) {
      if (r.total.minorUnits != total.minorUnits) continue;
      if (r.merchant.toLowerCase().trim() != needle) continue;
      if (r.date.difference(date).abs() <= const Duration(days: 3)) return r;
    }
    return null;
  }

  DateTime _parseDate(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(raw.trim());
      // A receipt dated in the future is a misread, not a real date.
      if (parsed != null && !parsed.isAfter(DateTime.now().add(const Duration(days: 1)))) return parsed;
    }
    return DateTime.now();
  }

  static int? _asInt(Object? v) => v is num ? v.round() : (v is String ? int.tryParse(v) : null);
  static double? _asDouble(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  /// The schema asks for major units (pesos) since that's what's printed on
  /// the receipt; Money stores minor units.
  static int? _asMinorUnits(Object? v) {
    final major = _asDouble(v);
    return major == null ? null : (major * 100).round();
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  String _systemPrompt(String categoryLines) {
    return '''
You extract structured data from photos of receipts. You are precise and never invent values.

Rules:
- Read only what is actually printed on the receipt. If a field is not printed, omit it rather than guessing.
- All money values are in MAJOR units (e.g. 160.50 means one hundred sixty pesos and fifty centavos). Never include a currency symbol.
- "total" is the final amount actually paid, after tax and discounts. This is the most important field — get it exactly right.
- If the receipt shows no separate subtotal, omit "subtotal". If there is no tax or discount, use 0.
- "date" must be ISO-8601 (YYYY-MM-DD), read from the receipt. If no date is printed, omit it.
- Line items: transcribe the printed item names as-is. "price" is the LINE total for that item (qty x unit price), not the unit price.
- "confidence" is your honest 0.0-1.0 confidence that you read the TOTAL correctly. Be strict and never inflate it. Use below 0.9 whenever you had to guess at any digit, whenever the total is partially obscured, or whenever you are reconstructing a number you cannot fully see. Only report 0.9 or above when every digit of the total is clearly legible.
- "quality_issue" reports what is wrong with the photo, if anything:
  - "blurry" — out of focus or motion-blurred text
  - "cropped" — part of the receipt (especially the total) is cut off by the frame
  - "glare" — reflections or bright spots hiding text
  - "too_dark" — underexposed and hard to read
  - "unreadable" — legible as an image but the text cannot be made out
  - "none" — the photo is clean and fully readable
  Report the issue even if you managed to guess the values anyway. A user would rather retake a photo than save a wrong amount.
- If the image is not a receipt at all (a person, a screenshot, a random object), set "is_receipt" to false and leave the other fields empty.

Pick "suggested_category_id" from EXACTLY this list — never invent an id:
$categoryLines

Choose the category that best matches what was actually bought. If nothing fits, use ${SeedIds.catOther}.
''';
  }

  Map<String, dynamic> _responseSchema(List<String> allowedIds) {
    return {
      'type': 'OBJECT',
      'properties': {
        'is_receipt': {'type': 'BOOLEAN', 'description': 'False if the image is not a receipt.'},
        'merchant': {'type': 'STRING', 'description': 'Store or business name printed on the receipt.'},
        'date': {'type': 'STRING', 'description': 'Receipt date as YYYY-MM-DD.'},
        'items': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'name': {'type': 'STRING'},
              'qty': {'type': 'INTEGER'},
              'price': {'type': 'NUMBER', 'description': 'Line total in major units.'},
            },
            'required': ['name', 'qty', 'price'],
          },
        },
        'subtotal': {'type': 'NUMBER', 'description': 'Pre-tax subtotal in major units, if printed.'},
        'tax': {'type': 'NUMBER', 'description': 'Tax in major units, 0 if none.'},
        'discount': {'type': 'NUMBER', 'description': 'Discount in major units, 0 if none.'},
        'total': {'type': 'NUMBER', 'description': 'Final amount paid, in major units.'},
        'suggested_category_id': {'type': 'STRING', 'enum': allowedIds},
        'confidence': {'type': 'NUMBER', 'description': 'Honest 0.0-1.0 confidence that the total was read correctly.'},
        'quality_issue': {
          'type': 'STRING',
          'enum': ['none', 'blurry', 'cropped', 'glare', 'too_dark', 'unreadable'],
          'description': 'What is wrong with the photo, or "none".',
        },
      },
      'required': ['is_receipt', 'merchant', 'total', 'suggested_category_id', 'confidence', 'quality_issue'],
    };
  }

  String? _textOf(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null) return null;
    for (final part in parts) {
      if (part is Map<String, dynamic> && part['text'] is String) return part['text'] as String;
    }
    return null;
  }

  Future<Map<String, dynamic>> _postWithRetry(String body) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final decoded = await _api.post('/ai/generate', jsonDecode(body) as Map<String, dynamic>);
        return decoded as Map<String, dynamic>;
      } on ApiException catch (e) {
        final status = e.statusCode ?? 0;
        final transient = status == 429 || status >= 500;
        if (transient && attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 900));
          continue;
        }
        developer.log('Receipt scan failed (${e.statusCode}): ${e.message}', name: 'ReceiptScan');
        throw ReceiptScanException(_friendlyErrorFor(status));
      }
    }
    throw const ReceiptScanException('The scanner is not working right now. Please try again in a moment.');
  }

  String _friendlyErrorFor(int statusCode) {
    return switch (statusCode) {
      400 => "Couldn't read that photo. Try a clearer picture of the receipt.",
      401 || 403 => 'The scanner is not configured correctly. Please check the API key.',
      404 => 'The scanner model is unavailable. Please try again later.',
      429 => "You've hit today's scan limit. Please try again later.",
      _ => 'The scanner is not working right now. Please try again in a moment.',
    };
  }
}
