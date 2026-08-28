import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../core/role_navigation.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../widgets/app_buttons.dart';
import 'forgot_password_screen.dart';
import 'role_selection_screen.dart';
import 'two_factor_setup_screen.dart';
import 'two_factor_verify_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correoCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();
  bool _ocultarContrasena = true;
  bool _cargando = false;

  @override
  void dispose() {
    _correoCtrl.dispose();
    _contrasenaCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _cargando = true);
    try {
      final usuario = await AuthService.iniciarSesion(
        correo: _correoCtrl.text,
        contrasena: _contrasenaCtrl.text,
      );

      if (!mounted) return;

      if (usuario.totpHabilitado) {
        // La sesión se inicia dentro de TwoFactorVerifyScreen, solo
        // después de validar el código de 6 dígitos.
        Navigator.of(context).pushReplacement(
          AppRoutes.fade(TwoFactorVerifyScreen(usuario: usuario)),
        );
        return;
      }

      // La verificación en dos pasos es obligatoria: si esta cuenta
      // todavía no la tiene activada, hay que configurarla ahora mismo
      // antes de poder entrar. Si el usuario se echa para atrás sin
      // completarla, simplemente no queda una sesión iniciada.
      final actualizado = await Navigator.of(context).push<Usuario>(
        AppRoutes.slide(TwoFactorSetupScreen(usuario: usuario)),
      );
      if (actualizado == null || !mounted) return;

      SessionService.instance.iniciarSesion(actualizado);
      if (actualizado.rol == null) {
        Navigator.of(context).pushReplacement(
          AppRoutes.fade(RoleSelectionScreen(usuario: actualizado)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          AppRoutes.fade(pantallaPrincipalParaRol(actualizado)),
        );
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              TextFormField(
                controller: _correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  helperText: 'El correo con el que creaste tu cuenta',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresa tu correo electrónico'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contrasenaCtrl,
                obscureText: _ocultarContrasena,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Te pediremos el código de verificación en '
                      'dos pasos después',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _ocultarContrasena
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _ocultarContrasena = !_ocultarContrasena),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Ingresa tu contraseña'
                    : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push(AppRoutes.slide(const ForgotPasswordScreen()));
                  },
                  child: const Text(
                    '¿Olvidaste tu contraseña?',
                    style: TextStyle(color: AppColors.accent, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'ENTRAR',
                isLoading: _cargando,
                onPressed: _entrar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
