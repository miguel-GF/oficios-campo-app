import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'account.dart';
import 'ai.dart';
import 'domain.dart';

class AiQuoteAssistantPage extends StatefulWidget {
  const AiQuoteAssistantPage({
    super.key,
    required this.trade,
    required this.clientHint,
    required this.catalogItems,
    this.existingLines = const [],
  });

  final String trade, clientHint;
  final List<CatalogItem> catalogItems;
  final List<QuoteLine> existingLines;

  @override
  State<AiQuoteAssistantPage> createState() => _AiQuoteAssistantPageState();
}

class _AiQuoteAssistantPageState extends State<AiQuoteAssistantPage> {
  final transcript = TextEditingController();
  final speech = SpeechToText();
  final api = AiApi();
  bool speechReady = false, listening = false, preparing = false;
  String? error;
  AiQuoteDraft? result;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSpeech());
  }

  Future<void> _initializeSpeech() async {
    final ready = await speech.initialize(
      onStatus: (status) {
        if (mounted && (status == 'done' || status == 'notListening')) {
          setState(() => listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => listening = false);
      },
    );
    if (mounted) setState(() => speechReady = ready);
  }

  Future<void> toggleListening() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    if (!speechReady) {
      setState(
        () => error = 'El dictado no está disponible; puedes escribirlo.',
      );
      return;
    }
    setState(() {
      listening = true;
      error = null;
    });
    await speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'es_MX',
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (value) {
        transcript.text = value.recognizedWords;
        transcript.selection = TextSelection.collapsed(
          offset: transcript.text.length,
        );
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> prepare() async {
    if (transcript.text.trim().length < 4) {
      setState(() => error = 'Cuenta qué trabajo harás, cantidades y precios.');
      return;
    }
    await speech.stop();
    setState(() {
      preparing = true;
      listening = false;
      error = null;
    });
    try {
      final value = await api.interpret(
        transcript: transcript.text,
        trade: widget.trade,
        clientHint: widget.clientHint,
      );
      if (mounted) {
        setState(() {
          result = value;
          preparing = false;
        });
      }
    } on AiEmailRequired {
      if (!mounted) return;
      setState(() => preparing = false);
      final registered = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const EmailRegistrationPage()),
      );
      if (registered == true) {
        await prepare();
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          preparing = false;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(speech.cancel());
    transcript.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final draft = result;
    return Scaffold(
      appBar: AppBar(title: const Text('Cotizar con voz')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (draft == null) ...[
            Text(
              'Cuéntame el jale como se lo explicarías a tu cliente.',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ejemplo: “Para Ana, dos contactos a 350 cada uno y cambio de centro de carga en 1,800”.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: transcript,
              minLines: 5,
              maxLines: 9,
              enabled: !preparing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Lo que entendimos',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 72,
              child: FilledButton.icon(
                onPressed: preparing ? null : toggleListening,
                icon: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 30,
                ),
                label: Text(listening ? 'Terminar dictado' : 'Hablar ahora'),
                style: FilledButton.styleFrom(
                  backgroundColor: listening ? colors.error : colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: preparing ? null : prepare,
              icon: preparing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                preparing ? 'Preparando conceptos…' : 'Crear conceptos con IA',
              ),
            ),
          ] else ...[
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: const Icon(Icons.auto_awesome_rounded),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Revisa antes de agregar',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'La IA puede equivocarse. Confirma cantidades y precios.',
            ),
            if (draft.clientName.isNotEmpty) ...[
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('Cliente'),
                subtitle: Text(draft.clientName),
              ),
            ],
            const SizedBox(height: 8),
            ...draft.lines.map((line) {
              final suggestion = suggestCatalogItem(
                line.concept,
                widget.catalogItems,
              );
              final alreadyInQuote =
                  findSimilarQuoteLineIndex(
                    line.concept,
                    widget.existingLines,
                  ) !=
                  null;
              final useCatalogPrice =
                  line.unitPriceCents == 0 && suggestion != null;
              final unitPrice = useCatalogPrice
                  ? suggestion.item.unitPriceCents
                  : line.unitPriceCents;
              return Card(
                child: ListTile(
                  leading: alreadyInQuote
                      ? const Icon(Icons.merge_type_rounded)
                      : null,
                  title: Row(
                    children: [
                      Expanded(child: Text(line.concept)),
                      if (alreadyInQuote)
                        const Chip(
                          label: Text('Ya existe'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${line.quantity == line.quantity.roundToDouble() ? line.quantity.toInt() : line.quantity} × ${money(unitPrice)}${useCatalogPrice ? ' · precio de tu catálogo' : ''}',
                  ),
                  trailing: Text(
                    money((line.quantity * unitPrice).round()),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, draft),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Agregar a mi cotización'),
            ),
            TextButton(
              onPressed: () => setState(() => result = null),
              child: const Text('Corregir dictado'),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: preparing ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Continuar manualmente'),
            ),
          ],
        ],
      ),
    );
  }
}
