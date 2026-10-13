# AGENTS.md — guia para agentes de IA neste fork

> Leia este arquivo inteiro antes de mudar qualquer coisa. Ele explica **o que é o projeto**,
> **o que já foi feito (com evidências)**, **as armadilhas conhecidas** e **os próximos passos**.
> Detalhes operacionais do port estão em [`rpi/README.md`](rpi/README.md).

## 1. O que é o projeto

**Objetivo:** rodar jogos de PlayStation 2 **nativamente** (sem emulador de CPU) num
**Raspberry Pi 2B** com Debian/Raspberry Pi OS, por **recompilação estática**.

- Este repositório é um **fork** de [`ran-j/PS2Recomp`](https://github.com/ran-j/PS2Recomp)
  (GPL-3.0). O fork vive em `j5252/PS2Recomp`, e o trabalho do port está na branch **`rpi2-armhf`**.
- O dono do projeto também tem um protótipo anterior em Python,
  [`PCgamerbom/ps2native`](https://github.com/PCgamerbom/ps2native), que só analisa ISOs/ELFs.
  Ele **não** é usado no pipeline atual. A decisão foi usar o PS2Recomp como base
  porque ele já traduz o R5900 (incluindo MMI de 128 bits e VU0 macro) e tem runtime, IOP e GS.
- Primeiro alvo de validação: um **homebrew próprio** (`rpi/samples/hello`). Primeiro jogo
  comercial: **Metal Slug 3 (PAL, `SLES_525.99`)**, fornecido pelo usuário a partir do próprio disco.

### Por que é possível (e quais são os limites)

- O PS2 usa MIPS (Emotion Engine) e o Pi usa ARM; não dá para reaproveitar o binário.
  O PS2Recomp traduz cada função MIPS para C++ (tradução literal, uma instrução vira uma linha) e
  liga com um runtime que reimplementa kernel/syscalls, IOP, GS, VU, áudio e controle.
- O código usa intrínsecos SSE para os registradores de 128 bits. No ARM, o **sse2neon** converte
  para NEON. O port da PS Vita (também ARMv7) já provava que o código compila em ARM de 32 bits.
- O **GS é renderizado por software**: a GPU só recebe o frame pronto como textura (raylib).
  Por isso a VideoCore IV (GLES2) do Pi 2B basta. **O gargalo esperado é a CPU** (4× Cortex-A7
  a 900 MHz). Jogos 2D leves são o alvo realista; 3D pesado (VU1) provavelmente não roda a 60 fps.
- **Seja honesto:** nunca afirme que um jogo "roda" sem ter executado de fato e observado o resultado.

## 2. Arquitetura (pipeline)

```
ISO do usuário ──► ELF do jogo ──► ps2_analyzer ──► config.toml ──► ps2_recomp ──► C++ gerado
                                   (host x86-64)                    (host x86-64)        │
                                                                                         ▼
     Raspberry Pi 2B ◄── ps2EntryRunner (armhf) ◄── build.sh: runtime + C++ gerado (cross-compile)
```

| Módulo | Papel |
| --- | --- |
| `ps2xAnalyzer/` | acha funções (DWARF, `.symtab`, banco de símbolos SCE, heurística) e gera o TOML |
| `ps2xRecomp/` | decodifica R5900 e emite C++ (uma função por arquivo) |
| `ps2xRuntime/` | memória, tabela de funções, syscalls, GS (software), VU, áudio, pad, VFS; host via raylib |
| `ps2xIOP/` | executa módulos IRX do IOP (R3000A) com fallbacks HLE |
| `ps2xTest/` | testes (`ps2x_tests`), framework próprio `MiniTest` |
| `rpi/` | **adição deste fork**: scripts e toolchain do port para o Pi |

O código gerado vai para `ps2xRuntime/src/runner/*.cpp` e `ps2xRuntime/include/ps2_recompiled_*.h`
(ignorados pelo git) e é compilado junto com o runtime no executável `ps2EntryRunner`.

## 3. O que este fork mudou

Commits em `rpi2-armhf` sobre `upstream/main`:

- `CMakeLists.txt`: em ARM Linux de 32 bits (não Vita/Android/MSVC), usa
  `-mcpu=${PS2X_ARM32_CPU} -mfpu=neon-vfpv4 -mfloat-abi=hard` (padrão `cortex-a7`).
- `ps2xRuntime/CMakeLists.txt`: opção `PS2X_RPI_DRM`, que compila o raylib com `PLATFORM=DRM` (GLES2)
  e desliga a UI de debug.
- `ps2xRuntime/cmake/ReleaseMode.cmake`: opção `PS2X_ENABLE_LTO` (padrão ON, como no upstream).
- `rpi/`: `setup.sh`, `build.sh`, `recompile.sh`, `chroot_common.sh`, `toolchain-armhf.cmake`,
  `samples/hello`, `README.md`.

As mudanças fora de `rpi/` foram mantidas pequenas e com padrão inalterado, para que um PR
upstream seja viável.

## 4. Estado atual (13/10/2026) e evidências

| Item | Resultado |
| --- | --- |
| Runtime + IOP compilam para armhf | ok. Binário ARMv7-A, NEON (Fused-MAC), VFPv4, ABI hard-float; depende de GLESv2/EGL/DRM/GBM |
| `ps2x_tests` armhf sob `qemu-arm` | **437 passaram, 0 falharam** |
| `hello.elf` (ps2dev, `-g`) → recompilado (474 arquivos) → `ps2EntryRunner` armhf | linka. **Não executado** (sem Pi/DRM no ambiente) |
| Metal Slug 3 `SLES_525.99` → recompilado | ok: 18.867 arquivos; 18.661 funções com nome real (o ELF tem `.symtab` e relocações, CodeWarrior) |
| Metal Slug 3 → `ps2EntryRunner` armhf | **não concluído**: com LTO deu OOM (7,4 GB); sem LTO leva cerca de 4 h numa máquina de 4 núcleos. Movido para uma máquina mais forte |
| Execução em Raspberry Pi real | **nunca feita** |
| Versão do sistema no Pi do usuário | **não confirmada**. O binário de trixie exige glibc ≥ 2.38 (não roda no Raspberry Pi OS 12/bookworm) |

## 5. Próximos passos (em ordem)

Cada passo tem um critério de aceite. Não pule para o seguinte sem cumprir o anterior.

1. **Concluir o build do Metal Slug 3 para armhf** numa máquina forte (`rpi/README.md`).
   Anote tempo, pico de RAM e tamanho do `ps2EntryRunner`.
   *Aceite:* `outrpi/ps2EntryRunner` gerado; `readelf -A` mostra NEON/hard-float.
2. **Validar o jogo no PC antes do Pi.** Compile o runner nativo x86-64 Linux (build normal do
   upstream, com raylib desktop) com o mesmo código gerado e rode o ELF com os arquivos do disco.
   Depurar no PC é muito mais rápido que no Pi.
   *Aceite:* o jogo passa do boot e mostra imagem, ou há uma lista documentada do que trava
   (syscall ou stub faltando, IRX, leitura de `.AFS`, vídeos `.SFD`).
3. **`hello` no Pi real.** Confirme a versão do sistema do Pi (`cat /etc/os-release`), refaça o
   `setup.sh` com a suite correta se precisar, rode num console de texto (sem desktop) e com o
   usuário nos grupos `video`/`render`.
   *Aceite:* o quadrado se move na tela; registrar FPS.
4. **Metal Slug 3 no Pi.** *Aceite:* boot e menu visíveis; medir FPS e uso de CPU por thread.
5. **Otimização para o Cortex-A7**, guiada por medição (`perf` no Pi):
   - nível de otimização separado para o código gerado (`-O1`/`-O2`) e para o runtime (`-O3`);
     mede tempo de build e FPS;
   - pontos quentes do GS por software (rasterização, conversão de formatos) com NEON;
   - `ccache` para rebuilds.
6. **CI**: workflow no GitHub Actions que roda `setup.sh` e `TESTS=1 build.sh` (só homebrew).
   *Aceite:* job verde e artefato `ps2EntryRunner` do hello.
7. **PR upstream** com as mudanças genéricas (flags ARMv7, `PS2X_RPI_DRM`, `PS2X_ENABLE_LTO`, `rpi/`),
   depois que os passos 3 e 6 estiverem prontos.

## 6. Problemas conhecidos

- **Dados tratados como código no MS3:** o CodeWarrior juntou código e dados na seção `main` (WAX).
  Cerca de 206 funções `sub_XXXXXXXX` (ex.: `sub_00546730` em diante) são strings/tabelas e geram
  "unhandled instruction". Só importa se forem executadas. Se for o caso, use `skip` no TOML ou
  limite as faixas pelo `.symtab`.
- **Saltos indiretos** (`jr`/`jalr`) viram despacho por tabela em tempo de execução (avisos
  `control-flow ... promoted N fallback entries`). É o comportamento esperado.
- **FFmpeg desligado** no build do Pi: vídeos MPEG/Sofdec (`.SFD`) viram frames vazios.
- **LTO** num jogo grande precisa de mais de 8 GB num único processo; o `build.sh` desliga por padrão.
- **WSL:** ler milhares de arquivos de `/mnt/c` derrubou a sessão do WSL várias vezes depois de um
  OOM; `wsl --shutdown` resolveu. Por isso o `build.sh` espelha o código dentro do chroot via `rsync`.
  No Git Bash, chame o WSL com `MSYS_NO_PATHCONV=1` e passe comandos por arquivo de script
  (o `wsl.exe` expande `$`).
- O `rpi/recompile.sh` apaga os `.cpp` de `src/runner/`, incluindo o placeholder versionado
  `register_functions.cpp`. Restaure com `git checkout -- ps2xRuntime/src/runner/register_functions.cpp`.

## 7. Regras

1. **Nunca versione material de jogos:** ISOs, ELFs, IRX, BIOS, assets ou código gerado a partir
   deles. `ps2xRuntime/src/runner/`, `include/ps2_recompiled_*.h`, `rpi/work/` e `outrpi/` são ignorados.
   Antes de commitar, confira `git status`; o `register_functions.cpp` modificado **não** entra.
2. **Licença:** o projeto é GPL-3.0. Código novo segue a mesma licença.
3. **Honestidade:** "compila", "passa nos testes", "roda no PC" e "roda no Pi" são estados
   diferentes. Reporte exatamente o que foi verificado.
4. Mudanças em arquivos do upstream: mínimas, atrás de opção, com padrão igual ao upstream.
5. Ao concluir um passo da seção 5, **atualize as seções 4 e 5 deste arquivo**.
6. Commits terminam com a linha de coautoria do agente quando aplicável. Não faça push forçado na `rpi2-armhf`.

## 8. Ambiente usado até agora (máquina do usuário)

- Windows 11 + WSL2 (`kali-linux`), 4 vCPUs, cerca de 8 GB de RAM no WSL.
- Chroot de build: `/opt/ps2x-rpi/trixie` (Debian 13, GCC 14.2 cross armhf, CMake 3.31, glibc 2.41).
- Toolchain PS2 (homebrew): `/opt/ps2dev` (ps2dev v2.0.0, GCC 15.2 para o EE).
- Dados do jogo fora do repo: `C:\Users\joao-\projects\ps2-games\mslug3\SLES_525.99`.
