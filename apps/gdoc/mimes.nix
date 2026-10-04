# Типы, которые открывает gdoc. Список общий для .desktop-записи
# (docs.nix) и приложений по умолчанию (mime.nix) — иначе они разъезжаются.
#
# Чего тут намеренно нет, хотя gdoc это читает:
#   text/csv, text/tab-separated-values, text/markdown — обычный текст,
#     который чаще правят, чем читают; остаётся за nvim;
#   application/epub+zip, application/pdf, image/vnd.djvu и прочее готовое —
#     gdoc такое не рисует, а просто передаёт просмотрщику, так что ставить
#     его посредником между файлом и zathura незачем (см. VIEWER_READS).
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
