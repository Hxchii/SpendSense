import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/features/ai_assistant/application/financial_snapshot_provider.dart';
import 'package:spendsense/features/ai_assistant/data/api/api_ai_chat_repository.dart';
import 'package:spendsense/features/ai_assistant/data/remote/http_ai_assistant_repository.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_action.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_chat_message.dart';
import 'package:spendsense/features/ai_assistant/domain/repositories/ai_assistant_repository.dart';
import 'package:spendsense/features/ai_assistant/domain/repositories/ai_chat_repository.dart';
import 'package:spendsense/features/budgets/application/budget_providers.dart';
import 'package:spendsense/features/budgets/domain/entities/budget.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/recurring_bills/application/recurring_bill_providers.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/savings_goals/application/savings_goal_providers.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// THE swap point for locally-saved chat history.
final aiChatRepositoryProvider = Provider<AiChatRepository>((ref) {
  return ApiAiChatRepository(client: ref.watch(apiClientProvider));
});

/// THE swap point for the AI call — now routed through the Laravel API, which
/// holds the Gemini key server-side.
final aiAssistantRepositoryProvider = Provider<AiAssistantRepository>((ref) {
  return HttpAiAssistantRepository(client: ref.watch(apiClientProvider));
});

final aiChatHistoryProvider = StreamProvider.autoDispose<List<AiChatMessage>>((ref) {
  return ref.watch(aiChatRepositoryProvider).watchHistory();
});

final aiChatSendingProvider = StateProvider.autoDispose<bool>((ref) => false);

final aiChatControllerProvider = Provider.autoDispose((ref) => AiChatController(ref));

// Same palette used for the manual wallet-color picker (wallet_form_screen.dart).
const _walletColors = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#4a3aa7', '#e34948'];

class AiChatController {
  AiChatController(this._ref);
  final Ref _ref;

  Future<void> send(String message) async {
    if (message.trim().isEmpty) return;
    final chatRepo = _ref.read(aiChatRepositoryProvider);
    final assistant = _ref.read(aiAssistantRepositoryProvider);

    _ref.read(aiChatSendingProvider.notifier).state = true;
    try {
      final userMessage = AiChatMessage(id: newId(), role: ChatRole.user, content: message.trim(), createdAt: DateTime.now());
      await chatRepo.addMessage(userMessage);

      final history = _ref.read(aiChatHistoryProvider).valueOrNull ?? const [];
      final snapshot = await _ref.read(financialSnapshotProvider.future);

      AiChatResponse response;
      try {
        response = await assistant.ask(message: message.trim(), history: history, snapshot: snapshot);
      } on AiAssistantException catch (e) {
        response = _assistantUnavailable(e.message);
      } catch (_) {
        response = _assistantUnavailable(null);
      }

      await chatRepo.addMessage(AiChatMessage(
        id: newId(),
        role: ChatRole.assistant,
        content: response.reply,
        createdAt: DateTime.now(),
        suggestions: response.suggestions,
        proposal: response.proposal,
      ));
    } finally {
      _ref.read(aiChatSendingProvider.notifier).state = false;
    }
  }

  /// The assistant call failed (rate limit, network, outage). Says so plainly
  /// instead of pretending to have an answer.
  AiChatResponse _assistantUnavailable(String? failureReason) {
    final reply = failureReason ?? 'The assistant is unavailable right now. Please try again in a moment.';
    return AiChatResponse(reply: reply, suggestions: const ['Try again']);
  }

  /// Resolves the proposal's names against whatever actually exists right
  /// now (never trusting the AI's spelling blindly), writes the real
  /// record via the same repositories manual entry uses, marks the message
  /// confirmed, and posts a plain-language confirmation.
  Future<void> confirmProposal(AiChatMessage message) async {
    final proposal = message.proposal;
    if (proposal == null) return;

    final confirmationText = switch (proposal) {
      AiTransactionProposal p => await _createTransaction(p),
      AiWalletProposal p => await _createWallet(p),
      AiBudgetProposal p => await _createBudget(p),
      AiSavingsGoalProposal p => await _createSavingsGoal(p),
      AiGoalContributionProposal p => await _addGoalContribution(p),
      AiRecurringBillProposal p => await _createRecurringBill(p),
    };

    final chatRepo = _ref.read(aiChatRepositoryProvider);
    await chatRepo.updateMessage(message.copyWith(proposalStatus: AiActionStatus.confirmed));
    await chatRepo.addMessage(AiChatMessage(id: newId(), role: ChatRole.assistant, content: confirmationText, createdAt: DateTime.now()));

    // The installment-plan flow (see system prompt) has the assistant log a
    // downpayment now and explicitly promise to set up the recurring bill
    // "once you confirm, just say the word" — but nothing else ever
    // re-invokes the assistant after a confirm, so that promise would
    // otherwise just go nowhere. Match both phrases together, not just
    // "once you confirm" alone — that shorter phrase is generic enough that
    // the model could plausibly write it for an unrelated proposal too,
    // spuriously re-invoking itself.
    final lower = message.content.toLowerCase();
    if (lower.contains('once you confirm') && lower.contains('say the word')) {
      await _autoContinue();
    }
  }

  Future<void> dismissProposal(AiChatMessage message) async {
    await _ref.read(aiChatRepositoryProvider).updateMessage(message.copyWith(proposalStatus: AiActionStatus.dismissed));
  }

  /// Silently re-prompts the assistant to fulfill a follow-up it already
  /// committed to in its own prior message — no visible "user" bubble, since
  /// the user didn't actually say anything here.
  Future<void> _autoContinue() async {
    const trigger = 'Continue with what you said you would do next.';
    final chatRepo = _ref.read(aiChatRepositoryProvider);
    final assistant = _ref.read(aiAssistantRepositoryProvider);
    final history = _ref.read(aiChatHistoryProvider).valueOrNull ?? const [];
    final snapshot = await _ref.read(financialSnapshotProvider.future);

    _ref.read(aiChatSendingProvider.notifier).state = true;
    try {
      AiChatResponse response;
      try {
        response = await assistant.ask(message: trigger, history: history, snapshot: snapshot);
      } on AiAssistantException catch (e) {
        response = _assistantUnavailable(e.message);
      } catch (_) {
        response = _assistantUnavailable(null);
      }

      await chatRepo.addMessage(AiChatMessage(
        id: newId(),
        role: ChatRole.assistant,
        content: response.reply,
        createdAt: DateTime.now(),
        suggestions: response.suggestions,
        proposal: response.proposal,
      ));
    } finally {
      _ref.read(aiChatSendingProvider.notifier).state = false;
    }
  }

  Future<List<Category>> _categoriesOfType(CategoryType type) => _ref.read(categoryRepositoryProvider).watchAll(type: type).first;
  Future<List<Wallet>> _wallets() => _ref.read(walletRepositoryProvider).watchAll().first;

  Category _resolveCategory(List<Category> categories, String name) {
    return categories.firstWhereOrNull((c) => c.name.toLowerCase() == name.toLowerCase()) ??
        categories.firstWhereOrNull((c) => c.name.toLowerCase() == 'other') ??
        categories.first;
  }

  Future<String> _createTransaction(AiTransactionProposal p) async {
    final categories = await _categoriesOfType(p.type == TransactionType.income ? CategoryType.income : CategoryType.expense);
    final wallets = await _wallets();
    if (wallets.isEmpty) return "Couldn't add that — you don't have a wallet yet.";
    final category = _resolveCategory(categories, p.categoryName);
    final wallet = p.walletName == null
        ? wallets.first
        : wallets.firstWhereOrNull((w) => w.name.toLowerCase() == p.walletName!.toLowerCase()) ?? wallets.first;
    final currency = (await _ref.read(financialSnapshotProvider.future)).currencySymbol;

    await _ref.read(transactionRepositoryProvider).create(TransactionDraft(
          walletId: wallet.id,
          categoryId: category.id,
          type: p.type,
          amount: p.amount,
          date: p.date,
          note: p.note,
        ));
    return 'Added: ${p.amount.format(currency)} to ${category.name} (${wallet.name}).';
  }

  Future<String> _createWallet(AiWalletProposal p) async {
    final wallets = await _wallets();
    final currency = (await _ref.read(financialSnapshotProvider.future)).currencySymbol;
    await _ref.read(walletRepositoryProvider).create(WalletDraft(
          name: p.name,
          type: p.type,
          startingBalance: p.startingBalance,
          colorHex: _walletColors[wallets.length % _walletColors.length],
        ));
    return 'Created wallet "${p.name}" with a starting balance of ${p.startingBalance.format(currency)}.';
  }

  Future<String> _createBudget(AiBudgetProposal p) async {
    final categories = await _categoriesOfType(CategoryType.expense);
    final category = _resolveCategory(categories, p.categoryName);
    final currency = (await _ref.read(financialSnapshotProvider.future)).currencySymbol;
    final now = DateTime.now();
    await _ref.read(budgetRepositoryProvider).create(BudgetDraft(
          categoryId: category.id,
          period: BudgetPeriod.monthly,
          limitAmount: p.limitAmount,
          startDate: DateTime(now.year, now.month, 1),
          endDate: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        ));
    return 'Set a monthly ${category.name} budget of ${p.limitAmount.format(currency)}.';
  }

  Future<String> _createSavingsGoal(AiSavingsGoalProposal p) async {
    final currency = (await _ref.read(financialSnapshotProvider.future)).currencySymbol;
    await _ref.read(savingsGoalRepositoryProvider).create(SavingsGoalDraft(
          name: p.name,
          targetAmount: p.targetAmount,
          iconKey: 'shield',
          targetDate: p.targetDate,
        ));
    return 'Created savings goal "${p.name}" — target ${p.targetAmount.format(currency)}.';
  }

  Future<String> _addGoalContribution(AiGoalContributionProposal p) async {
    final goals = await _ref.read(savingsGoalRepositoryProvider).watchAll().first;
    // If more than one goal shares this name, an ACTIVE one is what the
    // user almost certainly means — a name by itself gives no other way to
    // tell them apart, and silently picking whichever happens to be first
    // in the list risks adding money to a finished goal from months ago
    // instead of the new one the user is actually talking about.
    final goal = goals.firstWhereOrNull((g) => g.name.toLowerCase() == p.goalName.toLowerCase() && g.status == GoalStatus.active) ??
        goals.firstWhereOrNull((g) => g.name.toLowerCase() == p.goalName.toLowerCase());
    final currency = (await _ref.read(financialSnapshotProvider.future)).currencySymbol;
    if (goal == null) return "Couldn't find a savings goal called \"${p.goalName}\".";
    if (goal.status != GoalStatus.active) return '"${goal.name}" is already complete — no need to add more.';

    final wallets = await _wallets();
    final walletId = goal.walletId ?? wallets.firstWhereOrNull((w) => !w.archived)?.id;
    if (walletId == null) return "Couldn't add that — you don't have a wallet yet.";

    await _ref.read(savingsGoalContributionControllerProvider).contributeManually(goal.id, p.amount, walletId);

    final newTotal = goal.currentAmount + p.amount;
    if (newTotal > goal.targetAmount) {
      final over = newTotal - goal.targetAmount;
      return 'Added ${p.amount.format(currency)} to "${goal.name}" — that\'s ${over.format(currency)} over your '
          '${goal.targetAmount.format(currency)} target, so it\'s now marked complete.';
    }
    return 'Added ${p.amount.format(currency)} to "${goal.name}".';
  }

  Future<String> _createRecurringBill(AiRecurringBillProposal p) async {
    final categories = await _categoriesOfType(CategoryType.expense);
    final category = _resolveCategory(categories, p.categoryName);
    final currency = (await _ref.read(financialSnapshotProvider.future)).currencySymbol;
    String? walletId;
    if (p.walletName != null) {
      final wallets = await _wallets();
      walletId = wallets.firstWhereOrNull((w) => w.name.toLowerCase() == p.walletName!.toLowerCase())?.id;
    }
    await _ref.read(recurringBillRepositoryProvider).create(RecurringBillDraft(
          name: p.name,
          categoryId: category.id,
          walletId: walletId,
          amount: p.amount,
          frequency: p.frequency,
          nextDueDate: p.nextDueDate,
          totalOccurrences: p.totalOccurrences,
          autoLogTransaction: p.autoDeduct,
        ));
    final installmentNote = p.totalOccurrences == null ? '' : ' — stops automatically after ${p.totalOccurrences} payments';
    final autoDeductNote = p.autoDeduct ? ' — auto-deducts on its due date' : '';
    return 'Added recurring bill "${p.name}" — ${p.amount.format(currency)} ${p.frequency.name}$installmentNote$autoDeductNote.';
  }
}
