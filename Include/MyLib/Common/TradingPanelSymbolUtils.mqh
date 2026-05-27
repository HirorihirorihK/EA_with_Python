#ifndef TRADING_PANEL_SYMBOL_UTILS_MQH
#define TRADING_PANEL_SYMBOL_UTILS_MQH

double TradingPanelAdjustPoint(const string symbol)
{
    // Keep the legacy XAUUSD/GOLD pip conversion for backtest reproducibility.
    if (symbol == "XAUUSD" || symbol == "GOLD")
        return 0.1;

    const int symbol_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    switch (symbol_digits)
    {
    case 2:
    case 3:
        return 0.01;
    case 4:
    case 5:
        return 0.0001;
    }

    PrintFormat("Unsupported symbol digits for pip conversion: symbol=%s digits=%d",
                symbol, symbol_digits);
    return 0.0;
}

ENUM_ORDER_TYPE_FILLING TradingPanelGetOrderFillingPolicy(const string symbol)
{
    const long filling_mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

    if ((filling_mode & SYMBOL_FILLING_IOC) != 0)
        return ORDER_FILLING_IOC;
    if ((filling_mode & SYMBOL_FILLING_FOK) != 0)
        return ORDER_FILLING_FOK;

    return ORDER_FILLING_RETURN;
}

#endif

