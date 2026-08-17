/// Stable, well-known IDs shared between demo_seed.dart and the fake AI
/// repositories (receipt scan, assistant) so a scanned/suggested category
/// always points at a category that actually exists in the seed data.
class SeedIds {
  SeedIds._();

  static const walletCash = 'wallet-cash';
  static const walletBank = 'wallet-bank';
  static const walletEwallet = 'wallet-ewallet';

  static const catSalary = 'cat-salary';
  static const catAllowance = 'cat-allowance';
  static const catFood = 'cat-food';
  static const catTransport = 'cat-transport';
  static const catBills = 'cat-bills';
  static const catShopping = 'cat-shopping';
  static const catEntertainment = 'cat-entertainment';
  static const catHealth = 'cat-health';
  static const catEducation = 'cat-education';
  static const catOther = 'cat-other';

  static const goalEmergencyFund = 'goal-emergency-fund';
  static const billInternet = 'bill-internet';
  static const billPhone = 'bill-phone';
}
