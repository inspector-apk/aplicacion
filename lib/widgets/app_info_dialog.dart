import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Aviso informativo que explica para qué sirve Inspector, mostrado al
/// entrar a la app (ver `SplashScreen`).
Future<void> mostrarInfoDeLaApp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.accent, size: 22),
                SizedBox(width: 8),
                Text(
                  '¿Qué es Inspector?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Inspector conecta a dos tipos de usuario en Bogotá:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            const _PuntoInfo(
              icono: Icons.person_outline,
              texto: 'Cliente: solicita texto, imagen, audio o video de una '
                  'localidad (describe qué necesita y dónde) y le da '
                  'seguimiento a su solicitud hasta recibir la información.',
            ),
            const SizedBox(height: 8),
            const _PuntoInfo(
              icono: Icons.search,
              texto: 'Colaborador: ve las solicitudes disponibles en el '
                  'mapa, acepta la que quiera atender y entrega la '
                  'información solicitada.',
            ),
            const SizedBox(height: 14),
            const Text(
              'Tu cuenta y tus solicitudes viven en nuestro servidor para '
              'que puedas usarlas desde cualquier dispositivo. Verificamos '
              'tu correo al registrarte para confirmar que es real.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'ENTENDIDO',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PuntoInfo extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _PuntoInfo({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, color: AppColors.accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
