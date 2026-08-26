# Backend de verificación de correo — Inspector

Servicio pequeño (Node.js + Express + Nodemailer) que envía un código de
6 dígitos al correo del usuario durante el registro, y lo verifica. Es
**la única parte de Inspector que necesita internet y un servidor** — el
resto de la app sigue siendo 100% local (SQLite en el dispositivo).

No guarda nada en una base de datos: los códigos viven en memoria unos
minutos y se descartan. No se conecta a la base de datos de la app ni
conoce nada de los usuarios más allá del correo que está verificando.

## 1. Requisitos en el servidor

- Node.js 18 o superior (`node --version`).
- Una cuenta de Gmail (o Outlook/Office365) para enviar los correos.
- Acceso por SSH/terminal al servidor (VPS, dedicado, etc.).

## 2. Generar la contraseña de aplicación de Gmail

Gmail ya no acepta la contraseña normal de la cuenta para SMTP. Hay que
generar una "contraseña de aplicación":

1. Activa la verificación en 2 pasos en la cuenta de Gmail que va a
   enviar los correos (obligatorio para poder generar la contraseña de
   aplicación): <https://myaccount.google.com/security>
2. Genera la contraseña de aplicación en:
   <https://myaccount.google.com/apppasswords>
3. Guarda esos 16 caracteres, los vas a necesitar en el paso 4.

## 3. Copiar el proyecto al servidor

Desde tu máquina, sube esta carpeta `backend/` al servidor (ajusta la
ruta/usuario/IP a los tuyos):

```bash
scp -r backend usuario@tu-servidor:/opt/inspector-verificacion
```

O si prefieres, clona/copia el repo completo en el servidor y usa solo
la carpeta `backend/` de ahí.

## 4. Instalar dependencias y configurar

Ya en el servidor, por SSH:

```bash
cd /opt/inspector-verificacion
npm install
cp .env.example .env
nano .env   # completa GMAIL_USER, GMAIL_APP_PASSWORD y API_KEY
```

`API_KEY` es una clave que te inventas (una cadena larga y aleatoria).
Debe coincidir exactamente con la que pongas en
`lib/core/backend_config.dart` en la app Flutter — es una protección
básica para que no cualquiera pueda usar tu endpoint para mandar correos
desde tu cuenta.

## 5. Probar que funciona

```bash
npm start
```

En otra terminal (o desde tu PC si el puerto es accesible):

```bash
curl http://localhost:3000/api/salud
# Debe responder: {"ok":true}
```

Si funciona, detén el proceso con `Ctrl+C` — en el siguiente paso lo
dejamos corriendo permanentemente.

## 6. Dejarlo corriendo siempre (systemd)

Esto es lo que hace que el servicio **viva siempre en el servidor**:
arranca solo cuando el servidor reinicia, y si el proceso llegara a
caerse, systemd lo vuelve a levantar automáticamente.

```bash
# (Opcional pero recomendado) usuario dedicado, sin privilegios de login
sudo useradd -r -s /usr/sbin/nologin inspector
sudo chown -R inspector:inspector /opt/inspector-verificacion

# Instala el archivo de servicio
sudo cp /opt/inspector-verificacion/inspector-verificacion.service /etc/systemd/system/
sudo systemctl daemon-reload

# Actívalo para que arranque en cada reinicio del servidor, e inícialo ahora
sudo systemctl enable inspector-verificacion
sudo systemctl start inspector-verificacion

# Verifica que está activo
sudo systemctl status inspector-verificacion
```

Comandos útiles después:

```bash
# Ver logs en vivo
sudo journalctl -u inspector-verificacion -f

# Reiniciarlo (por ejemplo, después de cambiar el .env)
sudo systemctl restart inspector-verificacion

# Detenerlo
sudo systemctl stop inspector-verificacion
```

## 7. (Muy recomendado) HTTPS con nginx + Let's Encrypt

Exponer el puerto 3000 directo a internet sin cifrar no es buena idea.
Lo estándar es poner nginx delante como proxy y certificado gratuito de
Let's Encrypt, usando un subdominio (ej. `api.tudominio.com`):

```bash
sudo apt install nginx certbot python3-certbot-nginx

# Crea /etc/nginx/sites-available/inspector-verificacion con:
#   server {
#       listen 80;
#       server_name api.tudominio.com;
#       location / {
#           proxy_pass http://localhost:3000;
#           proxy_set_header Host $host;
#           proxy_set_header X-Real-IP $remote_addr;
#       }
#   }
sudo ln -s /etc/nginx/sites-available/inspector-verificacion /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Certificado HTTPS automático
sudo certbot --nginx -d api.tudominio.com
```

Con esto, la URL final del backend sería `https://api.tudominio.com` en
vez de `http://tu-ip:3000`.

## 8. Conectar la app Flutter

Edita `lib/core/backend_config.dart` en el proyecto de la app:

```dart
static const String baseUrl = 'https://api.tudominio.com'; // o http://tu-ip:3000
static const String apiKey = 'la-misma-clave-que-pusiste-en-.env';
```

Vuelve a compilar el APK (ver el README principal del proyecto) para que
tome estos valores.

## Firewall

Si usas nginx (paso 7), solo necesitas abrir los puertos 80 y 443. Si
expones el puerto 3000 directamente (sin nginx), abre ese puerto en el
firewall del servidor/proveedor (ej. `sudo ufw allow 3000`) — aunque de
nuevo, se recomienda el paso 7 en vez de esto.
