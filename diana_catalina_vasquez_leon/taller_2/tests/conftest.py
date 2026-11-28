import os
import sys

# Permite `import db, scraper, validacion` desde tests/ sin instalar nada.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
