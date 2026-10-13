# Raspberry Pi 2B (armhf) — port do runtime

Gera o `ps2EntryRunner` nativo para **Raspberry Pi 2B** (ARMv7 Cortex-A7, NEON, hard-float),
usando raylib em **KMS/DRM + OpenGL ES 2.0** (driver `vc4`, sem X11/Wayland).

O build roda num **chroot Debian** da mesma versão do sistema do Pi, com cross-compiler armhf.
Assim o binário pede o glibc certo. Funciona em Debian/Ubuntu/Kali nativos ou no WSL2.

## Estado

| Item | Situação |
| --- | --- |
| Runtime + IOP compilam para armhf (sse2neon em ARMv7) | ok |
| `ps2x_tests` no qemu-arm | **437/437 passam** |
| Homebrew `samples/hello` recompilado e linkado | ok (ainda não executado no Pi) |
| Jogo comercial grande (≈19 mil funções) | recompila; o build armhf leva horas numa máquina de 4 núcleos |
| Execução real no Pi 2B | **não testada ainda** |

O GS do runtime é renderizado **por software**: a GPU só recebe a imagem pronta como textura.
No Pi 2B o gargalo esperado é a CPU, não a GPU.

## Requisitos da máquina de build

- Linux x86-64 (ou WSL2), `sudo`, `debootstrap`, `rsync`, acesso à internet (FetchContent).
- RAM: 8 GB bastam **sem LTO** (padrão aqui). Com `LTO_ON=1`, um jogo grande passou de 7,4 GB
  num único processo `lto1-ltrans`; use só com 16 GB ou mais.
- Núcleos: o tempo cai quase linearmente com `JOBS`. Cada job de compilação de lote unity
  do código gerado pode usar 1–2 GB.
- Para compilar homebrew: toolchain [ps2dev](https://github.com/ps2dev/ps2dev/releases)
  (ex.: `/opt/ps2dev`).

## Passo a passo

```bash
git clone -b rpi2-armhf https://github.com/j5252/PS2Recomp.git
cd PS2Recomp
sudo apt install debootstrap rsync

# 1) Ambiente (uma vez). Use a mesma release do Debian do Pi:
#    Raspberry Pi OS 13 = trixie (padrão), Raspberry Pi OS 12 = bookworm.
sudo ./rpi/setup.sh                       # ou: sudo PS2X_RPI_SUITE=bookworm ./rpi/setup.sh

# 2) (opcional) validar o runtime em ARMv7 sob qemu
sudo TESTS=1 ./rpi/build.sh

# 3) Recompilar um ELF (gera C++ em ps2xRuntime/src/runner/ e include/)
sudo ./rpi/recompile.sh /caminho/para/SLUS_XXX.XX

# 4) Compilar o executável do Pi
sudo JOBS=16 ./rpi/build.sh
# resultado: outrpi/ps2EntryRunner
```

Se usar `PS2X_RPI_SUITE` no `setup.sh`, passe o mesmo valor ao `recompile.sh` e ao `build.sh`.

### Homebrew de teste

```bash
export PS2DEV=/opt/ps2dev PS2SDK=$PS2DEV/ps2sdk GSKIT=$PS2DEV/gsKit
export PATH=$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH
make -C rpi/samples/hello
sudo ./rpi/recompile.sh rpi/samples/hello/hello.elf
sudo ./rpi/build.sh
```

## Rodando no Pi

1. Raspberry Pi OS **Lite** (sem desktop) com o driver KMS ativo (`dtoverlay=vc4-kms-v3d`, padrão).
2. Copie `outrpi/ps2EntryRunner` e os arquivos do jogo (ELF + dados do disco).
3. Num console de texto (não dentro de uma sessão gráfica):
   ```bash
   ./ps2EntryRunner /caminho/no/pi/SLUS_XXX.XX
   ```
4. O usuário precisa estar nos grupos `video` e `render` (acesso a `/dev/dri`).

## Scripts

| Script | Função |
| --- | --- |
| `setup.sh` | cria o chroot Debian (`/opt/ps2x-rpi/<suite>`) com cross-compiler armhf e libs DRM/GBM/EGL/GLES/ALSA |
| `recompile.sh` | compila `ps2_analyzer`/`ps2_recomp` para o host e recompila um ELF |
| `build.sh` | espelha o código no chroot (rsync) e compila o runner armhf; `TESTS=1` roda os testes no qemu |
| `chroot_common.sh` | funções compartilhadas (montagens, execução no chroot) |
| `toolchain-armhf.cmake` | toolchain CMake (Cortex-A7, multiarch armhf, emulador qemu) |

Variáveis úteis do `build.sh`: `JOBS`, `CLEAN=1`, `BUILD_TYPE`, `LTO_ON=1`, `TESTS=1`.

## Dados de jogos

ELFs, ISOs e o código gerado a partir deles **não** vão para o repositório:
`ps2xRuntime/src/runner/`, os headers gerados em `include/` e `rpi/work/` estão no `.gitignore`.
O `register_functions.cpp` é versionado como placeholder; depois de recompilar um jogo, restaure-o com:

```bash
git checkout -- ps2xRuntime/src/runner/register_functions.cpp
```

## Notas sobre WSL

- Repositório em `/mnt/c` é lento; o `build.sh` espelha o código dentro do chroot por isso.
- Depois de um OOM, o WSL ficou instável (sessões caindo sem erro durante leituras pesadas de
  `/mnt/c`). `wsl --shutdown` resolveu.
