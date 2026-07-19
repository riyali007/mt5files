#ifndef ADVTP_SOUND_MANAGER_MQH
#define ADVTP_SOUND_MANAGER_MQH

void PlayATPSound(const string wav_name)
{
   if(!InpEnableSounds)
      return;

   if(StringLen(wav_name) <= 0)
      return;

   // Strategy Tester: optional — still try (often silent)
   ResetLastError();
   if(!PlaySound(wav_name))
      LogDebug("SOUND", "PlaySound failed '" + wav_name + "' err=" + IntegerToString(GetLastError()));
}

void SoundOnPartial()
{
   if(!InpSoundOnPartial)
      return;
   PlayATPSound(InpSoundPartial);
}

void SoundOnBreakevenSet()
{
   if(!InpSoundOnBreakeven)
      return;
   PlayATPSound(InpSoundBreakeven);
}

void SoundOnFullTP()
{
   if(!InpSoundOnFullTP)
      return;
   PlayATPSound(InpSoundFullTP);
}

void SoundOnSLOrBEHit()
{
   if(!InpSoundOnSLHit)
      return;
   PlayATPSound(InpSoundSLHit);
}

// Classify a full close for sound: FULL_TP / SL_HIT / BE_HIT / OTHER
string ClassifyManagedCloseReason(const TradeState &state,const double exit_price)
{
   double point = SymbolInfoDouble(state.symbol,SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   // Tolerance: 10 points or 2*spread-ish floor
   double tol = point * 10.0;

   MqlTick tick;
   if(SymbolInfoTick(state.symbol,tick))
   {
      double spread = MathAbs(tick.ask - tick.bid);
      if(spread * 2.0 > tol)
         tol = spread * 2.0;
   }

   // Full TP: exit at/through take profit
   if(state.take_profit > 0.0)
   {
      if(state.position_type == POSITION_TYPE_BUY)
      {
         if(exit_price + tol >= state.take_profit)
            return("FULL_TP");
      }
      else
      {
         if(exit_price - tol <= state.take_profit)
            return("FULL_TP");
      }
   }

   // BE hit: BE was applied and exit near entry or BE SL
   if(state.be_applied)
   {
      double be_level = state.stop_loss;
      if(be_level <= 0.0)
         be_level = state.entry_price;

      if(MathAbs(exit_price - be_level) <= tol || MathAbs(exit_price - state.entry_price) <= tol)
         return("BE_HIT");
   }

   // SL hit: exit at/through stop loss
   if(state.stop_loss > 0.0)
   {
      if(state.position_type == POSITION_TYPE_BUY)
      {
         if(exit_price - tol <= state.stop_loss)
            return("SL_HIT");
      }
      else
      {
         if(exit_price + tol >= state.stop_loss)
            return("SL_HIT");
      }
   }

   // Fallback from notes already used in registry
   return("OTHER");
}

void SoundOnManagedClose(const TradeState &state,const double exit_price)
{
   string reason = ClassifyManagedCloseReason(state,exit_price);

   if(reason == "FULL_TP")
   {
      SoundOnFullTP();
      return;
   }

   if(reason == "BE_HIT" || reason == "SL_HIT")
   {
      SoundOnSLOrBEHit();
      return;
   }

   // Basket/manual close etc. — soft optional: use SL sound only if you want
   // Leave silent for OTHER
}

#endif