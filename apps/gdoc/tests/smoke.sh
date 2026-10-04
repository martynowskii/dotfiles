#!/usr/bin/env bash
# Сквозная проверка на настоящих конвертерах — то, чего не делают юнит-тесты:
# они нарочно работают на заглушках, чтобы не зависеть от pandoc и chromium.
#
#   tests/smoke.sh [путь-до-gdoc]
#
# По умолчанию берёт gdoc из PATH. Документы делает сама, ничего из дома не
# читает и кэш держит во временном каталоге.
set -u
GDOC=${1:-gdoc}
# После cd в рабочий каталог относительный путь до gdoc перестал бы
# разрешаться, а командой из PATH его уже не считать.
case $GDOC in */*) GDOC=$(realpath "$GDOC") ;; esac

WORK=$(mktemp -d)
export XDG_CACHE_HOME="$WORK/cache"
trap 'rm -rf "$WORK"' EXIT

ok=0
bad=0
pass() { printf 'ок      %s\n' "$1"; ok=$((ok + 1)); }
flunk() { printf 'ПРОВАЛ  %s\n' "$1"; bad=$((bad + 1)); }

# Документ собирается и даёт настоящий PDF. Путь к нему — в $made, чтобы
# проверяющий дальше код не гадал, как он называется.
made=
renders() {
  local src=$1
  local out="$WORK/out-$src.pdf"
  made=
  if ! timeout 180 "$GDOC" -o "$out" -y -- "$src" >/dev/null 2>"$WORK/err"; then
    flunk "$src: $(head -1 "$WORK/err")"
    return 1
  fi
  if ! head -c5 "$out" | grep -q '%PDF-'; then
    flunk "$src: получился не PDF"
    return 1
  fi
  made=$out
  pass "$src -> $(stat -c%s "$out") Б"
}

cd "$WORK" || exit 1

printf '# Заголовок\n\nТекст, **жирный**, формула $e^{i\\pi}=-1$:\n\n$$\\int_0^\\infty e^{-x^2}dx=\\frac{\\sqrt{\\pi}}{2}$$\n\n| а | б |\n| - | - |\n| 1 | 2 |\n' > заметка.md
printf 'а,б,в\n1,2,3\n' > таблица.csv
printf '{\\rtf1\\ansi Privet.\\par}' > письмо.rtf
for f in таблица.csv письмо.rtf; do renders "$f" || true; done

# Markdown печатает typst; его PDF узнаётся по встроенным шрифтам.
if renders заметка.md; then
  if grep -aq 'NewCM\|Libertinus' "$made"; then
    pass "markdown напечатан typst'ом"
  else
    flunk "markdown прошёл мимо typst: шрифтов typst в PDF нет"
  fi
fi

# Картинка из markdown доезжает до PDF: pandoc распаковывает её в кэш, а
# typst читает её уже оттуда, запертый --root. python3 тут не новая
# зависимость — сам gdoc на нём и написан.
python3 - <<'PY'
import struct, zlib, pathlib
def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data)))
pixel = zlib.compress(b"\x00\xff\x00\x00")
pathlib.Path("рисунок.png").write_bytes(
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", pixel) + chunk(b"IEND", b""))
PY
printf '# С картинкой\n\n![подпись](рисунок.png)\n' > скартинкой.md
if renders скартинкой.md; then
  if grep -aq '/Image' "$made"; then
    pass "картинка из markdown попала в PDF"
  else
    flunk "картинка из markdown потерялась"
  fi
fi

# Сырой typst из документа не должен исполняться: иначе #read вклеил бы
# в PDF любой доступный файл.
printf 'Текст.\n\n```{=typst}\n#read("/etc/passwd")\n```\n' > атака.md
if renders атака.md; then
  if grep -aq 'root:x:' "$made"; then
    flunk "сырой typst исполнился: содержимое /etc/passwd попало в PDF"
  else
    pass "сырой typst из документа обезврежен"
  fi
fi

# Готовые форматы отдаются просмотрщику как есть.
printf '%%PDF-1.4\n%%готово\n' > готовый.pdf
got=$(timeout 60 "$GDOC" -p -- готовый.pdf 2>/dev/null)
if [ "$got" = "$WORK/готовый.pdf" ]; then
  pass "pdf передан как есть, без кэша"
else
  flunk "pdf не передан как есть: $got"
fi
if timeout 60 "$GDOC" -o "$WORK" -- готовый.pdf >/dev/null 2>&1; then
  flunk "--out на готовом PDF не отказал"
else
  pass "--out на готовом формате отказывает"
fi

# Кэш отдаёт тот же путь, а не пересобирает каждый раз.
first=$(timeout 180 "$GDOC" -p -- заметка.md 2>/dev/null)
second=$(timeout 180 "$GDOC" -p -- заметка.md 2>/dev/null)
if [ -n "$first" ] && [ "$first" = "$second" ]; then
  pass "кэш отдаёт тот же путь"
else
  flunk "путь разъехался: $first / $second"
fi

printf '\nитог: ок %d, провалов %d\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
