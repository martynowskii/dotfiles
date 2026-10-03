"""Тесты gdoc.

Модули приложения лежат каталогом выше и импортируются по имени, поэтому
их каталог добавляется в путь поиска:

    cd apps/gdoc && python3 -m unittest discover -s tests -t .

Внешние конвертеры не нужны: .pptx читается своим кодом через zipfile, а
сборка проверяется на подставном рендерере.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
