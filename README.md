# autocommit-pro

Script bash que automatiza commits diarios para llenar tu grafico de contribuciones de GitHub. Configurable con frecuencia flexible, rango de commits por ejecucion y push automatico via cron. Sin dependencias externas: solo bash, git y cron.

## Requisitos

- bash 3.2+
- git
- cron (`crontab`)

Compatible con **macOS** y **Linux**.

## Instalacion

```bash
git clone https://github.com/roncuevas/autocommit-pro.git
cd autocommit-pro
./install.sh
```

El instalador se encarga de:

1. Crear `config.sh` a partir del template
2. Crear `repo/` con su propio repositorio git y `contributions.log`
3. Preguntar por la URL del remote de GitHub (debe iniciar con `https://`)
4. Si la URL no incluye token, pregunta por un Personal Access Token (opcional)
5. Hacer push inicial al remote
6. Instalar el cron job

### Autenticacion con token

El instalador acepta dos formas de autenticacion:

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

### macOS: Full Disk Access

En macOS, cron necesita permisos de **Full Disk Access** para ejecutar scripts:

1. Abre **System Settings > Privacy & Security > Full Disk Access**
2. Presiona `Cmd+Shift+G` y navega a `/usr/sbin/cron`
3. Agrega `cron` a la lista

## Configuracion

Edita `config.sh` para personalizar el comportamiento:

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
GIT_REMOTE=""      # Nombre del remote (ej: "origin"). Vacio = sin push
GIT_BRANCH="main"  # Branch para push
```

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

### Actualizar autocommit-pro

```bash
git pull
```

Esto actualiza el tool sin afectar tus contribuciones en `repo/`.

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
├── config.sh.example          # Template de configuracion
├── config.sh                  # Tu configuracion (ignorado por git)
├── install.sh                 # Instalador
├── uninstall.sh               # Desinstalador
├── .gitignore
├── autocommit.log             # Log de ejecuciones (ignorado por git)
└── repo/                      ← repo separado (origin = tu repo de contribuciones)
    └── contributions.log      # Archivo modificado en cada commit
```

## Como funciona

1. `autocommit.sh` carga la configuracion de `config.sh`
2. Evalua si debe ejecutar hoy segun la frecuencia configurada
3. Calcula un numero aleatorio de commits dentro del rango definido
4. Por cada commit, agrega una linea con timestamp a `repo/contributions.log`, la agrega al staging y hace commit
5. Si hay un remote configurado, hace push automaticamente
6. Todo queda registrado en `autocommit.log`
