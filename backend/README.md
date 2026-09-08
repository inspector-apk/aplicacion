# Backend — Inspector

Servicio Node.js + Express + better-sqlite3 (un solo proceso, sin
microservicios) que guarda las **cuentas de usuario** y las
**solicitudes** (Cliente pide, Colaborador atiende) en una base de
datos compartida, para que todo funcione desde cualquier dispositivo —
una cuenta creada en un celular sirve para iniciar sesión en otro, y
una solicitud creada por un Cliente la puede ver un Colaborador en un
celular distinto.

Las contraseñas se hashean (SHA-256 + salt) **en el propio celular**
antes de enviarse: el servidor guarda y compara el hash, nunca ve una
contraseña en texto plano (excepto cuando el admin crea una cuenta
directamente desde el panel web — ver la sección de usuarios más
abajo). Cada persona se identifica también por su **alias** aleatorio
(ej. `Inspector_7K2QXR9L`), generado por este mismo servidor al
registrarse para garantizar que sea único.

## 1. Requisitos en el servidor

- Node.js 18 o superior (`node --version`).
- Acceso por SSH/terminal al servidor.

## 2. Copiar el proyecto al servidor

```bash
sudo mkdir -p /opt/inspector-verificacion
sudo chown $USER:$USER /opt/inspector-verificacion
git clone https://github.com/inspector-apk/aplicacion.git /tmp/inspector-repo
cp -r /tmp/inspector-repo/backend/. /opt/inspector-verificacion/
rm -rf /tmp/inspector-repo
cd /opt/inspector-verificacion
```

(Nota el `.` al final de `backend/.` — así sí se copian también los
archivos ocultos como `.env.example`, a diferencia de `backend/*`.)

## 3. Instalar dependencias y configurar

```bash
npm install
cp .env.example .env
nano .env   # completa API_KEY con una clave larga y aleatoria
```

`API_KEY` debe coincidir exactamente con la que pongas en
`lib/core/backend_config.dart` en la app Flutter.

## 4. Probar que funciona

```bash
npm start
```

En otra pestaña:

```bash
curl http://localhost:3000/api/salud
# Debe responder: {"ok":true}
```

`Ctrl+C` para detener antes del siguiente paso.

## 5. Dejarlo corriendo siempre (systemd)

Si ya tenías el servicio `inspector-verificacion` corriendo de una
versión anterior del backend, esto simplemente lo actualiza:

```bash
sudo cp /opt/inspector-verificacion/inspector-verificacion.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now inspector-verificacion
sudo systemctl restart inspector-verificacion
sudo systemctl status inspector-verificacion
```

Debe decir **"active (running)"**. Logs con
`sudo journalctl -u inspector-verificacion -f`.

## 6. HTTPS con nginx + Let's Encrypt

Ver la guía general del proyecto para configurar nginx como proxy y
`certbot` para el certificado — el proxy ya debería estar apuntando a
`localhost:3000` desde la configuración anterior del correo; solo hace
falta que el backend esté corriendo con el código nuevo.

## 7. Conectar la app Flutter

Edita `lib/core/backend_config.dart`:

```dart
static const String baseUrl = 'https://appinspector.servialco.com'; // o la URL que uses
static const String apiKey = 'la-misma-clave-que-pusiste-en-.env';
```

Vuelve a compilar el APK/IPA para que tome estos valores.

## Panel de administrador para PC

Panel web completo, pensado para verse **desde un computador**, en:

```
http://appinspector.servialco.com:12443/admin
```

Es un solo archivo estático (`backend/admin-panel.html`, sin
dependencias ni build) servido por el mismo backend en la ruta `/admin`,
con dos pestañas:

- **Usuarios**: buscar, ver resumen (clientes/colaboradores/bloqueados),
  **crear una cuenta nueva** (nombre, edad, correo, contraseña y rol —
  usa `POST /api/usuarios/admin-crear`), cambiar el rol de alguien,
  desactivar su 2FA, quitar un bloqueo temporal, y eliminar la cuenta.
- **Solicitudes**: buscar, filtrar por estado, ver el resumen de
  comisiones y eliminar.

Para entrar, pide la misma `API_KEY` del `.env` como "clave de
administrador" — no agrega ningún sistema de autenticación nuevo, solo
usa el mismo header `x-api-key` que ya protege el resto de la API. La
clave se guarda en el `sessionStorage` del navegador (se borra sola al
cerrar la pestaña o con "Cerrar sesión"), nunca en el propio archivo.

## Endpoints

Todos requieren el header `x-api-key` (excepto `/api/salud`). El
cuerpo de las peticiones admite hasta 60MB (una respuesta con video en
base64 puede pesar bastante) — si tu proxy (nginx, etc.) tiene su
propio límite de tamaño de body, revisa que también lo permita
(`client_max_body_size 60m;` en nginx).

- `POST /api/solicitudes` — crea una solicitud (`clienteAlias, tipos (array: texto/imagen/audio/video), categoria (personal/comercial/industrial), valorTotal, descripcion, localidad, latitud, longitud`)
- `GET /api/solicitudes/pendientes` — todas las solicitudes en estado `pendiente`
- `GET /api/solicitudes/activa?clienteAlias=...` — la solicitud "vigente" de un cliente: en curso, o completada con una respuesta que todavía no ha visto
- `GET /api/solicitudes/en-curso?colaboradorAlias=...` — las solicitudes que un colaborador tiene aceptadas
- `POST /api/solicitudes/:id/aceptar` (`colaboradorAlias`) — la acepta; si otro colaborador ya la tomó, responde `409`
- `POST /api/solicitudes/:id/responder` (`colaboradorAlias`, y uno o varios de `texto`, `imagenBase64`, `audioBase64`, `videoBase64` según lo que haya pedido la solicitud) — envía la respuesta del colaborador y con eso completa la solicitud; si falta contenido para alguno de los tipos pedidos, responde `400`
- `GET /api/solicitudes/:id/respuesta?clienteAlias=...` — entrega el contenido de la respuesta **una sola vez**: lo borra del servidor en el mismo momento en que se consulta con éxito; llamadas posteriores responden `409` ("ya fue vista")
- `GET /api/solicitudes/historial?clienteAlias=...` — historial completo (cualquier estado) de un cliente, sin el contenido de las respuestas — solo metadatos
- `POST /api/solicitudes/:id/cancelar` (`clienteAlias`) — el cliente cancela su propia solicitud pendiente
- `GET /api/solicitudes/todas` — todas, para el panel de administrador (tampoco incluye el contenido de las respuestas)
- `DELETE /api/solicitudes/:id` — elimina una solicitud, para el panel de administrador
- `POST /api/colaboradores/ubicacion` — el colaborador envía su posición mientras está "disponible" (`colaboradorAlias, latitud, longitud`), para mostrarlo en el mapa del cliente
- `POST /api/colaboradores/desconectar` — el colaborador avisa que ya no está disponible (`colaboradorAlias`)
- `GET /api/colaboradores/cercanos` — posiciones aproximadas y difuminadas de los colaboradores disponibles ahora mismo
- `GET /admin` — panel de administrador web para PC (ver arriba); no requiere `x-api-key` para cargar la página, la pide dentro de la propia página para usar la API

### Usuarios (cuentas)

- `POST /api/usuarios/registro` (`nombre, edad, correo, contrasenaHash, salt, aceptoPoliticas, declaraMayorEdad`) — crea la cuenta; el hash/salt ya vienen calculados desde el celular
- `GET /api/usuarios/salt?correo=...` — paso 1 del login: el salt de esa cuenta, para que el cliente calcule el mismo hash antes de verificar
- `POST /api/usuarios/login` (`correo, contrasenaHash`) — paso 2: compara el hash y devuelve la cuenta si coincide
- `GET /api/usuarios/buscar-recuperacion?texto=...` — busca por alias o nombre completo (recuperación de contraseña); devuelve `id, alias, correo` para que la app verifique el correo antes de dejar cambiarla
- `GET /api/usuarios/:id` — trae una cuenta actualizada (tras cualquier cambio)
- `PATCH /api/usuarios/:id/rol` (`rol`) — cambia el rol (`cliente`/`colaborador`)
- `PATCH /api/usuarios/:id/contrasena` (`contrasenaHash, salt`) — cambia la contraseña (ya hasheada)
- `PATCH /api/usuarios/:id/2fa` (`secreto` opcional) — activa el 2FA (si viene `secreto`) o lo desactiva (si no viene)
- `PATCH /api/usuarios/:id/perfil-colaborador` (`ocupacion, localidadTrabajo`)
- `PATCH /api/usuarios/:id/cuenta-bancaria` (`banco, numeroCuenta`) — ficticia, ver la app
- `PATCH /api/usuarios/:id/bloqueo` (`bloquear: true/false`) — pone o quita el bloqueo de 5 minutos por cancelar una solicitud aceptada
- `GET /api/usuarios` — lista todas las cuentas (sin hash/salt/secreto TOTP), para el panel de administrador
- `POST /api/usuarios/admin-crear` (`nombre, edad, correo, contrasena` en texto plano, `rol` opcional) — el admin crea una cuenta directamente desde el panel web; el servidor genera el salt y hashea ahí mismo
- `DELETE /api/usuarios/:id` — elimina una cuenta, para el panel de administrador

### Sobre la privacidad de las respuestas

El contenido de una respuesta (`respuesta_texto` / `respuesta_imagen_base64`
/ `respuesta_audio_base64` / `respuesta_video_base64`)
**nunca** se devuelve en ningún endpoint de lista (`pendientes`, `activa`,
`en-curso`, `todas`, `historial`) — solo en `GET /api/solicitudes/:id/respuesta`,
y solo si quien pregunta es el mismo `clienteAlias` dueño de la solicitud.
Al entregarlo, el servidor lo borra de su base de datos en la misma
consulta: no queda guardado en ningún lado después de que el cliente lo
vio una vez.

### Sobre la posición de los colaboradores en el mapa

La posición que envían los colaboradores (`POST /api/colaboradores/ubicacion`)
**no se guarda en la base de datos ni en disco** — vive solo en memoria
mientras el proceso del backend está corriendo, y cada colaborador
desaparece del mapa automáticamente si deja de enviarla por 90 segundos
(cerró la app, perdió conexión, etc.). Además, antes de entregarla a los
clientes (`GET /api/colaboradores/cercanos`) el servidor le aplica un
desplazamiento aleatorio de ~150m: nunca se expone la ubicación exacta
del colaborador, solo un punto aproximado alrededor de ella.
