import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// Shares export bytes directly via [XFile.fromData] rather than writing
/// through dart:io/path_provider — keeps this platform-independent (works
/// on mobile, desktop, and web without conditional imports).
class ExportService {
  Future<void> exportCsv({
    required List<Transaction> transactions,
    required Map<String, Category> categoriesById,
    required Map<String, Wallet> walletsById,
    required String currency,
  }) async {
    final rows = <List<String>>[
      ['Date', 'Type', 'Category', 'Wallet', 'Amount', 'Note'],
      for (final t in transactions)
        [
          _formatDate(t.date),
          t.type == TransactionType.income ? 'Income' : 'Expense',
          categoriesById[t.categoryId]?.name ?? 'Uncategorized',
          walletsById[t.walletId]?.name ?? 'Unknown',
          // Signed and unsymboled so spreadsheets parse it as a number.
          '${t.type == TransactionType.income ? '' : '-'}${(t.amount.minorUnits / 100).toStringAsFixed(2)}',
          t.note,
        ],
    ];
    final csvString = Csv().encode(rows);
    final bytes = Uint8List.fromList(utf8.encode(csvString));
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'text/csv', name: 'spendsense_transactions.csv')],
      text: 'SpendSense transaction export',
    ));
  }

  Future<void> exportPdf({
    required List<Transaction> transactions,
    required Map<String, Category> categoriesById,
    required Map<String, Wallet> walletsById,
    required String currency,
  }) async {
    // The pdf package's built-in Helvetica has no ₱ glyph, so amounts would
    // render as tofu boxes without an embedded Unicode font.
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));

    final income = transactions.where((t) => t.type == TransactionType.income).fold<int>(0, (s, t) => s + t.amount.minorUnits);
    final expense = transactions.where((t) => t.type == TransactionType.expense).fold<int>(0, (s, t) => s + t.amount.minorUnits);
    String money(int minorUnits) => '$currency${(minorUnits / 100).toStringAsFixed(2)}';

    final generatedOn = DateTime.now();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        margin: const pw.EdgeInsets.all(28),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text('SpendSense Transaction Report',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Text('SpendSense Transaction Report', style: pw.TextStyle(font: bold, fontSize: 20)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated ${_formatDate(generatedOn)} · ${transactions.length} transactions',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _summaryTile('Income', money(income), PdfColors.green700, bold),
              pw.SizedBox(width: 10),
              _summaryTile('Expenses', money(expense), PdfColors.red700, bold),
              pw.SizedBox(width: 10),
              _summaryTile('Net', money(income - expense), PdfColors.blueGrey800, bold),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Type', 'Category', 'Wallet', 'Amount', 'Note'],
            headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellHeight: 20,
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {4: pw.Alignment.centerRight},
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FixedColumnWidth(52),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FixedColumnWidth(80),
              5: const pw.FlexColumnWidth(2.4),
            },
            data: [
              for (final t in transactions)
                [
                  _formatDate(t.date),
                  t.type == TransactionType.income ? 'Income' : 'Expense',
                  categoriesById[t.categoryId]?.name ?? 'Uncategorized',
                  walletsById[t.walletId]?.name ?? 'Unknown',
                  '${t.type == TransactionType.income ? '+' : '-'}${money(t.amount.minorUnits)}',
                  t.note,
                ],
            ],
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'spendsense_transactions.pdf')],
      text: 'SpendSense transaction export',
    ));
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static pw.Widget _summaryTile(String label, String value, PdfColor accent, pw.Font bold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(), style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, letterSpacing: 0.6)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 13, color: accent)),
          ],
        ),
      ),
    );
  }
}
