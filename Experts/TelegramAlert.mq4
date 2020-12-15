//+------------------------------------------------------------------+
//|                                          TelegramSignalAlert.mq4 |
//|                                              Olorunishola Falana |
//|                                         sholafalana777@gmail.com |
//+------------------------------------------------------------------+
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

extern bool alert_orderclosed       = true;
extern bool alert_Pendingfilled     = true;
extern bool alert_new_pending       = true;
extern bool alert_new_order         = true;
extern bool alert_pending_deleted   = true;
//-- end input parameters

//--- global variables
CCustomBot bot;
int macd_handle         = 0;
datetime time_signal    = 0;
bool bTBotConnected     = false;

bool AlertonTelegram    = true;
bool MobileNotification = false;
bool EmailNotification  = false;

int nTotalOrders        = OrdersTotal();
int totalpnd            = 0;
int totalopn            = 0;
//-- end global variables

int init()
{
   SetUp();
   return 0;
}

int deinit()
{
   return 0;
}

string TypeMnem(int type)
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

/*
   [pair] [buy/sell] :arrow_right::door:[entry price]⠀ 
   :dart:TP: [takeprofit price]
   :heavy_multiplication_x:SL: [stoploss price]
*/
string GetOrderOpenMsg(int nOrderType, string sPair, string sEntryPrice, string sTP, string sSL)
{
   return StringFormat(
      "[%s] [%s] :arrow_right::door: [%s]\n:dart:TP: [%s]\n:heavy_multiplication_x:SL: [%s]",
      TypeMnem(nOrderType),
      sPair,
      sEntryPrice,
      sTP,
      sSL
   );
}

// [pair] [buy/sell]- Hit TP +[pip#/count] pips:white_check_mark:
string GetTPHitMsg(int nOrderType, string sPair, string sClosePrice, int nPips)
{
   return StringFormat(
      "[%s] [%s] - Hit TP @ %s || [%d] pips :white_check_mark:",
      TypeMnem(nOrderType),
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
      TypeMnem(nOrderType),
      sPair,
      sClosePrice,
      nPips
   );
}

// [pair] [buy/sell]- Closed @ +[pip#/count] pips:white_check_mark:
// [pair] [buy/self]- Closed @ -[pip#/count] pips:x:
string GetOrderClosedMsg(int nOrderType, string sPair, string sClosePrice, int nPips)
{
   return StringFormat(
      "[%s] [%s] - Closed @ %s || [%d] pips %s",
      TypeMnem(nOrderType),
      sPair,
      sClosePrice,
      nPips,
      nPips > 0 ? ":white_check_mark:" : ":x:"
   );
}

void BroadcastTelegramMsg(string sMsg)
{
   Print("Sending telegram message..");
   bot.SendMessage(InpChannelName, sMsg);
}

int CalculatePipDifference(double dEntryPrice, double dClosePrice)
{
   return 0; // TODO
}

void ProcessOrderClose()
{
   if(!alert_orderclosed) return;
   
   Print("Closing order");
   // if(MobileNotification) SendNotification("TODO");
   // if(EmailNotification) SendMail("TODO");
   
   if(AlertonTelegram)
   {
      int pips = CalculatePipDifference(OrderOpenPrice(), OrderClosePrice());
      string sClosedMsg = GetOrderClosedMsg(OrderType(), OrderSymbol(), DoubleToString(OrderClosePrice()), pips);
      BroadcastTelegramMsg(sClosedMsg);
   }
}

void ProcessOrderOpen(int nOrderType, string sPair, string sEntryPrice, string sTP, string sSL)
{
   if(!alert_new_order) return;
   
   Print("Opening order");
   // if(MobileNotification) SendNotification("TODO");
   // if(EmailNotification) SendMail("TODO");
   
   if(AlertonTelegram)
   {
      string sOpenMsg = GetOrderOpenMsg(
            nOrderType,
            sPair, 
            sEntryPrice,
            sTP,
            sSL
         );
      BroadcastTelegramMsg(sOpenMsg);
   }
}

bool ConnectTelegramBot()
{
   bot.Token(InpToken);
   
   Print("Connecting to telegram bot..");
   
   if(StringLen(InpChannelName) <= 0)
   {
      Print("Error: Channel name is empty");
   }
   else if (StringGetChar(InpChannelName, 0) != '@')
   {
      Print("Error: Channel name needs to start with '@'.");
   }
   else
   {
      int result = bot.GetMe();
   
      if(result == 0)
      {
         Print("Connected to telegram bot. Bot name: ", bot.Name());
         return true;
      }
      else
      {
         Print("Unable to connect to telegram bot.");
         Print("Error: ", GetErrorDescription(result));
      }
   }
   
   return false; // error occurred
}

// begin global variables
int g_anPreviousOpenOrders[];
// end global variables

void SetUp()
{
   // quit if unable to connect to telegram
   if (!ConnectTelegramBot())
   {
      Print("Telegram error: exiting bot.");
      return;
   }
   
   // initalize open order array
   FillArrayWithOpenOrders(g_anPreviousOpenOrders, True);
   
   PrintFormat("Detected %d existing orders during startup.", ArraySize(g_anPreviousOpenOrders));
   
   int nRealTickRate;
   
   if (InpTickRate < 30) nRealTickRate = 30;
   else nRealTickRate = InpTickRate;
   
   PrintFormat("Tick-rate set to %d.", nRealTickRate);
   
   MainLoop(nRealTickRate);
}

// using custom loop instead of event/ontick because they seem unreliable
void MainLoop(int nTickRate)
{
   // TODO check loop execution duration doesnt exceed the tick rate -> warn user if it does
   while (True)
   {
      UpdateOrders();
      Sleep(nTickRate);
   }
}

void UpdateOrders()
{
   int anCurrentOpenOrders[];
   
   // resize array and populate it with current open orders
   FillArrayWithOpenOrders(anCurrentOpenOrders, True);
   
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
         
         // TODO broadcast order closed
         PrintFormat("Detected order %d closed.", nTicketNumber);
         
         // set to negative number so we can remove at the end of the update
         g_anPreviousOpenOrders[i] = -1;
      }
   }
   
   // detect and broadcast new open orders
   for(int i = 0; i < ArraySize(anCurrentOpenOrders); i++)
   {
      int nTicketNumber = anCurrentOpenOrders[i];
      
      // negative ticket number -> no order in given slot
      if (nTicketNumber < 0) continue;
      
      // iterate previous orders -> if cant find ticket number in previous orders it's a new order -> broadcast to telegram
      bool bNewOrder = NumberInArray(g_anPreviousOpenOrders, nTicketNumber);
      
      // send telegram message if new order
      if (bNewOrder)
      {
         // TODO broadcast telegram message
         PrintFormat("New order detected with ticket number %d.", nTicketNumber);
      }
   }
   
   ArrayResize(g_anPreviousOpenOrders, ArraySize(anCurrentOpenOrders));
   
   for(int i = 0; i < ArraySize(g_anPreviousOpenOrders); i++)
   {
      if (g_anPreviousOpenOrders[i] < 0) continue; // -> negative ticket number means it's closed
   }
   ArrayCopy(g_anPreviousOpenOrders, anCurrentOpenOrders, 0, 0, WHOLE_ARRAY);
}

// TODO move to tools file

bool NumberInArray(const int &arr[], const int nNumber)
{
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if (arr[i] == nNumber) return True;
   }
   
   return False;
}

void FillArrayWithOpenOrders(int &arr[], const bool bResizeArray = True)
{
   const int DEFAULT_VALUE = -1;
   
   if (bResizeArray)
   {
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

// TODO remove below

int start()
{
   return 0;
   time_signal = 0;
   bot.Token(InpToken);
   
   // will infinitely loop if fatal error occurs 
   while (!ConnectTelegramBot()) Sleep(10000);
   
   // string msg, msgbuy, msgsell, msgclos, msgfilled, msgdel, action1, action2, action3, msgpend, action4; // TODO undo this retarded shit
   
   int nCurrentOrderTotal = OrdersTotal();
   
   if (nCurrentOrderTotal < nTotalOrders)
   {
      // last closed order fixed
      int nClosedOrders = OrdersHistoryTotal();
      
      if(nClosedOrders > 0 && OrderSelect(nClosedOrders - 1, SELECT_BY_POS, MODE_HISTORY))
      {
         switch(OrderType())
         {
            case OP_BUY:
            case OP_SELL:
            {
               ProcessOrderClose();
               
               nTotalOrders = nCurrentOrderTotal;
               return 0;
            }
         }
      }
   }
   
   // send new order alert
   datetime tLastOpenTime = 0;  
   int tmp_pnd, temp_opn;
   
   int nOrderType;            // OrderType()
   string sOrderPair;         // OrderSymbol()
   string sOrderOpenPrice;    // OrderOpenPrice()
   string sOrderTP;           // OrderTakeProfit()
   string sOrderSL;           // OrderStopLoss()
   
   for(int i = (OrdersTotal() - 1); i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      
      datetime tOrderOpen = OrderOpenTime();
      
      if(tOrderOpen > tLastOpenTime)
      {
         // TODO figure out why we don't just call ProcessOrderOpen() here
         tLastOpenTime     = tOrderOpen;
         nOrderType        = OrderType();
         sOrderPair        = OrderSymbol();
         sOrderOpenPrice   = DoubleToString(OrderOpenPrice(), _Digits); // TODO determine the difference between _Digits and Digits
         sOrderTP          = DoubleToString(OrderTakeProfit(), Digits);
         sOrderSL          = DoubleToString(OrderStopLoss(), Digits);
      }
      
      switch(OrderType())
      {
         case OP_BUY:
         case OP_SELL:
         {
            temp_opn += 1;
            break;
         }
         default:
         {
            tmp_pnd += 1;
            break;
         }
      }
   }
   
   if (nCurrentOrderTotal > nTotalOrders)
   {
      Print(OrderTicket());
      ProcessOrderOpen(nOrderType, sOrderPair, sOrderOpenPrice, sOrderTP, sOrderSL);
   }
   
   if(tmp_pnd != totalpnd)
   {
      //pending filled or deleted
      if(tmp_pnd < totalpnd)
      {
         if(totalopn < temp_opn)
         {
            if(alert_Pendingfilled) // TODO
            {
               /*
               msg = "Pending Filled";
               action2 = "Pending Filled";
               
               msgfilled = StringFormat(
                  "Symbol: %s\nAction: %s",
                  OrderSymbol(),
                  action2
               );
               
               if(MobileNotification)
               {
                  SendNotification(msgfilled);
               }
               
               if(EmailNotification)
               {
                  SendMail("Order changes Notification", msgfilled);
               }
               
               if(AlertonTelegram)
               {
                  BroadcastTelegramMsg(msgfilled);
               }
               */
            }
         }
         else
         {
            /*
            msg = "Pending Deleted";
            action3 = "Pending Deleted ";
            
            msgdel = StringFormat(
               "Symbol: %s\nAction: %s",
               OrderSymbol(),
               action3
            );
            */
         }
      
         if(alert_pending_deleted)
         {
            /*
            if(MobileNotification)
            {
               SendNotification(msgdel);
            }                
            
            if(EmailNotification)
            {
               SendMail("Order changes Notification", msgdel);
            }
            
            if(AlertonTelegram)
            {
               BroadcastTelegramMsg(msgdel);
            }
            */
         }
      }
      
      // new pending placed
      if(tmp_pnd > totalpnd)
      { 
         if(alert_new_pending)
         {
            /*
            msg = "New Pending order";
            action4 = "New Pending order ";
            
            msgpend = StringFormat(
               "Symbol: %s\nAction: %s",
               OrderSymbol(),
               action4
            );
            
            if(MobileNotification)
            {
               SendNotification(msgpend);
            }
            
            if(EmailNotification)
            {
               SendMail("Order changes Notification", msgpend);
            }
            
            if(AlertonTelegram)
            {
               BroadcastTelegramMsg(msgpend);
               // bot.SendMessage(InpChannelName, msgpend);
            }
            */
         }
      }
   }

   totalpnd = tmp_pnd;
   totalopn = temp_opn;
   nTotalOrders = nCurrentOrderTotal;
   
   return 0;
}