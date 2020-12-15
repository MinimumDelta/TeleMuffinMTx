// inspiration from https://github.com/sholafalana/MT5-MT4-Telegram-API-Bot
// emoji unicode: https://apps.timwhitlock.info/emoji/tables/unicode
// pip calculation: https://mql4tradingautomation.com/mql4-pips-normalization/

#property copyright     "Erik A. (Minimum Delta)"
#property link          "minimumdelta@gmail.com"
#property version       "1.1"
#property description   "BE ADVISED: Error logging is printed in the 'Experts' terminal tab.\nLive trading permission is not required for this bot.\nChannel name must start with '@' and is case-sensitive.\n\nMinimum tick-rate is 30ms."
#property strict
#include <Telegram.mqh>

//-- input parameters
input string InpChannelName      = "@MuffinPips"; // Channel Name (Case-Sensitive)
input string InpToken            = "1487864945:AAFsuhbnAHrOCZ2MVSoX2WWenMUo88cruGU"; // Bot API Token (Case-Sensitive)
input int    InpTickRate         = 1000; // Internal Update Interval (Milliseconds)
//-- end input parameters

//--- global variables
int g_anPreviousOpenOrders[]; // initialized in setup
CCustomBot bot;               // initialized in setup
//-- end global variables

// required functions
int init()
{
   SetUp();
   return 0;
}

int deinit() { return 0; }
// end required functions

// [pair] [buy/sell]- Hit TP +[pip#/count] pips:white_check_mark:
string GetTPHitMsg(int nOrderType, string sPair, string sClosePrice, int nPips)
{
   return StringFormat(
      "[%s] [%s] - Hit TP @ %s || [%d] pips :white_check_mark:",
      TransactionOpMnem(nOrderType),
      sPair,
      sClosePrice,
      nPips
   );
}

// [pair] [buy/sell]- Hit SL -[pip#/count] pips:x:
string GetSLHitMsg(int nOrderType, string sPair, string sClosePrice, int nPips)
{
   return StringFormat(
      "[%s] [%s] - Hit SL @ %s || [%d] pips :x:",
      TransactionOpMnem(nOrderType),
      sPair,
      sClosePrice,
      nPips
   );
}

void BroadcastTelegramMsg(string sMsg)
{
   bot.SendMessage(InpChannelName, sMsg);
}

int CalculatePipDifference(double dEntryPrice, double dClosePrice)
{
   return 0; // TODO
}

bool ConnectTelegramBot()
{
   bot.Token(InpToken);
   
   Print("Connecting to telegram bot..");
   
   if(StringLen(InpChannelName) <= 0)
   {
      MessageBox("Error: Channel name is empty.");
   }
   else if (StringGetChar(InpChannelName, 0) != '@')
   {
      MessageBox("Error: Channel name needs to start with '@'.");
   }
   else
   {
      int result = bot.GetMe();
   
      if(result == 0)
      {
         PrintFormat("Connected to telegram bot. Bot name: %s.", bot.Name());
         return true;
      }
      else
      {
         Print("ERROR: Unable to connect to telegram bot. Error message: %s.", GetErrorDescription(result));
      }
   }
   
   return false; // error occurred
}

void SetUp()
{
   // quit if unable to connect to telegram
   if (!ConnectTelegramBot())
   {
      MessageBox("Telegram error: exiting bot. See terminal output window.");
      return;
   }
   
   // initalize open order array
   FillArrayWithOpenOrders(g_anPreviousOpenOrders, true);
   
   PrintFormat("Detected %d existing orders during startup.", ArraySize(g_anPreviousOpenOrders));
   
   int nRealTickRate;
   
   if (InpTickRate < 30) nRealTickRate = 30;
   else nRealTickRate = InpTickRate;
   
   PrintFormat("Tick-rate set to %d.", nRealTickRate);
   
   MessageBox("Setup complete, bot is now live.");
   
   MainLoop(nRealTickRate);
}

// using custom loop instead of event/ontick because they seem unreliable for our use case
void MainLoop(int nTickRate)
{
   ulong ulTime;
   
   while (true)
   {
      Sleep(nTickRate);
      
      ulTime = GetMicrosecondCount();
      
      UpdateOrders();
      
      ulTime = GetMicrosecondCount() - ulTime;
      
      if (ulTime > (ulong)(nTickRate * 1000))
      {
         PrintFormat("WARNING: Update duration exceeded tick rate. ( %d > %d ).", ulTime, nTickRate * 1000);
      }
   }
}

void UpdateOrders()
{
   int anCurrentOpenOrders[];
   int nNewOpenOrders = 0;
   int nNewClosedOrders = 0;
   
   // resize array and populate it with current open orders
   FillArrayWithOpenOrders(anCurrentOpenOrders, true);
   
   // iterate previous orders and broadcast closed ones
   for(int i = 0; i < ArraySize(g_anPreviousOpenOrders); i++)
   {
      int nTicketNumber = g_anPreviousOpenOrders[i];
      
      // there should be no negative ticket numbers in the previous open orders
      if (nTicketNumber < 0)
      {
         Print("Previous open order array contains negative value.");
         continue;
      }
      
      // check if order closed -> broadcast to telegram
      if (OrderSelect(nTicketNumber, SELECT_BY_TICKET, MODE_HISTORY))
      {
         if (OrderCloseTime() == 0) continue; // -> order is still open 
         
         string sOrderOp = TransactionOpMnem(OrderType());
         string sMsg = StringFormat(
                           "[%s] [%s] - Closed @ %s || [%d] pips %s",
                           sOrderOp,
                           OrderSymbol(),
                           DoubleToString(OrderOpenPrice(), Digits),
                           DoubleToString(OrderTakeProfit(), Digits),
                           OrderProfit() > 0 ? ":white_check_mark:" : ":x:" // OrderProfit() is net value -> does not calculate swaps or commissions
                        );
      
         BroadcastTelegramMsg(sMsg);
         
         nNewClosedOrders += 1;
      }
   }
   
   // detect and broadcast new open orders
   for(int i = 0; i < ArraySize(anCurrentOpenOrders); i++)
   {
      int nTicketNumber = anCurrentOpenOrders[i];
      
      // negative ticket number -> no order in given slot
      if (nTicketNumber < 0) continue;
      
      // iterate previous orders -> if cant find ticket number in previous orders it's a new order -> broadcast to telegram
      bool bExistingOrder = NumberInArray(g_anPreviousOpenOrders, nTicketNumber);
      
      // send telegram message if new order
      if (!bExistingOrder)
      {
         string sOrderOp = TransactionOpMnem(OrderType());
         
         string sMsg = StringFormat(
                           "%s %s :arrow_right::door: [%s]\n:dart:TP: [%s]\n:heavy_multiplication_x:SL: [%s]",
                           sOrderOp,
                           OrderSymbol(),
                           DoubleToString(OrderOpenPrice(), Digits),
                           DoubleToString(OrderTakeProfit(), Digits),
                           DoubleToString(OrderStopLoss(), Digits)
                        );
      
         BroadcastTelegramMsg(sMsg);
         
         nNewOpenOrders += 1;
      }
   }
   
   if (nNewOpenOrders > 0 || nNewClosedOrders > 0)
   {
      PrintFormat("INFO: %d orders opened since last update. %d orders closed since last update.", nNewOpenOrders, nNewClosedOrders);
   }
   
   FillArrayWithOpenOrders(g_anPreviousOpenOrders, true);
}

// TODO move to tools file

bool NumberInArray(const int &arr[], const int nNumber)
{
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if (arr[i] == nNumber) return true;
   }
   
   return false;
}

void FillArrayWithOpenOrders(int &arr[], const bool bResizeArray = true)
{
   const int DEFAULT_VALUE = -1;
   
   if (bResizeArray)
   {
      ZeroMemory(arr);
      ArrayResize(arr, OrdersTotal());
   }
   
   for(int i = 0; i < ArraySize(arr); i++)
   {
      // try to select an open order based on index
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         arr[i] = OrderTicket();
      }
      else
      {
         arr[i] = DEFAULT_VALUE; // should not occur
         PrintFormat("Unable to find ticket number for open order with index %d.", i);
      }
   }
}

string TransactionOpMnem(int type)
{
  switch (type)
  {
    case OP_BUY: return("BUY");
    case OP_SELL: return("SELL");
    case OP_BUYLIMIT: return("LIMIT BUY");
    case OP_SELLLIMIT: return("LIMIT SELL");
    case OP_BUYSTOP: return("STOP BUY");
    case OP_SELLSTOP: return("STOP SELL");
    default: return("???");
  }
}

// Function to calculate the decimal digits
// Digits is a native variable in MetaTrader which is assigned as a value the number of digits after the point
double CalculateNormalizedDigits()
{
   //If there are 3 or less digits (JPY for example) then return 0.01 which is the pip value
   if(Digits<=3){
      return(0.01);
   }
   //If there are 4 or more digits then return 0.0001 which is the pip value
   else if(Digits>=4){
      return(0.0001);
   }
   //In all other cases (there shouldn't be any) return 0
   else return(0);
}