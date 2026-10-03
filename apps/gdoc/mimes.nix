# Типы, которые открывает gdoc. Список общий для .desktop-записи
# (docs.nix) и приложений по умолчанию (mime.nix) — иначе они разъезжаются.
#
# Чего тут намеренно нет, хотя gdoc это читает:
#   text/csv, text/tab-separated-values, text/markdown — обычный текст,
#     который чаще правят, чем читают; остаётся за nvim;
#   application/epub+zip — zathura показывает epub лучше и листает быстрее.
[
  # тексты
  "application/msword"
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  "application/vnd.oasis.opendocument.text"
  "application/rtf"
  "application/x-fictionbook+xml"

  # таблицы
  "application/vnd.ms-excel"
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  "application/vnd.ms-excel.sheet.macroEnabled.12"
  "application/vnd.oasis.opendocument.spreadsheet"
  "application/x-gnumeric"

  # презентации
  "application/vnd.ms-powerpoint"
  "application/vnd.openxmlformats-officedocument.presentationml.presentation"
]
