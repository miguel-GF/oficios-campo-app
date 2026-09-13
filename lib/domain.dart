import 'dart:math' as math;

const freeAiQuotesPerMonth = 2;
const guestAiQuotes = 1;
const defaultBrandColor = '#0E5E4A';

String normalizeBrandColor(String? value) {
  final color = value ?? '';
  return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)
      ? color.toUpperCase()
      : defaultBrandColor;
}

enum QuoteStatus { draft, finalized, sent, accepted, rejected }

enum QuoteOrigin { manual, ai }

enum PaymentMethod { cash, transfer, other }

enum PaymentStatus { pending, partial, paid }

/// The status a worker actually needs to understand in the field. Acceptance
/// and collection are stored separately, but presented as one coherent stage.
enum QuoteStage { draft, ready, sent, rejected, accepted, partial, paid }

QuoteStage quoteStage(QuoteStatus status, PaymentStatus paymentStatus) {
  if (status == QuoteStatus.draft) return QuoteStage.draft;
  if (status == QuoteStatus.finalized) return QuoteStage.ready;
  if (status == QuoteStatus.sent) return QuoteStage.sent;
  if (status == QuoteStatus.rejected) return QuoteStage.rejected;
  return switch (paymentStatus) {
    PaymentStatus.pending => QuoteStage.accepted,
    PaymentStatus.partial => QuoteStage.partial,
    PaymentStatus.paid => QuoteStage.paid,
  };
}

String quoteStageLabel(QuoteStage stage) => switch (stage) {
  QuoteStage.draft => 'BORRADOR',
  QuoteStage.ready => 'LISTA',
  QuoteStage.sent => 'ENVIADA',
  QuoteStage.rejected => 'NO ACEPTADA',
  QuoteStage.accepted => 'ACEPTADA · POR COBRAR',
  QuoteStage.partial => 'ABONO PARCIAL',
  QuoteStage.paid => 'PAGADA',
};

String quoteStatusValue(QuoteStatus value) => value.name;
QuoteStatus quoteStatusFrom(String value) => QuoteStatus.values.firstWhere(
  (item) => item.name == value,
  orElse: () => QuoteStatus.draft,
);

String paymentMethodValue(PaymentMethod value) => value.name;
PaymentMethod paymentMethodFrom(String value) =>
    PaymentMethod.values.firstWhere(
      (item) => item.name == value,
      orElse: () => PaymentMethod.other,
    );

class BusinessProfile {
  const BusinessProfile({
    required this.id,
    required this.name,
    required this.trade,
    required this.phone,
    required this.logoUri,
    this.iconKey,
    required this.brandColor,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, name, trade, phone, createdAt, updatedAt;
  final String? logoUri;
  final String? iconKey;
  final String brandColor;
}

class Client {
  const Client({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, name, phone, address, notes, createdAt, updatedAt;
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.concept,
    required this.unitPriceCents,
    required this.timesUsed,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, concept, createdAt, updatedAt;
  final int unitPriceCents, timesUsed;
}

class CatalogSuggestion {
  const CatalogSuggestion({required this.item, required this.score});

  final CatalogItem item;
  final double score;
}

String normalizeConcept(String value) {
  const accents = 'áéíóúüñÁÉÍÓÚÜÑ';
  const plain = 'aeiouunAEIOUUN';
  var result = value.trim().toLowerCase();
  for (var index = 0; index < accents.length; index++) {
    result = result.replaceAll(accents[index], plain[index]);
  }
  return result
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

CatalogSuggestion? suggestCatalogItem(
  String concept,
  Iterable<CatalogItem> items,
) {
  final normalized = normalizeConcept(concept);
  if (normalized.length < 3) return null;
  CatalogSuggestion? best;
  for (final item in items) {
    final score = conceptSimilarity(normalized, item.concept);
    if (score >= 0.55 && (best == null || score > best.score)) {
      best = CatalogSuggestion(item: item, score: score);
    }
  }
  return best;
}

/// Compara conceptos sin depender de la ortografía exacta de la transcripción.
/// Se usa como segunda barrera local: la IA propone, pero la app decide si
/// algo ya está en la cotización y evita duplicarlo sin pedir permiso.
double conceptSimilarity(String left, String right) {
  final normalizedLeft = normalizeConcept(left);
  final normalizedRight = normalizeConcept(right);
  if (normalizedLeft.length < 3 || normalizedRight.length < 3) return 0;
  if (normalizedLeft == normalizedRight) return 1;
  if (normalizedLeft.contains(normalizedRight) ||
      normalizedRight.contains(normalizedLeft)) {
    return 0.82;
  }
  final leftWords = normalizedLeft
      .split(' ')
      .where((word) => word.length > 1)
      .toSet();
  final rightWords = normalizedRight
      .split(' ')
      .where((word) => word.length > 1)
      .toSet();
  final union = leftWords.union(rightWords).length;
  return union == 0 ? 0 : leftWords.intersection(rightWords).length / union;
}

int? findSimilarQuoteLineIndex(
  String concept,
  Iterable<QuoteLine> lines, {
  double threshold = 0.62,
}) {
  var index = 0;
  int? bestIndex;
  var bestScore = 0.0;
  for (final line in lines) {
    final score = conceptSimilarity(concept, line.concept);
    if (score >= threshold && score > bestScore) {
      bestIndex = index;
      bestScore = score;
    }
    index++;
  }
  return bestIndex;
}

List<QuoteLine> appendUniqueQuoteLines(
  Iterable<QuoteLine> existing,
  Iterable<QuoteLine> additions,
) {
  final merged = existing
      .where(
        (line) => line.concept.trim().isNotEmpty || line.unitPriceCents > 0,
      )
      .toList();
  for (final addition in additions) {
    if (addition.concept.trim().isEmpty) continue;
    final duplicateIndex = findSimilarQuoteLineIndex(addition.concept, merged);
    if (duplicateIndex != null) {
      final current = merged[duplicateIndex];
      if (current.unitPriceCents == 0 && addition.unitPriceCents > 0) {
        merged[duplicateIndex] = current.copyWith(
          unitPriceCents: addition.unitPriceCents,
        );
      }
      continue;
    }
    merged.add(addition.copyWith(position: merged.length));
  }
  return merged;
}

class QuoteLine {
  const QuoteLine({
    required this.id,
    required this.concept,
    required this.quantity,
    required this.unitPriceCents,
    required this.position,
  });
  final String id, concept;
  final double quantity;
  final int unitPriceCents, position;
  QuoteLine copyWith({
    String? concept,
    double? quantity,
    int? unitPriceCents,
    int? position,
  }) => QuoteLine(
    id: id,
    concept: concept ?? this.concept,
    quantity: quantity ?? this.quantity,
    unitPriceCents: unitPriceCents ?? this.unitPriceCents,
    position: position ?? this.position,
  );
}

class Payment {
  const Payment({
    required this.id,
    required this.quoteId,
    required this.receiptNumber,
    required this.method,
    required this.amountCents,
    required this.paidAt,
    required this.notes,
    required this.voidedAt,
    required this.receiptFinalizedAt,
    required this.quotaPeriod,
  });
  final String id, quoteId, paidAt, notes;
  final int receiptNumber, amountCents;
  final PaymentMethod method;
  final String? voidedAt, receiptFinalizedAt, quotaPeriod;
}

class Quote {
  const Quote({
    required this.id,
    required this.quoteNumber,
    required this.clientId,
    required this.clientName,
    required this.status,
    required this.issuedAt,
    required this.validUntil,
    required this.notes,
    required this.totalCents,
    required this.finalizedAt,
    required this.quotaPeriod,
    required this.createdAt,
    required this.updatedAt,
    required this.lines,
    required this.payments,
    this.origin = QuoteOrigin.manual,
    this.clientPhone = '',
    this.clientAddress = '',
  });
  final String id, clientName, issuedAt, notes, createdAt, updatedAt;
  final String clientPhone, clientAddress;
  final int quoteNumber, totalCents;
  final String? clientId, validUntil, finalizedAt, quotaPeriod;
  final QuoteStatus status;
  final List<QuoteLine> lines;
  final List<Payment> payments;
  final QuoteOrigin origin;
  Quote copyWith({
    String? clientId,
    String? clientName,
    QuoteStatus? status,
    String? issuedAt,
    String? validUntil,
    String? notes,
    int? totalCents,
    String? finalizedAt,
    String? quotaPeriod,
    List<QuoteLine>? lines,
    List<Payment>? payments,
    QuoteOrigin? origin,
    String? clientPhone,
    String? clientAddress,
    bool unlinkClient = false,
  }) => Quote(
    id: id,
    quoteNumber: quoteNumber,
    clientId: unlinkClient ? null : clientId ?? this.clientId,
    clientName: clientName ?? this.clientName,
    status: status ?? this.status,
    issuedAt: issuedAt ?? this.issuedAt,
    validUntil: validUntil ?? this.validUntil,
    notes: notes ?? this.notes,
    totalCents: totalCents ?? this.totalCents,
    finalizedAt: finalizedAt ?? this.finalizedAt,
    quotaPeriod: quotaPeriod ?? this.quotaPeriod,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lines: lines ?? this.lines,
    payments: payments ?? this.payments,
    origin: origin ?? this.origin,
    clientPhone: clientPhone ?? this.clientPhone,
    clientAddress: clientAddress ?? this.clientAddress,
  );
}

class QuoteSummary {
  const QuoteSummary({
    required this.id,
    required this.quoteNumber,
    required this.clientName,
    required this.status,
    required this.issuedAt,
    required this.totalCents,
    required this.updatedAt,
    required this.paidCents,
    required this.balanceCents,
    required this.paymentStatus,
    this.origin = QuoteOrigin.manual,
  });
  final String id, clientName, issuedAt, updatedAt;
  final int quoteNumber, totalCents, paidCents, balanceCents;
  final QuoteStatus status;
  final PaymentStatus paymentStatus;
  final QuoteOrigin origin;
}

class UsageSummary {
  const UsageSummary({required this.period, required this.used});
  final String period;
  final int used;
}

enum DashboardRange { week, month }

class DashboardSummary {
  const DashboardSummary({
    required this.created,
    required this.accepted,
    required this.rejected,
    required this.partial,
    required this.paid,
    required this.pendingCents,
    required this.collectedCents,
  });

  final int created, accepted, rejected, partial, paid;
  final int pendingCents, collectedCents;
}

DashboardSummary dashboardSummary(
  List<QuoteSummary> quotes,
  DashboardRange range, {
  DateTime? clock,
}) {
  final now = clock ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = range == DashboardRange.week
      ? today.subtract(Duration(days: today.weekday - 1))
      : DateTime(now.year, now.month);
  final end = range == DashboardRange.week
      ? start.add(const Duration(days: 7))
      : DateTime(now.year, now.month + 1);
  final inRange = quotes.where((quote) {
    final issued = DateTime.tryParse(quote.issuedAt)?.toLocal();
    return issued != null && !issued.isBefore(start) && issued.isBefore(end);
  });
  var created = 0, accepted = 0, rejected = 0, partial = 0, paid = 0;
  var pendingCents = 0, collectedCents = 0;
  for (final quote in inRange) {
    created++;
    if (quote.status == QuoteStatus.accepted) accepted++;
    if (quote.status == QuoteStatus.rejected) rejected++;
    if (quote.paymentStatus == PaymentStatus.partial) partial++;
    if (quote.status == QuoteStatus.accepted &&
        quote.paymentStatus == PaymentStatus.paid) {
      paid++;
    }
    if (quote.status == QuoteStatus.accepted) {
      pendingCents += quote.balanceCents;
      collectedCents += quote.paidCents;
    }
  }
  return DashboardSummary(
    created: created,
    accepted: accepted,
    rejected: rejected,
    partial: partial,
    paid: paid,
    pendingCents: pendingCents,
    collectedCents: collectedCents,
  );
}

class BackupSnapshot {
  const BackupSnapshot({
    required this.schemaVersion,
    required this.exportedAt,
    required this.businessProfile,
    required this.clients,
    required this.quotes,
    required this.metadata,
    this.logoBase64,
    this.catalogItems = const [],
  });
  final int schemaVersion;
  final String exportedAt;
  final BusinessProfile? businessProfile;
  final List<Client> clients;
  final List<Quote> quotes;
  final Map<String, String> metadata;
  final String? logoBase64;
  final List<CatalogItem> catalogItems;
}

int quoteTotal(List<QuoteLine> lines) => lines.fold(
  0,
  (sum, line) => sum + (line.quantity * line.unitPriceCents).round(),
);

({int paidCents, int balanceCents, PaymentStatus status}) paymentSummary(
  int totalCents,
  List<Payment> payments,
) {
  final paid = payments
      .where((item) => item.voidedAt == null)
      .fold(0, (sum, item) => sum + item.amountCents);
  final balance = math.max(0, totalCents - paid);
  return (
    paidCents: paid,
    balanceCents: balance,
    status: paid <= 0
        ? PaymentStatus.pending
        : balance > 0
        ? PaymentStatus.partial
        : PaymentStatus.paid,
  );
}

String quotaPeriod([DateTime? date]) {
  final value = (date ?? DateTime.now()).toUtc();
  return '${value.year}-${value.month.toString().padLeft(2, '0')}';
}

UsageSummary usageSummary(int used, [String? period]) =>
    UsageSummary(period: period ?? quotaPeriod(), used: used);

String? validateQuoteForFinalization({
  required String clientName,
  required List<QuoteLine> lines,
  String? validUntil,
}) {
  if (clientName.trim().isEmpty) return 'Escribe el nombre del cliente.';
  if (lines.isEmpty) return 'Agrega al menos un concepto.';
  if (lines.any((line) => line.concept.trim().isEmpty)) {
    return 'Todos los conceptos necesitan una descripción.';
  }
  if (lines.any((line) => !line.quantity.isFinite || line.quantity <= 0)) {
    return 'Las cantidades deben ser mayores a cero.';
  }
  if (lines.any((line) => line.unitPriceCents < 0)) {
    return 'Los precios deben ser importes válidos.';
  }
  if (validUntil != null &&
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(validUntil)) {
    return 'La vigencia debe tener el formato AAAA-MM-DD.';
  }
  if (validUntil != null) {
    final parts = validUntil.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      return 'La fecha de vigencia no es válida.';
    }
  }
  return null;
}

String formatFolio(String prefix, int number) =>
    '$prefix-${number.toString().padLeft(6, '0')}';

String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)} MXN';

int parseMoneyToCents(String value) {
  var cleaned = value
      .trim()
      .replaceAll(RegExp(r'[\s\$]'), '')
      .replaceAll(RegExp(r'[^\d,.-]'), '');
  final comma = cleaned.lastIndexOf(','), dot = cleaned.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    final decimalMark = comma > dot ? ',' : '.';
    cleaned = cleaned
        .replaceAll(decimalMark == ',' ? '.' : ',', '')
        .replaceFirst(decimalMark, '.');
  } else if (comma >= 0) {
    cleaned = RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(cleaned)
        ? cleaned.replaceAll(',', '')
        : cleaned.replaceFirst(',', '.');
  } else if ('.'.allMatches(cleaned).length > 1 &&
      RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(cleaned)) {
    cleaned = cleaned.replaceAll('.', '');
  }
  final amount = double.tryParse(cleaned);
  return amount == null ? 0 : math.max(0, (amount * 100).round());
}

QuoteLine newLinePlaceholder(int position) => QuoteLine(
  id: 'line-${DateTime.now().microsecondsSinceEpoch}',
  concept: '',
  quantity: 1,
  unitPriceCents: 0,
  position: position,
);
