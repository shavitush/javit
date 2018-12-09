#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <cstrike>
#include <emitsoundany>

#undef REQUIRE_PLUGIN
#include <javit>

#pragma newdecls required
#pragma semicolon 1

enum
{
	VoteCT_None,
	VoteCT_Choosing,
	VoteCT_FastWrite,
	VoteCT_RandomNumber,
	VoteCT_Math
}

ConVar sv_alltalk = null;
ConVar mp_friendlyfire = null;
ConVar mp_teammates_are_enemies = null;

bool gB_TeamMuted[4];

char gS_BeepSound[PLATFORM_MAX_PATH];
bool gB_Medicated[MAXPLAYERS+1];

bool gB_VIP[MAXPLAYERS+1];
int gI_BeamSprite = -1;
int gI_HaloSprite = -1;

Handle gH_BanCookie = null;

Handle gH_HUD = null;
Handle gH_HUD_RandomNumber = null;
int gI_VoteCT = VoteCT_None;
float gF_VoteEnd = 0.0;
float gF_RoundStartTime = -15.0;
char gS_VoteCTAnswer[64];
char gS_VoteCTHUD[128];
ArrayList gA_RandomNumber = null;
char gS_LastWinnerID[32];

Database gH_SQLite = null;
int gI_ButtonID = -1;
int gI_ClientButton[MAXPLAYERS+1];
bool gB_CellsOpened = false;

char gS_Map[64];
char gS_ButtonOrigin[MAXPLAYERS+1][32];
char gS_MapButtonOrigin[32];

public Plugin myinfo =
{
	name = "Javit - Jailbreak Management",
	author = "shavit",
	description = "Jailbreak management for CS:S/CS:GO Jailbreak servers.",
	version = PLUGIN_VERSION,
	url = "https://github.com/shavitush"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("jbaddons");

	CreateNative("Javit_SetVIP", Native_SetVIP);

	return APLRes_Success;
}

public void OnPluginStart()
{
	EngineVersion version = GetEngineVersion();

	if(version != Engine_CSS && version != Engine_CSGO)
	{
		SetFailState("This plugin was not meant to be used for any other game besides CS:S and CS:GO.");
	}

	LoadTranslations("common.phrases");

	gH_HUD = CreateHudSynchronizer();
	gH_HUD_RandomNumber = CreateHudSynchronizer();

	sv_alltalk = FindConVar("sv_alltalk");
	mp_friendlyfire = FindConVar("mp_friendlyfire");
	mp_teammates_are_enemies = FindConVar("mp_teammates_are_enemies");

	mp_friendlyfire.Flags &= ~FCVAR_NOTIFY;

	if(mp_teammates_are_enemies != null)
	{
		mp_teammates_are_enemies.Flags &= ~FCVAR_NOTIFY;
	}

	gH_BanCookie = RegClientCookie("Banned_From_CT", "Tells if you are restricted from joining the CT team", CookieAccess_Protected);
	gA_RandomNumber = new ArrayList(2);

	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_death", Player_Death);
	HookEvent("player_hurt", Player_Hurt, EventHookMode_Pre);
	HookEvent("round_start", Round_Start);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	RegAdminCmd("sm_votect", Command_VoteCT, ADMFLAG_GENERIC, "Initiate a manual CT vote.");
	RegAdminCmd("sm_mutet", Command_MuteT, ADMFLAG_CHAT, "Mute all Ts.");
	RegAdminCmd("sm_tmute", Command_MuteT, ADMFLAG_CHAT, "Mute all Ts.");
	RegAdminCmd("sm_mutect", Command_MuteCT, ADMFLAG_CHAT, "Mute all CTs.");
	RegAdminCmd("sm_ctmute", Command_MuteCT, ADMFLAG_CHAT, "Mute all CTs.");
	RegAdminCmd("sm_muteall", Command_MuteAll, ADMFLAG_CHAT, "Mute everyone.");
	RegAdminCmd("sm_unmuteall", Command_UnmuteAll, ADMFLAG_CHAT, "Unmute everyone.");
	RegAdminCmd("sm_setbutton", Command_SetButton, ADMFLAG_CONVARS, "Set the cell open button.");

	RegConsoleCmd("sm_vip", Command_VIP, "Assign VIP status. Usage: sm_vip <target>");
	RegConsoleCmd("sm_open", Command_Open, "Assign VIP status. Usage: sm_vip <target>");
	RegConsoleCmd("sm_medic", Command_Medic, "Request assistance from the paramedics.");

	if(version == Engine_CSGO) // CS:S needs a very hacky method for this
	{
		RegConsoleCmd("sm_box", Command_Box, "It's boxing time!");
	}

	SQL_DBConnect();

	// TODO: sm_box
	// TODO: sm_givelr
	// TODO: sm_freekill sm_fk

	// TODO: sm_kickct sm_ctkick
	// TODO: sm_chooser sm_leader sm_warden
	// TODO: sm_choose sm_ctlist
	// TODO: restart round after successful votect - 60 sec godmode round
	// TODO: hook joingame and jointeam. joingame should be blocked, jointeam should respect ratios
}

public void OnMapStart()
{
	gI_ButtonID = -1;
	gS_MapButtonOrigin = "0 0 0";

	GetCurrentMap(gS_Map, 64);
	GetMapDisplayName(gS_Map, gS_Map, 64);

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT origin FROM maps WHERE map = '%s';", gS_Map);
	gH_SQLite.Query(SQL_GetButtonOrigin_Callback, sQuery);

	gF_RoundStartTime = -15.0;
	PrecacheSoundAny("ui/achievement_earned.wav", true);
	StopVoteCT("");

	if(GetEngineVersion() == Engine_CSS)
	{
		gI_BeamSprite = PrecacheModel("sprites/laser.vmt", true);
		gI_HaloSprite = PrecacheModel("sprites/halo01.vmt", true);
	}

	else
	{
		gI_BeamSprite = PrecacheModel("sprites/bomb_planted_ring.vmt", true);
		gI_HaloSprite = PrecacheModel("sprites/glow01.vmt", true);
	}

	Handle hConfig = LoadGameConfigFile("funcommands.games");

	if(hConfig == null)
	{
		SetFailState("Unable to load game config funcommands.games");

		return;
	}
	
	if(GameConfGetKeyValue(hConfig, "SoundBeep", gS_BeepSound, PLATFORM_MAX_PATH))
	{
		PrecacheSound(gS_BeepSound, true);
	}

	delete hConfig;
}

public void SQL_GetButtonOrigin_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("SQL error! Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		results.FetchString(0, gS_MapButtonOrigin, 32);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	gB_VIP[client] = false;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if(gI_VoteCT != VoteCT_None)
	{
		return Plugin_Handled;
	}

	if(mp_friendlyfire.BoolValue)
	{
		int team = GetClientTeam(attacker);

		if(team != CS_TEAM_T && team == GetClientTeam(victim))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	gB_VIP[client] = false;
	gB_Medicated[client] = false;
}

public void Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	// Clear unnecessary VIP statuses.
	int victim = GetClientOfUserId(event.GetInt("userid"));

	gB_VIP[victim] = false;

	int iVIPCount = 0;
	int iNonVIPs = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_T)
		{
			continue;
		}

		if(gB_VIP[i])
		{
			iVIPCount++;
		}

		else
		{
			iNonVIPs++;
		}
	}

	if(iNonVIPs <= 1 && iVIPCount > 0)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			gB_VIP[i] = false;
		}
	}
}

public void Player_Hurt(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if(!(1 <= attacker <= MaxClients))
	{
		return;
	}

	int damage = event.GetInt("dmg_health");

	if(GetEngineVersion() != Engine_CSGO)
	{
		PrintCenterText(attacker, "-%d HP", damage);

		return;
	}

	int entity = CreateEntityByName("point_worldtext"); 

	if(entity == -1)
	{
		return;
	}

	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", attacker);
	SDKHook(entity, SDKHook_SetTransmit, OnSetTransmit);

	char sDamage[8];
	IntToString(damage, sDamage, 8);
	DispatchKeyValue(entity, "message", sDamage);

	bool bKill = event.GetInt("health") <= 0;
	DispatchKeyValue(entity, "textsize", (bKill)? "16":"10");
	DispatchKeyValue(entity, "color", (bKill)? "255 0 0":"255 255 255");

	float pos[3];
	GetClientEyePosition(GetClientOfUserId(event.GetInt("userid")), pos);
	pos[0] += GetRandomFloat(-10.0, 10.0);
	pos[1] += GetRandomFloat(-10.0, 10.0);
	pos[2] += GetRandomFloat(4.0, 10.0); // above head

	float ang[3];
	GetClientEyeAngles(attacker, ang);
	
	TeleportEntity(entity, pos, ang, NULL_VECTOR);

	CreateTimer(0.8, Timer_KillEntity, EntIndexToEntRef(entity));
}

public Action Timer_KillEntity(Handle timer, any data)
{
	int entity = EntRefToEntIndex(data);

	if(data == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
	{
		return Plugin_Stop;
	}

	AcceptEntityInput(entity, "kill");

	return Plugin_Stop;
}

public Action OnSetTransmit(int entity, int client)
{
	int flags = GetEdictFlags(entity);

	if((flags & FL_EDICT_ALWAYS) > 0)
	{
		SetEdictFlags(entity, (flags & ~FL_EDICT_ALWAYS));
	}

	return (client == GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity"))? Plugin_Continue:Plugin_Handled;
} 

public void Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	gB_CellsOpened = false;
	gI_ButtonID = -1;
	gF_RoundStartTime = GetEngineTime();
	Javit_PrintToChatAll("\x03Terrorists\x01 are muted for the first \x0515 seconds\x01 of the round.");
	mp_friendlyfire.BoolValue = false;

	if(mp_teammates_are_enemies != null)
	{
		mp_teammates_are_enemies.BoolValue = false;
	}

	if(StrEqual(gS_MapButtonOrigin, "0 0 0"))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || !CheckCommandAccess(i, "sm_setbutton", ADMFLAG_CONVARS))
			{
				continue;
			}

			Javit_PrintToChat(i, "Cell button is not set! Use \x05!setbutton\x01 to set one.");
		}
	}
	
	else
	{
		if(gI_ButtonID != -1)
		{
			SDKUnhook(gI_ButtonID, SDKHook_UsePost, OnUsePost);
		}

		int entity = -1;

		while((entity = FindEntityByClassname(entity, "func_button")) != INVALID_ENT_REFERENCE)
		{
			float pos[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);

			char origin[32];
			FormatEx(origin, 32, "%f %f %f", pos[0], pos[1], pos[2]);

			if(StrEqual(origin, gS_MapButtonOrigin))
			{
				gI_ButtonID = entity;
				SDKHook(gI_ButtonID, SDKHook_UsePost, OnUsePost);

				break;
			}
		}
	}
}

public void OnUsePost(int entity, int activator, int caller, UseType type, float value)
{
	if(gB_CellsOpened)
	{
		return;
	}

	gB_CellsOpened = true;

	if(1 <= activator <= MaxClients)
	{
		Javit_PrintToChatAll("\x03%N\x01 has opened the cells.", activator);
	}
}

void SQL_DBConnect()
{
	delete gH_SQLite;

	KeyValues kv = new KeyValues("javit_jb");
	kv.SetString("driver", "sqlite");
	kv.SetString("database", "javit_jb");

	char sError[255];
	gH_SQLite = SQL_ConnectCustom(kv, sError, 255, true);
	delete kv;

	if(gH_SQLite == null)
	{
		SetFailState("Cannot connect to database. Error: %s", sError);
	}

	SQL_FastQuery(gH_SQLite, "CREATE TABLE IF NOT EXISTS `maps` (`map` VARCHAR(64) NOT NULL, `origin` VARCHAR(64) NOT NULL, PRIMARY KEY(`map`));");
}

bool OpenCells(int client = -1, bool force = false)
{
	if(gI_ButtonID == -1 || (!force && gB_CellsOpened))
	{
		return false;
	}

	AcceptEntityInput(gI_ButtonID, "Press", client, client);

	gB_CellsOpened = true;

	return true;
}

public Action Command_MuteT(int client, int args)
{
	gB_TeamMuted[CS_TEAM_T] = true;

	ShowActivity(client, "Muted all Terrorists.");

	return Plugin_Handled;
}

public Action Command_MuteCT(int client, int args)
{
	gB_TeamMuted[CS_TEAM_CT] = true;
	
	ShowActivity(client, "Muted all Counter-Terrorists.");

	return Plugin_Handled;
}

public Action Command_MuteAll(int client, int args)
{
	for(int i = CS_TEAM_NONE; i <= CS_TEAM_CT; i++)
	{
		gB_TeamMuted[i] = true;
	}
	
	ShowActivity(client, "Muted all players.");

	return Plugin_Handled;
}

public Action Command_UnmuteAll(int client, int args)
{
	for(int i = CS_TEAM_NONE; i <= CS_TEAM_CT; i++)
	{
		gB_TeamMuted[i] = false;
	}
	
	ShowActivity(client, "Unmuted all players.");

	return Plugin_Handled;
}

public Action Command_SetButton(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only used in-game.");

		return Plugin_Handled;
	}

	gI_ClientButton[client] = -1;
	gS_ButtonOrigin[client] = "0 0 0";

	return ShowSetButtonMenu(client);
}

Action ShowSetButtonMenu(int client)
{
	Menu menu = new Menu(MenuHandler_SetButton);
	menu.SetTitle("Cell button setter:");
	menu.AddItem("set", "Set button");
	menu.AddItem("apply", "Apply", (StrEqual(gS_ButtonOrigin[client], "0 0 0"))? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	menu.AddItem("reset", "Reset");

	menu.ExitButton = true;
	menu.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_SetButton(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "set"))
		{
			if(!IsPlayerAlive(param1))
			{
				Javit_PrintToChat(param1, "You have to be alive in order to select a button.");
				ShowSetButtonMenu(param1);

				return 0;
			}

			if(gI_ClientButton[param1] != -1)
			{
				SetEntityRenderFx(gI_ClientButton[param1], RENDERFX_NONE);
			}

			float pos[3];
			GetClientEyePosition(param1, pos);

			float angles[3];
			GetClientEyeAngles(param1, angles);

			TR_TraceRayFilter(pos, angles, MASK_SHOT, RayType_Infinite, TraceFilter_NoClients, param1);

			char classname[32];
			int entity = -1;

			if(TR_DidHit())
			{
				entity = TR_GetEntityIndex();

				if(entity != -1)
				{
					GetEntityClassname(entity, classname, 32);
				}
			}

			if(!StrEqual(classname, "func_button"))
			{
				Javit_PrintToChat(param1, "You have to aim on a button.");
				ShowSetButtonMenu(param1);

				return 0;
			}

			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
			FormatEx(gS_ButtonOrigin[param1], 32, "%f %f %f", pos[0], pos[1], pos[2]);
			gI_ClientButton[param1] = entity;

			SetEntityRenderFx(entity, RENDERFX_STROBE_FASTER);

			ShowSetButtonMenu(param1);
		}

		else if(StrEqual(sInfo, "apply"))
		{
			if(StrEqual(gS_ButtonOrigin[param1], "0 0 0"))
			{
				Javit_PrintToChat(param1, "You have to select a button first.");
				ShowSetButtonMenu(param1);

				return 0;
			}

			gI_ButtonID = gI_ClientButton[param1];
			gS_MapButtonOrigin = gS_ButtonOrigin[param1];

			SetEntityRenderFx(gI_ButtonID, RENDERFX_NONE);

			char sQuery[256];
			FormatEx(sQuery, 256, "REPLACE INTO maps (map, origin) VALUES ('%s', '%s');", gS_Map, gS_ButtonOrigin[param1]);
			gH_SQLite.Query(SQL_UpdateQuery_Callback, sQuery);

			Javit_PrintToChat(param1, "Applied cell button on \"%s\".", gS_Map);
			LogAction(-1, -1, "%L - Applied cell button on %s", param1, gS_Map);
		}

		else if(StrEqual(sInfo, "reset"))
		{
			gI_ButtonID = -1;
			gS_MapButtonOrigin = "0 0 0";

			char sQuery[256];
			FormatEx(sQuery, 256, "DELETE FROM maps WHERE map = '%s';", gS_Map);
			gH_SQLite.Query(SQL_UpdateQuery_Callback, sQuery);

			Javit_PrintToChat(param1, "Removed button from \"%s\".", gS_Map);
			LogAction(-1, -1, "%L - Removed cell button from %s", param1, gS_Map);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_UpdateQuery_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("SQL error (set button)! Reason: %s", error);

		return;
	}
}

public bool TraceFilter_NoClients(int entity, int contentsMask, any data)
{
	return entity != data;
}

public Action Command_Open(int client, int args)
{
	bool bAllowed = client == 0 || CheckCommandAccess(client, "javit_open", ADMFLAG_GENERIC) || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client));

	if(!bAllowed)
	{
		Javit_PrintToChat(client, "Your access level is not high enough for this command. Requirements: Alive CT or admin access.");

		return Plugin_Handled;
	}

	if(gI_ButtonID == -1)
	{
		Javit_PrintToChat(client, "A button is not set for this map.");

		return Plugin_Handled;
	}

	if(OpenCells(client))
	{
		Javit_PrintToChatAll("\x03%N\x01 has opened the cells.", client);
	}

	else
	{
		Javit_PrintToChat(client, "Cells could not be opened. Were they opened before?");
	}

	return Plugin_Handled;
}

public Action Command_Medic(int client, int args)
{
	if(!IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T || !(1 <= GetClientHealth(client) <= 99))
	{
		Javit_PrintToChat(client, "You may only use this command as an alive prisoner with less than 100 HP.");

		return Plugin_Handled;
	}

	if(gB_Medicated[client])
	{
		Javit_PrintToChat(client, "You may only use this command once per round.");

		return Plugin_Handled;
	}

	int health = GetClientHealth(client);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && (CheckCommandAccess(i, "javit_medic", ADMFLAG_SLAY) || (GetClientTeam(i) == CS_TEAM_CT && IsPlayerAlive(i))))
		{
			Javit_PrintToChat(i, "Player \x03%N\x01 has requested \x05medication\x01. HP: \x05%d", client, health);
			PlayBeepSound(i);
		}
	}

	gB_Medicated[client] = true;

	return Plugin_Handled;
}

bool CanBox(int client)
{
	bool bAllowed = client != 0 && (CheckCommandAccess(client, "javit_box", ADMFLAG_GENERIC) || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));

	if(!bAllowed)
	{
		Javit_PrintToChat(client, "Your access level is not high enough for this command. Requirements: Alive CT or admin access.");

		return false;
	}

	return true;
}

public Action Command_Box(int client, int args)
{
	return ShowBoxMenu(client);
}

Action ShowBoxMenu(int client)
{
	if(!CanBox(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Box);
	menu.SetTitle("Friendly boxing:");
	menu.AddItem("enable", "Enable", (mp_friendlyfire.BoolValue)? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	menu.AddItem("disable", "Disable", (mp_friendlyfire.BoolValue)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	menu.ExitButton = true;
	menu.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_Box(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!CanBox(param1))
		{
			return 0;
		}

		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "enable"))
		{
			// TODO: 5 sec warning in global hud - center of screen
			// TODO: don't allow *starting* box when the warning is shown to players

			if(mp_friendlyfire.BoolValue)
			{
				Javit_PrintToChat(param1, "Boxing is already enabled.");

				return 0;
			}

			SetBox(true);
			Javit_PrintToChatAll("\x03%N\x01 has \x05enabled\x01 prisoner boxing!", param1);
		}

		else if(StrEqual(sInfo, "disable"))
		{
			if(!mp_friendlyfire.BoolValue)
			{
				Javit_PrintToChat(param1, "Boxing is already disabled.");

				return 0;
			}

			SetBox(false);
			Javit_PrintToChatAll("\x03%N\x01 has \x05disabled\x01 prisoner boxing!", param1);
		}

		ShowBoxMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void SetBox(bool status)
{
	mp_friendlyfire.BoolValue = status;

	if(mp_teammates_are_enemies != null)
	{
		mp_teammates_are_enemies.BoolValue = status;
	}

	if(status)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				PlayBeepSound(i);
			}
		}
	}
}

void PlayBeepSound(int client)
{
	EngineVersion version = GetEngineVersion();

	if(version == Engine_CSS)
	{
		EmitSoundToClient(client, gS_BeepSound);
	}

	else
	{
		ClientCommand(client, "play */%s", gS_BeepSound);
	}
}

public Action Command_VIP(int client, int args)
{
	bool bCanVIP = client == 0 || CheckCommandAccess(client, "javit_vip", ADMFLAG_SLAY) || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client));

	if(!bCanVIP)
	{
		Javit_PrintToChat(client, "Your access level is not high enough for this command. Requirements: Alive CT or admin access.");

		return Plugin_Handled;
	}

	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_vip <target>");

		return Plugin_Handled;
	}

	char sArgs[MAX_TARGET_LENGTH];
	GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

	int iTarget = FindTarget(client, sArgs, false, false);

	if(iTarget == -1)
	{
		return Plugin_Handled;
	}

	if(GetTeamPlayerCount(CS_TEAM_T, true) <= 2)
	{
		ReplyToCommand(client, "You are not allowed to grant VIP access when only 2 or less Terrorists are alive.");

		return Plugin_Handled;
	}

	if(GetClientTeam(iTarget) != CS_TEAM_T)
	{
		ReplyToCommand(client, "Only Terrorists may be VIPs.");

		return Plugin_Handled;
	}

	gB_VIP[iTarget] = !gB_VIP[iTarget];

	Javit_PrintToChatAll("\x03%N\x01 is \x05%s\x01.", iTarget, (gB_VIP[iTarget])? "VIP":"not a VIP anymore");

	return Plugin_Handled;
}

int GetTeamPlayerCount(int team = -1, bool alive = false)
{
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		if((team == -1 || GetClientTeam(i) == team) && (!alive || IsPlayerAlive(i)))
		{
			count++;
		}
	}

	return count;
}

public Action Command_VoteCT(int client, int args)
{
	if(IsVoteInProgress())
	{
		ReplyToCommand(client, "A vote is already ongoing.");

		return Plugin_Handled;
	}

	if(gI_VoteCT != VoteCT_None)
	{
		StopVoteCT("Aborted current vote to start a new one.");
	}

	ShowActivity(client, "Started a manual CT vote.");

	if(client > 0)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || i == client || GetClientTeam(i) != CS_TEAM_CT)
			{
				continue;
			}

			CS_SwitchTeam(i, CS_TEAM_T);
			CS_RespawnPlayer(i);
		}

		CS_SwitchTeam(client, CS_TEAM_CT);
		CS_RespawnPlayer(client);
	}

	StartVoteCT();
	
	if(OpenCells(client, true))
	{
		Javit_PrintToChatAll("Cells have been opened.");
	}

	return Plugin_Handled;
}

void StopVoteCT(const char[] message, any ...)
{
	if(strlen(message) > 0) // not an empty parameter - print a message
	{
		char sFormatted[256];
		VFormat(sFormatted, 256, message, 2);

		Javit_PrintToChatAll("%s", sFormatted);
	}

	gS_VoteCTHUD = "";
	gI_VoteCT = VoteCT_None;
	gF_VoteEnd = 0.0;
}

void StartVoteCT()
{
	gI_VoteCT = VoteCT_Choosing;

	Menu menu = new Menu(VoteCT_Handler);
	menu.SetTitle("CT cycling vote:");
	menu.AddItem("fast", "Fast writer");
	menu.AddItem("random", "Random number");
	menu.AddItem("math", "Math");

	if((GetTeamScore(CS_TEAM_CT) + GetTeamScore(CS_TEAM_T) + 1) < 12 && GetTeamScore(CS_TEAM_CT) > 0)
	{
		menu.AddItem("extend", "Extend CT rounds to 12");
	}

	menu.DisplayVoteToAll(20);
}

public int VoteCT_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_VoteEnd)
	{
		gF_VoteEnd = GetEngineTime();

		char sInfo[32];
		menu.GetItem(param1, sInfo, 32);

		if(StrEqual(sInfo, "fast"))
		{
			gI_VoteCT = VoteCT_FastWrite;
			IntToString(GetRandomInt(10000000, 99999999), gS_VoteCTAnswer, 64);
			FormatEx(gS_VoteCTHUD, 128, "Be the first to type %s!", gS_VoteCTAnswer);
		}

		else if(StrEqual(sInfo, "random"))
		{
			gA_RandomNumber.Clear();
			gI_VoteCT = VoteCT_RandomNumber;
			IntToString(GetRandomInt(1, 350), gS_VoteCTAnswer, 64);
			gS_VoteCTHUD = "Submit a number from 1 to 350.";
		}

		else if(StrEqual(sInfo, "math"))
		{
			gI_VoteCT = VoteCT_Math;

			int iNumber1 = GetRandomInt(-2, 10);
			int iNumber2 = GetRandomInt(-2, 10);
			IntToString(iNumber1 * iNumber2, gS_VoteCTAnswer, 64);

			FormatEx(gS_VoteCTHUD, 128, "%d * %d = ?", iNumber1, iNumber2);
		}

		else
		{
			if(StrEqual(sInfo, "extend"))
			{
				Javit_PrintToChatAll("Voting is over. CT rounds have been extended to 12.");
			}

			StopVoteCT("");
		}
	}

	else if(action == MenuAction_VoteCancel)
	{
		StopVoteCT("Cycling vote aborted.");
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

public void OnGameFrame()
{
	int iTicks = GetGameTickCount();

	if(iTicks % 10 == 0)
	{
		Cron();
	}

	if(iTicks % 100 == 0)
	{
		BeaconVIPs();
	}
}

void Cron()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		PrintHUD(i);
		SetVoicePermissions(i);
	}
}

void BeaconVIPs()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!gB_VIP[i] || !IsClientInGame(i) || GetClientTeam(i) != CS_TEAM_T || !IsPlayerAlive(i))
		{
			continue;
		}

		Javit_BeaconEntity(i);
	}
}

void PrintHUD(int client)
{
	SetHudTextParams(-1.0, -0.7, 0.5, 255, 192, 203, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, gH_HUD, "%s", gS_VoteCTHUD);

	if(gI_VoteCT == VoteCT_RandomNumber)
	{
		SetHudTextParams(-1.0, -0.65, 0.5, 255, 220, 210, 255, 0, 0.0, 0.0, 0.0);

		float fTimeLeft = 25.0 - (GetEngineTime() - gF_VoteEnd);

		if(fTimeLeft >= 0.0)
		{
			ShowSyncHudText(client, gH_HUD_RandomNumber, "%.01f seconds left!", fTimeLeft);
		}
		
		else
		{
			ShowSyncHudText(client, gH_HUD_RandomNumber, "");

			if(gA_RandomNumber.Length == 0)
			{
				StopVoteCT("Time is up and no entries were submitted.");
			}

			else
			{
				DrawRandomNumberWinner();
			}
		}
	}
}

void SetVoicePermissions(int client)
{
	int iTeam = GetClientTeam(client);
	bool bAdmin = CheckCommandAccess(client, "voice_chat", ADMFLAG_CHAT);
	bool bAlive = IsPlayerAlive(client);
	bool bTMuted = (GetEngineTime() - gF_RoundStartTime) <= 15.0;
	bool bAlltalk = sv_alltalk.BoolValue;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		int iListenerTeam = GetClientTeam(i);
		ListenOverride iOverride = Listen_Yes;

		if((!bAdmin && (gB_TeamMuted[iTeam] || !bAlive || (iTeam != CS_TEAM_CT && bTMuted))) ||
			(!bAlltalk && iTeam != iListenerTeam))
		{
			iOverride = Listen_No;
		}

		SetListenOverride(i, client, iOverride);
	}
}

any Abs(any num)
{
	return (num < 0)? -num:num;
}

void DrawRandomNumberWinner()
{
	int iDistance = 350;
	int iWinner = 0;
	int iWinnerNumber = 0;
	int iAnswer = StringToInt(gS_VoteCTAnswer);

	int iLength = gA_RandomNumber.Length;

	for(int i = 0; i < iLength; i++)
	{
		int arr[2];
		gA_RandomNumber.GetArray(i, arr, 2);

		int client = GetClientFromSerial(arr[0]);

		if(client == 0)
		{
			continue;
		}

		int iRealDist = Abs(iAnswer - arr[1]);

		if(iRealDist < iDistance)
		{
			iDistance = iRealDist;
			iWinner = client;
			iWinnerNumber = arr[1];
		}
	}

	if(iWinner > 0)
	{
		Javit_PrintToChatAll("\x03%N\x01 won with the number \x05%d\x01. The random number was \x05%d\x01.", iWinner, iWinnerNumber, iAnswer);
		WinVoteCT(iWinner);
	}

	else
	{
		StopVoteCT("Winner is not present i9n the server.");
	}
}

void WinVoteCT(int client)
{
	EmitSoundToAllAny("ui/achievement_earned.wav");
	StopVoteCT("");

	Javit_PrintToChatAll("\x03%N\x01 is the new CT leader.", client);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || i == client || GetClientTeam(i) != CS_TEAM_CT)
		{
			continue;
		}

		CS_SwitchTeam(i, CS_TEAM_T);
		CS_RespawnPlayer(i);
	}

	CS_SwitchTeam(client, CS_TEAM_CT);
	CS_RespawnPlayer(client);

	GetClientAuthId(client, AuthId_Steam3, gS_LastWinnerID, 32);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(gI_VoteCT <= VoteCT_Choosing)
	{
		return Plugin_Continue;
	}

	if(IsFreeKiller(client))
	{
		Javit_PrintToChat(client, "You cannot write during votes as you're CT banned.");

		return Plugin_Handled;
	}

	char sAuthID[32];

	if(!GetClientAuthId(client, AuthId_Steam3, sAuthID, 32))
	{
		Javit_PrintToChat(client, "Could not authenticate your SteamID. Reconnect and try again.");

		return Plugin_Handled;
	}

	if(StrEqual(sAuthID, gS_LastWinnerID))
	{
		Javit_PrintToChat(client, "You have won the previous cycle vote, so you cannot participate in this one.");

		return Plugin_Handled;
	}

	if(gI_VoteCT == VoteCT_RandomNumber)
	{
		int iSerial = GetClientSerial(client);
		int iNumber = gA_RandomNumber.FindValue(iSerial);

		if(iNumber != -1)
		{
			Javit_PrintToChat(client, "You have already submitted a number. You have submitted the number \x05%d\x01.", gA_RandomNumber.Get(iNumber, 1));

			return Plugin_Handled;
		}

		iNumber = StringToInt(sArgs);

		if(!(1 <= iNumber <= 350))
		{
			Javit_PrintToChat(client, "Your number has to be between \x051\x01 and \x05350\x01.");

			return Plugin_Handled;
		}

		int arr[2];
		arr[0] = iSerial;
		arr[1] = iNumber;

		gA_RandomNumber.PushArray(arr);

		Javit_PrintToChat(client, "You have submitted the number \x05%d\x01.", iNumber);

		return Plugin_Handled;
	}

	else if(StrEqual(sArgs, gS_VoteCTAnswer))
	{
		WinVoteCT(client);
	}

	return Plugin_Continue;
}

bool IsFreeKiller(int client)
{
	if(AreClientCookiesCached(client))
	{
		char sBanned[8];
		GetClientCookie(client, gH_BanCookie, sBanned, 8);

		return view_as<bool>(StringToInt(sBanned));
	}

	return false;
}

public int Native_SetVIP(Handle plugin, int numParams)
{
	gB_VIP[GetNativeCell(1)] = GetNativeCell(2);
}

void Javit_BeaconEntity(int entity)
{
	float origin[3];

	if(entity <= MaxClients)
	{
		GetClientAbsOrigin(entity, origin);
	}

	else
	{
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	}

	origin[2] += 10;

	int colors[4] = {255, 255, 255, 255};

	TE_SetupBeamRingPoint(origin, 10.0, 250.0, gI_BeamSprite, gI_HaloSprite, 0, 60, 0.75, 2.5, 0.0, colors, 10, 0);
	TE_SendToAll();
}

void Javit_PrintToChat(int client, const char[] buffer, any ...)
{
	char sFormatted[256];
	VFormat(sFormatted, 256, buffer, 3);

	if(client != 0)
	{
		PrintToChat(client, "%s\x04[Jailbreak]\x01 %s", (GetEngineVersion() == Engine_CSGO)? " ":"", sFormatted);
	}

	else
	{
		PrintToServer("[Jailbreak] %s", sFormatted);
	}
}

void Javit_PrintToChatAll(const char[] format, any ...)
{
	char buffer[255];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			VFormat(buffer, 255, format, 2);
			Javit_PrintToChat(i, "%s", buffer);
		}
	}
}
