"""Back-compat shim: the client implementation now lives in the pipeline package.

Usage stays identical:
    from sm_client import SmartMoving
    sm = SmartMoving("ld", budget=50)
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pipeline"))

from sm_pipeline.client import BASE, LOG_PATH, BudgetExceeded, SmartMoving  # noqa: F401,E402
from sm_pipeline.instances import INSTANCES  # noqa: F401,E402
