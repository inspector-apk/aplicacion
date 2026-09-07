import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// En Android las capturas y grabaciones de pantalla ya están
/// bloqueadas de raíz (`FLAG_SECURE` en `MainActivity.kt`) — ahí nunca
/// hace falta esto.
///
/// En iOS, Apple NO permite a ninguna app bloquear la captura de
/// pantalla del sistema. Lo único posible es detectar cuando ya ocurrió
/// (`UIApplication.userDidTakeScreenshotNotification`, ver
/// `ios/Runner/AppDelegate.swift` — se inyecta en el workflow de
/// GitHub Actions porque `ios/` se regenera en cada build) y avisarle
/// a quien esté usando la app en ese momento. Es disuasivo, no
/// preventivo.
class ScreenshotDetectionService {
  ScreenshotDetectionService._();

  static const _canal = MethodChannel('inspector/capturas');

  static void iniciar(GlobalKey<NavigatorState> navigatorKey) {
    _canal.setMethodCallHandler((llamada) async {
      if (llamada.method != 'capturaDetectada') return;
      final context = navigatorKey.currentContext;
      if (context == null) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Se detectó una captura de pantalla'),
          content: const Text(
            'El contenido de Inspector es privado. Evita compartir '
            'capturas de pantalla de esta app con terceros.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    });
  }
}
