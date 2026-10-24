"""Both hosts now use one always-editable document; run its real data/focus regression."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("check_inline_editor.py")),run_name="__main__")
