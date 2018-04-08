#include <sourcemod>
#include <cstrike>
#include <sdktools>

#pragma semicolon 1

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[ZR] Ammo",
	author = "shavit",
	description = "idk",
	version = "1.0",
	url = "yourgame.co.il"
};

public void OnPluginStart()
{
	
}

public Action OnPlayerRunCmd(int client)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) != CS_TEAM_CT)
	{
		return Plugin_Continue;
	}
	
	int iRifle = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	
	if(iRifle != -1)
	{
		SetEntProp(iRifle, Prop_Send, "m_iPrimaryReserveAmmoCount", 200);
	}
	
	int iPistol = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	
	if(iPistol != -1)
	{
		SetEntProp(iPistol, Prop_Send, "m_iPrimaryReserveAmmoCount", 200);
	}
	
	return Plugin_Continue;
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}
