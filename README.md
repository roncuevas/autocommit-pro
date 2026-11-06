# autocommit-pro

Script bash que automatiza commits diarios para llenar tu grafico de contribuciones de GitHub. Configurable con frecuencia flexible, rango de commits por ejecucion y push automatico via cron.

## Requisitos

### Instalacion local

- bash 3.2+
- git
- cron (`crontab`)
- standard Unix tools (`awk`, `cksum`, `mktemp`)

Compatible con **macOS** y **Linux**.

### Docker

- Docker (y opcionalmente Docker Compose)

## Instalacion local

> **Importante: primero crea un fork de este repositorio en tu cuenta de GitHub y clona tu fork.** El modo `self` publica commits en ese repositorio; no configures el repositorio original como destino.

```bash
git clone https://github.com/TU-USUARIO/autocommit-pro.git
cd autocommit-pro
./install.sh
```

El instalador valida todos los valores antes de guardar la configuración o cambiar cron. También permite elegir la rama de destino. En modo `self` propone `autocommit-pro` para mantener los commits automáticos fuera de `main`; puedes elegir otra rama, pero `main` y `master` no se permiten para ese modo. Si `gh` ya está instalado y autenticado, propone usarlo; también puedes elegir autenticación por URL/token. Se encarga de:

1. Crear `config.sh` a partir del template
2. Elegir autenticación con GitHub CLI (`gh`) o token
3. Pedir tu **nombre y email de Git**; con `gh` se sugieren los datos del perfil y puedes editarlos
4. Elegir el destino: el repositorio separado `repo/` o el changelog de tu fork (`self`)
5. Para el destino separado, preguntar por la URL del remote de GitHub (debe iniciar con `https://`)
6. Hacer el push inicial de la rama elegida sin forzar el historial remoto
7. Instalar o reemplazar el cron job solo cuando la configuración y el repositorio estén listos

### Autenticación con GitHub CLI

Elige `gh` al inicio de la instalación. Si aún no hay una sesión activa, el instalador inicia `gh auth login`. Luego sugiere el nombre del perfil (o el login si no hay nombre) y el email principal verificado, consultados mediante GitHub CLI. Puedes aceptar o editar ambos valores. Si el email no está disponible con los permisos actuales, el instalador lo pide manualmente y no solicita alcances adicionales. Después ejecuta `gh auth setup-git --force --hostname github.com` para que Git use el helper oficial de `gh`, incluso si la sesión viene de `GH_TOKEN`. El remote queda sin token incrustado.

Puedes iniciar sesión antes de instalar con:

```bash
gh auth login
```

Consulta la documentación oficial de [`gh auth login`](https://cli.github.com/manual/gh_auth_login) y [`gh auth setup-git`](https://cli.github.com/manual/gh_auth_setup-git). El instalador también admite autenticación por URL/token o credenciales Git existentes. Para habilitar `gh`, instala GitHub CLI siguiendo la [guía oficial](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) y vuelve a ejecutar `./install.sh`. `gh auth setup-git` modifica la configuración global de Git para usar `gh` como helper de credenciales.

`gh` guarda la sesión en el almacén seguro del sistema cuando está disponible; si no encuentra uno, puede recurrir a un archivo de texto plano. Revisa `gh auth status` para confirmar el estado de la sesión y su almacenamiento.

### Autenticación con token

En modo `token`, el nombre y el email se ingresan manualmente; el token se usa para Git y no se consulta la API de perfil. El instalador acepta dos formas de autenticacion:

- **URL con token embebido:** pegar directamente la URL completa
  ```
  https://x-access-token:github_pat_XXXX@github.com/user/repo.git
  ```
- **URL + token por separado:** pegar `https://github.com/user/repo.git` y el instalador pregunta por el token

### Repos separados

`repo/` es un repositorio git independiente de autocommit-pro. Esto permite:

- Hacer `git pull` en autocommit-pro para recibir actualizaciones del tool
- Mantener el historial de contribuciones separado del historial de desarrollo
- Apuntar `repo/` a cualquier repo de GitHub sin mezclar historiales

El destino remoto de una instalación nueva debe estar vacío o compartir historial con `repo/`. El instalador no fuerza el push; si Git rechaza el historial, conserva los commits locales y no instala cron.

### Usar tu fork como destino

Al ejecutar `./install.sh`, elige `self` en **Destination** y luego la rama donde quieres publicar. Esta opción requiere que hayas clonado tu fork y que el remote `origin` apunte a él. Por defecto crea o usa `autocommit-pro`, separada de `main`; también puedes seleccionar otra rama distinta de `main` o `master`. Si la rama ya existe en el remoto, se sincroniza; si no, se crea desde el checkout actual y se publica sin modificar `main`. Cada ejecución agrega una entrada con fecha a `CHANGELOG.md` y crea entre `MIN_COMMITS` y `MAX_COMMITS` commits en esa rama. El script sincroniza la rama antes de escribir y se detiene si hay cambios locales, para no incluirlos en commits automáticos.

Si falla la sincronización, no se crean commits nuevos. Si falla el push, los commits ya creados quedan locales; el proceso devuelve error y vuelve a intentar publicarlos en una ejecución posterior. Si el checkout tiene cambios pendientes, commitea o guarda esos cambios antes de reintentar. Si la ejecución anterior fue terminada a la fuerza, revisa y elimina el directorio de lock indicado en `autocommit.log` antes de volver a ejecutar.

El destino predeterminado sigue siendo `separate`, que utiliza `repo/` como antes.

### macOS: Full Disk Access

En macOS, cron necesita permisos de **Full Disk Access** para ejecutar scripts:

1. Abre **System Settings > Privacy & Security > Full Disk Access**
2. Presiona `Cmd+Shift+G` y navega a `/usr/sbin/cron`
3. Agrega `cron` a la lista

## Configuracion

Edita `config.sh` para personalizar el comportamiento:

### Identidad Git (requerido)

```bash
GIT_USER_NAME="Tu Nombre"
GIT_USER_EMAIL="tu-email@users.noreply.github.com"
```

GitHub solo cuenta contribuciones cuando el email del commit esta vinculado a tu cuenta. El instalador pide estos datos automaticamente, pero puedes cambiarlos en `config.sh`.

Para encontrar tu email de GitHub ve a [github.com/settings/emails](https://github.com/settings/emails). Tambien puedes usar tu direccion noreply: `username@users.noreply.github.com`.

### Rango de commits

```bash
MIN_COMMITS=1   # Minimo de commits por ejecucion
MAX_COMMITS=5   # Maximo de commits por ejecucion
```

El numero real se elige aleatoriamente dentro de ese rango.

### Frecuencia

```bash
FREQUENCY="daily"
```

| Valor | Comportamiento |
|---|---|
| `daily` | Ejecuta todos los dias |
| `weekly` | Ejecuta un dia especifico de la semana |
| `every2days` | Ejecuta cada dos dias (dias pares del epoch) |
| `random` | Ejecuta con probabilidad configurable |

Opciones adicionales segun el modo:

```bash
WEEKLY_DAY=1      # Dia de la semana para modo weekly (1=Lun ... 7=Dom)
RANDOM_CHANCE=50  # Probabilidad (1-100) para modo random
```

### Horario del cron

```bash
CRON_HOUR=9     # Hora (formato 24h)
CRON_MINUTE=30  # Minuto
```

Para aplicar cambios de horario, ejecuta `./install.sh` de nuevo.

### Git remote

```bash
DESTINATION_MODE="separate" # "separate" usa repo/; "self" usa este fork
GIT_AUTH_METHOD="gh"     # "gh" usa GitHub CLI; "token" usa URL/token o credenciales Git
GIT_REMOTE=""      # Nombre del remote (ej: "origin"). Vacio = sin push
GIT_BRANCH=""       # Vacío: main en separate, autocommit-pro en self
```

El instalador permite elegir `GIT_BRANCH`. En modo `self`, el valor vacío selecciona `autocommit-pro` y `main`/`master` se rechazan. Ejecuta `./install.sh` para cambiar el destino o la rama.

Para cambiar `GIT_AUTH_METHOD` en una instalación local, vuelve a ejecutar `./install.sh`; así se comprueba la sesión `gh` y se configura el credential helper además de actualizar `config.sh`.

El script también valida el rango de commits, la frecuencia, los parámetros semanales/aleatorios y los valores del cron. Corrige cualquier valor inválido en `config.sh` y vuelve a ejecutar el instalador.

### Directorio de instalacion

```bash
INSTALL_DIR=""     # Auto-configurado por install.sh. No editar manualmente.
```

## Uso

### Ejecucion automatica

Una vez instalado, el cron job ejecuta `autocommit.sh` automaticamente segun el horario configurado.

### Ejecucion manual

```bash
./autocommit.sh
```

### Verificar cron

```bash
crontab -l
```

Deberias ver una linea con el marcador `# autocommit-pro`.

### Ver logs

Los eventos se registran en `autocommit.log`:

```bash
cat autocommit.log
```

El instalador y las ejecuciones locales escriben eventos con fecha, nivel y fase. Docker conserva el mismo registro en el volumen `autocommit-logs` (`/logs/autocommit.log`) y también muestra los eventos en `docker compose logs autocommit`.

### Actualizar autocommit-pro

```bash
git pull
```

Esto actualiza el tool sin afectar tus contribuciones en `repo/`.

## Instalacion con Docker

Ideal para desplegar en un VPS o cualquier servidor con Docker.

### Docker Compose (recomendado)

```bash
git clone https://github.com/TU-USUARIO/autocommit-pro.git
cd autocommit-pro
```

Usa `DESTINATION_MODE=separate` para publicar en un repositorio independiente vacío, o `DESTINATION_MODE=self` y la URL de tu fork para clonarlo y actualizarlo. Docker guarda ambos destinos en volúmenes persistentes; los commits locales pendientes no se pierden al reemplazar el contenedor.

Crea un archivo `.env` con tus variables:

```bash
REMOTE_URL=https://x-access-token:ghp_XXX@github.com/user/repo.git
DESTINATION_MODE=separate
GIT_AUTH_METHOD=token
GIT_USER_NAME=Tu Nombre
GIT_USER_EMAIL=tu-email@users.noreply.github.com
TZ=America/Mexico_City
```

Y levanta el contenedor:

```bash
docker compose up -d
```

En Docker puedes usar GitHub CLI en modo no interactivo con un token expuesto al proceso del contenedor. No lo agregues al archivo `.env` ni al comando como texto literal:

```bash
export GH_TOKEN="tu-token"
GIT_AUTH_METHOD=gh docker compose up -d
```

También se acepta `GITHUB_TOKEN`. La imagen instala `gh`, configura su helper Git al iniciar y elimina cualquier credencial del URL antes de clonar. Usa un token vigente con acceso de escritura al repositorio seleccionado; GitHub CLI no puede renovar automáticamente los tokens recibidos por estas variables. El token queda en el entorno del contenedor, accesible a quien tenga permisos sobre Docker. Para modo `self`, `REMOTE_URL` debe ser el URL HTTPS de tu fork.

### Pruebas

Ejecuta `bash tests/run.sh` para correr las pruebas unitarias de validación/configuración/logs y las pruebas de integración con remotos Git locales temporales. No se conectan a GitHub.

### Docker run

```bash
docker build -t autocommit-pro .

docker run -d --name autocommit \
  -e REMOTE_URL="https://x-access-token:ghp_XXX@github.com/user/repo.git" \
  -e DESTINATION_MODE=separate \
  -e GIT_AUTH_METHOD=token \
  -e GIT_USER_NAME="Tu Nombre" \
  -e GIT_USER_EMAIL="tu-email@users.noreply.github.com" \
  -e FREQUENCY=daily \
  -e MIN_COMMITS=1 \
  -e MAX_COMMITS=5 \
  -e TZ=America/Mexico_City \
  -v autocommit-repo:/app/repo \
  -v autocommit-self:/data \
  autocommit-pro
```

Las variables requeridas son `REMOTE_URL`, `GIT_USER_NAME` y `GIT_USER_EMAIL`. El resto tiene valores por defecto. Monta los volúmenes indicados también con `docker run` para conservar los commits locales.

### Variables de entorno

| Variable | Default | Descripcion |
|---|---|---|
| `DESTINATION_MODE` | `separate` | `separate` usa `/app/repo`; `self` clona el fork en `/data/autocommit-pro` |
| `GIT_AUTH_METHOD` | `token` | `gh` usa el helper de GitHub CLI; `token` usa `REMOTE_URL`/credenciales Git |
| `REMOTE_URL` | (requerido) | URL con token: `https://x-access-token:TOKEN@github.com/user/repo.git` |
| `GH_TOKEN` / `GITHUB_TOKEN` | (requerido en modo `gh`) | Token no interactivo para GitHub CLI en Docker |
| `GIT_USER_NAME` | (requerido) | Nombre para los commits |
| `GIT_USER_EMAIL` | (requerido) | Email vinculado a tu cuenta de GitHub |
| `MIN_COMMITS` | `1` | Minimo de commits por ejecucion |
| `MAX_COMMITS` | `5` | Maximo de commits por ejecucion |
| `FREQUENCY` | `daily` | `daily` / `weekly` / `every2days` / `random` |
| `WEEKLY_DAY` | `1` | Dia para modo weekly (1=Lun ... 7=Dom) |
| `RANDOM_CHANCE` | `50` | Probabilidad (1-100) para modo random |
| `CRON_HOUR` | `9` | Hora del cron (formato 24h) |
| `CRON_MINUTE` | `30` | Minuto del cron |
| `GIT_BRANCH` | `main` (`autocommit-pro` en `self`) | Rama para los commits y el push; se puede elegir durante la instalación o definir en Docker |
| `TZ` | `UTC` | Zona horaria (ej: `America/Mexico_City`) |

### Comandos utiles

```bash
docker compose logs -f           # Ver logs en tiempo real
docker compose down              # Detener y eliminar contenedor
docker compose up -d --build     # Rebuild y reiniciar
```

Los pushes fallidos se reportan como errores y dejan los commits en el volumen para el siguiente reintento. No se usan pushes forzados.

## Desinstalacion

```bash
./uninstall.sh
```

Esto remueve unicamente el cron job. Los archivos y el repositorio **no se eliminan**. Para una limpieza completa, borra el directorio manualmente:

```bash
rm -rf autocommit-pro
```

## Estructura del proyecto

```
autocommit-pro/                ← repo del tool (git pull para updates)
├── autocommit.sh              # Script principal
├── common.sh                  # Validación, config segura y lock
├── config.sh.example          # Template de configuracion
├── config.sh                  # Tu configuracion (ignorado por git)
├── install.sh                 # Instalador
├── uninstall.sh               # Desinstalador
├── Dockerfile                 # Imagen Docker
├── docker-compose.yml         # Docker Compose
├── entrypoint.sh              # Entrypoint del contenedor
├── tests/run.sh               # Ejecuta pruebas unitarias e integración
│   ├── unit.sh                # Validación, configuración y logs
│   └── integration.sh         # Flujos con repositorios Git temporales
├── .dockerignore
├── .gitignore
├── autocommit.log             # Log de ejecuciones (ignorado por git)
├── CHANGELOG.md               # Registro de commits en destino self
└── repo/                      ← repo separado (origin = tu repo de contribuciones)
    └── contributions.log      # Archivo modificado en cada commit
```

## Como funciona

1. `autocommit.sh` carga la configuracion de `config.sh`
2. Evalua si debe ejecutar hoy segun la frecuencia configurada
3. Calcula un numero aleatorio de commits dentro del rango definido
4. Configura `user.name` y `user.email` en el repo local para que los commits se atribuyan correctamente
5. En modo `separate`, cada commit agrega una linea a `repo/contributions.log`; en modo `self`, agrega una entrada a `CHANGELOG.md` en el fork
6. Si hay un remote configurado, hace push automaticamente
7. Todo queda registrado en `autocommit.log`; los errores hacen que la ejecución termine con código distinto de cero

## Pruebas locales

```bash
bash tests/run.sh
```

Las pruebas usan repositorios Git temporales y no publican cambios en GitHub.

Las pautas para contribuir y modificar los flujos están en [`AGENTS.md`](AGENTS.md); `CLAUDE.md` resume la arquitectura para Claude Code.
