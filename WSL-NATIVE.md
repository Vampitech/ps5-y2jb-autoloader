# Compilacion nativa completa en WSL2

Ruta preparada para Ubuntu 24.04 x86_64 sobre WSL2, sin Docker. No se ha ejecutado ni validado en una consola.

## Primer uso

Desde la terminal Ubuntu de WSL, no desde PowerShell:

```bash
mkdir -p ~/projects
cd ~/projects
git clone --recurse-submodules https://github.com/Vampitech/ps5-y2jb-autoloader.git
cd ps5-y2jb-autoloader
bash scripts/wsl-native.sh setup
bash scripts/wsl-native.sh all
```

Si ya clonaste el fork, ejecuta git pull --ff-only antes de usar el script. No ejecutes el script completo con sudo. Solo setup solicita sudo para instalar paquetes apt. Guarda el repositorio en el sistema Linux, no en /mnt/c, y utiliza rutas sin espacios.

## Que construye

setup instala herramientas de Ubuntu y una copia local de Node v22.14.0 (baseline fijada, no la ultima release), y compila el SDK de ps5-payload-dev/sdk. El SDK, Node y los alias del compilador se guardan en ~/.local/share/y2jb-native. No reemplaza /opt/ps5-payload-sdk ni configura alternativas globales. El clon inicial del SDK usa la rama predeterminada en ese momento; el manifiesto registra su commit. No es un entorno reproducible byte a byte.

all compila libmicrohttpd, mbedTLS y libcurl usando el script upstream adaptado a ese SDK; compila el frontend y Payload Manager; compila las revisiones fijadas de ELF Loader, kexp y unified-autoloader; incrusta el ELF del gestor; genera y2jb_update.zip; y crea download0.dat con makefs. No descarga releases ELF precompiladas. El SDK utiliza las fuentes y mecanismos de descarga de su propio build. El frontend utiliza el target upstream frontend-build, que ejecuta npm install y las comprobaciones de npm run build. Requiere Internet.

## Resultados

En dist-native/: y2jb_update.zip, pldmgr.elf, autoloader.elf, elfldr-ps5.elf, kexp.bin, build-manifest.txt, download0.dat y download0.dat.sha256. El ZIP tambien queda en la raiz del proyecto.

```bash
# Solo componentes y ZIP, sin imagen:
bash scripts/wsl-native.sh zip
# Otra release de las fuentes:
bash scripts/wsl-native.sh all v0.6.1
# Reconstruir solamente la imagen a partir del ZIP generado:
bash scripts/wsl-native.sh image
# Limitar paralelismo si falta memoria:
JOBS=2 bash scripts/wsl-native.sh all
```

Usa tags concretos: latest no se admite en esta ruta de fuentes. El valor predeterminado se lee de payload-manager.version. Los clones del gestor se conservan en el directorio local para editar y recompilar; no se resetean ni actualizan automaticamente.

Para compilar tu checkout editable del gestor:

```bash
MANAGER_SOURCE=$HOME/projects/ps5-payload-manager bash scripts/wsl-native.sh all
```

El script no cambia la revision de MANAGER_SOURCE; el manifiesto registra el commit realmente compilado y su estado Git. Los scripts upstream pueden modificar archivos generados. all/zip limpian resultados anteriores de los componentes y sustituyen los binarios de dependencias en src; guarda cualquier binario personalizado antes. Cada build vuelve a compilar las bibliotecas del gestor. No ejecutes build.sh --download-deps despues si quieres conservar el autoloader personalizado.

## Imagen UFS2 y limites

makefs genera una imagen little-endian UFS2 de 336789504 bytes, bloques de 32768 y fragmentos de 4096, con la estructura cache/splash_screen utilizada por el workflow upstream. No necesita montar la imagen ni usar privilegios root. No se garantiza equivalencia byte a byte con newfs en FreeBSD ni compatibilidad real hasta probarla en PS5. Conserva la imagen original y prueba primero el ZIP mediante el procedimiento de actualizacion del README. Una compilacion exitosa no demuestra estabilidad del exploit ni del gestor.

No actualices el firmware por este cambio. Un autoload.txt existente puede lanzar otro ELF en lugar del gestor incrustado.

Los resultados dist-native/ son locales: no los incluyas en commits. El workflow GitHub previamente agregado permanece separado y sigue utilizando el ELF de una release y Docker.
