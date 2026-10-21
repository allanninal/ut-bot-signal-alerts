//+------------------------------------------------------------------+
//|                                                  UTBotAlerts.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| UT Bot: an ATR trailing stop on the close (key value x ATR).     |
//| Buy when the close crosses above the stop line, sell when it     |
//| crosses below. ATR is Wilder's (RMA) seeded with the SMA of the  |
//| first values, as on TradingView. Optional: Heikin Ashi close as  |
//| the source, and an EMA trend filter (buy only above it, sell     |
//| only below it).                                                  |
//| Arrows and alerts come from closed bars only, so a signal never  |
//| appears and then disappears. The line moves on the live bar.     |
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
#property description "UT Bot ATR trailing stop with buy/sell arrows on closed bars, optional EMA trend filter and Heikin Ashi source."
#property description "Alerts: pop-up, sound, push, e-mail. Non-repainting: signals only on closed bars."
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   4
#property indicator_label1  "UT Bot stop"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrTomato
#property indicator_width1  2
#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrTomato
#property indicator_width3  2
#property indicator_label4  "Trend EMA"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGoldenrod
#property indicator_style4  STYLE_DOT

input group "UT Bot"
input double InpKey     = 1.0;     // Key value (sensitivity: ATR multiple)
input int    InpATR     = 10;      // ATR period
input bool   InpHeikin  = false;   // Use the Heikin Ashi close as the source
input group "Trend filter"
input bool   InpUseEMA  = false;   // Only signals with the EMA trend
input int    InpEMA     = 200;     // EMA period
input bool   InpShowEMA = true;    // Draw the EMA (when the filter is on)
input group "Display"
input bool   InpShowLine = true;   // Draw the stop line
input int    InpArrowGap = 12;     // Arrow distance from the candle, pixels

#include "SignalAlerts.mqh"

double g_line[],g_clr[],g_buy[],g_sell[],g_ema_draw[];
double g_atr[],g_src[],g_hao[],g_ema[];
const string PRODUCT="UT Bot";

int OnInit()
  {
   if(InpKey<=0 || InpATR<1 || InpEMA<1)
     {
      Print("UT Bot: key value, ATR period and EMA period must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   SetIndexBuffer(0,g_line,INDICATOR_DATA);
   SetIndexBuffer(1,g_clr,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,g_buy,INDICATOR_DATA);
   SetIndexBuffer(3,g_sell,INDICATOR_DATA);
   SetIndexBuffer(4,g_ema_draw,INDICATOR_DATA);
   SetIndexBuffer(5,g_atr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,g_src,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,g_hao,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,g_ema,INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(1,PLOT_ARROW,233);
   PlotIndexSetInteger(2,PLOT_ARROW,234);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,InpArrowGap);
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,-InpArrowGap);
   for(int p=0; p<4; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,InpShowLine ? DRAW_COLOR_LINE : DRAW_NONE);
   PlotIndexSetInteger(3,PLOT_DRAW_TYPE,(InpUseEMA && InpShowEMA) ? DRAW_LINE : DRAW_NONE);
   IndicatorSetString(INDICATOR_SHORTNAME,StringFormat("UT Bot (%.2f, %d%s%s)",InpKey,InpATR,
                      InpHeikin ? ", HA" : "",InpUseEMA ? ", EMA "+IntegerToString(InpEMA) : ""));
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   for(int i=start; i<rates_total; i++)
     {
      //--- source: close, or the Heikin Ashi close
      if(InpHeikin)
        {
         double hac=(open[i]+high[i]+low[i]+close[i])/4.0;
         g_hao[i]=(i==0 ? (open[i]+close[i])/2.0 : (g_hao[i-1]+g_src[i-1])/2.0);
         g_src[i]=hac;
        }
      else
        {
         g_hao[i]=open[i];
         g_src[i]=close[i];
        }
      //--- ATR: Wilder's smoothing of the true range, seeded with the SMA of the first InpATR values
      double tr=(i==0 ? high[i]-low[i] :
                 MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1]))));
      if(i<InpATR-1)
         g_atr[i]=EMPTY_VALUE;
      else
         if(i==InpATR-1)
           {
            double s=0;
            for(int k=0; k<InpATR; k++)
               s+=(k==0 ? high[k]-low[k] :
                   MathMax(high[k]-low[k],MathMax(MathAbs(high[k]-close[k-1]),MathAbs(low[k]-close[k-1]))));
            g_atr[i]=s/InpATR;
           }
         else
            g_atr[i]=(g_atr[i-1]*(InpATR-1)+tr)/InpATR;
      //--- EMA of the close, seeded with the SMA of the first InpEMA closes
      if(i<InpEMA-1)
         g_ema[i]=EMPTY_VALUE;
      else
         if(i==InpEMA-1)
           {
            double s=0;
            for(int k=0; k<InpEMA; k++)
               s+=close[k];
            g_ema[i]=s/InpEMA;
           }
         else
            g_ema[i]=g_ema[i-1]+2.0/(InpEMA+1)*(close[i]-g_ema[i-1]);
      g_ema_draw[i]=g_ema[i];
      //--- the trailing stop
      double prev=(i>0 ? g_line[i-1] : 0.0);
      g_buy[i]=EMPTY_VALUE;
      g_sell[i]=EMPTY_VALUE;
      if(g_atr[i]==EMPTY_VALUE)
        {
         g_line[i]=EMPTY_VALUE;
         g_clr[i]=0;
         continue;
        }
      if(prev==EMPTY_VALUE)
         prev=0.0;
      double src=g_src[i],p1=(i>0 ? g_src[i-1] : src),nloss=InpKey*g_atr[i];
      if(src>prev && p1>prev)
         g_line[i]=MathMax(prev,src-nloss);
      else
         if(src<prev && p1<prev)
            g_line[i]=MathMin(prev,src+nloss);
         else
            g_line[i]=(src>prev ? src-nloss : src+nloss);
      g_clr[i]=(src>g_line[i] ? 0 : 1);
      //--- signals: the source crosses the stop line; only on closed bars
      if(i==0 || i>rates_total-2 || g_line[i-1]==EMPTY_VALUE)
         continue;
      bool up=(src>g_line[i] && p1<=g_line[i-1]);
      bool dn=(src<g_line[i] && p1>=g_line[i-1]);
      if(InpUseEMA)
        {
         up=up && g_ema[i]!=EMPTY_VALUE && close[i]>g_ema[i];
         dn=dn && g_ema[i]!=EMPTY_VALUE && close[i]<g_ema[i];
        }
      if(up)
        {
         g_buy[i]=low[i];
         if(i==rates_total-2)
            SignalAlert(PRODUCT,"BUY at "+DoubleToString(close[i],_Digits)+", stop "+DoubleToString(g_line[i],_Digits),time[i],prev_calculated>0);
        }
      if(dn)
        {
         g_sell[i]=high[i];
         if(i==rates_total-2)
            SignalAlert(PRODUCT,"SELL at "+DoubleToString(close[i],_Digits)+", stop "+DoubleToString(g_line[i],_Digits),time[i],prev_calculated>0);
        }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
