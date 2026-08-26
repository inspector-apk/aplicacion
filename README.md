# Inspector

App móvil hecha en **Flutter** (Android + iOS desde el mismo código), con
almacenamiento 100% local en **SQLite** (paquete `sqflite`): alias,
roles, contraseñas (hasheadas con SHA-256 + salt) y solicitudes viven
únicamente en la base de datos local del dispositivo.

Hay dos funciones que sí requieren internet, cada una documentada por
separado:
- Cargar los mosaicos visuales del mapa de Bogotá (ver "Solicitudes y
  mapa" más abajo); sin conexión el mapa se ve en blanco pero el resto
  de la app sigue funcionando.
- **Verificar el correo durante el registro** (ver "Verificación de
  correo" más abajo): requiere el pequeño backend propio en `backend/`,
  desplegado en tu servidor, que envía el código por Gmail/Outlook SMTP.
  Sin ese backend desplegado y configurado, el registro no podrá enviar
  el código y quedará bloqueado en ese paso — es la única función de la
  app que depende de un servidor.

El APK de Android ya viene compilado en este repositorio (ver más abajo).
El paquete de iOS (IPA) no se puede generar desde este entorno Windows —
Apple exige compilarlo desde macOS — pero el código ya es compatible; la
sección "Compilar para iOS" trae los pasos exactos.

## APK ya compilado

`build/Inspector.apk` (~50 MB) es el APK de release ya compilado y listo
para instalar en un dispositivo Android (`adb install build\Inspector.apk`
o copiándolo al teléfono). Se generó con Flutter 3.47.0 stable e incluye
el ícono propio de Inspector (ver "Ícono de la app" más abajo).

## Qué incluye este repositorio

Este repositorio contiene el **código fuente de la app** (carpeta `lib/`,
`pubspec.yaml`, `analysis_options.yaml`) y el APK ya compilado. No incluye
las carpetas nativas `android/`, `ios/`, etc., porque esas se generan
automáticamente con el comando `flutter create` y dependen de la versión
de Flutter instalada en tu máquina — generarlas a mano suele causar
problemas de compatibilidad de Gradle/Kotlin. Los pasos de abajo las
generan por ti en segundos si necesitas recompilar.

## Pantallas implementadas

1. **Permiso de ubicación** (`lib/screens/location_permission_screen.dart`)
   — primera pantalla de la app; solicita el permiso de ubicación antes
   de dejar llegar a Login/Registro (con opción "Ahora no" para omitirlo).
2. **Splash** (`lib/screens/splash_screen.dart`) — fondo negro, logo de
   Inspector (lupa con ojo), botones "INICIAR SESIÓN" / "REGISTRARSE".
3. **Registro** (`lib/screens/register_screen.dart`) — nombre, edad,
   correo, contraseña + confirmación, política de tratamiento de datos
   (acordeón) y declaración de mayoría de edad, ambos checkboxes
   obligatorios. Al continuar, **no crea la cuenta todavía**: pasa a la
   pantalla de verificación de correo.
4. **Verificar correo** (`lib/screens/email_verification_screen.dart`) —
   pide el código de 6 dígitos enviado al correo ingresado (ver
   "Verificación de correo" más abajo). Solo al verificarlo correctamente
   se crea la cuenta de verdad en SQLite, se genera el alias único y
   **totalmente aleatorio** (`Inspector_XXXXXXXX`, 8 caracteres
   alfanuméricos al azar — no se deriva del nombre, correo ni ningún otro
   dato personal) y se muestra en un modal (`register_success_dialog.dart`).
5. **Login** (`lib/screens/login_screen.dart`) — correo + contraseña,
   enlace "¿Olvidaste tu contraseña?" que lleva a un flujo de
   recuperación 100% local por alias o nombre
   (`forgot_password_screen.dart`).
5. **Selección de rol** (`lib/screens/role_selection_screen.dart`) —
   aparece solo si el usuario aún no tiene rol asignado; guarda la
   elección (Colaborador / Cliente) en SQLite y no se vuelve a preguntar.
6. **Inicio Cliente** (`lib/screens/cliente_home_screen.dart`) — mapa de
   Bogotá estilo Uber/inDrive con un panel inferior: si no hay una
   solicitud activa, muestra el formulario para crear una (texto o
   imagen, descripción, localidad); si ya hay una, muestra su
   seguimiento en tiempo real (estado, tipo, localidad, botón cancelar).
7. **Inicio Colaborador** (`lib/screens/colaborador_home_screen.dart`) —
   mismo mapa, con un panel inferior que lista las solicitudes
   disponibles para aceptar y las que ya tiene en curso, con botón para
   marcarlas como completadas.
8. **Perfil** (`lib/screens/home_screen.dart`) — accesible desde el ícono
   de persona en la barra superior de las pantallas de mapa: alias,
   datos del usuario, la solicitud activa del Cliente (si tiene una), la
   tarjeta de "Datos profesionales" del Colaborador (ocupación y
   localidad donde prefiere trabajar, ambos opcionales), la tarjeta de
   "Seguridad" para activar/desactivar la verificación en dos pasos, y
   las opciones de cambiar de rol o cerrar sesión.
9. **Activar 2FA** (`lib/screens/two_factor_setup_screen.dart`) — genera
   una clave TOTP local y muestra un código QR + clave manual para
   escanear con Google Authenticator/Authy/Microsoft Authenticator; pide
   el primer código generado para confirmar antes de habilitarla.
10. **Verificar 2FA** (`lib/screens/two_factor_verify_screen.dart`) — paso
    adicional del login para quienes activaron la verificación en dos
    pasos: pide el código de 6 dígitos después de la contraseña.
11. **Panel de administrador** (`lib/screens/admin_panel_screen.dart`) —
    solo para la cuenta admin (ver abajo); dos pestañas de solo lectura
    con todos los usuarios registrados y todas las solicitudes creadas.

## Cuenta de administrador

La app crea automáticamente, la primera vez que arranca
(`AuthService.asegurarCuentaAdmin`, llamado desde `main()`), una cuenta
con rol `administrador`:

- **Correo:** `admin@inspector.com`
- **Contraseña:** `4321`

Esta cuenta nunca pasa por la pantalla de selección de rol (`Colaborador`
/`Cliente` siguen siendo los únicos roles que un usuario normal puede
elegir) y al iniciar sesión va directo al panel de administrador. Su
contraseña se guarda hasheada igual que la de cualquier otro usuario
(`PasswordService`, SHA-256 + salt), nunca en texto plano — pero sigue
siendo una contraseña por defecto conocida, así que si vas a distribuir
la app más allá de pruebas locales, cámbiala desde "¿Olvidaste tu
contraseña?" usando el alias generado (visible en el panel) apenas
instales la app.

## Almacenamiento local

- `lib/data/database_helper.dart`: crea y administra la tabla
  `usuarios` en SQLite (`sqflite`) con los campos `id, nombre, edad,
  correo, contrasena, salt, alias, rol, fecha_registro,
  acepto_politicas, declara_mayor_edad, totp_secret, totp_habilitado,
  ocupacion, localidad_trabajo`. Los dos últimos son opcionales y solo
  se editan desde el Perfil de un usuario con rol Colaborador.
- `lib/services/two_factor_service.dart`: verificación en dos pasos con
  TOTP (RFC 6238, `package:otp` + `package:base32`), compatible con
  Google Authenticator y similares — se genera y verifica 100% en el
  dispositivo, sin backend. Es **opcional**: cada usuario la activa desde
  su Perfil (tarjeta "Seguridad"); si la activa, el login le pide el
  código de 6 dígitos después de la contraseña.
- `lib/services/password_service.dart`: hashing SHA-256 con salt
  aleatorio por usuario (`package:crypto`). Las contraseñas nunca se
  guardan ni comparan en texto plano.
- `lib/services/alias_service.dart`: genera el alias único, validando
  contra la base de datos antes de asignarlo.
- `lib/services/auth_service.dart`: registro, login, recuperación de
  contraseña y selección de rol.
- `lib/services/session_service.dart`: usuario con sesión activa en
  memoria mientras la app está abierta.
- `lib/data/database_helper.dart` también administra la tabla
  `solicitudes` (`id, cliente_id, colaborador_id, tipo, descripcion,
  localidad, latitud, longitud, estado, fecha_creacion,
  fecha_actualizacion`) a través de `lib/services/solicitud_service.dart`.

## Solicitudes y mapa

- **Cliente pide, Colaborador atiende** (como pasajero/conductor en
  Uber): el Cliente llena el formulario (texto o imagen, descripción,
  localidad) y la solicitud queda `pendiente`; el Colaborador la ve en
  su lista de "Solicitudes disponibles" y la puede `aceptar`; al
  terminar la marca como `completada`. El Cliente ve el estado en
  tiempo real tanto en su pantalla principal como en su perfil.
- El mapa (`lib/widgets/bogota_map.dart`) usa el paquete `flutter_map`
  con mosaicos de OpenStreetMap (sin necesidad de API key, a diferencia
  de Google Maps).
- Las 20 localidades de Bogotá y sus coordenadas aproximadas están en
  `lib/core/bogota_localidades.dart`.
- El permiso de ubicación (`lib/services/location_service.dart`, paquete
  `geolocator`) se solicita al abrir la app, pero no es estrictamente
  bloqueante: si se omite, el mapa simplemente se centra en Bogotá en
  vez de la posición del usuario.

## Verificación de correo

El registro exige verificar el correo con un código de 6 dígitos antes
de crear la cuenta. A diferencia del resto de la app, **esto sí requiere
un backend propio y conexión a internet** — no hay forma de enviar un
correo real sin un servicio externo.

- El backend (carpeta `backend/`, Node.js + Express + Nodemailer) envía
  el código por SMTP de Gmail/Outlook y lo verifica; no guarda nada en
  una base de datos ni conoce a los usuarios de la app, solo el correo
  que está verificando. Tiene su propia guía de despliegue en
  `backend/README.md`, incluyendo cómo dejarlo corriendo permanentemente
  en tu servidor con `systemd`.
- `lib/services/email_verification_service.dart` es el lado de la app
  que llama a ese backend (`enviar-codigo` / `verificar-codigo`).
- `lib/core/backend_config.dart` tiene la URL y la API key del backend —
  **hay que editarlo con los valores reales después de desplegarlo** (por
  defecto trae valores de relleno) y volver a compilar el APK.
- Sin el backend desplegado y configurado, el paso de "Verificar correo"
  del registro fallará con un error de conexión — es la única función de
  Inspector que puede quedar bloqueada sin servidor. El resto de la app
  (login, mapa, solicitudes, 2FA, perfil) sigue funcionando igual.

## Requisitos para compilar

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal
  estable, la versión más reciente disponible).
- Android SDK + Java (Flutter los gestiona si instalas Android Studio,
  o puedes usar solo `cmdline-tools` + `sdkmanager`).
- Un dispositivo Android o emulador para probar (opcional para generar
  el APK).

Verifica que todo esté listo con:

```powershell
flutter doctor
```

## Cómo compilar el APK

1. Genera la carpeta nueva del proyecto con el scaffolding nativo,
   **limitado a Android e iOS** (`--platforms=android,ios`): algunos
   paquetes (`geolocator`, en concreto su variante de Windows) traen
   implementaciones de escritorio que en Windows exigen tener el "Modo
   desarrollador" activado (symlinks) si el proyecto incluye las
   carpetas `windows/`/`linux`/`macos`. Como esta app no los necesita,
   evita el problema por completo generando solo lo que hace falta:

   ```powershell
   flutter create --platforms=android,ios --org com.inspector --project-name inspector inspector_app
   ```

2. Copia el contenido de este repositorio (`lib/`, `pubspec.yaml`,
   `analysis_options.yaml`, `assets/`) dentro de `inspector_app/`,
   reemplazando los archivos generados por defecto:

   ```powershell
   Copy-Item -Recurse -Force .\lib\* .\inspector_app\lib\
   Copy-Item -Force .\pubspec.yaml .\inspector_app\pubspec.yaml
   Copy-Item -Force .\analysis_options.yaml .\inspector_app\analysis_options.yaml
   Copy-Item -Recurse -Force .\assets .\inspector_app\assets
   ```

3. Instala las dependencias:

   ```powershell
   cd inspector_app
   flutter pub get
   ```

4. **Agrega los permisos de ubicación e internet** en
   `android/app/src/main/AndroidManifest.xml` — no vienen en el
   `flutter create` por defecto, hay que añadirlos a mano justo debajo
   de la etiqueta `<manifest ...>` de apertura:

   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
   ```

5. Genera el ícono de la app (launcher / Descargas) a partir de
   `assets/icon/app_icon.png` — este paso escribe los mipmaps de Android
   (y los assets de iOS) y solo hace falta repetirlo si cambias la
   imagen del ícono:

   ```powershell
   dart run flutter_launcher_icons
   ```

6. (Opcional) Prueba la app en un emulador o dispositivo conectado:

   ```powershell
   flutter run
   ```

7. Genera el APK de release:

   ```powershell
   flutter build apk --release
   ```

   El archivo resultante queda en:
   `inspector_app/build/app/outputs/flutter-apk/app-release.apk`

## Compilar para iOS (requiere macOS)

**Apple exige que las apps de iOS se compilen y firmen desde macOS con
Xcode** — no es posible generar un IPA desde Windows/Linux bajo ninguna
circunstancia, ni siquiera instalando más herramientas; es una
restricción de la plataforma, no de este proyecto. El código en `lib/`
ya es 100% multiplataforma (Flutter/Dart puro, sin nada específico de
Android), así que no requiere cambios para correr en iOS — solo falta
generar el paquete nativo desde un Mac.

Opciones para conseguir ese Mac:

- Un Mac físico propio o prestado con Xcode instalado.
- Un servicio de CI en la nube con runner macOS: p. ej.
  [Codemagic](https://codemagic.io) (tiene plan gratuito orientado a
  Flutter) o un runner `macos-latest` de GitHub Actions.

Pasos una vez tengas acceso a macOS:

1. Instala [Xcode](https://apps.apple.com/app/xcode/id497799835) (App
   Store) y [Flutter](https://docs.flutter.dev/get-started/install/macos).
2. Repite los pasos 1–3 de la sección anterior (`flutter create`, copiar
   `lib/`/`pubspec.yaml`, `flutter pub get`), pero en macOS. Esto genera
   también la carpeta `ios/`.
3. Agrega el permiso de ubicación en `ios/Runner/Info.plist`, dentro del
   `<dict>` principal (igual que el paso 4 de Android, pero para iOS):

   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>Inspector usa tu ubicación para mostrarte el mapa y conectar solicitudes cercanas en Bogotá.</string>
   ```

4. Abre `ios/Runner.xcworkspace` en Xcode y configura un **Team** de
   firma (necesitas una cuenta de Apple: la gratuita alcanza para
   instalar en tus propios dispositivos por 7 días; una cuenta de pago
   de [Apple Developer Program](https://developer.apple.com/programs/)
   —99 USD/año— permite distribución vía TestFlight o Ad Hoc sin ese
   límite).
5. Compila:

   ```bash
   flutter build ios --release
   # o para generar directamente un .ipa distribuible:
   flutter build ipa --release
   ```

6. Instala en un iPhone conectado desde Xcode (`Product > Run` con el
   dispositivo seleccionado), o distribuye el `.ipa` resultante
   (`build/ios/ipa/`) vía TestFlight o instalación Ad Hoc.

## Primer arranque

La base de datos SQLite (`inspector.db`) se crea automáticamente la
primera vez que la app se ejecuta en el dispositivo (ver
`DatabaseHelper._initDatabase`); no requiere ningún paso manual.

## Ícono de la app

`assets/icon/app_icon.png` (fondo negro, para iOS y como ícono legacy de
Android) y `assets/icon/app_icon_foreground.png` (mismo logo con fondo
transparente, para el ícono adaptativo de Android) son la misma imagen
—lupa con ojo, dorado sobre negro— que se usa en la pantalla de Splash y
en el encabezado de Inicio, generada con el paquete `flutter_launcher_icons`.
Es la imagen que verás como ícono de la app en el cajón de aplicaciones y
en Descargas una vez instalado el APK. Para cambiarla: reemplaza esos dos
PNG y vuelve a correr `dart run flutter_launcher_icons` seguido de
`flutter build apk --release`.

## Notas de diseño

- Tema oscuro por defecto (`lib/core/app_theme.dart`), tipografía Roboto
  (fuente del sistema en Android, sin dependencias de red).
- Paleta: negro `#000000`, gris oscuro `#121212` / `#1C1C1E`, blanco
  `#F5F5F5`, acento dorado `#FFD700`.
- Transiciones fade/slide entre pantallas (`lib/core/app_routes.dart`).
