# glosa

**Docopt-style argument parsing in pure Bash.** Describe your command line
in plain text, and glosa turns the arguments into shell variables. One file,
no dependencies, Bash 3.2 (the macOS `/bin/bash`) through 5.x.

```bash
#!/usr/bin/env bash
set -euo pipefail
source glosa.sh

help='Resize a picture keeping the original.

Usage:
  resize <file> [--width=<px>] [--keep]
  resize -h | --help

Options:
  -w --width=<px>  Target width [default: 800]
  -k --keep        Keep the original file'

glosa::parse "$help" "$@"

echo "$file is resized to ${width}px"
if $keep; then echo "keeping the original"; fi
```

```console
$ ./resize photo.jpg -k
photo.jpg is resized to 800px
keeping the original
```

## Installation

Pick one:

- **Homebrew:** `brew install DavidMRGaona/tap/glosa`. This installs the
  `glosa` command and the sourceable file at
  `$(brew --prefix)/share/glosa/glosa.sh`.
- **Git submodule:** `git submodule add https://github.com/DavidMRGaona/glosa.git vendor/glosa`
- **Copy the file:**
  `curl -fsSLo glosa.sh https://raw.githubusercontent.com/DavidMRGaona/glosa/v0.1.0/glosa.sh`

## Usage

glosa works in two modes. Both produce exactly the same variables.

**Source mode** (recommended): a function call with no subprocess at all.

```bash
source glosa.sh
glosa::parse "$help" "$@"
glosa::parse --version "1.2.3" "$help" "$@"   # also handles --version
```

**CLI mode:** run `glosa` and `eval` the shell code it prints.

```bash
eval "$(glosa -h "$help" : "$@")"
eval "$(glosa --version "1.2.3" -h "$help" : "$@")"
```

Every value in the printed code is single-quoted, so no argument can inject
code into the `eval`, and values come through byte for byte (`~` included,
which Bash 3.2's `printf %q` would leave to tilde expansion). The test suite checks this with quotes,
`$()`, backticks, `;`, newlines and glob characters.

## Supported syntax

The help text needs a `Usage:` section. Its first word on each line is the
program name. Any section whose header ends in `options:` (`Options:`,
`Global options:`…) describes options. An option's description may wrap
onto indented lines, and `[default: …]` may sit on any of them. A section
ends at the first blank or unindented line.

| Element | Example | Variable | Value |
|---|---|---|---|
| Positional | `<file>`, `FILE` | `file`, `FILE` | the argument, or empty |
| Optional | `[<filter>]` | `filter` | the argument, or empty |
| Command | `store purge` | `purge` | `true` / `false` |
| Long flag | `--pick` | `pick` | `true` / `false` |
| Short and long alias | `-s --small` (in Options) | `small` | `true` / `false` |
| Short-only flag | `-t` | `_t` | `true` / `false` |
| Option with value | `--width=<px>`, `-w <px>` | `width` | the value, or its `[default: …]` |
| Variadic | `<args>...` | `args` | Bash array |
| Repeated option | `--file=<f>...` | `file` | Bash array |
| Counter | `-v...`, `go go` | `_v`, `go` | number of occurrences |
| Group | `(add \| rm)`, `[--a \| --b]` | | |
| Options shortcut | `[options]` | | any option from Options not used in a pattern |
| End of options | `--` | | everything after it is positional |

Name rules: `--skip-setup` becomes `skip_setup`, `<file-name>` becomes
`file_name`, and a short-only `-t` becomes `_t`. Names must be valid shell
identifiers and must not start with `_glosa_`. Names that Bash treats
specially are rejected as an invalid help text, because assigning them would
break the shell or be lost: `_` (so `[-]`), `PATH`, `IFS`, `HOME`, `PWD`,
`UID`, `LANG`, `LC_*`, `BASH_*`, `PS1`…

On the command line, glosa accepts `--width=800`, `--width 800`, `-w800`
and `-w 800`. It also accepts stacked shorts (`-kv`) and unique prefixes of
long options (`--wid 800`).

### Behaviour

- **Every variable is always defined**, even when the matching usage line
  does not mention it. Absent flags are `false`, absent counters `0`,
  absent values empty (or their default) and absent lists `()`. Scripts
  can safely use `set -u`.
- Flags hold the literal words `true` and `false`, so `if $keep; then` works.
- `-h` / `--help` print the whole help text and exit 0 **when they are the
  first argument**. The same goes for `--version` when you pass a version.
- glosa saves and restores the caller's `set -e`, `set -u`, `set -f`,
  `IFS`, `nocasematch` and locale, also before it exits on `-h` or an error.

### Exit codes

| Situation | Output | Exit |
|---|---|---|
| Arguments match | variables assigned | 0 |
| `-h`, `--help`, `--version` | help or version on stdout | 0 |
| Arguments do not match | message and the `Usage:` block on stderr | 1 |
| The help text itself is invalid | `glosa: invalid help text: …` on stderr | 2 |

In CLI mode, these exits reach your script as an `exit N` line in the code
you `eval`.

### Bash 3.2 and empty arrays

On Bash older than 4.4, expanding an empty array with `set -u` fails
(`args[@]: unbound variable`), even though the variable exists. Use the
portable form:

```bash
for arg in ${args[@]+"${args[@]}"}; do ...; done
```

## Performance

In source mode glosa never forks: no subshells, pipes or external commands,
only Bash builtins. Parsing a typical help takes a few milliseconds,
including Bash startup. `make bench` measures it on your machine.

Wall time of a whole `bash -c '…'` run, Bash startup included. Measured
with `hyperfine` on an Apple Silicon Mac, using the helps in `bench/helps`:

| Help | Bash 3.2, source | Bash 3.2, CLI | Bash 5.3, source | Bash 5.3, CLI |
|---|---|---|---|---|
| `resize` (2 lines, 2 options) | 5.1 ms | 8.3 ms | 10.1 ms | 17.0 ms |
| `projects` (1 line) | 4.8 ms | 8.1 ms | 9.8 ms | 16.8 ms |
| `store` (subcommands) | 4.9 ms | 8.2 ms | 9.9 ms | 16.9 ms |
| `dispatcher` (4 lines, variadic) | 5.9 ms | 9.1 ms | 10.8 ms | 18.0 ms |
| `feat` (groups, counters, defaults) | 7.5 ms | 11.0 ms | 12.6 ms | 19.6 ms |

Starting Bash itself takes about 2 ms (3.2) and 8 ms (5.3) of those
figures. CLI mode costs one extra Bash process.

## Development

```bash
make test       # bats suite with the bash on PATH
make test-all   # suite under /bin/bash (3.2) and Homebrew bash (5.x)
make lint       # shellcheck
make bench      # benchmark
```

You need [bats-core](https://github.com/bats-core/bats-core) and
[ShellCheck](https://www.shellcheck.net/).

## Why “glosa”?

In medieval manuscripts, a *glosa* (Latin *glossa*, from Greek *glōssa*,
“tongue, language”) was the note a scribe wrote in the margin to explain
the main text. The best known is the *Glossa Ordinaria*, the standard
commentary on the Bible. English kept the word as *gloss* and *glossary*.

A script's usage text is its own gloss: the lines that explain how to call
it. glosa reads those notes and turns them into variables.

## Credits

glosa implements the [docopt](http://docopt.org/) command-line interface
description language, created by Vladimir Keleshev (docopt is MIT-licensed).
glosa is written from scratch and shares no code with any docopt
implementation.

## License

Copyright (c) 2026 DavidMRGaona (https://github.com/DavidMRGaona)

glosa is free software under the [GNU General Public License v3.0 or
later](LICENSE). You may use, study, share and modify it, and you must keep
the copyright notice.

- Running `glosa` as a separate program (CLI mode) does not make your
  script a derivative work: they only exchange text.
- Sourcing `glosa.sh` (source mode) combines both in one program. If you
  distribute that program, it must be GPL-compatible.

---

## En español

**glosa** es un parser de argumentos estilo docopt escrito en Bash puro.
Describes el uso de tu script en texto y glosa convierte los argumentos en
variables. Es un único archivo sin dependencias y funciona desde Bash 3.2
(el de macOS) hasta 5.x.

**Instalación:**

- `brew install DavidMRGaona/tap/glosa`
- como submódulo de git
- copiando `glosa.sh`

**Uso:**

```bash
source glosa.sh
glosa::parse "$help" "$@"           # sin subprocesos
# o bien
eval "$(glosa -h "$help" : "$@")"   # modo CLI
```

- Todas las variables del uso quedan siempre definidas, así que puedes usar
  `set -u`.
- Los flags valen `true` o `false`, y los variádicos son arrays.
- `-h` o `--help` como primer argumento imprimen la ayuda.
- Si los argumentos no encajan, glosa muestra el error y el bloque
  `Usage:` y sale con 1.

El resto de la documentación está arriba, en inglés.
