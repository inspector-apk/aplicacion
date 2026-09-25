import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_colors.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/two_factor_service.dart';
import '../widgets/app_buttons.dart';

/// Activación de verificación en dos pasos (TOTP): genera una clave
/// secreta local, la muestra como código QR + texto para escanear con
/// una app autenticadora, y pide un código de confirmación antes de
/// guardarla como habilitada.
class TwoFactorSetupScreen extends StatefulWidget {
  final Usuario usuario;
  const TwoFactorSetupScreen({super.key, required this.usuario});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  late final String _secreto;
  final _codigoCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _secreto = TwoFactorService.generarSecreto();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmarActivacion() async {
    final valido = TwoFactorService.verificarCodigo(_secreto, _codigoCtrl.text);
    if (!valido) {
      setState(() => _error = 'Código incorrecto. Verifica la hora de tu '
          'teléfono e inténtalo de nuevo.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });
    final actualizado = await AuthService.activarDobleFactor(
      usuarioId: widget.usuario.id!,
      secreto: _secreto,
    );
    if (!mounted) return;
    Navigator.of(context).pop(actualizado);
  }

  @override
  Widget build(BuildContext context) {
    final uri = TwoFactorService.uriOtpAuth(_secreto, widget.usuario.correo);

    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en dos pasos')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              '1. Escanea este código con Google Authenticator, Authy o '
              'Microsoft Authenticator',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: uri,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '¿No puedes escanear? Ingresa esta clave manualmente:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _secreto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.accentText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '2. Ingresa el código de 6 dígitos que muestra la app',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _codigoCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'ACTIVAR',
              isLoading: _cargando,
              onPressed: _confirmarActivacion,
            ),
          ],
        ),
      ),
    );
  }
}
