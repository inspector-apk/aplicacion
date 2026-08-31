# Backend de solicitudes — Inspector

Servicio pequeño (Node.js + Express + better-sqlite3) que guarda las
**solicitudes** (Cliente pide, Colaborador atiende) en una base de datos
compartida, para que todos los usuarios de la app las vean sin importar
el dispositivo. Es necesario porque el resto de Inspector (usuarios,
2FA, etc.) es 100% local por dispositivo — pero una solicitud creada por
un Cliente en su celular tiene que poder verla un Colaborador en otro
celular distinto, y eso requiere sí o sí un servidor compartido.

No maneja usuarios ni contraseñas: identifica a cada persona solo por su
**alias** (el que ya genera la app, ej. `Inspector_7K2QXR9L`), nunca ve
correos ni datos personales.

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

## Endpoints

Todos requieren el header `x-api-key` (excepto `/api/salud`).

- `POST /api/solicitudes` — crea una solicitud (`clienteAlias, tipo, descripcion, localidad, latitud, longitud`)
- `GET /api/solicitudes/pendientes` — todas las solicitudes en estado `pendiente`
- `GET /api/solicitudes/activa?clienteAlias=...` — la solicitud "vigente" de un cliente: en curso, o completada con una respuesta que todavía no ha visto
- `GET /api/solicitudes/en-curso?colaboradorAlias=...` — las solicitudes que un colaborador tiene aceptadas
- `POST /api/solicitudes/:id/aceptar` (`colaboradorAlias`) — la acepta; si otro colaborador ya la tomó, responde `409`
- `POST /api/solicitudes/:id/responder` (`colaboradorAlias`, y `texto` o `imagenBase64`) — envía la respuesta del colaborador y con eso completa la solicitud
- `GET /api/solicitudes/:id/respuesta?clienteAlias=...` — entrega el contenido de la respuesta **una sola vez**: lo borra del servidor en el mismo momento en que se consulta con éxito; llamadas posteriores responden `409` ("ya fue vista")
- `GET /api/solicitudes/historial?clienteAlias=...` — historial completo (cualquier estado) de un cliente, sin el contenido de las respuestas — solo metadatos
- `POST /api/solicitudes/:id/cancelar` (`clienteAlias`) — el cliente cancela su propia solicitud pendiente
- `GET /api/solicitudes/todas` — todas, para el panel de administrador (tampoco incluye el contenido de las respuestas)
- `DELETE /api/solicitudes/:id` — elimina una solicitud, para el panel de administrador
- `POST /api/colaboradores/ubicacion` — el colaborador envía su posición mientras está "disponible" (`colaboradorAlias, latitud, longitud`), para mostrarlo en el mapa del cliente como los carros de Uber/Didi
- `POST /api/colaboradores/desconectar` — el colaborador avisa que ya no está disponible (`colaboradorAlias`)
- `GET /api/colaboradores/cercanos` — posiciones aproximadas y difuminadas de los colaboradores disponibles ahora mismo

### Sobre la privacidad de las respuestas

El contenido de una respuesta (`respuesta_texto` / `respuesta_imagen_base64`)
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
