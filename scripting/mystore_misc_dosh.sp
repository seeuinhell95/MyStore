//https://forums.alliedmods.net/showthread.php?p=2558324

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <mystore>

#include <colors>
#include <autoexecconfig>

#pragma semicolon 1
#pragma newdecls required

#define SOUND_MONEY 

#define MAX_PICKUP_DISTANCE 50.0

ConVar gc_bEnable;

char g_sChatPrefix[128];
char g_sCreditsName[64];

ConVar gc_iAmount;
ConVar gc_iMax;
ConVar gc_fRemoveTime;
ConVar gc_iRemoveType;

int g_iCount;

public void OnPluginStart()
{
	LoadTranslations("mystore.phrases");

	RegConsoleCmd("sm_dosh", CMD_DropMoney);

	HookEvent("round_start", Event_RoundStart);

	AutoExecConfig_SetFile("dosh", "MyStore");
	AutoExecConfig_SetCreateFile(true);

	gc_iAmount = AutoExecConfig_CreateConVar("mystore_dosh_amount", "100", "The amount of credits for one dosh.",  _, true, 1.0);
	gc_iMax = AutoExecConfig_CreateConVar("mystore_dosh_max", "100", "Max number of money on the ground. 0 - Disable.",  _, true, 0.0);
	gc_fRemoveTime = AutoExecConfig_CreateConVar("mystore_dosh_remove_time", "60.0", "Seconds until remove a dropped item. 0.0 = on round", _, true, 0.0);
	gc_iRemoveType = AutoExecConfig_CreateConVar("mystore_dosh_remove_type", "1", "0 - delete / 1 - give back to owner", _, true, 0.0, true, 1.0);

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

}

public void MyStore_OnConfigExecuted(ConVar enable, char[] name, char[] prefix, char[] credits)
{
	gc_bEnable = enable;
	strcopy(g_sChatPrefix, sizeof(g_sChatPrefix), prefix);
	strcopy(g_sCreditsName, sizeof(g_sCreditsName), credits);
}

public void OnMapStart()
{
	PrecacheModel("models/props/cs_assault/money.mdl", true);
	PrecacheSound("ui/item_paper_pickup.wav", true);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_iCount = 0;
}

public Action CMD_DropMoney(int client, int args)
{
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

	if (!IsPlayerAlive(client))
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "Must be Alive");
		return Plugin_Handled;
	}

	if (!MyStore_HasClientAccess(client))
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "You dont have permission");
		return Plugin_Handled;
	}

	int account = MyStore_GetClientCredits(client);
	if (account <= 0)
	{
		CReplyToCommand(client, "%s%t", g_sChatPrefix, "Not enough Credits");
		return Plugin_Handled;
	}

	if (g_iCount >= gc_iMax.IntValue && gc_iMax.IntValue != 0)
	{
		CReplyToCommand(client, "%s", "Too many money on the ground, you can't drop more at this time!");
		return Plugin_Handled;
	}

	char sBuffer[16];
	int value = gc_iAmount.IntValue;

	if (args > 0)
	{
		GetCmdArg(1, sBuffer, 16);
		value = StringToInt(sBuffer);
	}

	if (account < value)
	{
		value = account;
	}

	float eye_pos[3], eye_angles[3];

	GetClientEyePosition(client, eye_pos);
	GetClientEyeAngles(client, eye_angles);

	Handle trace = TR_TraceRayFilterEx(eye_pos, eye_angles, MASK_SOLID, RayType_Infinite, Filter_ExcludeStarter, client);
	if (!TR_DidHit(trace))
		return Plugin_Handled;

	int entity = CreateEntityByName("prop_physics_override");
	if (!IsValidEntity(entity))
		return Plugin_Handled;

	DispatchKeyValue(entity, "model", "models/props/cs_assault/money.mdl");
	DispatchKeyValue(entity, "rendercolor", "150 255 150");
	DispatchKeyValue(entity, "spawnflags", "4358");
	DispatchSpawn(entity);
	

	Format(sBuffer, sizeof(sBuffer), "%i", value);
	SetEntPropString(entity, Prop_Data, "m_iName", sBuffer);
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
	SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 2.0);

	float end_pos[3];
	TR_GetEndPosition(end_pos, trace);

	SubtractVectors(end_pos, eye_pos, end_pos);
	NormalizeVector(end_pos, end_pos);
	ScaleVector(end_pos, GetRandomFloat(280.0, 320.0));

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
	AddVectors(end_pos, velocity, velocity);
	velocity[2] = velocity[2] + 100.0;

	eye_pos[2] = eye_pos[2] - 6.0;
	eye_angles[0] = eye_angles[2] = GetRandomFloat(-20.0, 20.0);
	eye_angles[1] = eye_angles[1] + GetRandomFloat(70.0, 110.0);

	TeleportEntity(entity, eye_pos, eye_angles, velocity);
	EmitSoundToAll("ui/item_paper_pickup.wav", entity);

	SDKHook(entity, SDKHook_Use, OnUse);
	CreateTimer(0.5, Timer_Money, EntIndexToEntRef(entity));

	if (gc_fRemoveTime.FloatValue > 0.0)
	{
		CreateTimer(gc_fRemoveTime.FloatValue, Timer_Remove, EntIndexToEntRef(entity));
	}

	MyStore_SetClientCredits(client, account - value, "dosh");

	g_iCount ++;

	PrintToChat(client, "%s %i", "You dropped", value);
	return Plugin_Handled;
}

public Action Timer_Money(Handle timer, int reference)
{
	int entity = EntRefToEntIndex(reference);
	if ((entity != INVALID_ENT_REFERENCE) && IsValidEntity(entity))
	{
		float money_pos[3], client_pos[3];

		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", money_pos);
		for(int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && IsPlayerAlive(client))
			{
				GetClientAbsOrigin(client, client_pos);
				client_pos[2] = client_pos[2] +  32.0;
				if (GetVectorDistance(client_pos, money_pos) <= MAX_PICKUP_DISTANCE)
				{
					PickUpMoney(client, entity);
				}
			}
		}

		CreateTimer(0.2, Timer_Money, EntIndexToEntRef(entity));
	}
}

public Action Timer_Remove(Handle timer, int reference)
{
	int entity = EntRefToEntIndex(reference);
	if ((entity != INVALID_ENT_REFERENCE) && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
		g_iCount--;

		int dropper = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		char buffer[8];
		GetEntPropString(entity, Prop_Data, "m_iName", buffer, sizeof(buffer));

		int value = StringToInt(buffer);
		switch(gc_iRemoveType.IntValue)
		{
			case 0: CPrintToChat(dropper, "%s%t", g_sChatPrefix, "No pick up - removed");
			case 1:
			{
				MyStore_SetClientCredits(dropper, MyStore_GetClientCredits(dropper) + value, "dosh pickup");
				CPrintToChat(dropper, "%s%t", g_sChatPrefix, "No pick up - back to you");
			}
		}
	}
}

public Action OnUse(int entity, int pusher)
{
	if (IsClientInGame(pusher) && IsPlayerAlive(pusher))
	{
		PickUpMoney(pusher, entity);
	}
}

void PickUpMoney(int client, int entity)
{
	char buffer[8];
	GetEntPropString(entity, Prop_Data, "m_iName", buffer, sizeof(buffer));

	int value = StringToInt(buffer);
	MyStore_SetClientCredits(client, MyStore_GetClientCredits(client) - value, "dosh pickup");

	EmitSoundToAll("ui/item_paper_pickup.wav", entity);
	AcceptEntityInput(entity, "Kill");

	g_iCount--;

	PrintToChat(client, "%s %i", "You collected", value);
}

public bool Filter_ExcludeStarter(int entity, int contentsMask, int data)
{
	return (data != entity);
}