import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backup.dart';
import 'ai.dart';
import 'ai_quote_page.dart';
import 'account.dart';
import 'database.dart';
import 'documents.dart';
import 'domain.dart';
import 'subscription.dart';
import 'theme.dart';

String quoteStatusLabel(QuoteStatus status) => switch (status) {
  QuoteStatus.draft => 'BORRADOR',
  QuoteStatus.finalized => 'LISTA',
  QuoteStatus.sent => 'ENVIADA',
  QuoteStatus.accepted => 'ACEPTADA',
  QuoteStatus.rejected => 'RECHAZADA',
};

String quoteDisplayStatus(Quote quote) => quoteStageLabel(
  quoteStage(
    quote.status,
    paymentSummary(quote.totalCents, quote.payments).status,
  ),
);

String quoteSummaryDisplayStatus(QuoteSummary quote) =>
    quoteStageLabel(quoteStage(quote.status, quote.paymentStatus));

String paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Efectivo',
  PaymentMethod.transfer => 'Transferencia',
  PaymentMethod.other => 'Otro',
};

IconData tradeIcon(String trade) {
  final value = trade.toLowerCase();
  if (value.contains('electric')) return Icons.bolt_rounded;
  if (value.contains('plom')) return Icons.water_drop_rounded;
  if (value.contains('carpint')) return Icons.carpenter_rounded;
  if (value.contains('pint')) return Icons.format_paint_rounded;
  if (value.contains('jard') || value.contains('paisaj')) {
    return Icons.local_florist_rounded;
  }
  if (value.contains('alba') || value.contains('constr')) {
    return Icons.foundation_rounded;
  }
  if (value.contains('sold')) return Icons.hardware_rounded;
  if (value.contains('herr')) return Icons.handyman_rounded;
  if (value.contains('impermeab')) return Icons.roofing_rounded;
  if (value.contains('limp')) return Icons.cleaning_services_rounded;
  if (value.contains('refrig') || value.contains('climat')) {
    return Icons.ac_unit_rounded;
  }
  if (value.contains('cerraj')) return Icons.lock_outline_rounded;
  if (value.contains('gas')) return Icons.local_fire_department_rounded;
  if (value.contains('dise') || value.contains('decor')) {
    return Icons.design_services_rounded;
  }
  return Icons.handyman_rounded;
}

const commonTrades = [
  'Albañilería',
  'Plomería',
  'Electricidad',
  'Pintura',
  'Carpintería',
  'Jardinería',
  'Soldadura',
  'Herrería',
  'Impermeabilización',
  'Limpieza',
  'Refrigeración',
  'Climatización',
  'Cerrajería',
  'Instalación de gas',
  'Diseño y decoración',
];

class JaleIconChoice {
  const JaleIconChoice(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const jaleIconChoices = <JaleIconChoice>[
  JaleIconChoice('auto', 'Auto', Icons.handyman_rounded),
  JaleIconChoice('ai', 'IA', Icons.auto_awesome_rounded),
  JaleIconChoice('bolt', 'Rayo', Icons.bolt_rounded),
  JaleIconChoice('electrical', 'Eléctrico', Icons.electrical_services_rounded),
  JaleIconChoice('water', 'Gota', Icons.water_drop_rounded),
  JaleIconChoice('plumbing', 'Plomería', Icons.plumbing_rounded),
  JaleIconChoice('hammer', 'Martillo', Icons.handyman_rounded),
  JaleIconChoice('construction', 'Obra', Icons.construction_rounded),
  JaleIconChoice('paint', 'Pintura', Icons.format_paint_rounded),
  JaleIconChoice('wood', 'Madera', Icons.carpenter_rounded),
  JaleIconChoice('leaf', 'Hoja', Icons.local_florist_rounded),
  JaleIconChoice('garden', 'Jardín', Icons.grass_rounded),
  JaleIconChoice('wrench', 'Llave', Icons.build_rounded),
  JaleIconChoice('roof', 'Techo', Icons.roofing_rounded),
  JaleIconChoice('home', 'Casa', Icons.home_work_rounded),
  JaleIconChoice('clean', 'Limpieza', Icons.cleaning_services_rounded),
  JaleIconChoice('climate', 'Clima', Icons.ac_unit_rounded),
  JaleIconChoice('lock', 'Cerrojo', Icons.lock_outline_rounded),
  JaleIconChoice('gas', 'Gas', Icons.local_fire_department_rounded),
  JaleIconChoice('design', 'Diseño', Icons.design_services_rounded),
  JaleIconChoice('store', 'Negocio', Icons.storefront_rounded),
  JaleIconChoice('trusted', 'Confianza', Icons.verified_user_rounded),
];

IconData? iconFromKey(String? key) {
  if (key == null || key.isEmpty || key == 'auto') return null;
  for (final choice in jaleIconChoices) {
    if (choice.key == key) return choice.icon;
  }
  return null;
}

Color colorFromHex(String value) =>
    Color(int.parse('FF${value.substring(1)}', radix: 16));

Future<String?> pickAndCropLogo(BuildContext context) async {
  final toolbarColor = Theme.of(context).colorScheme.primary;
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  if (result == null || result.files.isEmpty) return null;
  final source = result.files.single.path;
  if (source == null) {
    throw Exception(
      'No pudimos leer esa imagen. Elige una imagen guardada en el teléfono.',
    );
  }
  final cropped = await ImageCropper().cropImage(
    sourcePath: source,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 92,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Ajusta tu logo',
        toolbarColor: toolbarColor,
        toolbarWidgetColor: Colors.white,
        lockAspectRatio: false,
      ),
      IOSUiSettings(title: 'Ajusta tu logo'),
    ],
  );
  if (cropped == null) return null;
  final documents = await getApplicationDocumentsDirectory();
  final branding = Directory(path.join(documents.path, 'branding'));
  await branding.create(recursive: true);
  final target = path.join(
    branding.path,
    'business-logo-${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await File(cropped.path).copy(target);
  return target;
}

class BusinessMark extends StatelessWidget {
  const BusinessMark({
    super.key,
    required this.logoUri,
    required this.trade,
    this.iconKey,
    this.size = 52,
  });
  final String? logoUri;
  final String trade;
  final String? iconKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(
        iconFromKey(iconKey) ?? tradeIcon(trade),
        color: colors.primary,
        size: size * .48,
      ),
    );
    if (logoUri == null || logoUri!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: Image.file(
        File(logoUri!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class JaleRoot extends StatefulWidget {
  const JaleRoot({super.key});
  @override
  State<JaleRoot> createState() => _JaleRootState();
}

class _JaleRootState extends State<JaleRoot> {
  Future<Database> database = openJaleDatabase();
  late final SubscriptionController subscription = SubscriptionController();
  late final JaleThemeController themeController = JaleThemeController();

  @override
  void initState() {
    super.initState();
    themeController.addListener(_redraw);
    themeController.load();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_redraw);
    themeController.dispose();
    subscription.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Jale',
    theme: themeController.theme,
    home: FutureBuilder<Database>(
      future: database,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorScreen(
            title: 'No pudimos abrir tus datos',
            message: 'La información local no se perdió. Intenta de nuevo.',
            retry: () => setState(() => database = openJaleDatabase()),
            home: () {},
          );
        }
        return snapshot.hasData
            ? JaleApp(
                db: snapshot.data!,
                subscription: subscription,
                themeController: themeController,
              )
            : const Loading();
      },
    ),
  );
}

class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({
    super.key,
    required this.title,
    required this.message,
    required this.retry,
    required this.home,
  });
  final String title;
  final String message;
  final VoidCallback retry;
  final VoidCallback home;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 64, color: colors.primary),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: retry,
                    child: const Text('Intentar de nuevo'),
                  ),
                ),
                TextButton(
                  onPressed: home,
                  child: const Text('Volver al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class JaleApp extends StatefulWidget {
  const JaleApp({
    super.key,
    required this.db,
    required this.subscription,
    required this.themeController,
  });
  final Database db;
  final SubscriptionController subscription;
  final JaleThemeController themeController;
  @override
  State<JaleApp> createState() => _JaleAppState();
}

class _JaleAppState extends State<JaleApp> {
  BusinessProfile? profile;
  List<QuoteSummary> quotes = [];
  List<Client> clients = [];
  UsageSummary? usage;
  int tab = 0;
  String? quoteId;
  String? loadError;
  bool pro = false;
  @override
  void initState() {
    super.initState();
    widget.subscription.addListener(_redraw);
    _refresh();
  }

  @override
  void dispose() {
    widget.subscription.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      final result = await Future.wait([
        getBusinessProfile(widget.db),
        listQuotes(widget.db),
        listClients(widget.db),
        getDocumentUsage(
          widget.db,
          limit: widget.subscription.manualQuoteLimit,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        loadError = null;
        profile = result[0] as BusinessProfile?;
        quotes = result[1] as List<QuoteSummary>;
        clients = result[2] as List<Client>;
        usage = result[3] as UsageSummary;
      });
    } catch (error) {
      if (mounted) setState(() => loadError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loadError != null) {
      return AppErrorScreen(
        title: 'Algo salió mal',
        message:
            'No pudimos actualizar tus datos. Tus cambios guardados siguen en el teléfono.',
        retry: _refresh,
        home: () => setState(() {
          loadError = null;
          quoteId = null;
          tab = 0;
        }),
      );
    }
    if (widget.subscription.loading || usage == null) return const Loading();
    if (profile == null) {
      return Onboarding(
        save: (name, trade, phone, logoUri, iconKey) async {
          await saveBusinessProfile(
            widget.db,
            name: name,
            trade: trade,
            phone: phone,
            logoUri: logoUri,
            iconKey: iconKey,
            brandColor: defaultBrandColor,
          );
          await _refresh();
        },
      );
    }
    if (quoteId != null) {
      return QuotePage(
        db: widget.db,
        id: quoteId!,
        profile: profile!,
        clients: clients,
        isPro: widget.subscription.isPro,
        freeManualLimit: widget.subscription.manualQuoteLimit,
        close: () async {
          await _refresh();
          if (mounted) setState(() => quoteId = null);
        },
      );
    }
    final pages = [
      HomePage(
        quotes: quotes,
        usage: usage!,
        isPro: widget.subscription.isPro,
        create: () async {
          try {
            final id = await createQuote(widget.db);
            if (mounted) setState(() => quoteId = id);
          } catch (error) {
            if (context.mounted) _message(context, error);
          }
        },
        open: (id) => setState(() => quoteId = id),
        showPro: () => setState(() => pro = true),
      ),
      ClientPage(db: widget.db, clients: clients, refresh: _refresh),
      SettingsPage(
        db: widget.db,
        profile: profile!,
        isPro: widget.subscription.isPro,
        refresh: _refresh,
        showPro: () => setState(() => pro = true),
        themeController: widget.themeController,
        subscription: widget.subscription,
      ),
    ];
    if (pro) {
      return Paywall(
        subscription: widget.subscription,
        close: () => setState(() => pro = false),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              profile: profile!,
              isPro: widget.subscription.isPro,
              usage: usage!,
            ),
            Expanded(child: pages[tab]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Inicio',
          ),
          NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: CircularProgressIndicator(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.profile,
    required this.isPro,
    required this.usage,
  });
  final BusinessProfile profile;
  final bool isPro;
  final UsageSummary usage;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          BusinessMark(
            logoUri: profile.logoUri,
            trade: profile.trade,
            iconKey: profile.iconKey,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JALE - ${profile.trade.isEmpty ? 'OFICIOS' : profile.trade.toUpperCase()}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(
                  profile.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Chip(
            label: Text(isPro ? 'PRO' : '${usage.remaining} GRATIS'),
            backgroundColor: isPro
                ? colors.tertiaryContainer
                : colors.secondaryContainer,
          ),
        ],
      ),
    );
  }
}

class TitleLabel extends StatelessWidget {
  const TitleLabel(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      value,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      child: Text(text),
    ),
  );
}

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.save});
  final Future<void> Function(String, String, String, String?, String?) save;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final name = TextEditingController();
  final trade = TextEditingController();
  final phone = TextEditingController();
  String? logoUri;
  String? iconKey;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    trade.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Escribe el nombre de tu negocio para comenzar.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.save(name.text, trade.text, phone.text, logoUri, iconKey);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> selectLogo() async {
    try {
      final selected = await pickAndCropLogo(context);
      if (mounted && selected != null) {
        setState(() {
          logoUri = selected;
          iconKey = null;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, colors.primary.withValues(alpha: .82)],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: colors.secondary,
                    child: Text(
                      'J',
                      style: TextStyle(
                        color: colors.onSecondary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'JALE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 42),
              const Text(
                'Haz que tu trabajo se vea tan bien como lo haces.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Crea cotizaciones, registra abonos y comparte recibos desde tu teléfono, incluso sin señal.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .86),
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 26),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Primero, cuéntanos de tu negocio',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Esta información aparecerá en tus documentos.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: BusinessMark(
                          logoUri: logoUri,
                          trade: trade.text,
                          iconKey: iconKey,
                          size: 76,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : selectLogo,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            logoUri == null
                                ? 'Agregar logo (gratis)'
                                : 'Logo listo · cambiar',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Input(label: 'NOMBRE DEL NEGOCIO *', controller: name),
                      TradePicker(
                        controller: trade,
                        onChanged: () => setState(() {}),
                      ),
                      BusinessIconPicker(
                        value: iconKey,
                        onChanged: (value) => setState(() {
                          iconKey = value;
                          if (value != null) logoUri = null;
                        }),
                      ),
                      const SizedBox(height: 10),
                      Input(label: 'TELÉFONO', controller: phone),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      ActionButton(
                        text: saving ? 'Guardando...' : 'Comenzar',
                        onTap: saving ? () {} : submit,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Tus datos se guardan localmente en este dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .72),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Input extends StatelessWidget {
  const Input({
    super.key,
    required this.label,
    this.controller,
    this.initial,
    this.onChanged,
    this.lines = 1,
    this.enabled = true,
  });
  final String label;
  final TextEditingController? controller;
  final String? initial;
  final ValueChanged<String>? onChanged;
  final int lines;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      initialValue: controller == null ? initial : null,
      onChanged: onChanged,
      enabled: enabled,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class TradePicker extends StatefulWidget {
  const TradePicker({super.key, required this.controller, this.onChanged});
  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<TradePicker> createState() => _TradePickerState();
}

class _TradePickerState extends State<TradePicker> {
  late bool custom;

  @override
  void initState() {
    super.initState();
    custom =
        widget.controller.text.isNotEmpty &&
        !commonTrades.contains(widget.controller.text);
  }

  void notifyChanged() => widget.onChanged?.call();

  @override
  Widget build(BuildContext context) {
    if (custom) {
      return Column(
        children: [
          TextField(
            controller: widget.controller,
            onChanged: (_) => notifyChanged(),
            decoration: const InputDecoration(
              labelText: 'OFICIO PERSONALIZADO',
              hintText: 'Escribe tu especialidad',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  custom = false;
                  widget.controller.clear();
                });
                notifyChanged();
              },
              icon: const Icon(Icons.list_alt_outlined, size: 18),
              label: const Text('Ver catálogo de oficios'),
            ),
          ),
        ],
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: commonTrades.contains(widget.controller.text)
          ? widget.controller.text
          : null,
      decoration: const InputDecoration(
        labelText: 'OFICIO O ESPECIALIDAD',
        hintText: 'Selecciona un oficio',
        prefixIcon: Icon(Icons.handyman_outlined),
      ),
      items: [
        ...commonTrades.map(
          (trade) => DropdownMenuItem(
            value: trade,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tradeIcon(trade), size: 19),
                const SizedBox(width: 10),
                Text(trade),
              ],
            ),
          ),
        ),
        const DropdownMenuItem(
          value: '__custom__',
          child: Text('＋ Agregar otro oficio'),
        ),
      ],
      onChanged: (value) {
        if (value == '__custom__') {
          setState(() {
            custom = true;
            widget.controller.clear();
          });
        } else if (value != null) {
          widget.controller.text = value;
        }
        notifyChanged();
      },
    );
  }
}

class BusinessIconPicker extends StatelessWidget {
  const BusinessIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedKey = value == null || value!.isEmpty ? 'auto' : value;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ICONO DEL NEGOCIO',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Auto usa el oficio; también puedes elegir el icono de IA u otro.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: jaleIconChoices.map((choice) {
              final selected = choice.key == selectedKey;
              return Semantics(
                button: true,
                selected: selected,
                label: 'Usar icono ${choice.label}',
                child: InkWell(
                  onTap: () =>
                      onChanged(choice.key == 'auto' ? null : choice.key),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 61,
                    height: 57,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : colors.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          choice.icon,
                          size: 22,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          choice.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.quotes,
    required this.usage,
    required this.isPro,
    required this.create,
    required this.open,
    required this.showPro,
  });
  final List<QuoteSummary> quotes;
  final UsageSummary usage;
  final bool isPro;
  final Future<void> Function() create;
  final ValueChanged<String> open;
  final VoidCallback showPro;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DashboardRange range = DashboardRange.week;
  String query = '', filter = 'all';

  @override
  Widget build(BuildContext context) {
    final stats = dashboardSummary(widget.quotes, range);
    final colors = Theme.of(context).colorScheme;
    final visibleQuotes = widget.quotes.where((quote) {
      final text = query.trim().toLowerCase();
      final matchesText =
          text.isEmpty ||
          quote.clientName.toLowerCase().contains(text) ||
          formatFolio('COT', quote.quoteNumber).toLowerCase().contains(text);
      final stage = quoteStage(quote.status, quote.paymentStatus);
      final matchesFilter = switch (filter) {
        'collect' =>
          quote.status == QuoteStatus.accepted && quote.balanceCents > 0,
        'paid' => stage == QuoteStage.paid,
        'rejected' => stage == QuoteStage.rejected,
        _ => true,
      };
      return matchesText && matchesFilter;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: colors.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COTIZA EN MENOS DE UN MINUTO',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Que tu trabajo hable bien de ti.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: widget.create,
                  child: const Text('+ Nueva cotización'),
                ),
              ],
            ),
          ),
        ),
        if (!widget.isPro)
          Card(
            child: ListTile(
              onTap: widget.showPro,
              title: Text(
                '${widget.usage.used} de ${widget.usage.limit} cotizaciones manuales usadas',
              ),
              trailing: const Text('Ver Pro'),
            ),
          ),
        Row(
          children: [
            const Expanded(child: TitleLabel('RESUMEN DE TU JALE')),
            SegmentedButton<DashboardRange>(
              segments: const [
                ButtonSegment(
                  value: DashboardRange.week,
                  label: Text('Semana'),
                ),
                ButtonSegment(value: DashboardRange.month, label: Text('Mes')),
              ],
              selected: {range},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => range = value.first),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MoneyMetric(
                        label: 'COBRADO',
                        amount: stats.collectedCents,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MoneyMetric(
                        label: 'POR COBRAR',
                        amount: stats.pendingCents,
                        color: colors.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SimpleBarChart(
                  values: [
                    stats.created,
                    stats.accepted,
                    stats.partial,
                    stats.paid,
                  ],
                  labels: const ['Hechas', 'Aceptadas', 'Parciales', 'Pagadas'],
                ),
                if (stats.rejected > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${stats.rejected} no aceptada${stats.rejected == 1 ? '' : 's'} en este periodo',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            hintText: 'Buscar cliente o folio',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                [
                      ('all', 'Todas'),
                      ('collect', 'Por cobrar'),
                      ('paid', 'Pagadas'),
                      ('rejected', 'No aceptadas'),
                    ]
                    .map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: FilterChip(
                          label: Text(option.$2),
                          selected: filter == option.$1,
                          onSelected: (_) => setState(() => filter = option.$1),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        const TitleLabel('COTIZACIONES RECIENTES'),
        if (visibleQuotes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.quotes.isEmpty
                    ? 'Tu historial empieza aquí'
                    : 'No encontramos cotizaciones con este filtro.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...visibleQuotes.map(
            (q) => Card(
              child: ListTile(
                onTap: () => widget.open(q.id),
                title: Text(
                  q.clientName.isEmpty ? 'Cliente pendiente' : q.clientName,
                ),
                subtitle: Text(
                  '${formatFolio('COT', q.quoteNumber)} · ${quoteSummaryDisplayStatus(q)}${q.status == QuoteStatus.accepted && q.balanceCents > 0 ? '\nSaldo pendiente: ${money(q.balanceCents)}' : ''}',
                ),
                trailing: Text(money(q.totalCents)),
              ),
            ),
          ),
      ],
    );
  }
}

class _MoneyMetric extends StatelessWidget {
  const _MoneyMetric({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color)),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              money(amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SimpleBarChart extends StatelessWidget {
  const _SimpleBarChart({required this.values, required this.labels});
  final List<int> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<int>(1, math.max);
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (index) {
        final height = 14 + (64 * values[index] / maximum);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${values[index]}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: height,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: .18 + (index * .16)),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  child: Text(
                    labels[index],
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class QuotePage extends StatefulWidget {
  const QuotePage({
    super.key,
    required this.db,
    required this.id,
    required this.profile,
    required this.clients,
    required this.isPro,
    required this.freeManualLimit,
    required this.close,
  });
  final Database db;
  final String id;
  final BusinessProfile profile;
  final List<Client> clients;
  final bool isPro;
  final int freeManualLimit;
  final Future<void> Function() close;
  @override
  State<QuotePage> createState() => _QuotePageState();
}

class _QuotePageState extends State<QuotePage> with WidgetsBindingObserver {
  Quote? quote;
  String? error;
  Timer? timer;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadQuote();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final value = quote;
      if (value != null) {
        timer?.cancel();
        unawaited(saveDraft(value));
      }
    }
  }

  Future<void> loadQuote() async {
    try {
      final value = await getQuote(widget.db, widget.id);
      if (mounted) {
        setState(() {
          quote = value;
          error = value == null ? 'No encontramos esa cotización.' : null;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  void update(Quote value) {
    setState(() => quote = value);
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 500), () => saveDraft(value));
  }

  Future<void> closeToHome() async {
    if (closing) return;
    closing = true;
    try {
      timer?.cancel();
      final value = quote;
      if (value != null) await saveQuoteDraft(widget.db, value);
      await widget.close();
    } finally {
      closing = false;
    }
  }

  Future<void> saveDraft(Quote value) async {
    try {
      await saveQuoteDraft(widget.db, value);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  Future<void> finishAndReview() async {
    try {
      final wasDraft = quote!.finalizedAt == null;
      final value = await finalizeQuote(
        widget.db,
        quote!,
        widget.isPro,
        freeLimit: widget.freeManualLimit,
      );
      if (value == null) return;
      if (wasDraft) await markCatalogItemsUsed(widget.db, value.lines);
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => QuoteReadyPage(
            db: widget.db,
            profile: widget.profile,
            quote: value,
            isPro: widget.isPro,
          ),
        ),
      );
      final latest = await getQuote(widget.db, value.id);
      if (mounted && latest != null) setState(() => quote = latest);
    } catch (error) {
      if (mounted) _message(context, error);
    }
  }

  Future<void> showVoiceDemo() async {
    if (!AiApi.isConfigured) {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const VoiceAiDemoPage()));
      return;
    }
    final catalogItems = await listCatalogItems(widget.db);
    if (!mounted) return;
    final result = await Navigator.of(context).push<AiQuoteDraft>(
      MaterialPageRoute(
        builder: (_) => AiQuoteAssistantPage(
          trade: widget.profile.trade,
          clientHint: quote?.clientName ?? '',
          catalogItems: catalogItems,
          existingLines: quote?.lines ?? const [],
        ),
      ),
    );
    if (result == null || !mounted || quote == null) return;
    final value = quote!;
    final aiLines = result.lines.asMap().entries.map((entry) {
      final suggestion = suggestCatalogItem(entry.value.concept, catalogItems);
      final price = entry.value.unitPriceCents == 0 && suggestion != null
          ? suggestion.item.unitPriceCents
          : entry.value.unitPriceCents;
      return QuoteLine(
        id: newId(),
        concept: entry.value.concept,
        quantity: entry.value.quantity,
        unitPriceCents: price,
        position: entry.key,
      );
    }).toList();
    final meaningfulExisting = value.lines
        .where(
          (line) => line.concept.trim().isNotEmpty || line.unitPriceCents > 0,
        )
        .length;
    final lines = appendUniqueQuoteLines(value.lines, aiLines);
    final skippedDuplicates =
        aiLines.length - (lines.length - meaningfulExisting);
    update(
      value.copyWith(
        clientName: result.clientName.isEmpty
            ? value.clientName
            : result.clientName,
        notes: result.notes.isEmpty ? value.notes : result.notes,
        lines: lines,
        origin: QuoteOrigin.ai,
      ),
    );
    final saveToCatalog = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('¿Guardar estos conceptos?'),
        content: const Text(
          'Los tendrás listos para tu siguiente cotización con el precio que acabas de revisar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Guardar en catálogo'),
          ),
        ],
      ),
    );
    if (saveToCatalog == true) {
      for (final line in aiLines.where((line) => line.unitPriceCents > 0)) {
        await saveCatalogItem(
          widget.db,
          concept: line.concept,
          unitPriceCents: line.unitPriceCents,
        );
      }
      if (mounted) {
        _message(context, Exception('Conceptos guardados en tu catálogo.'));
      }
    }
    if (skippedDuplicates > 0 && mounted) {
      _message(
        context,
        Exception(
          '$skippedDuplicates concepto(s) parecido(s) ya estaban en la cotización; no se duplicaron.',
        ),
      );
    }
  }

  Future<void> addFromCatalog() async {
    final items = await listCatalogItems(widget.db);
    if (!mounted) return;
    if (items.isEmpty) {
      _message(
        context,
        Exception(
          'Tu catálogo todavía está vacío. La IA te sugerirá qué guardar.',
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<CatalogItem>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            const Text(
              'Tu catálogo',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text('Toca un concepto para agregarlo con su último precio.'),
            const SizedBox(height: 10),
            ...items.map(
              (item) => ListTile(
                onTap: () => Navigator.pop(sheet, item),
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text(item.concept),
                subtitle: Text(money(item.unitPriceCents)),
                trailing: item.timesUsed > 0
                    ? Text('${item.timesUsed} usos')
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || quote == null) return;
    final value = quote!;
    update(
      value.copyWith(
        lines: [
          ...value.lines.where(
            (line) => line.concept.isNotEmpty || line.unitPriceCents > 0,
          ),
          QuoteLine(
            id: newId(),
            concept: selected.concept,
            quantity: 1,
            unitPriceCents: selected.unitPriceCents,
            position: value.lines.length,
          ),
        ],
      ),
    );
  }

  Future<void> changeStatus(QuoteStatus status) async {
    try {
      final latest = await setQuoteStatus(widget.db, quote!.id, status);
      if (mounted && latest != null) setState(() => quote = latest);
    } catch (error) {
      if (mounted) _message(context, error);
    }
  }

  Future<void> saveClientFromQuote() async {
    try {
      final value = quote!;
      final client = await saveClient(widget.db, name: value.clientName);
      final linked = value.copyWith(clientId: client.id);
      await saveQuoteDraft(widget.db, linked);
      if (mounted) setState(() => quote = linked);
      if (mounted) {
        _message(context, Exception('Cliente guardado en tu catálogo.'));
      }
    } catch (error) {
      if (mounted) _message(context, error);
    }
  }

  Future<void> addPayment() async {
    try {
      final value = quote!;
      final summary = paymentSummary(value.totalCents, value.payments);
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialog) => PaymentDialog(
          balanceCents: summary.balanceCents,
          save: (method, amountCents, notes) async {
            await recordPayment(widget.db, value, method, amountCents, notes);
            if (dialog.mounted) Navigator.pop(dialog, true);
          },
        ),
      );
      if (saved == true) {
        final latest = await getQuote(widget.db, value.id);
        if (mounted && latest != null) setState(() => quote = latest);
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  Future<void> shareReceipt(Payment payment) async {
    try {
      final finalized = await finalizeReceipt(
        widget.db,
        payment.id,
        widget.isPro,
      );
      final latest = await getQuote(widget.db, quote!.id);
      if (latest == null) return;
      await shareReceiptPdf(widget.profile, latest, finalized, widget.isPro);
      if (mounted) setState(() => quote = latest);
    } catch (error) {
      if (mounted) _message(context, error);
    }
  }

  Future<void> voidPaymentAndReload(Payment payment) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Anular pago'),
        content: const Text(
          'El registro se conservará para mantener trazabilidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await voidPayment(widget.db, payment.id);
      final latest = await getQuote(widget.db, quote!.id);
      if (mounted && latest != null) setState(() => quote = latest);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) closeToHome();
        },
        child: AppErrorScreen(
          title: 'No pudimos abrir esta cotización',
          message:
              'Tus datos locales siguen protegidos. Puedes volver al historial o intentar de nuevo.',
          retry: loadQuote,
          home: closeToHome,
        ),
      );
    }
    final value = quote;
    if (value == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) closeToHome();
        },
        child: const Loading(),
      );
    }
    final contentLocked = value.payments.any(
      (payment) => payment.voidedAt == null,
    );
    final items = <Widget>[
      if (value.status != QuoteStatus.draft)
        Row(
          children: [
            Chip(
              label: Text(quoteDisplayStatus(value)),
              backgroundColor: value.status == QuoteStatus.accepted
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : const Color(0xffe4f0f4),
            ),
            const Spacer(),
            if (value.status != QuoteStatus.accepted)
              TextButton(
                onPressed: () => changeStatus(QuoteStatus.accepted),
                child: const Text('Cliente aceptó'),
              ),
            if (value.status != QuoteStatus.rejected &&
                !value.payments.any((payment) => payment.voidedAt == null))
              TextButton(
                onPressed: () => changeStatus(QuoteStatus.rejected),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('No aceptó'),
              ),
          ],
        ),
      if (contentLocked)
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: const ListTile(
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('Total protegido'),
            subtitle: Text(
              'Anula los pagos antes de cambiar cliente, conceptos o total.',
            ),
          ),
        ),
      VoiceAiCard(onTap: contentLocked ? () {} : showVoiceDemo),
      ClientChooser(
        initial: value.clientName,
        clients: widget.clients,
        enabled: !contentLocked,
        onTyped: (text) => update(
          value.copyWith(
            unlinkClient: true,
            clientName: text,
            clientPhone: '',
            clientAddress: '',
          ),
        ),
        onSelected: (client) => update(
          value.copyWith(
            clientId: client.id,
            clientName: client.name,
            clientPhone: client.phone,
            clientAddress: client.address,
          ),
        ),
        onSaveNew: value.clientId == null ? saveClientFromQuote : null,
      ),
      Row(
        children: [
          const Expanded(child: TitleLabel('CONCEPTOS')),
          TextButton.icon(
            onPressed: contentLocked ? null : addFromCatalog,
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Catálogo'),
          ),
        ],
      ),
    ];
    for (var i = 0; i < value.lines.length; i++) {
      final line = value.lines[i];
      items.add(
        LineInput(
          line: line,
          enabled: !contentLocked,
          onDelete: () {
            final lines = [...value.lines]..removeAt(i);
            update(value.copyWith(lines: lines));
          },
          onChanged: (next) {
            final lines = [...value.lines];
            lines[i] = next;
            update(value.copyWith(lines: lines));
          },
        ),
      );
    }
    items.addAll([
      OutlinedButton(
        onPressed: contentLocked
            ? null
            : () => update(
                value.copyWith(
                  lines: [
                    ...value.lines,
                    newLinePlaceholder(value.lines.length),
                  ],
                ),
              ),
        child: const Text('+ Agregar concepto'),
      ),
      Input(
        label: 'NOTAS',
        initial: value.notes,
        lines: 3,
        enabled: !contentLocked,
        onChanged: (text) => update(value.copyWith(notes: text)),
      ),
    ]);
    if (value.status == QuoteStatus.accepted) {
      final summary = paymentSummary(value.totalCents, value.payments);
      items.addAll([
        const TitleLabel('PAGOS'),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pagado'),
                    Text(
                      money(summary.paidCents),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Saldo'),
                    Text(
                      money(summary.balanceCents),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ...value.payments.map(
          (payment) => Card(
            child: ListTile(
              title: Text(formatFolio('REC', payment.receiptNumber)),
              subtitle: Text(
                '${money(payment.amountCents)} · ${paymentMethodLabel(payment.method)}${payment.voidedAt == null ? '' : ' · ANULADO'}',
              ),
              trailing: payment.voidedAt != null
                  ? Icon(
                      Icons.block,
                      color: Theme.of(context).colorScheme.error,
                    )
                  : PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'share') shareReceipt(payment);
                        if (action == 'void') voidPaymentAndReload(payment);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'share',
                          child: Text('Compartir recibo'),
                        ),
                        PopupMenuItem(value: 'void', child: Text('Anular')),
                      ],
                    ),
            ),
          ),
        ),
        if (summary.balanceCents > 0)
          ActionButton(text: '+ Registrar pago', onTap: addPayment),
      ]);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeToHome();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 54,
          title: Text(formatFolio('COT', value.quoteNumber)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: closeToHome,
          ),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: items),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        money(quoteTotal(value.lines)),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: finishAndReview,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: Text(
                        value.status == QuoteStatus.draft
                            ? 'Finalizar y ver PDF'
                            : 'Ver y compartir PDF',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuoteReadyPage extends StatefulWidget {
  const QuoteReadyPage({
    super.key,
    required this.db,
    required this.profile,
    required this.quote,
    required this.isPro,
  });
  final Database db;
  final BusinessProfile profile;
  final Quote quote;
  final bool isPro;

  @override
  State<QuoteReadyPage> createState() => _QuoteReadyPageState();
}

class _QuoteReadyPageState extends State<QuoteReadyPage> {
  bool sharing = false;

  Future<void> share() async {
    setState(() => sharing = true);
    try {
      await shareQuotePdf(widget.profile, widget.quote, widget.isPro);
      if (widget.quote.status == QuoteStatus.finalized) {
        await setQuoteStatus(widget.db, widget.quote.id, QuoteStatus.sent);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => sharing = false);
        _message(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cotización lista')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.primary,
                  child: const Icon(Icons.check_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '¡Cotización guardada!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Revísala antes de enviarla a tu cliente.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) =>
                  quotePdfBytes(widget.profile, widget.quote, widget.isPro),
              useActions: false,
              allowPrinting: false,
              allowSharing: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName:
                  '${formatFolio('COT', widget.quote.quoteNumber)}.pdf',
              onError: (_, _) => const Center(
                child: Text('No pudimos mostrar la vista previa.'),
              ),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: sharing ? null : () => Navigator.pop(context),
                    child: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: sharing ? null : share,
                    icon: sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_outlined),
                    label: Text(sharing ? 'Abriendo...' : 'Compartir PDF'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceAiCard extends StatelessWidget {
  const VoiceAiCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.secondary,
                foregroundColor: colors.onSecondary,
                child: const Icon(Icons.mic_none_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 2,
                      children: [
                        Text(
                          'Cotiza hablando',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Chip(
                          label: Text(AiApi.isConfigured ? 'BETA' : 'DEMO'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      AiApi.isConfigured
                          ? 'Habla y revisa los conceptos antes de agregarlos.'
                          : 'Mira la demo completa: voz, IA, cotización y PDF.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                AiApi.isConfigured
                    ? Icons.arrow_forward_rounded
                    : Icons.play_circle_outline_rounded,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VoiceAiDemoPage extends StatefulWidget {
  const VoiceAiDemoPage({super.key});

  @override
  State<VoiceAiDemoPage> createState() => _VoiceAiDemoPageState();
}

class _VoiceAiDemoPageState extends State<VoiceAiDemoPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController waveform;
  Timer? demoTimer;
  int stage = 0;

  @override
  void initState() {
    super.initState();
    waveform = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  void playDemo() {
    demoTimer?.cancel();
    setState(() => stage = 1);
    waveform.repeat(reverse: true);
    demoTimer = Timer.periodic(const Duration(milliseconds: 1350), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (stage >= 4) {
        timer.cancel();
        waveform.stop();
        return;
      }
      setState(() => stage++);
      if (stage == 4) waveform.stop();
    });
  }

  void resetDemo() {
    demoTimer?.cancel();
    waveform.stop();
    setState(() => stage = 0);
  }

  @override
  void dispose() {
    demoTimer?.cancel();
    waveform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cotizar con voz'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: const Text('DEMO'),
              visualDensity: VisualDensity.compact,
              backgroundColor: colors.secondaryContainer,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            color: colors.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: colors.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Esto es una simulación de cómo funcionará la voz + IA. No activa tu micrófono, no manda datos y no consume documentos.',
                      style: TextStyle(color: colors.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'De una frase a una cotización lista',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Mira el recorrido completo que tendrá la función cuando la liberemos.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 15),
          ),
          const SizedBox(height: 22),
          DemoStageIndicator(stage: stage),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _stageCard(context),
          ),
          const SizedBox(height: 18),
          if (stage < 4)
            FilledButton.icon(
              onPressed: playDemo,
              icon: Icon(
                stage == 0
                    ? Icons.play_arrow_rounded
                    : Icons.fast_forward_rounded,
              ),
              label: Text(
                stage == 0 ? 'Reproducir demo completa' : 'Continuar demo',
              ),
            )
          else ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DemoPdfPage())),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Ver PDF de ejemplo'),
            ),
            OutlinedButton.icon(
              onPressed: resetDemo,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Repetir demostración'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stageCard(BuildContext context) {
    switch (stage) {
      case 1:
        return DemoListeningCard(
          key: const ValueKey('listening'),
          controller: waveform,
        );
      case 2:
        return const DemoTranscriptCard(key: ValueKey('transcript'));
      case 3:
        return const DemoParsingCard(key: ValueKey('parsing'));
      case 4:
        return const DemoQuoteResultCard(key: ValueKey('ready'));
      default:
        return const DemoIntroCard(key: ValueKey('intro'));
    }
  }
}

class DemoStageIndicator extends StatelessWidget {
  const DemoStageIndicator({super.key, required this.stage});
  final int stage;

  @override
  Widget build(BuildContext context) {
    const labels = ['Hablas', 'Transcribe', 'Ordena', 'Lista'];
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: index <= stage
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  foregroundColor: index <= stage
                      ? colors.onPrimary
                      : colors.onSurfaceVariant,
                  child: Text('${index + 1}'),
                ),
                const SizedBox(height: 5),
                Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: index <= stage
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class DemoIntroCard extends StatelessWidget {
  const DemoIntroCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          Icon(
            Icons.mic_none_rounded,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          const Text(
            'Tú hablas. Jale entiende.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Pulsa reproducir para ver una simulación completa.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class DemoListeningCard extends StatelessWidget {
  const DemoListeningCard({super.key, required this.controller});
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'Escuchando…',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          DemoWaveform(animation: controller),
          const SizedBox(height: 14),
          Text(
            'Detectando una solicitud de cotización',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class DemoWaveform extends StatelessWidget {
  const DemoWaveform({super.key, required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => SizedBox(
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < 13; index++)
            Container(
              width: 5,
              height:
                  15 +
                  (math.sin(animation.value * math.pi * 2 + index).abs() * 36),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        ],
      ),
    ),
  );
}

class DemoTranscriptCard extends StatelessWidget {
  const DemoTranscriptCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Texto entendido',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '“Para Miguel González, una tubería nueva con cambio de chapa, cada uno en 500 pesos.”',
            style: TextStyle(fontSize: 17, height: 1.35),
          ),
        ],
      ),
    ),
  );
}

class DemoParsingCard extends StatelessWidget {
  const DemoParsingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Jale está ordenando la información',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(color: colors.primary),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: const [
                Chip(
                  avatar: Icon(Icons.person_outline, size: 18),
                  label: Text('Cliente'),
                ),
                Chip(
                  avatar: Icon(Icons.list_alt_outlined, size: 18),
                  label: Text('Conceptos'),
                ),
                Chip(
                  avatar: Icon(Icons.attach_money, size: 18),
                  label: Text('Precios'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DemoQuoteResultCard extends StatelessWidget {
  const DemoQuoteResultCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Cotización preparada',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                const Text('COT-000042', style: TextStyle(fontSize: 11)),
              ],
            ),
            const Divider(height: 22),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.person_outline),
              title: Text('Cliente'),
              subtitle: Text('Miguel González'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.plumbing_outlined),
              title: Text('Tubería nueva'),
              trailing: Text(r'$500'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.lock_outline),
              title: Text('Cambio de chapa'),
              trailing: Text(r'$500'),
            ),
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  r'$1,000',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DemoPdfPage extends StatelessWidget {
  const DemoPdfPage({super.key});

  static const profile = BusinessProfile(
    id: 'demo-business',
    name: 'Oficios González',
    trade: 'Plomería',
    phone: '55 0000 0000',
    logoUri: null,
    iconKey: 'water',
    brandColor: defaultBrandColor,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  );
  static const quote = Quote(
    id: 'demo-quote',
    quoteNumber: 42,
    clientId: null,
    clientName: 'Miguel González',
    status: QuoteStatus.finalized,
    issuedAt: '2026-01-01T00:00:00Z',
    validUntil: null,
    notes: '',
    totalCents: 100000,
    finalizedAt: '2026-01-01T00:00:00Z',
    quotaPeriod: '2026-01',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    lines: [
      QuoteLine(
        id: 'demo-line-1',
        concept: 'Tubería nueva',
        quantity: 1,
        unitPriceCents: 50000,
        position: 0,
      ),
      QuoteLine(
        id: 'demo-line-2',
        concept: 'Cambio de chapa',
        quantity: 1,
        unitPriceCents: 50000,
        position: 1,
      ),
    ],
    payments: [],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PDF de ejemplo')),
    body: PdfPreview(
      build: (_) => quotePdfBytes(profile, quote, false),
      useActions: false,
      allowPrinting: false,
      allowSharing: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      padding: const EdgeInsets.all(12),
    ),
  );
}

class ClientChooser extends StatelessWidget {
  const ClientChooser({
    super.key,
    required this.initial,
    required this.clients,
    required this.onTyped,
    required this.onSelected,
    this.onSaveNew,
    this.enabled = true,
  });
  final String initial;
  final List<Client> clients;
  final ValueChanged<String> onTyped;
  final ValueChanged<Client> onSelected;
  final VoidCallback? onSaveNew;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_search_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'CLIENTE',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Autocomplete<Client>(
            initialValue: TextEditingValue(text: initial),
            displayStringForOption: (client) => client.name,
            optionsBuilder: (value) {
              final query = value.text.trim().toLowerCase();
              if (query.isEmpty) return clients;
              return clients.where(
                (client) =>
                    client.name.toLowerCase().contains(query) ||
                    client.phone.toLowerCase().contains(query),
              );
            },
            onSelected: onSelected,
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onTyped,
                  onSubmitted: (_) => onSubmitted(),
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del cliente *',
                    hintText: 'Busca un cliente o escribe uno nuevo',
                  ),
                ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 5),
            child: Text(
              clients.isEmpty
                  ? 'Escribe el nombre; podrás guardarlo después en Clientes.'
                  : 'Busca por nombre o teléfono, o escribe un cliente nuevo.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          if (onSaveNew != null && enabled)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: initial.trim().isEmpty ? null : onSaveNew,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Guardar este cliente en el catálogo'),
              ),
            ),
        ],
      ),
    ),
  );
}

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({
    super.key,
    required this.balanceCents,
    required this.save,
  });
  final int balanceCents;
  final Future<void> Function(PaymentMethod, int, String) save;
  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final amount = TextEditingController();
  final notes = TextEditingController();
  PaymentMethod method = PaymentMethod.cash;
  bool busy = false;

  @override
  void dispose() {
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final cents = parseMoneyToCents(amount.text);
    if (cents <= 0 || cents > widget.balanceCents) {
      _message(context, Exception('Escribe un abono válido dentro del saldo.'));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.save(method, cents, notes.text);
    } catch (error) {
      if (mounted) {
        setState(() => busy = false);
        _message(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar pago'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo actual: ${money(widget.balanceCents)}'),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Importe *'),
          ),
          const SizedBox(height: 12),
          const Text('Forma de pago'),
          Wrap(
            spacing: 6,
            children: PaymentMethod.values
                .map(
                  (value) => ChoiceChip(
                    label: Text(paymentMethodLabel(value)),
                    selected: method == value,
                    onSelected: (_) => setState(() => method = value),
                  ),
                )
                .toList(),
          ),
          TextField(
            controller: notes,
            decoration: const InputDecoration(labelText: 'Nota'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? 'Guardando...' : 'Guardar pago'),
      ),
    ],
  );
}

class LineInput extends StatelessWidget {
  const LineInput({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onDelete,
    this.enabled = true,
  });
  final QuoteLine line;
  final ValueChanged<QuoteLine> onChanged;
  final VoidCallback onDelete;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final quantity = TextFormField(
      initialValue: '${line.quantity}',
      keyboardType: TextInputType.number,
      enabled: enabled,
      onChanged: (text) =>
          onChanged(line.copyWith(quantity: double.tryParse(text) ?? 0)),
    );
    final price = TextFormField(
      initialValue: '${line.unitPriceCents / 100}',
      keyboardType: TextInputType.number,
      enabled: enabled,
      onChanged: (text) =>
          onChanged(line.copyWith(unitPriceCents: parseMoneyToCents(text))),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: line.concept,
                    decoration: const InputDecoration(
                      hintText: 'Trabajo o material',
                    ),
                    enabled: enabled,
                    onChanged: (text) =>
                        onChanged(line.copyWith(concept: text)),
                  ),
                ),
                IconButton(
                  onPressed: enabled ? onDelete : null,
                  tooltip: 'Eliminar concepto',
                  icon: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: quantity),
                Expanded(child: price),
                Text(money((line.quantity * line.unitPriceCents).round())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ClientPage extends StatelessWidget {
  const ClientPage({
    super.key,
    required this.db,
    required this.clients,
    required this.refresh,
  });
  final Database db;
  final List<Client> clients;
  final Future<void> Function() refresh;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const TitleLabel('CLIENTES'),
          IconButton.filled(
            onPressed: () => clientDialog(context, db, null, refresh),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      if (clients.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 42),
                SizedBox(height: 8),
                Text(
                  'Todavía no tienes clientes guardados.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                Text(
                  'Agrégalos aquí y después podrás elegirlos al hacer una cotización.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ...clients.map(
        (client) => Card(
          child: ListTile(
            onTap: () => clientDialog(context, db, client, refresh),
            title: Text(client.name),
            subtitle: Text(
              client.phone.isEmpty ? 'Sin telefono' : client.phone,
            ),
          ),
        ),
      ),
    ],
  );
}

class ClientEditorPage extends StatefulWidget {
  const ClientEditorPage({super.key, required this.db, this.client});
  final Database db;
  final Client? client;

  @override
  State<ClientEditorPage> createState() => _ClientEditorPageState();
}

class _ClientEditorPageState extends State<ClientEditorPage> {
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController address;
  late final TextEditingController notes;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.client?.name);
    phone = TextEditingController(text: widget.client?.phone);
    address = TextEditingController(text: widget.client?.address);
    notes = TextEditingController(text: widget.client?.notes);
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Escribe el nombre del cliente.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await saveClient(
        widget.db,
        id: widget.client?.id,
        name: name.text,
        phone: phone.text,
        address: address.text,
        notes: notes.text,
        createdAt: widget.client?.createdAt,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editing = widget.client != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Editar cliente' : 'Nuevo cliente')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Card(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    child: const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      editing
                          ? 'Actualiza los datos para encontrarlos rápido al cotizar.'
                          : 'Guarda los datos una sola vez y reutilízalos en tus cotizaciones.',
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: name,
            autofocus: !editing,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del cliente *',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: notes,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notas',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: colors.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: FilledButton.icon(
          onPressed: saving ? null : submit,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(saving ? 'Guardando…' : 'Guardar cliente'),
        ),
      ),
    );
  }
}

Future<void> clientDialog(
  BuildContext context,
  Database db,
  Client? client,
  Future<void> Function() refresh,
) async {
  try {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientEditorPage(db: db, client: client),
      ),
    );
    if (saved == true) await refresh();
  } catch (error) {
    if (context.mounted) _message(context, error);
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.db,
    required this.profile,
    required this.isPro,
    required this.refresh,
    required this.showPro,
    required this.themeController,
    required this.subscription,
  });
  final Database db;
  final BusinessProfile profile;
  final bool isPro;
  final Future<void> Function() refresh;
  final VoidCallback showPro;
  final JaleThemeController themeController;
  final SubscriptionController subscription;
  @override
  Widget build(BuildContext context) {
    Future<void> selectPalette(JalePalette palette) async {
      try {
        await themeController.select(palette);
      } catch (error) {
        if (context.mounted) _message(context, error);
      }
    }

    User? signedInUser;
    if (AiApi.authConfigured) {
      signedInUser = Supabase.instance.client.auth.currentUser;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TitleLabel('TU NEGOCIO'),
        Card(
          child: ListTile(
            leading: BusinessMark(
              logoUri: profile.logoUri,
              trade: profile.trade,
              iconKey: profile.iconKey,
              size: 46,
            ),
            title: Text(profile.name),
            subtitle: Text(
              '${profile.trade}${profile.phone.isEmpty ? '' : ' · ${profile.phone}'}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => profileEditor(context, db, profile, refresh),
          ),
        ),
        const TitleLabel('APARIENCIA'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text('Elige el ambiente de Jale'),
                subtitle: Text('Puedes cambiarlo cuando quieras.'),
              ),
              ...jalePalettes.map(
                (palette) => ListTile(
                  onTap: () => selectPalette(palette),
                  title: Text(palette.name),
                  subtitle: Text(palette.description),
                  leading: CircleAvatar(
                    radius: 13,
                    backgroundColor: palette.primary,
                  ),
                  trailing: themeController.palette.id == palette.id
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const Icon(Icons.circle_outlined),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Tema oscuro'),
                subtitle: const Text(
                  'Fondo negro y contraste suave para la noche.',
                ),
                value: themeController.darkMode,
                onChanged: (value) async {
                  try {
                    await themeController.setDarkMode(value);
                  } catch (error) {
                    if (context.mounted) _message(context, error);
                  }
                },
              ),
            ],
          ),
        ),
        const TitleLabel('CUENTA'),
        Card(
          child: ListTile(
            leading: Icon(
              signedInUser == null
                  ? Icons.person_add_alt_rounded
                  : Icons.verified_user_outlined,
            ),
            title: Text(signedInUser?.email ?? 'Guardar mis créditos'),
            subtitle: Text(
              signedInUser == null
                  ? 'Regístrate por correo para obtener 2 usos extra de IA.'
                  : 'Tu cuenta protege créditos y compras de Jale Pro.',
            ),
            trailing: Icon(
              signedInUser == null
                  ? Icons.arrow_forward_rounded
                  : Icons.more_vert_rounded,
            ),
            onTap: () async {
              if (signedInUser == null) {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const EmailRegistrationPage(),
                  ),
                );
                await refresh();
                return;
              }
              final signOut = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Cuenta de Jale'),
                  content: Text(signedInUser!.email ?? ''),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Cerrar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
              if (signOut == true) {
                await Supabase.instance.client.auth.signOut();
                await refresh();
              }
            },
          ),
        ),
        const TitleLabel('SUSCRIPCIÓN'),
        Card(
          child: ListTile(
            title: Text(isPro ? 'Jale Pro' : 'Plan Gratis'),
            trailing: Text(
              isPro ? 'PRO' : 'Mejorar',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            onTap: isPro
                ? () async {
                    try {
                      await subscription.manage();
                    } catch (error) {
                      if (context.mounted) _message(context, error);
                    }
                  }
                : showPro,
          ),
        ),
        const TitleLabel('RESPALDO'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Exportar respaldo cifrado'),
                onTap: () => backupDialog(context, db, true, refresh),
              ),
              ListTile(
                title: const Text('Importar respaldo'),
                onTap: () => backupDialog(context, db, false, refresh),
              ),
            ],
          ),
        ),
        const TitleLabel('PRIVACIDAD'),
        Card(
          child: ListTile(
            title: const Text('Borrar todos los datos locales'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('¿Borrar todo de este teléfono?'),
                  content: const Text(
                    'Se eliminarán clientes, cotizaciones, pagos y catálogo. Esta acción no se puede deshacer sin un respaldo.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(dialog).colorScheme.error,
                      ),
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Sí, borrar todo'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await deleteAllLocalData(db);
                await refresh();
              } catch (error) {
                if (context.mounted) _message(context, error);
              }
            },
          ),
        ),
      ],
    );
  }
}

Future<void> profileEditor(
  BuildContext context,
  Database db,
  BusinessProfile profile,
  Future<void> Function() refresh,
) async {
  try {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BusinessProfileEditorPage(db: db, profile: profile),
      ),
    );
    if (saved == true) await refresh();
  } catch (error) {
    if (context.mounted) _message(context, error);
  }
}

class BusinessProfileEditorPage extends StatefulWidget {
  const BusinessProfileEditorPage({
    super.key,
    required this.db,
    required this.profile,
  });
  final Database db;
  final BusinessProfile profile;

  @override
  State<BusinessProfileEditorPage> createState() =>
      _BusinessProfileEditorPageState();
}

class _BusinessProfileEditorPageState extends State<BusinessProfileEditorPage> {
  late final TextEditingController name;
  late final TextEditingController trade;
  late final TextEditingController phone;
  late String? logoUri;
  late String? iconKey;
  late String brandColor;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.profile.name);
    trade = TextEditingController(text: widget.profile.trade);
    phone = TextEditingController(text: widget.profile.phone);
    logoUri = widget.profile.logoUri;
    iconKey = widget.profile.iconKey;
    brandColor = normalizeBrandColor(widget.profile.brandColor);
  }

  @override
  void dispose() {
    name.dispose();
    trade.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> chooseLogo() async {
    try {
      final selected = await pickAndCropLogo(context);
      if (mounted && selected != null) {
        setState(() {
          logoUri = selected;
          iconKey = null;
          error = null;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Escribe el nombre de tu negocio.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await saveBusinessProfile(
        widget.db,
        name: name.text,
        trade: trade.text,
        phone: phone.text,
        logoUri: logoUri,
        iconKey: iconKey,
        brandColor: brandColor,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const documentColors = [
      '#0E5E4A',
      '#215A8E',
      '#8A422A',
      '#5F477C',
      '#20272B',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Identidad del negocio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Card(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  BusinessMark(
                    logoUri: logoUri,
                    trade: trade.text,
                    iconKey: iconKey,
                    size: 76,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Así te verán tus clientes',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'El logo o icono aparecerá en tu app y en el PDF.',
                          style: TextStyle(color: colors.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del negocio *',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TradePicker(controller: trade, onChanged: () => setState(() {})),
          const SizedBox(height: 2),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'LOGO O ICONO',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'Puedes subir una foto gratis o elegir un icono precargado.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: saving ? null : chooseLogo,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                logoUri == null ? 'Subir logo gratis' : 'Cambiar foto',
              ),
            ),
          ),
          BusinessIconPicker(
            value: iconKey,
            onChanged: (value) => setState(() {
              iconKey = value;
              if (value != null) logoUri = null;
            }),
          ),
          Text(
            'COLOR DEL DOCUMENTO',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'Se verá en la cabecera de tus PDFs. Esta opción es gratuita.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: documentColors.map((value) {
              final selected = brandColor == value;
              return Semantics(
                button: true,
                selected: selected,
                label: 'Elegir color $value',
                child: GestureDetector(
                  onTap: () => setState(() => brandColor = value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: selected ? 46 : 40,
                    height: selected ? 46 : 40,
                    decoration: BoxDecoration(
                      color: colorFromHex(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? colors.onSurface : Colors.transparent,
                        width: selected ? 3 : 0,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorFromHex(brandColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Vista previa del encabezado del PDF',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: colors.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: FilledButton.icon(
          onPressed: saving ? null : submit,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(saving ? 'Guardando…' : 'Guardar cambios'),
        ),
      ),
    );
  }
}

Future<void> profileDialog(
  BuildContext context,
  Database db,
  BusinessProfile profile,
  bool isPro,
  Future<void> Function() refresh,
) async {
  final name = TextEditingController(text: profile.name);
  final trade = TextEditingController(text: profile.trade);
  final phone = TextEditingController(text: profile.phone);
  var logoUri = profile.logoUri;
  var iconKey = profile.iconKey;
  var brandColor = normalizeBrandColor(profile.brandColor);
  var busy = false;
  await showDialog(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setLocal) => AlertDialog(
        title: const Text('Identidad del negocio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              TradePicker(controller: trade, onChanged: () => setLocal(() {})),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Telefono'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              BusinessMark(
                logoUri: logoUri,
                trade: trade.text,
                iconKey: iconKey,
                size: 72,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    try {
                      final selected = await pickAndCropLogo(dialog);
                      if (dialog.mounted && selected != null) {
                        setLocal(() {
                          logoUri = selected;
                          iconKey = null;
                        });
                      }
                    } catch (error) {
                      if (dialog.mounted) _message(dialog, error);
                    }
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    logoUri == null
                        ? 'Elegir logo (gratis)'
                        : 'Logo seleccionado',
                  ),
                ),
              ),
              BusinessIconPicker(
                value: iconKey,
                onChanged: (value) => setLocal(() {
                  iconKey = value;
                  if (value != null) logoUri = null;
                }),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'COLOR DE TUS DOCUMENTOS',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Se verá en la cabecera de tus PDFs. Esta opción es gratuita.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  children:
                      [
                        '#0E5E4A',
                        '#215A8E',
                        '#8A422A',
                        '#5F477C',
                        '#20272B',
                      ].map((value) {
                        final selected = brandColor == value;
                        return Semantics(
                          button: true,
                          label: 'Elegir color $value',
                          child: GestureDetector(
                            onTap: () => setLocal(() => brandColor = value),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: selected ? 46 : 40,
                              height: selected ? 46 : 40,
                              decoration: BoxDecoration(
                                color: colorFromHex(value),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(dialog).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: selected ? 3 : 0,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorFromHex(brandColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Vista previa de tu documento',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setLocal(() => busy = true);
                    try {
                      await saveBusinessProfile(
                        db,
                        name: name.text,
                        trade: trade.text,
                        phone: phone.text,
                        logoUri: logoUri,
                        iconKey: iconKey,
                        brandColor: brandColor,
                      );
                      if (dialog.mounted) Navigator.pop(dialog);
                      await refresh();
                    } catch (error) {
                      if (dialog.mounted) {
                        setLocal(() => busy = false);
                        _message(dialog, error);
                      }
                    }
                  },
            child: Text(busy ? 'Guardando...' : 'Guardar'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  trade.dispose();
  phone.dispose();
}

Future<void> backupDialog(
  BuildContext context,
  Database db,
  bool export,
  Future<void> Function() refresh,
) async {
  final password = TextEditingController();
  await showDialog(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(export ? 'Proteger respaldo' : 'Abrir respaldo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!export)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'El respaldo reemplazará los datos de este teléfono. Exporta uno actual primero si deseas conservarlos.',
              ),
            ),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña (8 caracteres mínimo)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              if (password.text.length < 8) {
                throw Exception(
                  'La contrasena debe tener al menos 8 caracteres.',
                );
              }
              if (export) {
                await exportEncryptedBackup(db, password.text);
              } else {
                await importEncryptedBackup(db, password.text);
                await refresh();
              }
              if (dialog.mounted) Navigator.pop(dialog);
            } catch (error) {
              if (context.mounted) _message(context, error);
            }
          },
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  password.dispose();
}

class Paywall extends StatefulWidget {
  const Paywall({super.key, required this.subscription, required this.close});
  final SubscriptionController subscription;
  final VoidCallback close;

  @override
  State<Paywall> createState() => _PaywallState();
}

class _PaywallState extends State<Paywall> {
  String selectedPlan = 'yearly';
  bool busy = false;

  Future<void> buy() async {
    setState(() => busy = true);
    try {
      await widget.subscription.buy(selectedPlan);
    } catch (error) {
      if (error.toString().contains('EMAIL_REQUIRED') && mounted) {
        final registered = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const EmailRegistrationPage()),
        );
        if (registered == true) {
          await widget.subscription.buy(selectedPlan);
        }
      } else if (mounted) {
        _message(context, error);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = widget.subscription.plans;
    String price(String id) =>
        plans.where((plan) => plan.basePlanId == id).firstOrNull?.price ??
        'No disponible';
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextButton(
              onPressed: widget.close,
              child: const Text(
                '< Volver',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const Text(
              'JALE PRO',
              style: TextStyle(
                color: Color(0xffffd18a),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Cotiza hablando, cobra mejor y trabaja sin límites.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            const _ProBenefit(
              icon: Icons.mic_rounded,
              text: 'Cotizaciones con IA sin límite*',
            ),
            const _ProBenefit(
              icon: Icons.receipt_long_rounded,
              text: 'Cotizaciones manuales ilimitadas',
            ),
            const _ProBenefit(
              icon: Icons.insights_rounded,
              text: 'Resumen de cobros y actividad',
            ),
            const _ProBenefit(
              icon: Icons.branding_watermark_outlined,
              text: 'PDF sin marca de Jale',
            ),
            const SizedBox(height: 22),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'monthly',
                  label: Text('Mensual\n${price('monthly')}'),
                ),
                ButtonSegment(
                  value: 'yearly',
                  label: Text('Anual\n${price('yearly')}'),
                ),
              ],
              selected: {selectedPlan},
              showSelectedIcon: false,
              onSelectionChanged: busy
                  ? null
                  : (value) => setState(() => selectedPlan = value.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 25),
            FilledButton(
              onPressed: busy ? null : buy,
              child: Text(
                busy
                    ? 'Abriendo Google Play…'
                    : 'Continuar con ${selectedPlan == 'yearly' ? 'Anual' : 'Mensual'}',
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await widget.subscription.restore();
                } catch (error) {
                  if (error.toString().contains('EMAIL_REQUIRED') &&
                      context.mounted) {
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const EmailRegistrationPage(),
                      ),
                    );
                  } else if (context.mounted) {
                    _message(context, error);
                  }
                }
              },
              child: const Text(
                'Restaurar compra',
                style: TextStyle(color: Color(0xffffd18a)),
              ),
            ),
            const Text(
              '*Sujeto a uso razonable para proteger el servicio. La renovación y cancelación se administran en Google Play.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProBenefit extends StatelessWidget {
  const _ProBenefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xffffd18a)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

String friendlyErrorMessage(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  return switch (raw) {
    'FREE_LIMIT_REACHED' =>
      'Ya usaste tus cotizaciones manuales gratuitas de este periodo.',
    'AI_LIMIT_REACHED' =>
      'Ya usaste tus cotizaciones con IA gratuitas de este periodo.',
    'EMAIL_REQUIRED' => 'Registra tu correo para continuar usando la IA.',
    'RATE_LIMITED' =>
      'Espera un momento antes de volver a intentar la cotización.',
    'REQUEST_TOO_LARGE' =>
      'El dictado es demasiado largo. Intenta resumirlo un poco.',
    'FAIR_USE_REVIEW' =>
      'Pausamos temporalmente la IA para proteger tu cuenta. Escríbenos si necesitas ayuda.',
    'DATABASE_NOT_CONFIGURED' =>
      'El servicio todavía está terminando de configurarse. Intenta más tarde.',
    'AUTH_NOT_CONFIGURED' =>
      'El registro todavía no está disponible. Puedes continuar manualmente.',
    'INTEGRITY_REQUIRED' || 'INTEGRITY_INVALID' || 'DEVICE_UNTRUSTED' =>
      'No pudimos comprobar esta instalación. Instala la versión oficial de Jale.',
    'ORIGIN_DENIED' =>
      'No pudimos conectar con Jale. Intenta de nuevo más tarde.',
    _ => raw.isEmpty ? 'Algo salió mal. Intenta de nuevo.' : raw,
  };
}

void _message(BuildContext context, Object error) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
