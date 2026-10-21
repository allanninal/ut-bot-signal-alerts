//+------------------------------------------------------------------+
//|                                                    UTBotDump.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (not shipped): dumps the MT4 UT Bot buffers and checks   |
//| repainting in the Strategy Tester, via IndTest4/Dump4.mqh.       |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

input double InpKey    = 1.0;
input int    InpATR    = 10;
input bool   InpHeikin = false;
input bool   InpUseEMA = false;
input int    InpEMA    = 200;

double IndValue(const int buf,const int shift)
  {
   return(iCustom(NULL,0,"UTBotAlerts\\UTBotAlerts",InpKey,InpATR,InpHeikin,InpUseEMA,InpEMA,true,true,0.3,
                  false,false,"alert.wav",false,false,buf,shift));
  }

#include <IndTest4/Dump4.mqh>
//+------------------------------------------------------------------+
