# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Compare what MT5 drew (DumpIndicator CSVs) with the Python reference, bar by bar.

    python3 tests/check_parity.py <dump dir>   (needs numpy and pandas)

Each CONFIG is one DumpIndicator run (tag -> parameters). Dumps hold buffers b0 (stop line), b2 (buy), b3 (sell).
Pass: every closed bar's line within 1e-9 relative, and the same arrows on the same bars."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from reference import utbot  # noqa: E402

CONFIGS = {   # tag: (reference kwargs, DumpIndicator InpParams)
    "ut_default": (dict(), ""),
    "ut_k2_a14_ema": (dict(key=2.0, atr_period=14, use_ema=True, ema_period=200),
                      "d:2.0|i:14|b:false|b:true|i:200|b:true|b:true|i:12|b:false|b:false|s:alert.wav|b:false|b:false"),
    "ut_k1_a10_ha": (dict(key=1.0, atr_period=10, heikin=True),
                     "d:1.0|i:10|b:true|b:false|i:200|b:true|b:true|i:12|b:false|b:false|s:alert.wav|b:false|b:false"),
}


def check(csv: Path, kw: dict) -> tuple[bool, str]:
    d = pd.read_csv(csv)
    o, h, l, c = (d[k].to_numpy(float) for k in ("open", "high", "low", "close"))
    trail, buy, sell = utbot(o, h, l, c, **kw)
    closed = slice(0, len(d) - 1)
    mt_line, mt_buy, mt_sell = (d[k].to_numpy(float) for k in ("b0", "b2", "b3"))
    ok_line = np.allclose(mt_line[closed], trail[closed], rtol=1e-9, atol=0, equal_nan=True)
    bad_line = int((~np.isclose(mt_line[closed], trail[closed], rtol=1e-9, atol=0, equal_nan=True)).sum())
    same_buy = np.array_equal(np.isnan(mt_buy[closed]), np.isnan(buy[closed]))
    same_sell = np.array_equal(np.isnan(mt_sell[closed]), np.isnan(sell[closed]))
    nb, ns = int((~np.isnan(buy[closed])).sum()), int((~np.isnan(sell[closed])).sum())
    ok = ok_line and same_buy and same_sell
    return ok, (f"{csv.stem:40} bars {len(d):>6}  line {'OK' if ok_line else f'{bad_line} differ'}  "
                f"buys {nb:>4} {'OK' if same_buy else 'DIFFER'}  sells {ns:>4} {'OK' if same_sell else 'DIFFER'}")


if __name__ == "__main__":
    root = Path(sys.argv[1])
    allok, n = True, 0
    for tag, (kw, _) in CONFIGS.items():
        for f in sorted(root.glob(f"{tag}_*.csv")):
            ok, msg = check(f, kw)
            allok &= ok
            n += 1
            print(("PASS " if ok else "FAIL ") + msg)
    print(f"\n{'ALL PASS' if allok and n else 'FAILURES'} ({n} files)")
    sys.exit(0 if allok and n else 1)
