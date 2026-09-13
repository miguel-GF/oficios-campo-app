import 'package:flutter/material.dart';

import 'session.dart';

class EmailRegistrationPage extends StatefulWidget {
  const EmailRegistrationPage({super.key});

  @override
  State<EmailRegistrationPage> createState() => _EmailRegistrationPageState();
}

class _EmailRegistrationPageState extends State<EmailRegistrationPage> {
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_authChanged);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_authChanged);
    super.dispose();
  }

  void _authChanged() {
    if (mounted && AuthService.instance.signedIn) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> openLogin() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AuthService.instance.beginLogin();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No pudimos abrir el acceso seguro.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cuenta de Jale')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.shield_outlined,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        const Text(
          'Guarda tus créditos y tu plan Pro',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Text(
          'Abriremos el acceso seguro de Jale. Al volver tendrás 2 cotizaciones con IA cada mes.',
          textAlign: TextAlign.center,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : openLogin,
          icon: const Icon(Icons.open_in_browser),
          label: Text(busy ? 'Abriendo…' : 'Continuar de forma segura'),
        ),
        const SizedBox(height: 10),
        const Text(
          'Jale no recibe tu contraseña. La sesión se completa en el portal de Neon Auth.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
