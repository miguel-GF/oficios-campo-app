import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'domain.dart';

PdfColor _color(String hex) =>
    PdfColor.fromInt(0xFF000000 | int.parse(hex.substring(1), radix: 16));
String _date(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? value
      : '${parsed.day}/${parsed.month}/${parsed.year}';
}

String _method(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Efectivo',
  PaymentMethod.transfer => 'Transferencia',
  PaymentMethod.other => 'Otro',
};

Future<Uint8List> _document({
  required BusinessProfile profile,
  required Quote quote,
  Payment? payment,
  required bool isPro,
}) async {
  final pdf = pw.Document();
  final accent = _color(normalizeBrandColor(profile.brandColor));
  pw.MemoryImage? logo;
  if (profile.logoUri != null && profile.logoUri!.isNotEmpty) {
    try {
      logo = pw.MemoryImage(await File(profile.logoUri!).readAsBytes());
    } catch (_) {
      logo = null;
    }
  }
  final summary = paymentSummary(quote.totalCents, quote.payments);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(28),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Este documento no es un comprobante fiscal.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
              pw.Text(
                'Página ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
            ],
          ),
          if (!isPro)
            pw.Text(
              'Creado con Jale',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
        ],
      ),
      build: (_) {
        final title = payment == null ? 'COTIZACIÓN' : 'RECIBO DE PAGO';
        final folio = formatFolio(
          payment == null ? 'COT' : 'REC',
          payment == null ? quote.quoteNumber : payment.receiptNumber,
        );
        final children = <pw.Widget>[
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: accent, width: 3)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logo != null) ...[
                  pw.ClipRRect(
                    horizontalRadius: 8,
                    verticalRadius: 8,
                    child: pw.Image(logo, width: 54, height: 54),
                  ),
                  pw.SizedBox(width: 10),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        profile.name,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      if (profile.trade.isNotEmpty)
                        pw.Text(
                          '${profile.trade}${profile.phone.isEmpty ? '' : ' · ${profile.phone}'}',
                          style: const pw.TextStyle(color: PdfColors.grey),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    pw.Text(
                      folio,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(_date(payment?.paidAt ?? quote.issuedAt)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
        ];
        if (payment == null) {
          children.addAll([
            pw.Text(
              'Cliente',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(quote.clientName),
            if (quote.clientPhone.isNotEmpty) pw.Text(quote.clientPhone),
            if (quote.clientAddress.isNotEmpty) pw.Text(quote.clientAddress),
            pw.SizedBox(height: 14),
          ]);
          final rows = <pw.TableRow>[
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: ['Concepto', 'Cant.', 'Precio', 'Importe']
                  .map(
                    (item) => pw.Padding(
                      padding: const pw.EdgeInsets.all(7),
                      child: pw.Text(
                        item,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ];
          rows.addAll(
            quote.lines.map(
              (line) => pw.TableRow(
                children:
                    [
                          line.concept,
                          '${line.quantity}',
                          money(line.unitPriceCents),
                          money((line.quantity * line.unitPriceCents).round()),
                        ]
                        .map(
                          (item) => pw.Padding(
                            padding: const pw.EdgeInsets.all(7),
                            child: pw.Text(item),
                          ),
                        )
                        .toList(),
              ),
            ),
          );
          children.add(
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey200),
              ),
              children: rows,
            ),
          );
          children.addAll([
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total: ${money(quote.totalCents)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ]);
          if (quote.validUntil != null) {
            children.add(pw.Text('Válida hasta ${_date(quote.validUntil!)}'));
          }
          if (quote.notes.isNotEmpty) {
            children.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 14),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text('Notas\n${quote.notes}'),
              ),
            );
          }
        } else {
          children.addAll([
            pw.Text(
              'Recibimos de',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(quote.clientName),
            pw.SizedBox(height: 14),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                'Pago de ${formatFolio('COT', quote.quoteNumber)}${payment.notes.isEmpty ? '' : ' · ${payment.notes}'}',
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text('Forma de pago: ${_method(payment.method)}'),
            pw.SizedBox(height: 18),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Recibido: ${money(payment.amountCents)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Total de la cotización: ${money(quote.totalCents)}\nPagado acumulado: ${money(summary.paidCents)}\nSaldo pendiente: ${money(summary.balanceCents)}',
            ),
          ]);
        }
        return children;
      },
    ),
  );
  return pdf.save();
}

Future<void> shareQuotePdf(
  BusinessProfile profile,
  Quote quote,
  bool isPro,
) async => Printing.sharePdf(
  bytes: await quotePdfBytes(profile, quote, isPro),
  filename: '${formatFolio('COT', quote.quoteNumber)}.pdf',
);

Future<Uint8List> quotePdfBytes(
  BusinessProfile profile,
  Quote quote,
  bool isPro,
) => _document(profile: profile, quote: quote, isPro: isPro);

Future<void> shareReceiptPdf(
  BusinessProfile profile,
  Quote quote,
  Payment payment,
  bool isPro,
) async => Printing.sharePdf(
  bytes: await _document(
    profile: profile,
    quote: quote,
    payment: payment,
    isPro: isPro,
  ),
  filename: '${formatFolio('REC', payment.receiptNumber)}.pdf',
);
