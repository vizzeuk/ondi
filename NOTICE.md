# Créditos y licencias de terceros

Ondi es una interfaz. El trabajo de convertir cada juego en una app de Mac lo hace un motor open source que Ondi descarga en el primer uso y no forma parte de este repositorio.

## Motor

**nxnative** — <https://github.com/seedds/nxnative>
Copyright (c) 2026 seedds. Licencia MIT.
Ondi lo descarga en `~/Library/Application Support/Ondi/engine`, en una versión fija probada, y le aplica `patches/nxnative-keymap.patch` (la opción `DM_KEYMAP` para elegir las teclas). El motor incluye componentes de terceros con sus propias licencias (Ryujinx, deko3d, MacNativeGames y otros); están listados en su `dm/third_party/README.md`.

## Herramientas que Ondi descarga (no se incluyen en este repositorio)

| Herramienta | Origen | Licencia |
|---|---|---|
| Python 3.12 (python-build-standalone) | <https://github.com/astral-sh/python-build-standalone> | PSF / varias |
| lz4, capstone, fonttools, backports.zstd, nsz | PyPI | BSD / MIT |
| .NET 10 | <https://dotnet.microsoft.com> (dotnet-install.sh) | MIT |
| zstd 1.5.7 | <https://github.com/facebook/zstd> (compilado en el Mac) | BSD |
| glslang 16.6 | <https://github.com/KhronosGroup/glslang> | BSD-3-Clause y otras |

Xcode y su compilador de Metal son de Apple; cada usuario los instala desde la App Store.

## Marcas

Nintendo Switch es una marca de Nintendo. Ondi no está afiliado a Nintendo ni a ninguna editorial de juegos, y no usa sus logos, tipografías ni arte.
