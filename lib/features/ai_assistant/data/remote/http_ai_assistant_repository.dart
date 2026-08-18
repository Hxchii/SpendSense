import 'dart:convert';

import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_action.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_chat_message.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/financial_snapshot.dart';
import 'package:spendsense/features/ai_assistant/domain/repositories/ai_assistant_repository.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// Reaches Gemini through the SpendSense API rather than calling Google
/// directly, so the API key stays on the server instead of shipping inside
/// the APK where it can be extracted. The prompt and tool schemas stay here,
/// with the backend acting purely as transport.
class HttpAiAssistantRepository implements AiAssistantRepository {
  HttpAiAssistantRepository({required ApiClient client}) : _api = client;

  final ApiClient _api;

  @override
  Future<AiChatResponse> ask({
    required String message,
    required List<AiChatMessage> history,
    required FinancialSnapshot snapshot,
  }) async {
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt(snapshot)},
        ],
      },
      'contents': [
        for (final m in history)
          {
            'role': m.role == ChatRole.user ? 'user' : 'model',
            'parts': [
              {'text': m.content},
            ],
          },
        {
          'role': 'user',
          'parts': [
            {'text': message},
          ],
        },
      ],
      'tools': [
        {'functionDeclarations': _toolDeclarations},
      ],
      // A prior version capped output at 350 tokens; this model spends a large
      // share of that on internal "thinking" before it ever writes the reply,
      // so ambiguous messages were getting cut off mid-generation with no
      // usable text or function call at all. Capping the thinking budget and
      // giving the actual output more room fixes that.
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 1024,
        'thinkingConfig': {'thinkingBudget': 512},
      },
    });

    final decoded = await _postWithRetry(body);
    final parts = _partsOf(decoded);
    if (parts == null || parts.isEmpty) {
      throw const AiAssistantException("Sorry, I didn't understand that. Please try again with simpler words.");
    }

    final call = _findFunctionCall(parts);
    if (call != null) {
      if (call.name == 'ask_clarifying_question') {
        final question = call.args['question'] as String?;
        if (question != null && question.isNotEmpty) {
          final replies = (call.args['quick_replies'] as List<dynamic>?)?.cast<String>() ?? const [];
          return AiChatResponse(reply: question, suggestions: replies);
        }
      } else {
        final proposal = _proposalFromCall(call.name, call.args);
        if (proposal != null) {
          final confirmationMessage = call.args['confirmation_message'] as String? ?? _defaultConfirmation(proposal, snapshot.currencySymbol);
          return AiChatResponse(reply: confirmationMessage, proposal: proposal);
        }
      }
    }

    final text = parts.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '').join().trim();
    if (text.isEmpty) {
      throw const AiAssistantException("Sorry, I didn't understand that. Please try again with simpler words.");
    }
    return AiChatResponse(reply: text);
  }

  Future<Map<String, dynamic>> _postWithRetry(String body) async {
    // Gemini's hosted models occasionally return transient 429/5xx under
    // load; one short retry clears most of them without the user noticing.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final decoded = await _api.post('/ai/generate', jsonDecode(body) as Map<String, dynamic>);
        return decoded as Map<String, dynamic>;
      } on ApiException catch (e) {
        final transient = e.statusCode == 429 || (e.statusCode ?? 0) >= 500;
        if (transient && attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 900));
          continue;
        }
        throw AiAssistantException(_friendlyErrorFor(e.statusCode ?? 0));
      }
    }
    throw const AiAssistantException('The assistant is not working right now. Please try again in a moment.');
  }

  List<dynamic>? _partsOf(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final content = candidates.first['content'] as Map<String, dynamic>?;
    return content?['parts'] as List<dynamic>?;
  }

  ({String name, Map<String, dynamic> args})? _findFunctionCall(List<dynamic> parts) {
    for (final p in parts) {
      final call = (p as Map<String, dynamic>)['functionCall'] as Map<String, dynamic>?;
      if (call != null) return (name: call['name'] as String, args: (call['args'] as Map<String, dynamic>?) ?? const {});
    }
    return null;
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _parseDate(Map<String, dynamic> args, {DateTime? fallback}) {
    final raw = args['date'] as String?;
    if (raw == null) return fallback ?? DateTime.now();
    return DateTime.tryParse(raw) ?? (fallback ?? DateTime.now());
  }

  /// A *next* due date in the past is never what the user meant — the model
  /// has no reliable sense of the current date and can answer "today" with a
  /// date from its training data. Past dates collapse to today rather than
  /// creating a bill that shows up hundreds of days overdue.
  DateTime _parseUpcomingDate(Map<String, dynamic> args, {required DateTime fallback}) {
    final parsed = _parseDate(args, fallback: fallback);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return parsed.isBefore(today) ? today : parsed;
  }

  /// Same guard for an optional deadline (a savings goal's target date): a
  /// target already in the past is a misread, not a real deadline.
  DateTime? _parseOptionalUpcomingDate(Object? raw) {
    if (raw is! String) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return parsed.isBefore(today) ? null : parsed;
  }

  AiProposal? _proposalFromCall(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'log_transaction':
        final typeStr = args['type'] as String?;
        final amount = (args['amount'] as num?)?.toDouble();
        final category = (args['category'] as String?)?.trim();
        if (typeStr == null || amount == null || amount <= 0 || category == null || category.isEmpty) return null;
        return AiTransactionProposal(
          type: typeStr == 'income' ? TransactionType.income : TransactionType.expense,
          amount: Money.fromMajor(amount),
          categoryName: category,
          walletName: (args['wallet'] as String?)?.trim(),
          date: _parseDate(args),
          note: (args['note'] as String?)?.trim() ?? '',
        );

      case 'create_wallet':
        final walletName = (args['name'] as String?)?.trim();
        final typeStr = args['wallet_type'] as String?;
        if (walletName == null || walletName.isEmpty) return null;
        return AiWalletProposal(
          name: walletName,
          type: WalletType.values.firstWhere((t) => t.name == typeStr, orElse: () => WalletType.cash),
          startingBalance: Money.fromMajor((args['starting_balance'] as num?)?.toDouble() ?? 0),
        );

      case 'create_budget':
        final category = (args['category'] as String?)?.trim();
        final limit = (args['limit_amount'] as num?)?.toDouble();
        if (category == null || category.isEmpty || limit == null || limit <= 0) return null;
        return AiBudgetProposal(categoryName: category, limitAmount: Money.fromMajor(limit));

      case 'create_savings_goal':
        final goalName = (args['name'] as String?)?.trim();
        final target = (args['target_amount'] as num?)?.toDouble();
        if (goalName == null || goalName.isEmpty || target == null || target <= 0) return null;
        return AiSavingsGoalProposal(
          name: goalName,
          targetAmount: Money.fromMajor(target),
          targetDate: _parseOptionalUpcomingDate(args['target_date']),
        );

      case 'add_goal_contribution':
        final goalName = (args['goal_name'] as String?)?.trim();
        final amount = (args['amount'] as num?)?.toDouble();
        if (goalName == null || goalName.isEmpty || amount == null || amount <= 0) return null;
        return AiGoalContributionProposal(goalName: goalName, amount: Money.fromMajor(amount));

      case 'create_recurring_bill':
        final billName = (args['name'] as String?)?.trim();
        final category = (args['category'] as String?)?.trim();
        final amount = (args['amount'] as num?)?.toDouble();
        if (billName == null || billName.isEmpty || category == null || category.isEmpty || amount == null || amount <= 0) return null;
        final freqStr = args['frequency'] as String?;
        final totalOccurrences = (args['total_occurrences'] as num?)?.toInt();
        return AiRecurringBillProposal(
          name: billName,
          categoryName: category,
          amount: Money.fromMajor(amount),
          frequency: BillFrequency.values.firstWhere((f) => f.name == freqStr, orElse: () => BillFrequency.monthly),
          nextDueDate: _parseUpcomingDate(args, fallback: DateTime.now().add(const Duration(days: 7))),
          totalOccurrences: (totalOccurrences != null && totalOccurrences > 0) ? totalOccurrences : null,
          autoDeduct: args['auto_deduct'] == true,
          walletName: (args['wallet'] as String?)?.trim(),
        );

      default:
        return null;
    }
  }

  String _defaultConfirmation(AiProposal p, String currency) => 'Here\'s what I\'ll do: ${p.summary(currency)}. Confirm below to save it.';

  List<Map<String, dynamic>> get _toolDeclarations => [
        {
          'name': 'log_transaction',
          'description': 'Drafts an income or expense entry for the user to review and confirm.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'type': {'type': 'STRING', 'enum': ['income', 'expense']},
              'amount': {
                'type': 'NUMBER',
                'description': 'Amount in major currency units (e.g. 500 for ₱500.00) that the user explicitly stated for THIS transaction. Never reuse a number mentioned earlier for something else.',
              },
              'category': {'type': 'STRING', 'description': 'Must match one of the available category names exactly.'},
              'wallet': {'type': 'STRING', 'description': 'Wallet name, if specified or implied; omit otherwise.'},
              'note': {'type': 'STRING'},
              'date': {
                'type': 'STRING',
                'description':
                    'ISO 8601 date (YYYY-MM-DD), computed from TODAY\'S DATE as given at the top of your instructions — never from your own assumption about the current year. Omit entirely for today.',
              },
              'confirmation_message': {'type': 'STRING', 'description': 'One short sentence describing this action to show the user.'},
            },
            'required': ['type', 'amount', 'category', 'confirmation_message'],
          },
        },
        {
          'name': 'create_wallet',
          'description': 'Drafts a new wallet/account (cash, bank, e-wallet, or credit) for the user to review and confirm.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'name': {'type': 'STRING'},
              'wallet_type': {'type': 'STRING', 'enum': ['cash', 'bank', 'eWallet', 'credit']},
              'starting_balance': {
                'type': 'NUMBER',
                'description': 'Only set this if the user explicitly stated a starting balance for THIS wallet — omit it (defaults to 0) rather than reusing an unrelated number.',
              },
              'confirmation_message': {'type': 'STRING'},
            },
            'required': ['name', 'wallet_type', 'confirmation_message'],
          },
        },
        {
          'name': 'create_budget',
          'description': 'Drafts a monthly spending limit for an expense category for the user to review and confirm.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'category': {'type': 'STRING', 'description': 'Must match one of the available expense category names exactly.'},
              'limit_amount': {
                'type': 'NUMBER',
                'description': 'The monthly limit the user explicitly stated for THIS budget. Never reuse a number from an earlier, differently-purposed message in this conversation.',
              },
              'confirmation_message': {'type': 'STRING'},
            },
            'required': ['category', 'limit_amount', 'confirmation_message'],
          },
        },
        {
          'name': 'create_savings_goal',
          'description': 'Drafts a new savings goal for the user to review and confirm.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'name': {'type': 'STRING'},
              'target_amount': {
                'type': 'NUMBER',
                'description': 'The amount the user explicitly wants to save TOWARD IN TOTAL for this goal. Never reuse a contribution amount, a different goal\'s amount, or any other number mentioned earlier for a different purpose — if the user hasn\'t stated a target amount for this specific goal, call ask_clarifying_question instead of guessing.',
              },
              'target_date': {
                'type': 'STRING',
                'description':
                    'ISO 8601 date (YYYY-MM-DD), computed from TODAY\'S DATE as given at the top of your instructions — never from your own assumption about the current year. Must be in the future. Omit if not mentioned.',
              },
              'confirmation_message': {'type': 'STRING'},
            },
            'required': ['name', 'target_amount', 'confirmation_message'],
          },
        },
        {
          'name': 'add_goal_contribution',
          'description': 'Drafts adding money toward an existing savings goal for the user to review and confirm.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'goal_name': {
                'type': 'STRING',
                'description':
                    'Must match one of the "Savings goals available" names listed below — check that list character-by-character '
                    'before concluding a goal doesn\'t exist. If the user\'s wording is close but not exact (different '
                    'capitalization, a nickname, extra words), still match it to the closest listed name rather than saying you '
                    'don\'t see it.',
              },
              'amount': {'type': 'NUMBER', 'description': 'The amount the user explicitly wants to add toward this goal right now.'},
              'confirmation_message': {
                'type': 'STRING',
                'description':
                    'Compare this amount against the goal\'s "remaining" figure in "Savings goals available" below — if this '
                    'contribution is MORE than what\'s remaining, say so plainly (e.g. "that\'s ₱1,000 more than your ₱30,000 '
                    'target needs, so this will finish the goal with a bit extra") instead of confirming silently as if it were '
                    'an exact or partial contribution.',
              },
            },
            'required': ['goal_name', 'amount', 'confirmation_message'],
          },
        },
        {
          'name': 'create_recurring_bill',
          'description': 'Drafts a recurring bill or subscription for the user to review and confirm.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'name': {'type': 'STRING'},
              'category': {'type': 'STRING', 'description': 'Must match one of the available expense category names exactly.'},
              'amount': {
                'type': 'NUMBER',
                'description': 'The per-cycle amount the user explicitly stated for THIS bill. Never reuse a number mentioned earlier for something else.',
              },
              'frequency': {'type': 'STRING', 'enum': ['weekly', 'monthly', 'yearly']},
              'date': {
                'type': 'STRING',
                'description': 'Next due date, ISO 8601 (YYYY-MM-DD), computed from TODAY\'S DATE as given at the top of your instructions — never from your own assumption about the current year. Must be today or later. The user explicitly stated the day/date this bill is next due (e.g. "today", "the 15th", "due next Friday"). This is NOT optional to collect: if the user never mentioned a specific date, call ask_clarifying_question and ask which day it\'s due instead of silently guessing one — a wrong due date means the wrong day gets charged, especially when auto_deduct is true.',
              },
              'total_occurrences': {
                'type': 'NUMBER',
                'description': 'Only set this for a FIXED-LENGTH installment plan (e.g. "3 monthly payments of 5000 for a downpayment") — the number of payments after which the bill stops automatically. Omit entirely for an ongoing bill/subscription with no end (e.g. rent, Netflix). Never guess a count that wasn\'t stated.',
              },
              'auto_deduct': {
                'type': 'BOOLEAN',
                'description': 'True only if the user explicitly asked for this to auto-pay / auto-deduct itself (e.g. "auto-pay my Netflix", "just deduct it automatically each month"). Defaults to false (bill stays manual, user taps "Mark paid") when not explicitly requested — never turn this on just because a bill is a fixed monthly amount.',
              },
              'wallet': {
                'type': 'STRING',
                'description': 'Wallet name this bill pays from, if stated or clearly implied. If auto_deduct is true and no wallet has been mentioned, you must ask which wallet to use with quick_replies (the real wallet names below) instead of silently picking one — this determines exactly where money gets pulled from. If auto_deduct is false, it is fine to omit.',
              },
              'confirmation_message': {'type': 'STRING'},
            },
            'required': ['name', 'category', 'amount', 'frequency', 'date', 'confirmation_message'],
          },
        },
        {
          'name': 'ask_clarifying_question',
          'description':
              'Asks the user one short question when a detail is missing to complete a pending request. '
              'MANDATORY: whenever the valid answers are a small known set — an exact category name, wallet name, '
              'wallet type, or bill frequency — you MUST populate quick_replies with those exact real names copied '
              'from this conversation\'s data below, never leave it empty in that case. This is not optional; a '
              'category or wallet question with no quick_replies is an incomplete call. Only omit quick_replies for '
              'genuinely open-ended questions with no small set of valid answers (e.g. "what should the note say?").',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'question': {'type': 'STRING'},
              'quick_replies': {
                'type': 'ARRAY',
                'items': {'type': 'STRING'},
                'description': 'The exact category/wallet/goal names from the data below, copied verbatim — 2-5 short tappable options. Required whenever a known small set exists; omit only for genuinely open-ended questions.',
              },
            },
            'required': ['question'],
          },
        },
      ];

  String _systemPrompt(FinancialSnapshot snapshot) {
    final categories = snapshot.spendingByCategory.entries
        .map((e) => '${e.key}: ${e.value.format(snapshot.currencySymbol)}')
        .join(', ');
    final now = DateTime.now();
    final today = _isoDate(now);
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '''
TODAY'S DATE IS $today (${weekdays[now.weekday - 1]}). You have no other way of knowing the current date, so you
MUST use this one for every date you produce. Never rely on your training data to guess what today is.
Resolve relative dates against it: "today" = $today, "tomorrow" = ${_isoDate(now.add(const Duration(days: 1)))},
"next week" = ${_isoDate(now.add(const Duration(days: 7)))}. Every date you send to a tool must be a real
ISO 8601 date (YYYY-MM-DD) computed from $today, and unless the user is clearly describing something in the past,
it must not be earlier than $today.

You are SpendSense's built-in financial assistant. Match the user's tone — a casual greeting gets a casual reply,
not a data dump. Only bring up numbers when the question actually calls for them, and when you do, use ONLY the
aggregated data below (you have no access to raw transactions). Keep replies concise (1-4 sentences).

Precision over speed: every tool parameter marked required in its schema must come from something the user
actually said — never fill one in with a plausible-sounding guess just to finish the call in one turn. Slower and
correct beats fast and wrong, especially for anything that moves money (amounts, wallets) or sets a schedule
(due dates, frequencies). If more than one required detail is missing, ask for all of them together in one
question rather than one at a time where reasonable.

Many users are not fluent English speakers — expect typos, dropped articles/verbs ("i just had unexpected
expenses its 300"), and phrasing borrowed from other languages. Read for intent, not grammar: never comment on or
correct their wording, never ask them to "rephrase" or be more precise as a first response — make your best
reasonable interpretation and only fall back to ask_clarifying_question for the one specific detail that's
genuinely missing (e.g. which category), not the whole message. Reply in short, plain sentences using common
words — avoid idioms, slang, and complex sentence structure, since your reader may be translating as they go.

You can also act on the user's behalf using the tools provided — logging a transaction, creating a wallet,
setting a budget, creating a savings goal, contributing to a goal, or adding a recurring bill. The category,
wallet, and goal name lists below are the CURRENT, REAL, authoritative data — always check them before claiming
something doesn't exist or is empty. If a list below is genuinely empty, it's fine to say so, but never say "I
don't have any expense categories set up" or similar when the list below is NOT actually empty — read it first.
This applies just as much to goal names: if "Savings goals available" below lists a goal, it exists — never tell
the user you don't see a goal that's actually sitting right there in that list. Re-read the list before replying
"I don't see a goal called X" — this exact mistake has happened before and it's always been because the list was
misread, not because the goal was actually missing.
Only ever reference category/wallet/goal names from the lists below — if the user's wording doesn't clearly match
one (e.g. "internet bill" ≈ "Bills & Utilities" — recognize the obvious semantic match instead of asking), or a
required detail (amount, which category, etc.) is missing or ambiguous, use ask_clarifying_question instead of
guessing or calling a tool with incomplete/invented data. Whenever you ask a question whose valid answers are a
small known set (an exact category name, wallet name, wallet type, or bill frequency), you MUST give
ask_clarifying_question a quick_replies list containing ALL the genuinely relevant real options from the list
below — not just "Other" by itself. Concrete example of what NOT to do: asking "which category?" for an internet
bill and offering only ["Other"] as if Bills & Utilities, Shopping, etc. didn't exist in the list below — that is
a failed call, since it hides real, relevant options the user should be able to tap. "Other" may be included
alongside the relevant options, but must never be the sole option when other categories exist. This is required,
not optional, every single time that condition applies. Every action tool call requires a
one-sentence confirmation_message written in your own voice describing exactly what you're about to do — the
user reviews and confirms it before anything is actually saved, so nothing happens silently.

Critical rule: never carry a number or value from one field into a different field it wasn't stated for, even
within the same multi-turn exchange — and never carry a number forward once the user has moved on to a NEW,
unrelated request, no matter how recently a similar-looking number appeared. Two concrete examples of what NOT
to do:
(1) User says "add 1000 to my emergency fund"; no such goal exists yet, so you correctly ask whether to create
one; user says "okay". At this point you only know the goal's NAME ("Emergency Fund") — you do NOT know its
target amount. The 1000 was a contribution amount for a goal that didn't exist, not a target. Calling
create_savings_goal with target_amount=1000 here would be wrong — ask what the target amount should be instead.
(2) Earlier in the conversation the user mentioned a 5000/month installment plan for one bill. Several turns
later, for a completely different, newly-named bill, the user gives only a name ("cloth") with no amount stated
for THIS bill. Reusing the earlier 5000 here would be wrong — that number belonged to a different bill entirely.
Call ask_clarifying_question for the missing amount (and category) instead of guessing.
Every parameter must trace back to something the user explicitly stated FOR THAT SPECIFIC ACTION, in THIS
specific request — never inferred by proximity, recency, or reuse from a different topic.

Installment plans: if the user describes a fixed-length payment plan with a downpayment (e.g. "I'll pay 5000 down
and split 15000 across 3 months"), this is a TWO-PART request — handle it across two turns, not one, and do not
let the second part silently vanish:
(1) THIS turn: call log_transaction for ONLY the downpayment amount as a one-time expense. In confirmation_message,
use this exact phrasing pattern (the app listens for it to know a follow-up is owed) — do not paraphrase it away:
"...Once you confirm, just say the word and I'll set up the ₱5000/month bill for the remaining 3 payments." Only
use this exact "once you confirm, just say the word" phrasing for this specific two-part installment flow — never
for any other proposal, since it has a special meaning here.
(2) On the user's very next reply — even a short "ok"/"yes"/"go ahead" — follow through on that promise yourself:
call create_recurring_bill for the remaining recurring payments, reusing ONLY the amount/count from the ORIGINAL
installment message (never asking the user to repeat themselves), with total_occurrences set to the number of
REMAINING recurring payments (excluding the downpayment already logged).
If there's no downpayment at all (a plain fixed-length plan), just call create_recurring_bill directly in one turn
with total_occurrences set. Leave total_occurrences unset entirely for anything open-ended like rent or a
subscription.

Auto-deduct: only set create_recurring_bill's auto_deduct to true when the user explicitly asks for that bill to
pay/deduct itself automatically. When they do, remind them in confirmation_message that they can undo the latest
auto-payment afterward if needed (e.g. they end up paying late). Never enable it on your own initiative just
because a bill sounds fixed or certain — that decision belongs to the user.

Currency symbol: ${snapshot.currencySymbol}
Period: ${snapshot.periodLabel}
Total income: ${snapshot.totalIncome.format(snapshot.currencySymbol)}
Total expenses: ${snapshot.totalExpense.format(snapshot.currencySymbol)}
Spending by category: ${categories.isEmpty ? 'none recorded yet' : categories}
Budgets: ${snapshot.budgetSummaries.isEmpty ? 'none set' : snapshot.budgetSummaries.join('; ')}
Savings goals: ${snapshot.goalSummaries.isEmpty ? 'none set' : snapshot.goalSummaries.join('; ')}
Expense categories available: ${snapshot.expenseCategoryNames.join(', ')}
Income categories available: ${snapshot.incomeCategoryNames.join(', ')}
Wallets available: ${snapshot.walletNames.join(', ')}
Savings goals available: ${snapshot.goalNames.isEmpty ? 'none yet' : snapshot.goalNames.join(', ')}
''';
  }

  String _friendlyErrorFor(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'The assistant setup has a problem. Please tell the app developer.';
      case 403:
        return 'The assistant is not allowed to answer right now. Please tell the app developer.';
      case 429:
        return 'Too many questions at once. Please wait a moment and try again.';
      default:
        return 'The assistant is not working right now. Please try again in a moment.';
    }
  }
}

class AiAssistantException implements Exception {
  const AiAssistantException(this.message);
  final String message;

  @override
  String toString() => message;
}
