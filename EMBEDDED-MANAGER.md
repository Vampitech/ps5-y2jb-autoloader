# Payload Manager incrustado: fork de Vampitech

Este build conserva las dependencias del exploit fijadas por los submodulos y recompila solamente el autoloader unificado con el ELF seleccionado de itsPLK/ps5-payload-manager. No modifica el codigo del exploit ni requiere un Payload Manager externo para el arranque predeterminado.

## Compilar en GitHub

1. Habilita Actions en tu fork si GitHub lo solicita.
2. Abre Actions > Build with embedded Payload Manager > Run workflow.
3. Deja la version vacia para usar payload-manager.version, indica un tag concreto o escribe latest.
4. Descarga el artefacto de la ejecucion completada. Extrae el contenedor del artefacto: el archivo de instalacion es y2jb_update.zip, no el ZIP exterior de Actions.
5. Conserva embedded-build-manifest.txt para identificar el gestor, los commits y los hashes utilizados.

El workflow no publica releases y no se ejecuta automaticamente. Los workflows originales no utilizan este nuevo script: usa el workflow indicado para obtener el gestor actualizado.

## Actualizaciones futuras

Edita payload-manager.version para cambiar la version predeterminada, o selecciona una version en cada ejecucion. latest se resuelve una sola vez por build; el manifiesto registra el tag real. Para repetir una compilacion, utiliza el tag concreto y los mismos commits. La imagen SDK tambien depende del Dockerfile upstream, por lo que esto no garantiza builds reproducibles byte a byte.

No ejecutes build.sh --download-deps despues del script personalizado: puede sobrescribir el autoloader reconstruido con la release upstream fijada.

## Compilacion local

Requiere Git, Bash, GitHub CLI autenticada, curl, Python 3, Make, sha256sum y Docker accesible al usuario.

```bash
git clone --recurse-submodules https://github.com/Vampitech/ps5-y2jb-autoloader.git
cd ps5-y2jb-autoloader
gh auth login
bash scripts/build_embedded_manager.sh
# Otra version:
bash scripts/build_embedded_manager.sh latest
```

El script rechaza releases sin un SHA-256 valido en la API de GitHub, verifica la descarga y comprueba la cabecera ELF. El hash verifica integridad frente a los metadatos de la release, no constituye una auditoria del binario ni una firma independiente.

## Instalacion y limites

Utiliza el procedimiento de actualizacion documentado en el README upstream para y2jb_update.zip. No actualices el firmware de la consola por este cambio. Conserva tu paquete anterior. Una compilacion correcta no demuestra compatibilidad ni estabilidad en tu consola: este fork necesita pruebas reales.

Un autoload.txt existente puede sustituir el arranque predeterminado y lanzar otro ELF. Si observas una version distinta, revisa la configuracion de autoload antes de atribuirlo al gestor incrustado.

Este workflow genera solamente y2jb_update.zip, no la imagen download0.dat.
