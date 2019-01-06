#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include <mystore>

#include <colors>

#include <autoexecconfig>

ConVar gc_bEnable;

ConVar gc_iMin;
ConVar gc_iMax;
ConVar gc_fAutoStop;
ConVar gc_fSpeed;
ConVar gc_bAlive;

char g_sCreditsName[64];
char g_sChatPrefix[128];

char g_sMenuItem[64];
char g_sMenuExit[64];

Handle g_hTimerRun[MAXPLAYERS+1] = {null, ...};
Handle g_hTimerStopFlip[MAXPLAYERS+1] = {null, ...};

bool g_bFlipping[MAXPLAYERS+1] = {false, ...};
bool g_bHead[MAXPLAYERS+1] = {false, ...};

int g_iBet[MAXPLAYERS+1] = {-1, ...};
int g_iPosition[MAXPLAYERS+1] = {-1, ...};

public void OnPluginStart()
{
	LoadTranslations("mystore.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_coinflip", Command_CoinFlip, "Open the CoinFlip casino game");

	AutoExecConfig_SetFile("gamble", "MyStore");
	AutoExecConfig_SetCreateFile(true);

	gc_fSpeed = AutoExecConfig_CreateConVar("mystore_coinflip_speed", "0.1", "Speed the wheel spin", _, true, 0.1, true, 0.80);
	gc_fAutoStop = AutoExecConfig_CreateConVar("mystore_coinflip_stop", "10.0", "Seconds a roll should auto stop", _, true, 0.0);
	gc_bAlive = AutoExecConfig_CreateConVar("mystore_coinflip_alive", "1", "0 - Only dead player can start a game. 1 - Allow alive player to start a game.", _, true, 0.0);
	gc_iMin = AutoExecConfig_CreateConVar("mystore_coinflip_min", "20", "Minium amount of credits to spend", _, true, 1.0);
	gc_iMax = AutoExecConfig_CreateConVar("mystore_coinflip_max", "2000", "Maximum amount of credits to spend", _, true, 2.0);

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

	MyStore_RegisterHandler("coinflip", _, _, _, CoinFlip_Menu, _, false, true);
}

public void MyStore_OnConfigExecuted(ConVar enable, char[] name, char[] prefix, char[] credits)
{
	gc_bEnable = enable;
	strcopy(g_sCreditsName, sizeof(g_sCreditsName), credits);
	strcopy(g_sChatPrefix, sizeof(g_sChatPrefix), prefix);

	ReadCoreCFG();
}

public void OnClientAuthorized(int client, const char[] auth)
{
	// Reset all player variables
	g_iPosition[client] = -1;
	g_bFlipping[client] = false;
	g_iBet[client] = 0;
}

public void OnClientDisconnect(int client)
{
	// Stop and close open timer
	delete g_hTimerRun[client];
	delete g_hTimerStopFlip[client];
}

public void CoinFlip_Menu(int client, int itemid)
{
	Panel_PreCoinFlip(client);
}

public Action Command_CoinFlip(int client, int args)
{
	// Command comes from console
	if (!client)
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "Command is in-game only");

		return Plugin_Handled;
	}

	if (!gc_bEnable.BoolValue)
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "Store Disabled");

		return Plugin_Handled;
	}

	if (!MyStore_HasClientAccess(client))
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "You dont have permission");

		return Plugin_Handled;
	}

	if (args < 1 || args > 2)
	{
		Panel_PreCoinFlip(client);
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "Type in chat !coinflip");

		return Plugin_Handled;
	}

	char sBuffer[32];
	GetCmdArg(1, sBuffer, 32);
	int iBet;
	int iCredits = MyStore_GetClientCredits(client);

	if (IsCharNumeric(sBuffer[0]))
	{
		iBet = StringToInt(sBuffer);
	}
	else if (StrEqual(sBuffer,"all"))
	{
		iBet = iCredits;
	}
	else if (strcmp(sBuffer,"half"))
	{
		iBet = RoundFloat(iCredits / 2.0);
	}
	else if (StrEqual(sBuffer,"third"))
	{
		iBet = RoundFloat(iCredits / 3.0);
	}
	else if (strcmp(sBuffer,"quater"))
	{
		iBet = RoundFloat(iCredits / 4.0);
	}

	if (iBet < gc_iMin.IntValue)
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "You have to spend at least x credits.", gc_iMin.IntValue, g_sCreditsName);

		return Plugin_Handled;
	}
	else if (iBet > gc_iMax.IntValue)
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "You can't spend that much credits", gc_iMax.IntValue, g_sCreditsName);

		return Plugin_Handled;
	}

	if (iBet > iCredits)
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "Not enough Credits");

		return Plugin_Handled;
	}

	g_bFlipping[client] = false;

	g_iBet[client] = iBet;

	if (args == 1)
	{
		Panel_ChooseSide(client);
	}
	else if (args == 2)
	{
		GetCmdArg(2, sBuffer, 32);

		if (StrEqual(sBuffer, "h") || StrEqual(sBuffer, "head"))
		{
			g_bHead[client] = true;
		}
		else if (StrEqual(sBuffer, "t") || StrEqual(sBuffer, "tail"))
		{
			g_bHead[client] = false;
		}
		else
		{
			CReplyToCommand(client, "%s%t", g_sChatPrefix, "Type in chat !coinflip");

			return Plugin_Handled;
		}

		MyStore_SetClientCredits(client, MyStore_GetClientCredits(client) - g_iBet[client], "Bet CoinFlip");
		Start_CoinFlip(client);
	}

	return Plugin_Handled;
}

void Panel_PreCoinFlip(int client)
{
	// reset coinflip
	g_iPosition[client] = GetRandomInt(1,6);
	g_bFlipping[client] = false;

	if (g_iBet[client] == -1)
	{
		g_iBet[client] = gc_iMin.IntValue;
	}

	Panel_CoinFlip(client);
}

// Open the start coinflip panel
void Panel_CoinFlip(int client)
{
	char sBuffer[128];
	int iCredits = MyStore_GetClientCredits(client);
	Panel panel = new Panel();

	Format(sBuffer, sizeof(sBuffer), "%t\n%t", "coinflip", "Title Credits", g_sCreditsName, iCredits);
	panel.SetTitle(sBuffer);

	PanelInject_CoinFlip(panel, client);
	panel.DrawText(" ");

	if (!gc_bAlive.BoolValue && IsPlayerAlive(client))
	{
		Format(sBuffer, sizeof(sBuffer), "    \n    %t", "Must be dead");
		panel.DrawText(sBuffer);
	}
	else
	{
		Format(sBuffer, sizeof(sBuffer), "    %t\n    %t", "Type in chat !coinflip", "or use buttons below");
		panel.DrawText(sBuffer);
	}
	panel.DrawText(" ");

	panel.CurrentKey = 3;
	Format(sBuffer, sizeof(sBuffer), "%t", "Bet Minium", gc_iMin.IntValue);
	panel.DrawItem(sBuffer, iCredits < gc_iMin.IntValue || !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	panel.CurrentKey = 4;
	Format(sBuffer, sizeof(sBuffer), "%t", "Bet Maximum", iCredits > gc_iMax.IntValue ? gc_iMax.IntValue : iCredits);
	panel.DrawItem(sBuffer, iCredits < gc_iMin.IntValue || !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	panel.CurrentKey = 5;
	Format(sBuffer, sizeof(sBuffer), "%t", "Bet Random", gc_iMin.IntValue, iCredits > gc_iMax.IntValue ? gc_iMax.IntValue : iCredits);
	panel.DrawItem(sBuffer, iCredits < gc_iMin.IntValue || !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	panel.CurrentKey = 6;
	//Draw item rerun when already have bet - Panel line #14 - Panel item #4
	Format(sBuffer, sizeof(sBuffer), "%t", "Rerun x Credits", g_iBet[client], g_sCreditsName);
	panel.DrawItem(sBuffer, g_iBet[client] > iCredits || g_iBet[client] == 0 || !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_SPACER : ITEMDRAW_DEFAULT);

	panel.DrawText(" ");
	panel.CurrentKey = 7;
	Format(sBuffer, sizeof(sBuffer), "%t", "Back");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);
	panel.CurrentKey = 8;
	Format(sBuffer, sizeof(sBuffer), "%t", "Game Info");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);
	panel.CurrentKey = 9;
	Format(sBuffer, sizeof(sBuffer), "%t", "Exit");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);

	panel.Send(client, Handler_CoinFlip, MENU_TIME_FOREVER);

	delete panel;
}

public int Handler_CoinFlip(Menu panel, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch(itemNum)
		{
			case 3, 4, 5:
			{
				// Decline when player come back to life
				int credits = MyStore_GetClientCredits(client);
				if (!gc_bAlive.BoolValue && IsPlayerAlive(client))
				{
					Panel_CoinFlip(client);

					CPrintToChat(client, "%s%t", g_sChatPrefix, "Must be dead");

					FakeClientCommand(client, "play sound/%s", g_sMenuExit);
				}
				else
				{
					switch(itemNum)
					{
						case 3: g_iBet[client] = gc_iMin.IntValue;
						case 4: g_iBet[client] = credits > gc_iMax.IntValue ? gc_iMax.IntValue : credits;
						case 5: g_iBet[client] = GetRandomInt(gc_iMin.IntValue, credits > gc_iMax.IntValue ? gc_iMax.IntValue : credits);
					}

					Panel_ChooseSide(client);

					FakeClientCommand(client, "play sound/%s", g_sMenuItem);
				}
			}
			case 6:
			{
				// Decline when player come back to life
				if (!gc_bAlive.BoolValue && IsPlayerAlive(client))
				{
					Panel_CoinFlip(client);
					CPrintToChat(client, "%s%t", g_sChatPrefix, "Must be dead");

					FakeClientCommand(client, "play sound/%s", g_sMenuExit);
				}
				// show place color panel
				else
				{
					Panel_ChooseSide(client);
					FakeClientCommand(client, "play sound/%s", g_sMenuItem);
				}
			}
			case 7:
			{
				FakeClientCommand(client, "play sound/%s", g_sMenuExit);
				MyStore_SetClientPreviousMenu(client, MENU_PARENT);
				MyStore_DisplayPreviousMenu(client);
			}
			case 8:
			{
				Panel_GameInfo(client);
				FakeClientCommand(client, "play sound/%s", g_sMenuItem);
			}
			case 9: FakeClientCommand(client, "play sound/%s", g_sMenuExit);
		}
	}

	delete panel;
}

// Open the choose color panel
void Panel_ChooseSide(int client)
{
	char sBuffer[128];
	int iCredits = MyStore_GetClientCredits(client);
	Panel panel = new Panel();

	Format(sBuffer, sizeof(sBuffer), "%t\n%t", "coinflip", "Title Credits", g_sCreditsName, iCredits);
	panel.SetTitle(sBuffer);

	// Show the coinflip - Panel line #5-9
	PanelInject_CoinFlip(panel, client);	
	panel.DrawText(" ");
	if (!gc_bAlive.BoolValue && IsPlayerAlive(client))
	{
		Format(sBuffer, sizeof(sBuffer), "    \n    %t", "Must be dead");
		panel.DrawText(sBuffer);
	}
	else
	{
		Format(sBuffer, sizeof(sBuffer), "    %t\n    %t", "Type in chat !coinflip", "or use buttons below");
		panel.DrawText(sBuffer);
	}
	panel.DrawText(" ");

	panel.CurrentKey = 3;
	Format(sBuffer, sizeof(sBuffer), "%t '████' - %t", "Bet on", "Head");
	panel.DrawItem(sBuffer, !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_SPACER : ITEMDRAW_DEFAULT);

	panel.CurrentKey = 4;
	Format(sBuffer, sizeof(sBuffer), "%t '▓▓▓▓' - %t", "Bet on", "Tail");
	panel.DrawItem(sBuffer, !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_SPACER : ITEMDRAW_DEFAULT);

	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.CurrentKey = 7;
	Format(sBuffer, sizeof(sBuffer), "%t", "Back");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);
	panel.CurrentKey = 8;
	Format(sBuffer, sizeof(sBuffer), "%t", "Game Info");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);
	panel.CurrentKey = 9;
	Format(sBuffer, sizeof(sBuffer), "%t", "Exit");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);

	panel.Send(client, Handler_PlaceColor, MENU_TIME_FOREVER);

	delete panel;
}

public int Handler_PlaceColor(Menu panel, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch(itemNum)
		{
			case 3, 4:
			{
				// Decline when player come back to life
				if (!gc_bAlive.BoolValue && IsPlayerAlive(client))
				{
					Panel_CoinFlip(client);

					FakeClientCommand(client, "play sound/%s", g_sMenuExit);

					CPrintToChat(client, "%s%t", g_sChatPrefix, "Must be dead");
				}
				// Remove Credits & start the game
				else
				{
					int iCredits = MyStore_GetClientCredits(client);
					if (iCredits >= g_iBet[client])
					{
						switch(itemNum)
						{
							case 3: g_bHead[client] = true;
							case 4: g_bHead[client] = false;
						}

						MyStore_SetClientCredits(client, iCredits - g_iBet[client], "Bet CoinFlip");
						Start_CoinFlip(client);
					}
					// when player has yet had not enough Credits (double check)
					else
					{
						FakeClientCommand(client, "play sound/%s", g_sMenuExit);
						Panel_CoinFlip(client);

						CPrintToChat(client, "%s%t", g_sChatPrefix, "Not enough Credits", g_sCreditsName);
					}
				}
			}
			case 7:
			{
				Panel_CoinFlip(client);
				FakeClientCommand(client, "play sound/%s", g_sMenuExit);
			}
			case 8:
			{
				Panel_GameInfo(client);
				FakeClientCommand(client, "play sound/%s", g_sMenuItem);
			}
			case 9: FakeClientCommand(client, "play sound/%s", g_sMenuExit);
		}
	}

	delete panel;
}

void Start_CoinFlip(int client)
{
	g_bFlipping[client] = true;
	MyStore_SetClientRecurringMenu(client, true);

	// end possible still running timers
	delete g_hTimerStopFlip[client];
	delete g_hTimerRun[client];

	//play a start sound
	FakeClientCommand(client, "play sound/%s", g_sMenuItem);

	g_hTimerRun[client] = CreateTimer(gc_fSpeed.FloatValue, Timer_Run, GetClientUserId(client), TIMER_REPEAT); // run speed for all rolls
	TriggerTimer(g_hTimerRun[client]);

	g_hTimerStopFlip[client] = CreateTimer(GetAutoStopTime(), Timer_StopCoinFlip, GetClientUserId(client)); // stop first roll
}

void Panel_RunAndWin(int client)
{
	char sBuffer[128];
	int iCredits = MyStore_GetClientCredits(client);
	Panel panel = new Panel();

	Format(sBuffer, sizeof(sBuffer), "%t\n%t", "coinflip", "Title Credits", g_sCreditsName, iCredits);
	panel.SetTitle(sBuffer);

	// When coinflip is running step postion by one
	if (g_bFlipping[client])
	{
		g_iPosition[client]++;
		if (g_iPosition[client] > 12)
		{
			g_iPosition[client] = 1;
		}
	}

	// Show the coinflip - Panel line #5-9
	PanelInject_CoinFlip(panel, client);
	panel.DrawText(" ");
	// When coinflip is still running
	if (g_bFlipping[client])
	{
		// Draw the placed bet
		panel.DrawText(" ");
		Format(sBuffer, sizeof(sBuffer), "    %t", "Your bet", g_iBet[client], g_sCreditsName);
		panel.DrawText(sBuffer);

		// Draw Spacer item - Panel line #12 - Panel item #3
		panel.DrawText(" ");

		// Draw the placed color

		if (g_bHead[client])
		{
			Format(sBuffer, sizeof(sBuffer), "    %t '████' - %t", "Bet on", "Head");
		}
		else
		{
			Format(sBuffer, sizeof(sBuffer), "    %t '▓▓▓▓' - %t", "Bet on", "Tail");
		}

		panel.DrawText(sBuffer);
		panel.DrawText(" ");
		panel.DrawText(" ");
	}
	// When coinflip has stopped
	else
	{
		if (g_iPosition[client] != 3 && g_iPosition[client] != 9)
		{
			if (g_iPosition[client] < 7)
			{
				g_iPosition[client] = 3;
				g_bFlipping[client] = false;

				Panel_RunAndWin(client);

				delete panel;
				return;
			}
			else if (g_iPosition[client] > 6)
			{
				g_iPosition[client] = 9;
				g_bFlipping[client] = false;

				Panel_RunAndWin(client);

				delete panel;
				return;
			}
		}

		// If indicator is on choosen color -> WIN
		if ((g_bHead[client] && g_iPosition[client] < 7) || (!g_bHead[client] && g_iPosition[client] > 6))
		{
			// Build & draw won text - Panel line #12
			panel.DrawText(" ");
			Format(sBuffer, sizeof(sBuffer), "    You won with %s", g_bHead[client] ? "Head" : "Tail");
			panel.DrawText(sBuffer);

			// Draw Spacer Line - Panel line #13
			panel.DrawText(" ");

			// Build & draw text - Panel line #14
			Format(sBuffer, sizeof(sBuffer), "    %t", "You win x Credits", g_iBet[client] * 2, g_sCreditsName);
			panel.DrawText(sBuffer);

			panel.DrawText(" ");
			panel.DrawText(" ");
			// Process the won Credits & remaining notfiction
			ProcessWin(client, g_iBet[client], 2);
		}
		else
		{
			Panel_CoinFlip(client);

			delete panel;
			return;
		}
	}
	panel.CurrentKey = 6;
	//Draw item rerun when already have bet - Panel line #14 - Panel item #4
	Format(sBuffer, sizeof(sBuffer), "%t", "Rerun x Credits", g_iBet[client], g_sCreditsName);
	panel.DrawItem(sBuffer, g_iBet[client] > iCredits || g_bFlipping[client] || !gc_bAlive.BoolValue && IsPlayerAlive(client) ? ITEMDRAW_SPACER : ITEMDRAW_DEFAULT);
	panel.DrawText(" ");
	//Draw item info - Panel line #15 - Panel item #5
	panel.CurrentKey = 7;
	Format(sBuffer, sizeof(sBuffer), "%t", "Back");
	panel.DrawItem(sBuffer, g_bFlipping[client] ? ITEMDRAW_SPACER : ITEMDRAW_DEFAULT);
	panel.CurrentKey = 8;
	Format(sBuffer, sizeof(sBuffer), "%t", "Game Info");
	panel.DrawItem(sBuffer, g_bFlipping[client] ? ITEMDRAW_SPACER : ITEMDRAW_DEFAULT);
	panel.CurrentKey = 9;
	Format(sBuffer, sizeof(sBuffer), "%t", g_bFlipping[client] ? "Cancel" : "Exit");
	panel.DrawItem(sBuffer);

	panel.Send(client, Handler_RunWin, MENU_TIME_FOREVER);

	delete panel;
}

public int Handler_RunWin(Menu panel, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch(itemNum)
		{
			// Item 4 - Rerun bet
			case 6:
			{
				// Decline when player come back to life
				if (!gc_bAlive.BoolValue && IsPlayerAlive(client))
				{
					Panel_CoinFlip(client);
					CPrintToChat(client, "%s%t", g_sChatPrefix, "Must be dead");

					FakeClientCommand(client, "play sound/%s", g_sMenuExit);
				}
				// show place color panel
				else
				{
					Panel_ChooseSide(client);
					FakeClientCommand(client, "play sound/%s", g_sMenuItem);
				}
			}
			// Item 6 - go back to casino
			case 7:
			{
				Panel_CoinFlip(client);

				FakeClientCommand(client, "play sound/%s", g_sMenuExit);
			}
			case 8:
			{
				Panel_GameInfo(client);
				FakeClientCommand(client, "play sound/%s", g_sMenuItem);
			}
			// Item 9 - exit cancel
			case 9:
			{
				delete g_hTimerRun[client];
				delete g_hTimerStopFlip[client];

				MyStore_SetClientRecurringMenu(client, false);

				if (g_bFlipping[client])
				{
					Panel_CoinFlip(client);
				}

				g_bFlipping[client] = false;
				FakeClientCommand(client, "play sound/%s", g_sMenuExit);
			}
		}
	}

	delete panel;
}

// Inject the coin into panels
void PanelInject_CoinFlip(Panel panel, int client)
{
	panel.DrawText(" ");
	switch(g_iPosition[client])
	{
		case 1:
		{
			panel.DrawText("              ██");
			panel.DrawText("            ████");
			panel.DrawText("          ██████");
			panel.DrawText("            ████");
			panel.DrawText("              ██");
		}
		case 2:
		{
			panel.DrawText("            ████");
			panel.DrawText("          ██████");
			panel.DrawText("        ████████");
			panel.DrawText("          ██████");
			panel.DrawText("            ████");
		}
		case 3:
		{
			panel.DrawText("          ██████");
			panel.DrawText("        ██  ██  ██");
			panel.DrawText("      ███        ███");
			panel.DrawText("        ██  ██  ██");
			panel.DrawText("          ██████");
		}
		case 4:
		{
			panel.DrawText("            ████");
			panel.DrawText("          ██████");
			panel.DrawText("        ████████");
			panel.DrawText("          ██████");
			panel.DrawText("            ████");
		}
		case 5:
		{
			panel.DrawText("              ██");
			panel.DrawText("            ████");
			panel.DrawText("          ██████");
			panel.DrawText("            ████");
			panel.DrawText("              ██");
		}
		case 6:
		{
			panel.DrawText("              ██");
			panel.DrawText("              ██");
			panel.DrawText("              ██");
			panel.DrawText("              ██");
			panel.DrawText("              ██");
		}
		case 7:
		{
			panel.DrawText("              ▓▓");
			panel.DrawText("            ▓▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("            ▓▓▓▓");
			panel.DrawText("              ▓▓");
		}
		case 8:
		{
			panel.DrawText("            ▓▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("        ▓▓▓▓▓▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("            ▓▓▓▓");
		}
		case 9:
		{
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("        ▓▓        ▓▓");  // two spaces '  ' has size of one block '█'
			panel.DrawText("      ▓▓▓▓    ▓▓▓▓");
			panel.DrawText("        ▓▓▓    ▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
		}
		case 10:
		{
			panel.DrawText("            ▓▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("        ▓▓▓▓▓▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("            ▓▓▓▓");
		}
		case 11:
		{
			panel.DrawText("              ▓▓");
			panel.DrawText("            ▓▓▓▓");
			panel.DrawText("          ▓▓▓▓▓▓");
			panel.DrawText("            ▓▓▓▓");
			panel.DrawText("              ▓▓");
		}
		case 12:
		{
			panel.DrawText("              ▓▓");
			panel.DrawText("              ▓▓");
			panel.DrawText("              ▓▓");
			panel.DrawText("              ▓▓");
			panel.DrawText("              ▓▓");
		}
		default:
		{
			panel.DrawText("       ██████      |      ▓▓▓▓▓▓");
			panel.DrawText("     ██  ██  ██    |    ▓▓        ▓▓");
			panel.DrawText("   ███        ███  |  ▓▓▓▓    ▓▓▓▓");
			panel.DrawText("     ██  ██  ██    |    ▓▓▓    ▓▓▓");
			panel.DrawText("       ██████      |      ▓▓▓▓▓▓");
		}
	}
}

/******************************************************************************
                   functions
******************************************************************************/

//Randomize the stop time to the next number isn't predictable
float GetAutoStopTime()
{
	return GetRandomFloat(gc_fAutoStop.FloatValue/2 - 0.8, gc_fAutoStop.FloatValue/2 + 1.2);
}

void ProcessWin(int client, int bet, int multiply)
{
	int iProfit = bet * multiply;

	// Add profit to balance
	MyStore_SetClientCredits(client, MyStore_GetClientCredits(client) + iProfit, "CoinFlip Win");

	// Play sound and notify other player abot this win
	CPrintToChatAll("%s%t", g_sChatPrefix, "Player won x Credits", client, iProfit, g_sCreditsName, "coinflip");

	FakeClientCommand(client, "play sound/%s", g_sMenuItem);
}

/******************************************************************************
                   Panel
******************************************************************************/

//Show the games info panel
void Panel_GameInfo(int client)
{
	char sBuffer[255];
	int iCredits = MyStore_GetClientCredits(client);
	Panel panel = new Panel();

	//Build the panel title three lines high - Panel line #1-3
	Format(sBuffer, sizeof(sBuffer), "%t\n%t", "coinflip", "Title Credits", g_sCreditsName, iCredits);
	panel.SetTitle(sBuffer);

	// Draw Spacer Line - Panel line #4
	panel.DrawText(" ");
	panel.DrawText(" ");


	Format(sBuffer, sizeof(sBuffer), "    %s", "Bet on a Head/Tail");
	panel.DrawText(" ");
	panel.DrawText(" ");

	panel.DrawText(sBuffer);

	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.DrawText(" ");
	Format(sBuffer, sizeof(sBuffer), "    %s %t %i", "Win = ", "bet x", 2);
	panel.DrawText(sBuffer);

	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.DrawText(sBuffer);


	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.DrawText(" ");
	panel.CurrentKey = 7;
	Format(sBuffer, sizeof(sBuffer), "%t", "Back");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);
	panel.DrawText(" ");
	panel.CurrentKey = 9;
	Format(sBuffer, sizeof(sBuffer), "%t", "Exit");
	panel.DrawItem(sBuffer, ITEMDRAW_DEFAULT);

	panel.Send(client, Handler_RunWin, 14);

	delete panel;
}

/******************************************************************************
                   Timer
******************************************************************************/

// The game runs and roll the coinflip
public Action Timer_Run(Handle tmr, int userid)
{
	int client = GetClientOfUserId(userid);

	// When client disconnected end timer
	if (!IsClientInGame(client) || !IsClientConnected(client))
	{
		g_hTimerRun[client] = null;

		return Plugin_Handled;
	}

	// Rebuild panel with new position
	Panel_RunAndWin(client);

	// When coinflip stopped end timer
	if (!g_bFlipping[client])
	{
		g_hTimerRun[client] = null;

		MyStore_SetClientRecurringMenu(client, false);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// Timer to slow and stop coinflip
public Action Timer_StopCoinFlip(Handle tmr, int userid)
{
	int client = GetClientOfUserId(userid);

	// When client disconnected end timer
	if (!IsClientInGame(client) || !IsClientConnected(client))
	{
		g_hTimerStopFlip[client] = null;

		return Plugin_Handled;
	}

	// When coinflip stopped
	if (g_bFlipping[client])
	{
		g_bFlipping[client] = false;

		delete g_hTimerRun[client];

		MyStore_SetClientRecurringMenu(client, false);

		g_hTimerStopFlip[client] = null;

		// Show results
		Panel_RunAndWin(client);
	}
	else g_hTimerStopFlip[client] = null;

	return Plugin_Handled;
}

void ReadCoreCFG()
{
	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/core.cfg");

	Handle hParser = SMC_CreateParser();
	char error[128];
	int line = 0;
	int col = 0;

	SMC_SetReaders(hParser, INVALID_FUNCTION, Callback_CoreConfig, INVALID_FUNCTION);
	SMC_SetParseEnd(hParser, INVALID_FUNCTION);

	SMCError result = SMC_ParseFile(hParser, sFile, line, col);
	delete hParser;

	if (result == SMCError_Okay)
		return;

	SMC_GetErrorString(result, error, sizeof(error));
	MyStore_LogMessage(0, LOG_ERROR, "ReadCoreCFG: Error: %s on line %i, col %i of %s", error, line, col, sFile);
}

public SMCResult Callback_CoreConfig(Handle parser, char[] key, char[] value, bool key_quotes, bool value_quotes)
{
	if (StrEqual(key, "MenuItemSound", false))
	{
		strcopy(g_sMenuItem, sizeof(g_sMenuItem), value);
	}
	else if (StrEqual(key, "MenuExitBackSound", false))
	{
		strcopy(g_sMenuExit, sizeof(g_sMenuExit), value);
	}

	return SMCParse_Continue;
}