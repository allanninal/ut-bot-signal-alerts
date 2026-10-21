# SPDX-License-Identifier: MPL-2.0
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
# distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/
# UT Bot: idea by Yo_adriiiiaan (from an original idea by HPotter); TradingView "UT Bot Alerts" by QuantNomad.
"""Independent Python reference for UT Bot Alerts, written from the TradingView Pine script's semantics
(QuantNomad's "UT Bot Alerts"), not translated from the MQL5 code:

    xATR  = ta.atr(c)                                   # Wilder's RMA of the true range, SMA-seeded
    nLoss = a * xATR
    trail = src > trail[1] and src[1] > trail[1] ? max(trail[1], src - nLoss)
          : src < trail[1] and src[1] < trail[1] ? min(trail[1], src + nLoss)
          : src > trail[1] ? src - nLoss : src + nLoss
    buy   = src > trail and crossover(src, trail)       # crossover: src > trail and src[1] <= trail[1]
    sell  = src < trail and crossunder(src, trail)

Additions in the MT5 product: optional Heikin Ashi close as src; optional EMA(200) of the close as a trend filter
(buy only above it, sell only below), EMA seeded with the SMA of the first `period` closes."""
import numpy as np

NAN = np.nan


def true_range(h, l, c):
    tr = h - l
    tr[1:] = np.maximum(tr[1:], np.maximum(np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])))
    return tr


def rma(x, n):
    out = np.full(len(x), NAN)
    if len(x) < n:
        return out
    out[n - 1] = x[:n].mean()
    for i in range(n, len(x)):
        out[i] = (out[i - 1] * (n - 1) + x[i]) / n
    return out


def ema(x, n):
    out = np.full(len(x), NAN)
    if len(x) < n:
        return out
    out[n - 1] = x[:n].mean()
    k = 2.0 / (n + 1)
    for i in range(n, len(x)):
        out[i] = out[i - 1] + k * (x[i] - out[i - 1])
    return out


def heikin_close(o, h, l, c):
    return (o + h + l + c) / 4.0


def utbot(o, h, l, c, key=1.0, atr_period=10, heikin=False, use_ema=False, ema_period=200):
    """Returns (trail, buy, sell) arrays; buy/sell hold the arrow price (low/high) or NaN.
    The last bar is treated as still forming: no signal on it."""
    n = len(c)
    src = heikin_close(o, h, l, c) if heikin else c.copy()
    atr = rma(true_range(h, l, c), atr_period)
    e = ema(c, ema_period)
    trail = np.full(n, NAN)
    buy, sell = np.full(n, NAN), np.full(n, NAN)
    for i in range(n):
        if np.isnan(atr[i]):
            continue
        prev = trail[i - 1] if i > 0 and not np.isnan(trail[i - 1]) else 0.0
        s, s1, nl = src[i], (src[i - 1] if i > 0 else src[i]), key * atr[i]
        if s > prev and s1 > prev:
            trail[i] = max(prev, s - nl)
        elif s < prev and s1 < prev:
            trail[i] = min(prev, s + nl)
        else:
            trail[i] = s - nl if s > prev else s + nl
        if i == 0 or i == n - 1 or np.isnan(trail[i - 1]):
            continue
        up = s > trail[i] and s1 <= trail[i - 1]
        dn = s < trail[i] and s1 >= trail[i - 1]
        if use_ema:
            up = up and not np.isnan(e[i]) and c[i] > e[i]
            dn = dn and not np.isnan(e[i]) and c[i] < e[i]
        if up:
            buy[i] = l[i]
        if dn:
            sell[i] = h[i]
    return trail, buy, sell
