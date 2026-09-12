import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai.dart';

class EmailRegistrationPage extends StatefulWidget {
  const EmailRegistrationPage({super.key});

  @override
  State<EmailRegistrationPage> createState() => _EmailRegistrationPageState();
}

class _EmailRegistrationPageState extends State<EmailRegistrationPage> {
  final email = TextEditingController();
  final code = TextEditingController();
  bool codeSent = false, busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (!AiApi.authConfigured) {
      setState(() => error = 'El registro aún no está configurado.');
      return;
    }
    final value = email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      setState(() => error = 'Escribe un correo válido.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: value,
        shouldCreateUser: true,
      );
      if (mounted) {
        setState(() {
          codeSent = true;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'No pudimos enviar el código.';
        });
      }
    }
  }

  Future<void> verifyCode() async {
    final token = code.text.trim();
    if (token.length < 6) {
      setState(() => error = 'Escribe el código que llegó a tu correo.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: email.text.trim().toLowerCase(),
        token: token,
      );
      try {
        await AiApi().syncAccount();
      } catch (_) {
        // Auth remains valid; the backend will initialize the account on use.
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'El código no es válido o ya venció.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Guarda tus créditos')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          codeSent ? 'Revisa tu correo' : 'Obtén 2 cotizaciones más con IA',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          codeSent
              ? 'Escribe el código que enviamos. No necesitas recordar una contraseña.'
              : 'Tu correo permite conservar tus créditos y recuperar Jale en otro teléfono.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: email,
          enabled: !codeSent && !busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Correo electrónico'),
        ),
        if (codeSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : (codeSent ? verifyCode : sendCode),
          child: Text(
            busy
                ? 'Espera…'
                : (codeSent ? 'Confirmar código' : 'Enviar código'),
          ),
        ),
        if (codeSent)
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    codeSent = false;
                    code.clear();
                  }),
            child: const Text('Cambiar correo'),
          ),
      ],
    ),
  );
}
