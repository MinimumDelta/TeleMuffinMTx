// inspiration from https://github.com/dennislwm/MT4-Telegram-Bot-Recon
// emoji unicode: https://www.unicode.org/emoji/charts/full-emoji-list.html
// pip calculation: https://mql4tradingautomation.com/mql4-pips-normalization/

#property copyright     "Erik A. (Minimum Delta)"
#property link          "minimumdelta@gmail.com"
#property version       "1.1"
#property description   "BE ADVISED: Error logging is printed in the 'Experts' terminal tab.\nLive trading permission is not required for this bot.\nChannel name must start with '@' and is case-sensitive.\n\nMinimum tick-rate is 30ms, recommended tick-rate is between 100ms and 1000ms (1 second)."
#property strict
#include <Telegram.mqh>

//--- input parameters
input string InpChannelName      = "@MuffinPips";  // Channel Name (Case-Sensitive)
input string InpToken            = "ENTER KEY HERE"; // Bot API Token (Case-Sensitive)
input int    InpTickRate         = 1000;           // Internal Update Interval (Milliseconds)
input string InpNotificationAcc  = "";             // MetaQuotes Account ID for Notifications
//-- end input parameters

//--- global variables -> all initialized in SetUp function
int g_anPreviousOpenOrders[];
int g_anClosedOrderTickets[];
int g_anOpenedOrderTickets[];
CCustomBot bot;               // TODO rename this g_cBot
//-- end global variables

//--- required functions
int init()
{
   SetUp();
   return 0;
}

int deinit() 
{
   SendNotification("WARNING: MuffinMT4 Telegram Bot offline.");
   return 0;
}
//-- end required functions

void BroadcastTelegramMsg(string sMsg)
{
   bot.SendMessage(InpChannelName, sMsg);
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
   FillArrayWithOpenOrders(g_anPreviousOpenOrders);
   
   PrintFormat("Detected %d existing orders during startup.", ArraySize(g_anPreviousOpenOrders));
   
   int nRealTickRate;
   
   if (InpTickRate < 30) nRealTickRate = 30;
   else nRealTickRate = InpTickRate;
   
   PrintFormat("Tick-rate set to %d.", nRealTickRate);
   
   MessageBox("Setup complete, bot is now live.");
   SendNotification("MuffinMT4 Telegram Bot is now live.");
   
   MainLoop(nRealTickRate);
}

// using custom loop instead of event/ontick because they seem unreliable for our use case
void MainLoop(int nTickRate)
{
   ulong ulTime;
   bool bSleep = true;
   
   while (true)
   {
      if (bSleep) Sleep(nTickRate);
      
      // using microseconds instead of milliseconds because of the larger datatype (ulong vs uint)
      ulTime = GetMicrosecondCount();
      
      // perform update
      UpdateOrders();
      
      // get time diff
      ulTime = GetMicrosecondCount() - ulTime;
      
      // notify if diff too large (happens when lots of telegram messages are sent during an update
      if (ulTime > (ulong)(nTickRate * 1000))
      {
         PrintFormat("WARNING: Update duration exceeded 10 seconds -> ( %dms )", ulTime / 1000);
         bSleep = false; // so we can process the requests immediately
      }
      else // unable to figure out a bug that happens when spamming transactions but this fixes it
      {
         ZeroMemory(g_anClosedOrderTickets);
         ZeroMemory(g_anOpenedOrderTickets);
         ArrayResize(g_anClosedOrderTickets, 256);
         ArrayResize(g_anOpenedOrderTickets, 256);
         bSleep = true;
      }
   }
}

void UpdateOrders()
{
   int anCurrentOpenOrders[];
   int nNewOpenOrders = 0;
   int nNewClosedOrders = 0;
   
   // resize array and populate it with current open orders
   // this should be the ONLY place to pull order history during the update loop
   FillArrayWithOpenOrders(anCurrentOpenOrders);
   
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
      
      // make sure message hasn't already been sent -> unsure why this sometimes happens
      if (NumberInArray(g_anClosedOrderTickets, nTicketNumber))
      {
         PrintFormat("Closed order %d already broadcasted, skipping..", nTicketNumber);
         continue;
      }
      
      // check if order closed -> broadcast to telegram
      if (OrderSelect(nTicketNumber, SELECT_BY_TICKET, MODE_HISTORY))
      {
         if (OrderCloseTime() == 0) continue; // -> order is still open 
         
         // determine if order was manually closed or hit TP/SL
         if (OrderType() == OP_BUY)
         {
            if (OrderTakeProfit() > 0 && OrderClosePrice() >= OrderTakeProfit()) // hit TP
            {
               ProcessTP();
            }
            else if (OrderStopLoss() > 0 && OrderClosePrice() <= OrderStopLoss()) // hit SL
            {
               ProcessSL();
            }
            else // manual close
            {
               ProcessManualClose();
            }
         }
         else if (OrderType() == OP_SELL)
         {
            if (OrderStopLoss() > 0 && OrderClosePrice() >= OrderStopLoss()) // hit SL
            {
               ProcessSL();
            }
            else if (OrderTakeProfit() > 0 && OrderClosePrice() <= OrderTakeProfit()) // hit TP
            {
               ProcessTP();
            }
            else // manual close
            {
               ProcessManualClose();
            }
         }
         else // other ops are not supported at this time
         {
            continue;
         }
         
         // this will only support 256 transactions, which shouldn't be a problem because the cache is cleared after when the backlog has been processed
         for(int j = 0; j < ArraySize(g_anClosedOrderTickets); j++)
         {
            if (g_anClosedOrderTickets[i] == 0)
            {
               g_anClosedOrderTickets[i] = nTicketNumber;
               break;
            }
         }
         
         nNewClosedOrders += 1;
      }
      else
      {
         PrintFormat("Unable to find closed order with ticket number %d.", nTicketNumber);
      }
   }
   
   // detect and broadcast new open orders
   for(int i = 0; i < ArraySize(anCurrentOpenOrders); i++)
   {
      int nTicketNumber = anCurrentOpenOrders[i];
      
      // negative ticket number -> no order in given slot -> bad
      if (nTicketNumber < 0)
      {
         Print("Current open order array contains negative value.");
         continue;
      }
      
      if (NumberInArray(g_anOpenedOrderTickets, nTicketNumber))
      {
         PrintFormat("New opened order already broadcast, skipping. Ticket number: %d.", nTicketNumber);
         continue;
      }
      
      if (OrderSelect(nTicketNumber, SELECT_BY_TICKET, MODE_TRADES))
      {
         // somehow a closed order made it's way in here -> bad
         if (OrderCloseTime() != 0)
         {
            // idk if i should increment closed orders or not.. TODO maybe determine if the order was closed during the current/previous update cycle
            PrintFormat("Closed order found in open order array. Ticket number: %d.", nTicketNumber);
            continue;
         }
         
         // iterate previous orders -> if cant find ticket number in previous orders it's a new order -> broadcast to telegram
         bool bExistingOrder = NumberInArray(g_anPreviousOpenOrders, nTicketNumber);
         
         // send telegram message if new order
         if (!bExistingOrder)
         {
            ProcessBuy();
            
            // this will only support 256 transactions, which shouldn't be a problem because the cache is cleared after when the backlog has been processed
            for(int j = 0; j < ArraySize(g_anOpenedOrderTickets); j++)
            {
               if (g_anOpenedOrderTickets[i] == 0)
               {
                  g_anOpenedOrderTickets[i] = nTicketNumber;
                  break;
               }
            }
            
            nNewOpenOrders += 1;
         }
      }
      else
      {
         PrintFormat("ERROR: Unable to find order opened with ticket number %d.", nTicketNumber);
         continue;
      }
   }
   
   // notify if changes have happened
   if (nNewOpenOrders > 0 || nNewClosedOrders > 0)
   {
      PrintFormat("INFO: %d orders opened since last update. %d orders closed since last update.", nNewOpenOrders, nNewClosedOrders);
   }
   
   // IMPORTANT: copy array -> do not populate from current order list -> new orders can happen during update cycle meaning they will be incorrectly marked as processed
   ZeroMemory(g_anPreviousOpenOrders);
   ArrayResize(g_anPreviousOpenOrders, ArraySize(anCurrentOpenOrders));
   ArrayCopy(g_anPreviousOpenOrders, anCurrentOpenOrders);
}

// [pair] [buy/sell]- Hit TP +[pip#/count] pips:white_check_mark:
void ProcessTP()
{
   string sOrderOp   = TransactionOpMnem(OrderType());
   string sMsg       = StringFormat(
                     "%s %s ➡ %s\n ➡TP: %s\n ✖️SL: %s\n",
                     sOrderOp,
                     OrderSymbol(),
                     DoubleToString(OrderOpenPrice(), Digits),
                     DoubleToString(OrderOpenPrice(), Digits),
                     CalculatePipDifference()
                  );

   BroadcastTelegramMsg(sMsg);
}

// [pair] [buy/sell]- Hit SL -[pip#/count] pips:x:
void ProcessSL()
{
   string sOrderOp   = TransactionOpMnem(OrderType());
   string sMsg       = StringFormat(
                     "%s %s - Hit SL!\n%s -> %s\n%d pips :x:",
                     sOrderOp,
                     OrderSymbol(),
                     DoubleToString(OrderOpenPrice(), Digits),
                     DoubleToString(OrderStopLoss(), Digits),
                     CalculatePipDifference()
                  );
   
   BroadcastTelegramMsg(sMsg);
}

// [pair] [buy/sell]- Closed @ +[pip#/count] pips:white_check_mark:
// [pair] [buy/self]- Closed @ -[pip#/count] pips:x:
void ProcessManualClose()
{
   string sOrderOp   = TransactionOpMnem(OrderType());
   string sEmoji     = OrderProfit() > 0 ? ":white_check_mark:" : ":x:"; // OrderProfit() is net value -> does not calculate swaps or commissions
   string sMsg       = StringFormat(
                     "%s %s - Manual Order Close\n%s -> %s\n%d pips %s",
                     sOrderOp,
                     OrderSymbol(),
                     DoubleToString(OrderOpenPrice(), Digits),
                     DoubleToString(OrderClosePrice(), Digits),
                     CalculatePipDifference(),
                     sEmoji
                  );

   BroadcastTelegramMsg(sMsg);
}

void ProcessBuy()
{
   string sOrderOp   = TransactionOpMnem(OrderType()); 
   string sMsg       = StringFormat(
                     "%s %s :arrow_right::door: %s\n:dart:TP: %s\n:heavy_multiplication_x:SL: %s\n",
                     sOrderOp,
                     OrderSymbol(),
                     DoubleToString(OrderOpenPrice(), Digits),
                     DoubleToString(OrderTakeProfit(), Digits),
                     DoubleToString(OrderStopLoss(), Digits)
                  );

   BroadcastTelegramMsg(sMsg);
}

// ========================================================================================= Helper functions

// determines if nNumber is in array arr
bool NumberInArray(const int &arr[], const int nNumber)
{
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if (arr[i] == nNumber) return true;
   }
   
   return false;
}

// populates array arr with open orders
void FillArrayWithOpenOrders(int &arr[])
{
   const int DEFAULT_VALUE = -1;
   
   ZeroMemory(arr);
   ArrayResize(arr, OrdersTotal());
   
   for(int i = 0; i < ArraySize(arr); i++)
   {
      // try to select an open order based on index
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderCloseTime() != 0)
         {
            PrintFormat("Closed order trying to sneak into open order array, skipping...");
            continue;
         }
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

int CalculatePipDifference()
{

   double dDigits = CalculateNormalizedDigits();
   if (OrderType() == OP_BUY)
   {
      return (int)((OrderClosePrice() - OrderOpenPrice()) / dDigits);
   }
   
   if (OrderType() == OP_SELL)
   {
      return (int)((OrderOpenPrice() - OrderClosePrice()) / dDigits);
   }
   
   return 0; // other type of order - not handled rn
}

// Function to calculate the decimal digits
// Digits is a native variable in MetaTrader which is assigned as a value the number of digits after the point
double CalculateNormalizedDigits()
{
   // If there are 3 or less digits (JPY for example) then return 0.01 which is the pip value
   if(Digits <= 3)
   {
      return 0.01;
   }
   // If there are 4 or more digits then return 0.0001 which is the pip value
   else if(Digits >= 4)
   {
      return 0.0001;
   }
   // In all other cases (there shouldn't be any) return 0
   else return 0;
}
