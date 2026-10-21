//+------------------------------------------------------------------+
//|                                                  UTBotAlerts.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| MT4 edition of UT Bot Signal Alerts: the same calculation as the |
//| MT5 indicator (an ATR trailing stop on the close, key value x    |
//| ATR; buy when the close crosses above the stop line, sell when   |
//| it crosses below; Wilder's ATR seeded with the SMA of the first  |
//| values, as on TradingView; optional Heikin Ashi source and EMA   |
//| trend filter).                                                   |
//| Arrows and alerts come from closed bars only, so a signal never  |
//| appears and then disappears. The line moves on the live bar.     |
//| MT4 differences: the stop line is two buffers (blue/red), and    |
//| the arrow gap is a fraction of ATR (MT4 has no pixel shift).     |
//| Buffers for iCustom match MT5: 0 stop line, 2 buy, 3 sell.       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// Licence: Mozilla Public License 2.0. This Source Code Form is subject
// to the terms of the MPL, v. 2.0. If a copy of the MPL was not
// distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/
// Origin: the UT Bot idea (an ATR trailing stop on the close) is by
// Yo_adriiiiaan ("UT Bot Strategy"), from an original idea by HPotter;
// the TradingView "UT Bot Alerts" script is by QuantNomad. This file is
// an independent MQL implementation of that published method.
// SPDX-License-Identifier: MPL-2.0
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property strict
#property description "UT Bot ATR trailing stop with buy/sell arrows on closed bars, optional EMA trend filter and Heikin Ashi source."
#property description "Alerts: pop-up, sound, push, e-mail. Non-repainting: signals only on closed bars."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1  clrNONE
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_color3  clrDodgerBlue
#property indicator_width3  2
#property indicator_color4  clrTomato
#property indicator_width4  2
#property indicator_color5  clrTomato
#property indicator_width5  2
#property indicator_color6  clrGoldenrod

input double InpKey      = 1.0;    // Key value (sensitivity: ATR multiple)
input int    InpATR      = 10;     // ATR period
input bool   InpHeikin   = false;  // Use the Heikin Ashi close as the source
input bool   InpUseEMA   = false;  // Only signals with the EMA trend
input int    InpEMA      = 200;    // EMA period
input bool   InpShowEMA  = true;   // Draw the EMA (when the filter is on)
input bool   InpShowLine = true;   // Draw the stop line
input double InpArrowGap = 0.3;    // Arrow distance from the candle (x ATR)

#include "SignalAlerts.mqh"

//--- series-indexed (0 = live bar), as every MT4 buffer
double g_line[],g_up[],g_buy[],g_sell[],g_dn[],g_ema_draw[];
double g_atr[],g_src[],g_hao[],g_ema[];
const string PRODUCT="UT Bot";

int OnInit()
  {
   if(InpKey<=0 || InpATR<1 || InpEMA<1 || InpArrowGap<0)
     {
      Print("UT Bot: key value, ATR period and EMA period must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   IndicatorBuffers(10);
   SetIndexBuffer(0,g_line);
   SetIndexBuffer(1,g_up);
   SetIndexBuffer(2,g_buy);
   SetIndexBuffer(3,g_sell);
   SetIndexBuffer(4,g_dn);
   SetIndexBuffer(5,g_ema_draw);
   SetIndexBuffer(6,g_atr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,g_src,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,g_hao,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,g_ema,INDICATOR_CALCULATIONS);
   SetIndexStyle(0,DRAW_NONE);
   SetIndexStyle(1,InpShowLine ? DRAW_LINE : DRAW_NONE);
   SetIndexStyle(4,InpShowLine ? DRAW_LINE : DRAW_NONE);
   SetIndexStyle(2,DRAW_ARROW);
   SetIndexStyle(3,DRAW_ARROW);
   SetIndexArrow(2,233);
   SetIndexArrow(3,234);
   SetIndexStyle(5,(InpUseEMA && InpShowEMA) ? DRAW_LINE : DRAW_NONE,STYLE_DOT);
   SetIndexLabel(0,"UT Bot stop");
   SetIndexLabel(1,NULL);
   SetIndexLabel(2,"Buy");
   SetIndexLabel(3,"Sell");
   SetIndexLabel(4,NULL);
   SetIndexLabel(5,InpUseEMA ? "Trend EMA" : NULL);
   for(int b=0; b<10; b++)
      SetIndexEmptyValue(b,EMPTY_VALUE);
   IndicatorShortName(StringFormat("UT Bot (%.2f, %d%s%s)",InpKey,InpATR,
                      InpHeikin ? ", HA" : "",InpUseEMA ? ", EMA "+IntegerToString(InpEMA) : ""));
   IndicatorDigits(_Digits);
   return(INIT_SUCCEEDED);
  }

//--- true range of the bar at series index s (n = bars in total; the oldest bar has no previous close)
double TrueRange(const int s,const int n,const double &high[],const double &low[],const double &close[])
  {
   if(s==n-1)
      return(high[s]-low[s]);
   return(MathMax(high[s]-low[s],MathMax(MathAbs(high[s]-close[s+1]),MathAbs(low[s]-close[s+1]))));
  }

//--- the two coloured halves of the stop line at series index s, joined to the bar before when the colour changes
void Segments(const int s,const int n)
  {
   g_up[s]=EMPTY_VALUE;
   g_dn[s]=EMPTY_VALUE;
   if(g_line[s]==EMPTY_VALUE)
      return;
   bool up=(g_src[s]>g_line[s]);
   if(up)
      g_up[s]=g_line[s];
   else
      g_dn[s]=g_line[s];
   if(s+1>=n || g_line[s+1]==EMPTY_VALUE)
      return;
   //--- the older bar back to its own colour (a join from an earlier tick of this bar may be stale), then the join
   bool was_up=(g_src[s+1]>g_line[s+1]);
   g_up[s+1]=(was_up ? g_line[s+1] : EMPTY_VALUE);
   g_dn[s+1]=(was_up ? EMPTY_VALUE : g_line[s+1]);
   if(was_up!=up)
     {
      if(up)
         g_up[s+1]=g_line[s+1];
      else
         g_dn[s+1]=g_line[s+1];
     }
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);
   //--- oldest bar first: i counts from the oldest bar (as in the MT5 code), s is the series index
   int first=(prev_calculated>0 ? rates_total-prev_calculated : rates_total-1);
   if(first>=rates_total-1)
      first=rates_total-1;
   for(int s=first; s>=0; s--)
     {
      int i=rates_total-1-s;
      //--- source: close, or the Heikin Ashi close
      if(InpHeikin)
        {
         double hac=(open[s]+high[s]+low[s]+close[s])/4.0;
         g_hao[s]=(i==0 ? (open[s]+close[s])/2.0 : (g_hao[s+1]+g_src[s+1])/2.0);
         g_src[s]=hac;
        }
      else
        {
         g_hao[s]=open[s];
         g_src[s]=close[s];
        }
      //--- ATR: Wilder's smoothing of the true range, seeded with the SMA of the first InpATR values
      if(i<InpATR-1)
         g_atr[s]=EMPTY_VALUE;
      else
         if(i==InpATR-1)
           {
            double sum=0;
            for(int k=0; k<InpATR; k++)
               sum+=TrueRange(rates_total-1-k,rates_total,high,low,close);
            g_atr[s]=sum/InpATR;
           }
         else
            g_atr[s]=(g_atr[s+1]*(InpATR-1)+TrueRange(s,rates_total,high,low,close))/InpATR;
      //--- EMA of the close, seeded with the SMA of the first InpEMA closes
      if(i<InpEMA-1)
         g_ema[s]=EMPTY_VALUE;
      else
         if(i==InpEMA-1)
           {
            double sum=0;
            for(int k=0; k<InpEMA; k++)
               sum+=close[rates_total-1-k];
            g_ema[s]=sum/InpEMA;
           }
         else
            g_ema[s]=g_ema[s+1]+2.0/(InpEMA+1)*(close[s]-g_ema[s+1]);
      g_ema_draw[s]=g_ema[s];
      //--- the trailing stop
      double prev=(i>0 ? g_line[s+1] : 0.0);
      g_buy[s]=EMPTY_VALUE;
      g_sell[s]=EMPTY_VALUE;
      if(g_atr[s]==EMPTY_VALUE)
        {
         g_line[s]=EMPTY_VALUE;
         Segments(s,rates_total);
         continue;
        }
      if(prev==EMPTY_VALUE)
         prev=0.0;
      double src=g_src[s],p1=(i>0 ? g_src[s+1] : src),nloss=InpKey*g_atr[s];
      if(src>prev && p1>prev)
         g_line[s]=MathMax(prev,src-nloss);
      else
         if(src<prev && p1<prev)
            g_line[s]=MathMin(prev,src+nloss);
         else
            g_line[s]=(src>prev ? src-nloss : src+nloss);
      Segments(s,rates_total);
      //--- signals: the source crosses the stop line; only on closed bars (s>=1)
      if(i==0 || s<1 || g_line[s+1]==EMPTY_VALUE)
         continue;
      bool up=(src>g_line[s] && p1<=g_line[s+1]);
      bool dn=(src<g_line[s] && p1>=g_line[s+1]);
      if(InpUseEMA)
        {
         up=up && g_ema[s]!=EMPTY_VALUE && close[s]>g_ema[s];
         dn=dn && g_ema[s]!=EMPTY_VALUE && close[s]<g_ema[s];
        }
      if(up)
        {
         g_buy[s]=low[s]-InpArrowGap*g_atr[s];
         if(s==1)
            SignalAlert(PRODUCT,"BUY at "+DoubleToString(close[s],_Digits)+", stop "+DoubleToString(g_line[s],_Digits),time[s],prev_calculated>0);
        }
      if(dn)
        {
         g_sell[s]=high[s]+InpArrowGap*g_atr[s];
         if(s==1)
            SignalAlert(PRODUCT,"SELL at "+DoubleToString(close[s],_Digits)+", stop "+DoubleToString(g_line[s],_Digits),time[s],prev_calculated>0);
        }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
