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

Handle gH_BanCookie = null;

Handle gH_HUD = null;
Handle gH_HUD_RandomNumber = null;
int gI_VoteCT = VoteCT_None;
float gF_VoteEnd = 0.0;
float gF_RoundStartTime = -15.0;
char gS_VoteCTAnswer[64];
char gS_VoteCTHUD[128];
ArrayList gA_RandomNumber = null;

ConVar sv_alltalk = null;

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
	RegAdminCmd("sm_votect", Command_VoteCT, ADMFLAG_GENERIC, "Initiate a manual CT vote.");

	LoadTranslations("common.phrases");

	gH_HUD = CreateHudSynchronizer();
	gH_HUD_RandomNumber = CreateHudSynchronizer();
	CreateTimer(0.1, Timer_Cron, 0, TIMER_REPEAT);

	sv_alltalk = FindConVar("sv_alltalk");

	gH_BanCookie = RegClientCookie("Banned_From_CT", "Tells if you are restricted from joining the CT team", CookieAccess_Protected);
	gA_RandomNumber = new ArrayList(2);

	HookEvent("round_start", Round_Start);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	// TODO: muteall unmuteall mutet mutect

	// TODO: sm_open with manual setting, use local sqlite database for entity output info. hook buttons too
	// TODO: sm_kickct sm_ctkick
	// TODO: sm_chooser sm_leader sm_warden
	// TODO: sm_choose sm_ctlist
	// TODO: sm_vip (+ beacon)
	// TODO: sm_box
	// TODO: sm_givelr
	// TODO: voice chat management, respect sv_alltalk
	// TODO: sm_freekill sm_fk
	// TODO: sm_medic

	// TODO: hook joingame and jointeam. joingame should be blocked, jointeam should respect ratios

	// TODO: damage text
	// https://github.com/rogeraabbccdd/CSGO-Damage-Text
}

public void OnMapStart()
{
	gF_RoundStartTime = -15.0;
	PrecacheSoundAny("ui/achievement_earned.wav", true);
	StopVoteCT("");
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if(gI_VoteCT != VoteCT_None)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	gF_RoundStartTime = GetEngineTime();
	Javit_PrintToChatAll("\x03Terrorists\x01 are muted for the first \x0515 seconds\x01 of the round.");
}

public Action Command_VoteCT(int client, int args)
{
	if(IsVoteInProgress() || gI_VoteCT != VoteCT_None)
	{
		ReplyToCommand(client, "A vote is already ongoing.");

		return Plugin_Handled;
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
	// TODO: open cells here

	return Plugin_Handled;
}

void StopVoteCT(const char[] message, any ...)
{
	if(strlen(message) > 0) // not an empty parameter - print a message
	{
		char[] sFormatted = new char[256];
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

		char[] info = new char[32];
		menu.GetItem(param1, info, 32);

		if(StrEqual(info, "fast"))
		{
			gI_VoteCT = VoteCT_FastWrite;
			IntToString(GetRandomInt(10000000, 99999999), gS_VoteCTAnswer, 64);
			FormatEx(gS_VoteCTHUD, 128, "Be the first to type %s!", gS_VoteCTAnswer);
		}

		else if(StrEqual(info, "random"))
		{
			gA_RandomNumber.Clear();
			gI_VoteCT = VoteCT_RandomNumber;
			IntToString(GetRandomInt(1, 350), gS_VoteCTAnswer, 64);
			strcopy(gS_VoteCTHUD, 128, "Submit a number from 1 to 350.");
		}

		else if(StrEqual(info, "math"))
		{
			gI_VoteCT = VoteCT_Math;

			int iNumber1 = GetRandomInt(-2, 10);
			int iNumber2 = GetRandomInt(-2, 10);
			IntToString(iNumber1 * iNumber2, gS_VoteCTAnswer, 64);

			FormatEx(gS_VoteCTHUD, 128, "%d * %d = ?", iNumber1, iNumber2);
		}

		else
		{
			if(StrEqual(info, "extend"))
			{
				Javit_PrintToChatAll("Voting is over. CT rounds have been extended to 12.");
			}

			StopVoteCT("");
		}
	}

	else if(action == MenuAction_VoteCancel)
	{
		StopVoteCT("");
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Timer_Cron(Handle timer)
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

	return Plugin_Continue;
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

		if((!bAdmin && (!bAlive || (iTeam != CS_TEAM_CT && bTMuted))) ||
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
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(gI_VoteCT <= VoteCT_Choosing)
	{
		return Plugin_Continue;
	}

	if(IsFreeKiller(client))
	{
		ReplyToCommand(client, "You cannot write during votes as you're CT banned.");

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

		int[] arr = new int[2];
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
		char[] sBanned = new char[8];
		GetClientCookie(client, gH_BanCookie, sBanned, 8);

		return view_as<bool>(StringToInt(sBanned));
	}

	return false;
}

public int Native_SetVIP(Handle plugin, int numParams)
{
	// TODO: implement
}

void Javit_PrintToChat(int client, const char[] buffer, any ...)
{
	char[] sFormatted = new char[256];
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
	char[] buffer = new char[255];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			VFormat(buffer, 255, format, 2);
			Javit_PrintToChat(i, "%s", buffer);
		}
	}
}
