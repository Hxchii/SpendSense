import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const Map<String, IconData> _categoryIcons = {
  'salary': LucideIcons.banknote,
  'allowance': LucideIcons.gift,
  'food': LucideIcons.soup,
  'transport': LucideIcons.carFront,
  'bills': LucideIcons.receipt,
  'shopping': LucideIcons.shoppingBag,
  'entertainment': LucideIcons.clapperboard,
  'health': LucideIcons.heartPulse,
  'education': LucideIcons.graduationCap,
  'other': LucideIcons.circleEllipsis,
  'shield': LucideIcons.shieldCheck,
  'piggyBank': LucideIcons.piggyBank,
  'plane': LucideIcons.plane,
  'home': LucideIcons.home,
  'car': LucideIcons.car,
  'laptop': LucideIcons.laptop,
  'gift': LucideIcons.gift,
  'target': LucideIcons.target,
};

/// Curated set offered when picking an icon for a savings goal.
const goalIconChoices = [
  'shield', 'piggyBank', 'plane', 'home', 'car', 'laptop', 'education', 'gift', 'target',
];

IconData categoryIcon(String key) => _categoryIcons[key] ?? LucideIcons.circleEllipsis;

const Map<String, IconData> _walletIcons = {
  'cash': LucideIcons.banknote,
  'bank': LucideIcons.landmark,
  'eWallet': LucideIcons.wallet,
  'credit': LucideIcons.creditCard,
};

IconData walletTypeIcon(String key) => _walletIcons[key] ?? LucideIcons.wallet;
