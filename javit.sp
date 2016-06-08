#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <emitsoundany>
#include <smlib/clients>
#include <jbaddons>

#pragma newdecls required

#define PISTOLS
#define PRIMARIES
#define SNIPERS
#define LRNAMES
#include <javit>

#pragma semicolon 1

#define PLUGIN_VERSION "1.0b"

#define DEBUG

bool gB_Late = false;

GameEngines gG_GameEngine = Game_Unknown;

Database gH_SQL = null;

char gSLR_SecondaryWeapons[2][32];
char gSLR_PrimaryWeapons[2][32];
char gILR_HealthValues[2];
char gILR_ArmorValues[2];
char gSLR_MonitorModel[PLATFORM_MAX_PATH];

LRTypes gLR_Current = LR_None;
LRTypes gLR_ChosenRequest[MAXPLAYERS+1];
int gLR_Weapon_Turn = 0;

int gLR_Players[2];
float gLR_SpecialCooldown[MAXPLAYERS+1];

int gLR_S4SMode = 0; // 1 is mag4mag

float gLR_PreJumpPosition[MAXPLAYERS+1][3];
int gLR_Deagles[2];
Handle gLR_DeagleTossTimer = null;
float gLR_DeaglePosition[2][3];
bool gLR_DeaglePositionMeasured[2];
bool gLR_DroppedDeagle[MAXPLAYERS+1];
bool gLR_OnGround[MAXPLAYERS+1];
float gLR_CirclePosition[3];

bool gB_RebelRound = false;
bool gB_Freeday[MAXPLAYERS+1];

int gI_BeamSprite = -1;
int gI_HaloSprite = -1;
int gI_ExplosionSprite = -1;
int gI_SmokeSprite = -1;

ConVar gCV_IgnoreGrenadeRadio = null;

Handle gH_Forwards_OnLRAvailable = null;
Handle gH_Forwards_OnLRStart = null;
Handle gH_Forwards_OnLRFinish = null;

public Plugin myinfo =
{
    name = "Javit",
    author = "shavit",
    description = "Lastrequest handler for CS:S/CS:GO Jailbreak servers.",
    version = PLUGIN_VERSION,
    url = "https://github.com/shavitush/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("javit");

    CreateNative("Javit_GetClientLR", Native_GetClientLR);
    CreateNative("Javit_GetLRName", Native_GetLRName);
    CreateNative("Javit_GetClientPartner", Native_GetClientPartner);

    gB_Late = late;

    return APLRes_Success;
}

public void OnPluginStart()
{
    EngineVersion evEngine = GetEngineVersion();

    if(evEngine == Engine_CSS)
    {
        gG_GameEngine = Game_CSS;
    }

    else if(evEngine == Engine_CSGO)
    {
        gG_GameEngine = Game_CSGO;
    }

    else
    {
        SetFailState("This plugin was not meant to be used for any other game besides CS:S and CS:GO.");
    }

    CreateConVar("javit_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

    RegConsoleCmd("sm_lr", Command_LastRequest, "Wish something before you finally die.");
    RegConsoleCmd("sm_lastrequest", Command_LastRequest, "Wish something before you finally die.");

    RegConsoleCmd("sm_top", Command_Top, "Opens a menu that shows the top25 jailbreakers!");
    RegConsoleCmd("sm_lrtop", Command_Top, "Opens a menu that shows the top25 jailbreakers!");

    RegAdminCmd("sm_abortlr", Command_AbortLR, ADMFLAG_SLAY, "Aborts the current active LR.");
    RegAdminCmd("sm_stoplr", Command_AbortLR, ADMFLAG_SLAY, "Aborts the current active LR.");

    #if defined DEBUG
    RegConsoleCmd("sm_testlr", Command_TestLR);
    #endif

    HookEvent("player_spawn", Player_Spawn);
    HookEvent("player_death", Player_Death);
    HookEvent("player_jump", Player_Jump);
    HookEvent("weapon_fire", Weapon_Fire);

    HookEvent("round_start", Round_Start);
    HookEvent("round_end", Round_End);

    gCV_IgnoreGrenadeRadio = FindConVar("sv_ignoregrenaderadio");

    if(gCV_IgnoreGrenadeRadio != null)
    {
        gCV_IgnoreGrenadeRadio.BoolValue = false;
    }

    if(gB_Late)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsValidClient(i))
            {
                OnClientPutInServer(i);
            }
        }
    }

    SQL_DBConnect();

    gH_Forwards_OnLRAvailable = CreateGlobalForward("Javit_OnLRAvailable", ET_Event);
    gH_Forwards_OnLRStart = CreateGlobalForward("Javit_OnLRStart", ET_Event, Param_Cell, Param_Cell, Param_Cell);
    gH_Forwards_OnLRFinish = CreateGlobalForward("Javit_OnLRFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell);
}

public void OnClientPutInServer(int client)
{
    gLR_ChosenRequest[client] = LR_None;
    gLR_SpecialCooldown[client] = 0.0;
    gLR_DroppedDeagle[client] = false;
    gB_Freeday[client] = false;

    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(client, SDKHook_WeaponCanUse, WeaponEquip);

    if(gH_SQL != null)
    {
        char[] sAuthID3 = new char[32];
    	GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32);

    	char[] sName = new char[MAX_NAME_LENGTH];
    	GetClientName(client, sName, MAX_NAME_LENGTH);

    	int iLength = ((strlen(sName) * 2) + 1);
    	char[] sEscapedName = new char[iLength];
        gH_SQL.Escape(sName, sEscapedName, iLength);

    	char[] sQuery = new char[256];
    	FormatEx(sQuery, 256, "INSERT INTO players (auth, name) VALUES ('%s', '%s') ON DUPLICATE KEY UPDATE name = '%s';", sAuthID3, sEscapedName, sEscapedName);
    	gH_SQL.Query(SQL_InsertUser_Callback, sQuery, GetClientSerial(client), DBPrio_High);
    }
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
        int client = GetClientFromSerial(data);

        if(!client)
        {
            LogError("Javit error! Failed to insert a disconnected player's data to the table. Reason: %s", error);
        }

        else
        {
            LogError("Javit error! Failed to insert \"%N\"'s data to the table. Reason: %s", client, error);
        }

        return;
	}
}

public void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		CloseHandle(gH_SQL);
	}

	if(SQL_CheckConfig("javit"))
	{
		char[] sError = new char[255];

		if(!(gH_SQL = SQL_Connect("javit", true, sError, 255)))
		{
			SetFailState("Javit startup failed. Reason: %s", sError);
		}

		SQL_LockDatabase(gH_SQL);
		SQL_FastQuery(gH_SQL, "SET NAMES 'utf8';");
		SQL_UnlockDatabase(gH_SQL);

		gH_SQL.Query(SQL_CreateTable_Callback, "CREATE TABLE IF NOT EXISTS `players` (`auth` VARCHAR(32) NOT NULL, `name` VARCHAR(32) NOT NULL DEFAULT '< blank >', `wins` INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(`auth`));", 0, DBPrio_High);
	}

	else
	{
		SetFailState("Javit startup failed. Reason: %s", "\"javit\" is not a specified entry in databases.cfg.");
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Javit error! Data table creation failed. Reason: %s", error);

		return;
	}
}

public Action WeaponEquip(int client, int weapon)
{
    if(gLR_Current != LR_None && (client == gLR_Players[LR_Prisoner] || client == gLR_Players[LR_Guard]))
    {
        switch(gLR_Current)
        {
            case LR_DeagleToss:
            {
                if(gLR_DroppedDeagle[client] && (weapon == gLR_Deagles[LR_Prisoner] || weapon == gLR_Deagles[LR_Guard]))
                {
                    return Plugin_Handled;
                }
            }
        }
    }

    return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if(gLR_Current != LR_None && (victim == gLR_Players[LR_Prisoner] || victim == gLR_Players[LR_Guard]))
    {
        int iPartner = GetLRPartner(victim);

        if(damagetype != DMG_BURN)
        {
            if(attacker == 0 || attacker != iPartner && inflictor != iPartner)
            {
                return Plugin_Continue;
            }

            else if(gLR_Current == LR_NadeFight && attacker == victim)
            {
                return Plugin_Handled;
            }
        }

        switch(gLR_Current)
        {
            case LR_Dodgeball:
            {
                char[] sWeapon = new char[32];
                GetClientWeapon(attacker, sWeapon, 32);

                if(!StrEqual(sWeapon, "weapon_flashbang"))
                {
                    SetEntityHealth(victim, 1);

                    return Plugin_Handled;
                }
            }

            case LR_NoScopeBattle:
            {
                bool bShouldDamage = false;

                char[] sWeapon = new char[32];
                GetClientWeapon(attacker, sWeapon, 32);

                if(gG_GameEngine == Game_CSS)
                {
                    for(int i = 0; i < sizeof(gS_CSSSnipers); i++)
                    {
                        if(StrEqual(sWeapon, gS_CSSSnipers[i]))
                        {
                            bShouldDamage = true;

                            break;
                        }
                    }
                }

                else if(gG_GameEngine == Game_CSGO)
                {
                    for(int i = 0; i < sizeof(gS_CSGOSnipers); i++)
                    {
                        if(StrEqual(sWeapon, gS_CSGOSnipers[i]))
                        {
                            bShouldDamage = true;

                            break;
                        }
                    }
                }

                if(!bShouldDamage)
                {
                    return Plugin_Handled;
                }
            }

            case LR_NadeFight:
            {
                char[] sWeapon = new char[32];
                GetClientWeapon(attacker, sWeapon, 32);

                if(!StrEqual(sWeapon, "weapon_hegrenade"))
                {
                    return Plugin_Handled;
                }
            }

            case LR_Backstabs, LR_KnifeFight:
            {
                char[] sWeapon = new char[32];
                GetClientWeapon(attacker, sWeapon, 32);

                if(!StrEqual(sWeapon, "weapon_knife") || (gLR_Current == LR_Backstabs && damage < 100))
    			{
    				return Plugin_Handled;
    			}
            }

            case LR_Pro90:
            {
                char[] sWeapon = new char[32];
                GetClientWeapon(attacker, sWeapon, 32);

                if(!StrEqual(sWeapon, "weapon_p90"))
    			{
    				return Plugin_Handled;
    			}
            }

            case LR_Headshots, LR_Jumpshots:
            {
                char[] sWeapon = new char[32];
                int iWeapon = GetClientWeapon(attacker, sWeapon, 32);

                bool bShouldWork = false;

                if(gLR_Current == LR_Headshots)
                {
                    bShouldWork = StrEqual(sWeapon, "weapon_deagle") && damagetype & CS_DMG_HEADSHOT;
                }

                else if(gLR_Current == LR_Jumpshots)
                {
                    bShouldWork = !(StrEqual(sWeapon, "weapon_knife") || GetEntityFlags(attacker) & FL_ONGROUND);
                }

                if(bShouldWork)
    			{
                    SDKHooks_TakeDamage(victim, attacker, attacker, GetClientHealth(victim) * 1.0, CS_DMG_HEADSHOT, iWeapon);

                    TE_SetupExplosion(damagePosition, gI_ExplosionSprite, 5.0, 1, 0, 50, 40);
                    TE_SendToAll();

                    TE_SetupSmoke(damagePosition, gI_SmokeSprite, 10.0, 3);
                    TE_SendToAll();

                    Javit_PlayWowSound();

                    return Plugin_Handled;
    			}

                else
                {
                    return Plugin_Handled;
                }
            }

            case LR_RussianRoulette:
            {
                int iWeapon = GetPlayerWeaponSlot(attacker, CS_SLOT_SECONDARY);

                int iRandom = GetRandomInt(1, 4);

                switch(iRandom)
                {
                    case 1:
                    {
                        SDKHooks_TakeDamage(victim, attacker, attacker, GetClientHealth(victim) * 1.0, CS_DMG_HEADSHOT, iWeapon);
                    }

                    case 2:
                    {
                        SDKHooks_TakeDamage(attacker, attacker, victim, GetClientHealth(attacker) * 1.0, CS_DMG_HEADSHOT, iWeapon);
                    }

                    default:
                    {
                        return Plugin_Handled;
                    }
                }

                return Plugin_Handled;
            }

            case LR_Flamethrower:
            {
                if(damagetype == DMG_BURN)
                {
                    attacker = GetLRPartner(victim);
                    damage = GetRandomFloat(2.0, 7.0);

                    return Plugin_Changed;
                }

                else
                {
                    return Plugin_Handled;
                }
            }

            case LR_DRHax:
            {
                if(inflictor == GetLRPartner(victim))
                {
                    attacker = GetLRPartner(victim);
                    damage *= GetRandomFloat(1.3, 1.6);

                    return Plugin_Changed;
                }

                else
                {
                    return Plugin_Handled;
                }
            }

            case LR_DeagleToss:
            {
                return Plugin_Handled;
            }

            case LR_CircleOfDoom:
            {
                SlapPlayer(victim, 0, true);
            }
        }
    }

    return Plugin_Continue;
}

public void OnMapStart()
{
    if(gG_GameEngine == Game_CSS)
    {
        gI_BeamSprite = PrecacheModel("sprites/laser.vmt", true);
        gI_HaloSprite = PrecacheModel("sprites/halo01.vmt", true);

        strcopy(gSLR_MonitorModel, PLATFORM_MAX_PATH, "models/props_lab/monitor01a.mdl");
    }

    else
    {
        gI_BeamSprite = PrecacheModel("sprites/laserbeam.vmt", true);
        gI_HaloSprite = PrecacheModel("sprites/glow01.vmt", true);

        strcopy(gSLR_MonitorModel, PLATFORM_MAX_PATH, "models/props_lab/monitor02a.mdl");
    }

    PrecacheModel(gSLR_MonitorModel);

    PrecacheSoundAny("buttons/blip1.wav", true);

    AddFileToDownloadsTable("sound/javit/lr_activated.mp3");
    PrecacheSoundAny("javit/lr_activated.mp3", true);

    AddFileToDownloadsTable("sound/javit/lr_start.mp3");
    PrecacheSoundAny("javit/lr_start.mp3", true);

    AddFileToDownloadsTable("sound/javit/lr_error.mp3");
    PrecacheSoundAny("javit/lr_error.mp3", true);

    AddFileToDownloadsTable("sound/javit/lr_wow.mp3");
    PrecacheSoundAny("javit/lr_wow.mp3", true);

    AddFileToDownloadsTable("sound/javit/lr_hax.mp3");
    PrecacheSoundAny("javit/lr_hax.mp3", true);

    gI_ExplosionSprite = PrecacheModel("materials/sprites/blueglow2.vmt");
    gI_SmokeSprite = PrecacheModel("materials/sprites/steam1.vmt");

    CreateTimer(0.50, Timer_Beacon, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    if(gLR_Current != LR_None && (client == gLR_Players[LR_Prisoner] || client == gLR_Players[LR_Guard]))
    {
        Javit_PlayMissSound();

        Javit_StopLR("Last requested aborted - \x03%N\x01 has disconnected.", client);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(gLR_Current == LR_Dodgeball && StrEqual(classname, "flashbang_projectile"))
	{
        CreateTimer(1.5, Timer_KillFlashbang, entity, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_KillFlashbang(Handle Timer, any entity)
{
    if(IsValidEntity(entity) && entity != INVALID_ENT_REFERENCE)
	{
        AcceptEntityInput(entity, "Kill");
	}
}

public void Player_Spawn(Event e, const char[] name, bool dB)
{
    int userid = e.GetInt("userid");
    int client = GetClientOfUserId(userid);

    if(!IsValidClient(client, true))
    {
        return;
    }

    SetEntityHealth(client, 100);
    SetEntityGravity(client, 1.0);

    Client_RemoveAllWeapons(client);

    GivePlayerItem(client, "weapon_knife");

    if(GetClientTeam(client) == CS_TEAM_CT)
    {
        GivePlayerItem(client, "weapon_deagle");
        GivePlayerItem(client, gG_GameEngine == Game_CSS? "weapon_m4a1":"weapon_m4a1_silencer");

        SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
    }
}

public void Player_Death(Event e, const char[] name, bool dB)
{
    int userid = e.GetInt("userid");
    int victim = GetClientOfUserId(userid);

    userid = e.GetInt("attacker");
    int attacker = GetClientOfUserId(userid);

    if(attacker == 0 || (!IsValidClient(attacker) && !IsValidClient(victim)))
    {
        return;
    }

    if(gLR_Current != LR_None && attacker == gLR_Players[LR_Guard] || victim == gLR_Players[LR_Guard])
    {
        switch(gLR_Current)
        {
            case LR_Flamethrower:
            {
                if(IsValidClient(victim))
                {
                    ExtinguishEntity(victim);
                }
            }
        }

        Javit_FinishLR(attacker, victim, gLR_Current);
    }

    if(Javit_IsItLRTime())
    {
        Javit_AnnounceLR();
    }
}

public void Player_Jump(Event e, const char[] name, bool dB)
{
    if(gLR_Current == LR_None)
    {
        return;
    }

    int userid = e.GetInt("userid");
    int client = GetClientOfUserId(userid);

    GetClientAbsOrigin(client, gLR_PreJumpPosition[client]);

    if(!IsValidClient(client, true))
    {
        return;
    }

    switch(gLR_Current)
    {
        case LR_DeagleToss:
        {
            if(!gLR_DroppedDeagle[client])
            {
                GetClientAbsOrigin(client, gLR_PreJumpPosition[client]);

                gLR_OnGround[client] = false;
            }
        }
    }
}

public void Weapon_Fire(Event e, const char[] name, bool dB)
{
    if(gLR_Current == LR_None)
    {
        return;
    }

    int userid = e.GetInt("userid");
    int client = GetClientOfUserId(userid);

    if(!IsValidClient(client, true) || (client != gLR_Players[LR_Prisoner] && client != gLR_Players[LR_Guard]))
    {
        return;
    }

    char[] sWeapon = new char[32];
    e.GetString("weapon", sWeapon, 32);

    // Javit_PrintToChatAll(sWeapon);

    switch(gLR_Current)
    {
        case LR_Dodgeball:
        {
            if(StrEqual(sWeapon, "flashbang"))
            {
                GivePlayerItem(client, "weapon_flashbang");

                DataPack dp = new DataPack();
                dp.WriteCell(GetClientSerial(client));
                dp.WriteString("weapon_flashbang");

                CreateTimer(0.15, AutoSwitchTimer, dp);
            }
        }

        case LR_Shot4Shot, LR_RussianRoulette:
        {
            int iClip = 0;

            int iWeapon = GetPlayerWeaponSlot(gLR_Players[gLR_Weapon_Turn], CS_SLOT_SECONDARY);

            if(gLR_S4SMode == 0) // shot4shot/rr
            {
                gLR_Weapon_Turn = !gLR_Weapon_Turn;

                iWeapon = GetPlayerWeaponSlot(gLR_Players[gLR_Weapon_Turn], CS_SLOT_SECONDARY);

                iClip = 1;
            }

            else // mag4mag
            {
                int iClip1 = GetEntProp(iWeapon, Prop_Data, "m_iClip1");

                if(iClip1 == 1)
                {
                    gLR_Weapon_Turn = !gLR_Weapon_Turn;
                    iWeapon = GetPlayerWeaponSlot(gLR_Players[gLR_Weapon_Turn], CS_SLOT_SECONDARY);

                    iClip = 7;
                }
            }

            if(iWeapon != -1)
            {
                if(iClip > 0)
                {
                    SetEntProp(iWeapon, Prop_Data, "m_iClip1", iClip);
                }
            }

            else
            {
                Javit_StopLR("LR aborted - couldn't find pistol on \x03%N\x01.", gLR_Players[gLR_Weapon_Turn]);

                Javit_PlayMissSound();
            }
        }

        case LR_NadeFight:
        {
            if(StrEqual(sWeapon, "hegrenade"))
            {
                DataPack dp = new DataPack();
                dp.WriteCell(GetClientSerial(client));
                dp.WriteString("weapon_hegrenade");

                CreateTimer(0.25, AutoSwitchTimer, dp);
            }
        }

        case LR_Flamethrower:
        {
            int iPartner = GetLRPartner(client);

            if(StrEqual(sWeapon, "knife") && ShootFlame(client, iPartner, 280.00))
            {
                IgniteEntity(iPartner, 1.00, false);
            }
        }

        case LR_DRHax:
        {
            if(StrEqual(sWeapon, "knife"))
            {
                ShootMonitor(client);
            }
        }

        case LR_ShotgunFight:
        {
            if(StrEqual(sWeapon, "xm1014"))
            {
                int color[4] = {0, 0, 0, 255};

                for(int i = 0; i < 3; i++)
                {
                    color[i] = GetRandomInt(0, 255);
                }

                color[3] = GetRandomInt(220, 255);

                float fEyeOrigin[3];
                GetClientEyePosition(client, fEyeOrigin);

                float fEyeAngles[3];
                GetClientEyeAngles(client, fEyeAngles);

                float fAdd[3];
                GetAngleVectors(fEyeAngles, fAdd, NULL_VECTOR, NULL_VECTOR);

                fEyeOrigin[0] += (fAdd[0] * 30.0);
                fEyeOrigin[1] += (fAdd[1] * 30.0);
                fEyeOrigin[2] -= 5.0;

                float fEnd[3];
                Handle trace = TR_TraceRayFilterEx(fEyeOrigin, fEyeAngles, MASK_SHOT, RayType_Infinite, bFilterShotgun);

                if(TR_DidHit(trace))
                {
                    TR_GetEndPosition(fEnd, trace);

                    TE_SetupBeamPoints(fEyeOrigin, fEnd, gI_BeamSprite, gI_HaloSprite, 0, 0, 0.75, 5.0, 5.0, 0, 0.0, color, 0);
                    TE_SendToAll(0.0);
                }
            }
        }

        case LR_Molotovs:
        {
            if(StrEqual(sWeapon, "molotov"))
            {
                DataPack dp = new DataPack();
                dp.WriteCell(GetClientSerial(client));
                dp.WriteString("weapon_molotov");

                CreateTimer(0.40, AutoSwitchTimer, dp);
            }
        }
    }

    return;
}

public Action CS_OnCSWeaponDrop(int client, int weapon)
{
    switch(gLR_Current)
    {
        case LR_Shot4Shot, LR_Randomization, LR_RussianRoulette:
        {
            if(client == gLR_Players[LR_Prisoner] || client == gLR_Players[LR_Guard])
            {
                return Plugin_Handled;
            }
        }

        case LR_DeagleToss:
        {
            if(weapon == gLR_Deagles[LR_Prisoner] || weapon == gLR_Deagles[LR_Guard])
            {
                if(gLR_DroppedDeagle[client])
                {
                    Javit_PrintToChat(client, "You have already tossed this deagle.");

                    return Plugin_Handled;
                }

                if(gLR_OnGround[client])
                {
                    Javit_PrintToChat(client, "You may not drop the gun unless you jump.");

                    return Plugin_Handled;
                }

                gLR_DroppedDeagle[client] = true;
            }
        }
    }

    return Plugin_Continue;
}

public Action AutoSwitchTimer(Handle Timer, any data)
{
    ResetPack(data);
    int serial = ReadPackCell(data);

    char[] sWeapon = new char[32];
    ReadPackString(data, sWeapon, 32);

    CloseHandle(data);

    int client = GetClientFromSerial(serial);

    if(!client)
    {
        return Plugin_Stop;
    }

    FakeClientCommand(client, "use weapon_knife");

    if(!StrEqual(sWeapon, "weapon_flashbang"))
    {
        int iWeapon = GivePlayerItem(client, sWeapon);

        SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", iWeapon);
        ChangeEdictState(client, FindDataMapOffs(client, "m_hActiveWeapon"));
    }

    FakeClientCommand(client, "use %s", sWeapon);

    return Plugin_Stop;
}

public void Round_Start(Event e, const char[] name, bool dB)
{
    Javit_StopLR(STOPLR_NOTHING);

    int iT = Javit_GetClientAmount(CS_TEAM_T, false);

    for(int i = 1; i <= MaxClients; i++)
    {
        if(gB_Freeday[i])
        {
            if(iT < 5)
            {
                Javit_PrintToChat(i, "There are only \x05%d Terrorists\x01 alive, there must be at least 5 to claim your freeday.", iT);
            }

            else
            {
                Javit_SetVIP(i, true);

                Javit_PrintToChatAll("\x03%N\x01 picked to have a \x05freeday\x01 as his previous LR!", i);
            }

            gB_Freeday[i] = false;
        }
    }
}

public void Round_End(Event e, const char[] name, bool dB)
{
    Javit_StopLR(STOPLR_NOTHING);
}

public Action Command_LastRequest(int client, int args)
{
    if(!IsValidClient(client, false))
    {
        return Plugin_Handled;
    }

    if(!IsPlayerAlive(client))
    {
        Javit_PrintToChat(client, "You have to be alive in order to use this command.");

        return Plugin_Handled;
    }

    if(GetClientTeam(client) != CS_TEAM_T || Javit_GetClientAmount(CS_TEAM_T, true) != 1)
    {
        Javit_PrintToChat(client, "You have to be the only alive Terrorist in order to use this command.");

        return Plugin_Handled;
    }

    if(Javit_GetClientAmount(CS_TEAM_CT, true) < 1)
    {
        Javit_PrintToChat(client, "There are no available guards to fulfill your last request.");

        return Plugin_Handled;
    }

    if(gLR_Current != LR_None)
    {
        Javit_PrintToChat(client, "You may only use this command if there are no active LRs.");

        return Plugin_Handled;
    }

    if(gB_RebelRound)
    {
        Javit_PrintToChat(client, "You have chose to be a rebel, no LRs for you buddy!");

        return Plugin_Handled;
    }

    return Javit_ShowLRMenu(client);
}

public int MenuHandler_LastRequestType(Menu m, MenuAction a, int p1, int p2)
{
    if(a == MenuAction_Select)
    {
        if(!IsValidClient(p1, true) || GetClientTeam(p1) != CS_TEAM_T || !Javit_IsItLRTime())
        {
            return 0;
        }

        char[] sInfo = new char[8];
        m.GetItem(p2, sInfo, 8);

        int iLR = StringToInt(sInfo);

        if(iLR == -1)
        {
            Javit_PrintToChat(p1, "ERROR: No LRs are available.");

            return 0;
        }

        LRTypes LRChosen = view_as<LRTypes>(iLR);

        switch(LRChosen)
        {
            case LR_Rebel:
            {
                gB_RebelRound = true;

                SetEntityHealth(p1, 140 + (90 * Javit_GetClientAmount(CS_TEAM_CT, true)));

                Client_RemoveAllWeapons(p1);
                GivePlayerItem(p1, "weapon_knife");
                Client_GiveWeaponAndAmmo(p1, "weapon_deagle", false, 9999);
                Client_GiveWeaponAndAmmo(p1, gG_GameEngine == Game_CSGO? "weapon_negev":"weapon_m249", true, 9999);

                Javit_PlayMissSound();

                Javit_PrintToChatAll("\x03%N\x01 chose to be a \x04REBEL!\x01", p1);

                return 0;
            }

            case LR_Freeday:
            {
                gB_Freeday[p1] = true;

                ForcePlayerSuicide(p1);
                Javit_PlayWowSound();

                Javit_PrintToChatAll("\x03%N\x01 chose to have a \x05freeday\x01 tomorrow!", p1);

                return 0;
            }
        }

        gLR_ChosenRequest[p1] = LRChosen;

        Javit_DisplayCTList(p1);
    }

    else if(a == MenuAction_End)
    {
        delete m;
    }

    return 0;
}

public int MenuHandler_LastRequestCT(Menu m, MenuAction a, int p1, int p2)
{
    if(a == MenuAction_Select)
    {
        if(!IsValidClient(p1, true) || GetClientTeam(p1) != CS_TEAM_T || !Javit_IsItLRTime())
        {
            return 0;
        }

        char[] sInfo = new char[8];
        m.GetItem(p2, sInfo, 8);

        int iPartner = StringToInt(sInfo);

        if(!IsValidClient(iPartner, true) || GetClientTeam(iPartner) != CS_TEAM_CT)
        {
            Javit_PrintToChat(p1, "ERROR: LR partner disconnected or is not a CT.");
            Javit_PrintToChat(p1, "Showing up the list again.");

            Javit_DisplayCTList(p1);

            return 0;
        }

        switch(gLR_ChosenRequest[p1])
        {
            case LR_RandomLR:
            {
                Javit_InitializeLR(p1, iPartner, view_as<LRTypes>(GetRandomInt(2, sizeof(gS_LRNames) - 1)), true);
            }

            case LR_RussianRoulette, LR_CircleOfDoom:
            {
                float fClientOrigin[3];
                GetClientAbsOrigin(p1, fClientOrigin);

                float fEyeAngles[3];
                GetClientEyeAngles(p1, fEyeAngles);

                float fAdd[3];
                GetAngleVectors(fEyeAngles, fAdd, NULL_VECTOR, NULL_VECTOR);

                fClientOrigin[0] += fAdd[0] * 125.0;
                fClientOrigin[1] += fAdd[1] * 125.0;

                fEyeAngles[1] += 180.0;

                if(fEyeAngles[1] > 180.0)
                {
                    fEyeAngles[1] -= 360.0;
                }

                float fPartnerOrigin[3];
                GetClientAbsOrigin(iPartner, fPartnerOrigin);

                TeleportEntity(iPartner, fClientOrigin, fEyeAngles, NULL_VECTOR);

                if(GetClientAimTarget(p1, false) != iPartner || !IsSafeTeleport(p1, 250.0))
                {
                    Javit_PrintToChat(p1, "ERROR: Your partner cannot teleport to this place!");
                    Javit_PrintToChat(p1, "Please look at somewhere else.");

                    Javit_ShowLRMenu(p1);

                    TeleportEntity(iPartner, fPartnerOrigin, NULL_VECTOR, NULL_VECTOR);

                    return 0;
                }

                Javit_InitializeLR(p1, iPartner, gLR_ChosenRequest[p1], false);
            }

            default:
            {
                Javit_InitializeLR(p1, iPartner, gLR_ChosenRequest[p1], false);
            }
        }
    }

    else if(a == MenuAction_Cancel && p2 == MenuCancel_ExitBack)
    {
        if(p2 == MenuCancel_ExitBack)
        {
            Javit_ShowLRMenu(p1);
        }
    }

    else if(a == MenuAction_End)
    {
        delete m;
    }

    return 0;
}

public Action Command_AbortLR(int client, int args)
{
    if(gLR_Current == LR_None && !gB_RebelRound)
    {
        Javit_PrintToChat(client, "There are no active LRs right now.");

        return Plugin_Handled;
    }

    Javit_StopLR("LR aborted by admin command.");

    LogAction(client, -1, "Aborted LR [CT: %L] [T: %L]", gLR_Players[LR_Guard], gLR_Players[LR_Prisoner]);

    return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    char[] sQuery = new char[128];
    FormatEx(sQuery, 128, "SELECT name, wins, auth FROM players WHERE wins != 0 ORDER BY wins DESC LIMIT 25;");

    gH_SQL.Query(SQL_Top_Callback, sQuery, GetClientSerial(client));

    return Plugin_Handled;
}

public void SQL_Top_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Javit (select wins) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_ShowSteamID3);

	char[] sTitle = new char[32];
	FormatEx(sTitle, 32, "Top 25 Jailer%s:", results.RowCount > 1? "s":"");

	menu.SetTitle(sTitle);

	int iCount = 0;

	while(results.FetchRow())
	{
		// 0 - player name
		char sName[MAX_NAME_LENGTH];
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		// 1 - wins
		int iWins = results.FetchInt(1);

		// 2 - steamid3
		char sAuth[32];
		results.FetchString(2, sAuth, 32);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "#%d - %s (%d LR win%s)", ++iCount, sName, iWins, iWins > 1? "s":"");
		menu.AddItem(sAuth, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "No results.");
	}

	menu.ExitButton = true;

	menu.Display(client, 20);
}

public int MenuHandler_ShowSteamID3(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[32];
		menu.GetItem(param2, info, 32);

		PrintToConsole(param1, "SteamID3: %s", info);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DB_AddWin(int client)
{
	char[] sAuthID = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "UPDATE players SET wins = wins + 1 WHERE auth = '%s';", sAuthID);
	gH_SQL.Query(SQL_UpdateWins_Callback, sQuery);
}

public void SQL_UpdateWins_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Javit (update wins) SQL query failed. Reason: %s", error);

		return;
	}
}

public Action Timer_Beacon(Handle Timer)
{
    if(gLR_Current == LR_None)
    {
        return Plugin_Continue;
    }

    for(int i = 0; i < sizeof(gLR_Players); i++)
    {
        if(IsValidClient(gLR_Players[i], true))
        {
            Javit_BeaconEntity(gLR_Players[i], true);
        }
    }

    switch(gLR_Current)
    {
        case LR_CircleOfDoom:
        {
            for(int i = 1; i <= 6; i++)
            {
                gLR_CirclePosition[2] += 10;

                if(i == 1)
                {
                    TE_SetupBeamRingPoint(gLR_CirclePosition, 220.0, 220.0, gI_BeamSprite, gI_HaloSprite, 0, 0, 0.60, 5.0, 0.0, {255, 0, 0, 255}, 1, 0);
                    TE_SendToAll();
                }

                TE_SetupBeamRingPoint(gLR_CirclePosition, 280.0, 280.0, gI_BeamSprite, gI_HaloSprite, 0, 0, 25.0, 0.60, 0.0, {255, 0, 0, 255}, 1, 0);
                TE_SendToAll();
            }

            gLR_CirclePosition[2] -= 60;

            float fPosition[sizeof(gLR_Players)][3];
            GetClientAbsOrigin(gLR_Players[LR_Prisoner], fPosition[LR_Prisoner]);
            GetClientAbsOrigin(gLR_Players[LR_Guard], fPosition[LR_Guard]);

            if(GetVectorDistance(fPosition[LR_Prisoner], gLR_CirclePosition) > 130.00)
            {
                SDKHooks_TakeDamage(gLR_Players[LR_Prisoner], gLR_Players[LR_Guard], gLR_Players[LR_Guard], GetClientHealth(gLR_Players[LR_Prisoner]) * 1.0, CS_DMG_HEADSHOT);
            }

            else if(GetVectorDistance(fPosition[LR_Guard], gLR_CirclePosition) > 130.00)
            {
                SDKHooks_TakeDamage(gLR_Players[LR_Guard], gLR_Players[LR_Prisoner], gLR_Players[LR_Prisoner], GetClientHealth(gLR_Players[LR_Guard]) * 1.0, CS_DMG_HEADSHOT);
            }
        }
    }

    return Plugin_Continue;
}

#if defined DEBUG
public Action Command_TestLR(int client, int args)
{
    Javit_InitializeLR(client, client, LR_Dodgeball, false);

    return Plugin_Handled;
}
#endif

// functions
public void Javit_PrintToChat(int client, const char[] buffer, any ...)
{
    char[] sFormatted = new char[256];
    VFormat(sFormatted, 256, buffer, 3);

    PrintToChat(client, "%s\x04[Jailbreak]\x01 %s", gG_GameEngine == Game_CSGO? " ":"", sFormatted);
}

stock void Javit_PrintToChatAll(const char[] format, any ...)
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

public void Javit_StopLR(const char[] message, any ...)
{
    if(!StrEqual(message, "")) // not an empty parameter - print a message
    {
        char[] sFormatted = new char[256];
        VFormat(sFormatted, 256, message, 2);

        Javit_PrintToChatAll(sFormatted);
    }

    if(gCV_IgnoreGrenadeRadio != null)
    {
        gCV_IgnoreGrenadeRadio.BoolValue = false;
    }

    gB_RebelRound = false;
    gLR_Current = LR_None;

    for(int i = 0; i < sizeof(gLR_Players); i++)
    {
        if(gLR_Players[i] != 0 && IsValidClient(gLR_Players[i], true))
        {
            SetEntityHealth(gLR_Players[i], 100);

            Client_RemoveAllWeapons(gLR_Players[i]);

            Weapon_CreateForOwner(gLR_Players[i], "weapon_knife");
            Weapon_CreateForOwner(gLR_Players[i], gSLR_SecondaryWeapons[i]);
            Weapon_CreateForOwner(gLR_Players[i], gSLR_PrimaryWeapons[i]);

            SetEntityHealth(gLR_Players[i], gILR_HealthValues[i]);
            SetEntProp(gLR_Players[i], Prop_Send, "m_ArmorValue", gILR_ArmorValues[i]);

            SetEntPropFloat(gLR_Players[i], Prop_Data, "m_flLaggedMovementValue", 1.0);
            SetEntityGravity(gLR_Players[i], 1.0);

            SetEntityFlags(gLR_Players[i], GetEntityFlags(gLR_Players[i]) & ~FL_ATCONTROLS);

            ExtinguishEntity(gLR_Players[i]);

            gLR_SpecialCooldown[gLR_Players[i]] = 0.0;
            gLR_DroppedDeagle[gLR_Players[i]] = false;
        }

        gLR_DeaglePositionMeasured[i] = false;
    }

    gLR_Players[LR_Prisoner] = 0;
    gLR_Players[LR_Guard] = 0;

    if(gLR_DeagleTossTimer != null)
    {
        KillTimer(gLR_DeagleTossTimer);

        gLR_DeagleTossTimer = null;
    }
}

public int Javit_GetClientAmount(int team, bool alive)
{
    int iAlive = 0;

    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsValidClient(i, alive) || GetClientTeam(i) != team)
        {
            continue;
        }

        iAlive++;
    }

    return iAlive;
}

public void Javit_BeaconEntity(int entity, bool sound)
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

    int colors[4] = {0, 0, 0, 255};
    colors[0] = GetRandomInt(0, 255);
    colors[1] = GetRandomInt(0, 255);
    colors[2] = GetRandomInt(0, 255);

    TE_SetupBeamRingPoint(origin, 10.0, 250.0, gI_BeamSprite, gI_HaloSprite, 0, 60, 0.75, 2.5, 0.0, colors, 10, 0);
    TE_SendToAll();

    if(sound)
    {
        EmitAmbientSoundAny("buttons/blip1.wav", origin, entity, SNDLEVEL_RAIDSIREN);
    }
}

public void Javit_AnnounceLR()
{
    int iLRPlayer = 0;

    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i, true) && GetClientTeam(i) == CS_TEAM_T)
        {
            iLRPlayer = i;

            Command_LastRequest(iLRPlayer, 0);

            break;
        }
    }

    for(int i = 1; i <= 3; i++)
    {
        Javit_PrintToChatAll("\x03%N\x01 can have a \x05last request\x01!", iLRPlayer);
    }

    EmitSoundToAllAny("javit/lr_activated.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL);

    Call_StartForward(gH_Forwards_OnLRAvailable);
    Call_Finish();
}

public bool Javit_InitializeLR(int prisoner, int guard, LRTypes type, bool random)
{
    bool result = true;
    Call_StartForward(gH_Forwards_OnLRStart);
    Call_PushCell(view_as<int>(type));
    Call_PushCell(prisoner);
    Call_PushCell(guard);
    Call_Finish(result);

    if(!result)
    {
        return false;
    }

    if(!IsValidClient(prisoner, true) || !IsValidClient(guard, true) || !Javit_IsItLRTime())
    {
        return false;
    }

    if(gCV_IgnoreGrenadeRadio != null)
    {
        gCV_IgnoreGrenadeRadio.BoolValue = true;
    }

    EmitSoundToAllAny("javit/lr_start.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL);

    gLR_Current = type;

    gLR_Players[LR_Prisoner] = prisoner;
    gLR_Players[LR_Guard] = guard;

    for(int i = 0; i < sizeof(gLR_Players); i++)
    {
        int iSecondary = GetPlayerWeaponSlot(gLR_Players[i], CS_SLOT_SECONDARY);

        if(iSecondary != -1)
        {
            GetEntityClassname(iSecondary, gSLR_SecondaryWeapons[i], 32);
        }

        int iPrimary = GetPlayerWeaponSlot(gLR_Players[i], CS_SLOT_PRIMARY);

        if(iPrimary != -1)
        {
            GetEntityClassname(iPrimary, gSLR_PrimaryWeapons[i], 32);
        }

        gILR_HealthValues[i] = GetClientHealth(gLR_Players[i]);

        gILR_ArmorValues[i] = GetClientArmor(gLR_Players[i]);
        SetEntProp(gLR_Players[i], Prop_Send, "m_ArmorValue", 0);
    }

    Javit_PrintToChatAll("\x03%N\x01 wishes to play \x05%s\x01%s as his last request with \x03%N\x01.", gLR_Players[LR_Prisoner], gS_LRNames[gLR_Current], random? " \x04[random]\x01":"", gLR_Players[LR_Guard]);

    switch(type)
    {
        case LR_Dodgeball:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 1);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
                GivePlayerItem(gLR_Players[i], "weapon_flashbang");
            }
        }

        case LR_Shot4Shot:
        {
            char[] sPistol = new char[128];
            char[] sPistolName = new char[128];

            if(gG_GameEngine == Game_CSS)
            {
                int iWeapon = GetRandomInt(0, sizeof(gS_CSSPistols) - 1);

                strcopy(sPistol, 128, gS_CSSPistols[iWeapon]);
                strcopy(sPistolName, 128, gS_CSSPistolNames[iWeapon]);
            }

            else if(gG_GameEngine == Game_CSGO)
            {
                int iWeapon = GetRandomInt(0, sizeof(gS_CSGOPistols) - 1);

                strcopy(sPistol, 128, gS_CSGOPistols[iWeapon]);
                strcopy(sPistolName, 128, gS_CSGOPistolNames[iWeapon]);
            }

            Javit_PrintToChatAll("Shot4Shot weapon: \x05%s\x01.", sPistolName);

            int iFirst = GetRandomInt(0, 1); // "provably fair" :^)
            gLR_Weapon_Turn = iFirst;

            Javit_PrintToChatAll("The first to shoot is \x03%N\x01!", gLR_Players[iFirst]);

            if(GetRandomInt(1, 4) == 4)
            {
                Javit_PrintToChatAll("\x05~MAG4MAG HYPE~");

                gLR_S4SMode = 1;
            }

            else
            {
                gLR_S4SMode = 0;
            }

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);

                Client_GiveWeaponAndAmmo(gLR_Players[i], sPistol, true, 0, -1, i == iFirst? (gLR_S4SMode == 1? 7:1):0, -1);
            }
        }

        case LR_Randomization:
        {
            char[] sPistol = new char[128];
            char[] sPistolName = new char[128];

            char[] sPrimary = new char[128];
            char[] sPrimaryName = new char[128];

            if(gG_GameEngine == Game_CSS)
            {
                int iSecondary = GetRandomInt(0, sizeof(gS_CSSPistols) - 1);
                strcopy(sPistol, 128, gS_CSSPistols[iSecondary]);
                strcopy(sPistolName, 128, gS_CSSPistolNames[iSecondary]);

                int iPrimary = GetRandomInt(0, sizeof(gS_CSSPrimaries) - 1);
                strcopy(sPrimary, 128, gS_CSSPrimaries[iPrimary]);
                strcopy(sPrimaryName, 128, gS_CSSPrimaryNames[iPrimary]);
            }

            else if(gG_GameEngine == Game_CSGO)
            {
                int iSecondary = GetRandomInt(0, sizeof(gS_CSGOPistols) - 1);
                strcopy(sPistol, 128, gS_CSGOPistols[iSecondary]);
                strcopy(sPistolName, 128, gS_CSGOPistolNames[iSecondary]);

                int iPrimary = GetRandomInt(0, sizeof(gS_CSGOPrimaries) - 1);
                strcopy(sPrimary, 128, gS_CSGOPrimaries[iPrimary]);
                strcopy(sPrimaryName, 128, gS_CSGOPrimaryNames[iPrimary]);
            }

            int iHP = GetRandomInt(500, 2500);
            float fSpeed = GetRandomFloat(0.50, 1.50);
            float fGravity = GetRandomFloat(0.75, 1.25);

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                SetEntityHealth(gLR_Players[i], iHP);
                SetEntPropFloat(gLR_Players[i], Prop_Data, "m_flLaggedMovementValue", fSpeed);
                SetEntityGravity(gLR_Players[i], fGravity);

                Client_RemoveAllWeapons(gLR_Players[i]);
                Client_GiveWeaponAndAmmo(gLR_Players[i], sPistol, false, 9999, -1, 9999, -1);
                Client_GiveWeaponAndAmmo(gLR_Players[i], sPrimary, true, 9999, -1, 9999, -1);
            }

            Javit_PrintToChatAll("\x04??? \x05%s", sPistolName);
            Javit_PrintToChatAll("\x04??? \x05%s", sPrimaryName);
            Javit_PrintToChatAll("\x04??? \x05%d", iHP);
            Javit_PrintToChatAll("\x04??? \x05%.02f", fSpeed);
            Javit_PrintToChatAll("\x04??? \x05%.02f", fGravity);
        }

        case LR_NoScopeBattle:
        {
            char[] sSniper = new char[128];
            char[] sSniperName = new char[128];

            if(gG_GameEngine == Game_CSS)
            {
                int iWeapon = GetRandomInt(0, sizeof(gS_CSSSnipers) - 1);

                strcopy(sSniper, 128, gS_CSSSnipers[iWeapon]);
                strcopy(sSniperName, 128, gS_CSSSniperNames[iWeapon]);
            }

            else if(gG_GameEngine == Game_CSGO)
            {
                int iWeapon = GetRandomInt(0, sizeof(gS_CSGOSnipers) - 1);

                strcopy(sSniper, 128, gS_CSGOSnipers[iWeapon]);
                strcopy(sSniperName, 128, gS_CSGOSniperNames[iWeapon]);
            }

            Javit_PrintToChatAll("We will use \x05%s\x01 for this battle.", sSniperName);

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);
                SetEntProp(gLR_Players[i], Prop_Send, "m_ArmorValue", 100);

                GivePlayerItem(gLR_Players[i], "weapon_knife");

                DataPack dp = new DataPack();
                dp.WriteCell(GetClientSerial(gLR_Players[i]));

                int iSniper = Client_GiveWeaponAndAmmo(gLR_Players[i], sSniper, false, 9990, -1, 10, -1);
                dp.WriteCell(iSniper);

                CreateTimer(0.50, Timer_SwitchToWeapon, dp, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case LR_NadeFight:
        {
            int iHP = GetRandomInt(225, 340);

            Javit_PrintToChatAll("Your HP is \x05%d\x01, let's go!!!", iHP);

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], iHP);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
                GivePlayerItem(gLR_Players[i], "weapon_hegrenade");
            }
        }

        case LR_Backstabs:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
            }
        }

        case LR_Pro90:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 2000);

                GivePlayerItem(gLR_Players[i], "weapon_knife");

                DataPack dp = new DataPack();
                dp.WriteCell(GetClientSerial(gLR_Players[i]));

                int iWeapon = Client_GiveWeaponAndAmmo(gLR_Players[i], "weapon_p90", false, 0, -1, 9999, -1);
                dp.WriteCell(iWeapon);

                CreateTimer(0.50, Timer_SwitchToWeapon, dp, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case LR_Headshots:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 999);

                GivePlayerItem(gLR_Players[i], "weapon_knife");

                DataPack dp = new DataPack();
                dp.WriteCell(GetClientSerial(gLR_Players[i]));

                int iWeapon = Client_GiveWeaponAndAmmo(gLR_Players[i], "weapon_deagle", false, 0, -1, 9999, -1);
                dp.WriteCell(iWeapon);

                CreateTimer(0.50, Timer_SwitchToWeapon, dp, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        case LR_Jumpshots:
        {
            char[] sPistol = new char[32];
            char[] sRifle = new char[32];

            if(gG_GameEngine == Game_CSS)
            {
                strcopy(sPistol, 32, "weapon_usp");
                strcopy(sRifle, 32, "weapon_scout");
            }

            else if(gG_GameEngine == Game_CSGO)
            {
                strcopy(sPistol, 32, "weapon_usp_silencer");
                strcopy(sRifle, 32, "weapon_ssg08");
            }

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                SetEntityHealth(gLR_Players[i], 100);

                Client_RemoveAllWeapons(gLR_Players[i]);
                GivePlayerItem(gLR_Players[i], "weapon_knife");
                Client_GiveWeaponAndAmmo(gLR_Players[i], sPistol, false, 9999, -1, 9999, -1);
                Client_GiveWeaponAndAmmo(gLR_Players[i], sRifle, true, 9999, -1, 9999, -1);
            }
        }

        case LR_RussianRoulette:
        {
            int iFirst = GetRandomInt(0, 1); // "provably fair" :^)
            gLR_Weapon_Turn = iFirst;

            Javit_PrintToChatAll("The game is simple, 25%% to win, 25%% to lose and 50%% to keep the roulette goin'.");
            Javit_PrintToChatAll("\x03%N\x01, you're first to go!", gLR_Players[iFirst]);

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);

                Client_GiveWeaponAndAmmo(gLR_Players[i], "weapon_deagle", true, 0, -1, i == iFirst? 1:0, -1);

                SetEntityFlags(gLR_Players[i], GetEntityFlags(gLR_Players[i]) | FL_ATCONTROLS);
            }
        }

        case LR_KnifeFight:
        {
            Javit_PrintToChatAll("STAB STAB STAB!");

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
            }
        }

        case LR_Flamethrower:
        {
            Javit_PrintToChatAll("It's time.. to catch a fire!");

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                PrintHintText(gLR_Players[i], "Tapping your mouse button\nwill result in a fire!");

                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 120);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
            }
        }

        case LR_DRHax:
        {
            EmitSoundToAllAny("javit/lr_hax.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL);

            Javit_PrintToChatAll("HAXXXXXXXXXXXXX");

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                PrintHintText(gLR_Players[i], "Tap your mouse button\nto shoot a monitor!");

                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 250);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
            }
        }

        case LR_DeagleToss:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                PrintHintText(gLR_Players[i], "Throw it as far as you can.");

                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);

                gLR_Deagles[i] = Client_GiveWeaponAndAmmo(gLR_Players[i], "weapon_deagle", true, 0, -1, 0, -1);

                GetClientAbsOrigin(gLR_Players[i], gLR_DeaglePosition[i]);

                gLR_DeaglePositionMeasured[i] = false;
                gLR_DroppedDeagle[gLR_Players[i]] = false;
            }

            gLR_DeagleTossTimer = CreateTimer(0.5, Timer_DeagleToss, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        }

        case LR_ShotgunFight:
        {
            Javit_PrintToChatAll("pew pew pew");

            int iHP = GetRandomInt(250, 300);

            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], iHP);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
                Client_GiveWeaponAndAmmo(gLR_Players[i], "weapon_xm1014", true, 9999);
            }
        }

        case LR_Molotovs:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                PrintHintText(gLR_Players[i], "Burn him before he burns you.");

                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 200);

                GivePlayerItem(gLR_Players[i], "weapon_knife");
                GivePlayerItem(gLR_Players[i], "weapon_molotov");
            }
        }

        case LR_CircleOfDoom:
        {
            for(int i = 0; i < sizeof(gLR_Players); i++)
            {
                PrintHintText(gLR_Players[i], "Starting in 3...");

                Client_RemoveAllWeapons(gLR_Players[i]);
                SetEntityHealth(gLR_Players[i], 100);

                GivePlayerItem(gLR_Players[i], "weapon_knife");

                SetEntityFlags(gLR_Players[i], GetEntityFlags(gLR_Players[i]) | FL_ATCONTROLS);

                CreateTimer(3.0, Timer_UnfreezePlayers, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
            }

            GetClientAbsOrigin(gLR_Players[LR_Prisoner], gLR_CirclePosition);
        }
    }

    return true;
}

public Action Timer_UnfreezePlayers(Handle Timer)
{
    if(gLR_Current != LR_CircleOfDoom)
    {
        return Plugin_Stop;
    }

    Javit_PlayMissSound();

    for(int i = 0; i < sizeof(gLR_Players); i++)
    {
        PrintHintText(gLR_Players[i], "Stab him out of the circle, GO!!!");

        SetEntityFlags(gLR_Players[i], GetEntityFlags(gLR_Players[i]) & ~FL_ATCONTROLS);
    }

    return Plugin_Stop;
}

public Action Timer_DeagleToss(Handle Timer)
{
    for(int i = 0; i < sizeof(gLR_Players); i++)
    {
        if(gLR_DeaglePositionMeasured[i])
        {
            continue;
        }

        if(!IsValidEntity(gLR_Deagles[i]))
        {
            Javit_StopLR("Aborting Deagle Toss! \x03%N\x01's deagle couldn't be found.");

            break;
        }

        if(GetEntPropEnt(gLR_Deagles[i], Prop_Data, "m_hOwner") == INVALID_ENT_REFERENCE)
        {
            float fTempPosition[3];
            GetEntPropVector(gLR_Deagles[i], Prop_Send, "m_vecOrigin", fTempPosition);

            if(GetVectorDistance(fTempPosition, gLR_DeaglePosition[i]) < 30.0)
            {
                gLR_DeaglePositionMeasured[i] = true;
            }

            gLR_DeaglePosition[i][0] = fTempPosition[0];
            gLR_DeaglePosition[i][1] = fTempPosition[1];
            gLR_DeaglePosition[i][2] = fTempPosition[2];

            if(gLR_DeaglePositionMeasured[i])
            {
                int color[4] = {0, 0, 0, 255};

                if(i == LR_Prisoner)
                {
                    color[0] = 255;
                }

                else
                {
                    color[2] = 255;
                }

                TE_SetupBeamPoints(gLR_DeaglePosition[i], gLR_PreJumpPosition[gLR_Players[i]], gI_BeamSprite, gI_HaloSprite, 0, 0, 15.0, 5.0, 5.0, 0, 0.0, color, 0);
                TE_SendToAll(0.0);
            }
        }
    }

    if(gLR_DeaglePositionMeasured[LR_Prisoner] && gLR_DeaglePositionMeasured[LR_Guard])
    {
        if(GetVectorDistance(gLR_DeaglePosition[LR_Prisoner], gLR_DeaglePosition[LR_Guard]) >= 1500.00)
        {
            Javit_StopLR("The deagles are too far away. Aborting LR.");
        }

        else
        {
            CreateTimer(3.0, Timer_KillTheLoser, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);

            Javit_PlayWowSound();
        }

        gLR_DeagleTossTimer = null;

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action Timer_KillTheLoser(Handle Timer, any data)
{
    if(gLR_Current != LR_DeagleToss)
    {
        return Plugin_Stop;
    }

    float[] fDistances = new float[sizeof(gLR_Players)];

    for(int i = 0; i < sizeof(gLR_Players); i++)
    {
        fDistances[i] = GetVectorDistance(gLR_DeaglePosition[i], gLR_PreJumpPosition[gLR_Players[i]]);
    }

    Javit_PrintToChatAll("RESULTS:\n\x04Prisoner: [\x03%N\x04] - \x05%.02f\n\x04Guard: [\x03%N\x04] - \x05%.02f", gLR_Players[LR_Prisoner], fDistances[LR_Prisoner], gLR_Players[LR_Guard], fDistances[LR_Guard]);

    int iWinner = gLR_Players[(fDistances[LR_Prisoner] > fDistances[LR_Guard])? LR_Prisoner:LR_Guard];
    int iPartner = GetLRPartner(iWinner);

    SDKHooks_TakeDamage(iPartner, iWinner, iWinner, GetClientHealth(iPartner) * 1.0, CS_DMG_HEADSHOT);

    Javit_PlayMissSound();

    return Plugin_Stop;
}

public Action Timer_SwitchToWeapon(Handle Timer, any data)
{
    ResetPack(data);
    int iSerial = ReadPackCell(data);
    int iWeapon = ReadPackCell(data);
    CloseHandle(data);

    int client = GetClientFromSerial(iSerial);

    if(client == 0)
    {
        return Plugin_Stop;
    }

    SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", iWeapon);
    ChangeEdictState(client, FindDataMapOffs(client, "m_hActiveWeapon"));

    return Plugin_Stop;
}

public void Javit_DisplayCTList(int client)
{
    Menu menu = new Menu(MenuHandler_LastRequestCT);

    char[] sTitle = new char[128];
    FormatEx(sTitle, 128, "%s\nChoose a guard:", gS_LRNames[gLR_ChosenRequest[client]]);
    menu.SetTitle(sTitle);

    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsValidClient(i, true) || GetClientTeam(i) != CS_TEAM_CT)
        {
            continue;
        }

        char[] sInfo = new char[8];
        IntToString(i, sInfo, 8);

        char[] sDisplay = new char[MAX_NAME_LENGTH];
        GetClientName(i, sDisplay, MAX_NAME_LENGTH);

        menu.AddItem(sInfo, sDisplay);
    }

    if(menu.ItemCount == 0)
    {
        Javit_PrintToChat(client, "There are no available guards to fulfill your last request.");

        return;
    }

    menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);
}

public void Javit_FinishLR(int winner, int loser, LRTypes type)
{
    Call_StartForward(gH_Forwards_OnLRFinish);
    Call_PushCell(view_as<int>(type));
    Call_PushCell(winner);
    Call_PushCell(loser);
    Call_Finish();

    Javit_StopLR("\x03%N\x01 won \x05%s\x01 against \x03%N\x01!", winner, gS_LRNames[type], loser);

    SetEntityHealth(winner, 100);

    if(GetPlayerWeaponSlot(winner, CS_SLOT_KNIFE) == -1)
    {
        GivePlayerItem(winner, "weapon_knife");
    }

    bool bAdmin = false;

    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i) && CheckCommandAccess(i, "sm_admin", ADMFLAG_GENERIC) && GetClientTeam(i) >= 2)
        {
            bAdmin = true;

            break;
        }
    }

    if(Javit_GetClientAmount(CS_TEAM_T, false) + Javit_GetClientAmount(CS_TEAM_CT, false) >= 14 || bAdmin)
    {
        DB_AddWin(winner);

        Javit_PrintToChat(winner, "You earned 1 point for winning this LR! Write \x05!top\x01 to see the rankings.");
    }
}

public Action Javit_ShowLRMenu(int client)
{
    if(!IsValidClient(client, true) || GetClientTeam(client) != CS_TEAM_T)
    {
        return Plugin_Handled;
    }

    Menu menu = new Menu(MenuHandler_LastRequestType);
    menu.SetTitle("Choose a last request:");

    for(int i = 1; i < sizeof(gS_LRNames); i++)
    {
        // add any csgo exclusive lrs here
        if(gG_GameEngine != Game_CSGO && i == view_as<int>(LR_Molotovs))
        {
            continue;
        }

        if(!LibraryExists("jbaddons") && i == view_as<int>(LR_Freeday))
        {
            continue;
        }

        char[] sInfo = new char[8];
        IntToString(i, sInfo, 8);

        menu.AddItem(sInfo, gS_LRNames[i]);
    }

    if(menu.ItemCount == 0)
    {
        menu.AddItem("-1", "Nothing");
    }

    menu.ExitButton = true;

    menu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}

public void Javit_PlayMissSound()
{
    EmitSoundToAllAny("javit/lr_error.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL);
}

public void Javit_PlayWowSound()
{
    EmitSoundToAllAny("javit/lr_wow.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL);
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
    switch(gLR_Current)
    {
        case LR_NoScopeBattle:
        {
            if(client == gLR_Players[LR_Prisoner] || client == gLR_Players[LR_Guard])
            {
                buttons &= ~IN_ATTACK2;
            }
        }

        case LR_DeagleToss:
        {
            if(GetEntityFlags(client) & FL_ONGROUND)
            {
                gLR_OnGround[client] = true;
            }
        }
    }

    return Plugin_Continue;
}

public bool Javit_IsItLRTime()
{
    return (Javit_GetClientAmount(CS_TEAM_T, true) == 1 && Javit_GetClientAmount(CS_TEAM_CT, true) > 0);
}

public bool bFilterNothing(int entity, int mask)
{
    return (entity == 0);
}

public bool bFilterPlayers(int entity, int mask, any data)
{
    return (entity != data);
}

public bool bFilterShotgun(int entity, int mask)
{
    return (entity >= MaxClients);
}

public bool IsSafeTeleport(int client, float distance)
{
    float fEyePos[3];
    float fEyeAngles[3];

    bool bLookingAtWall = false;

    GetClientEyePosition(client, fEyePos);
    GetClientEyeAngles(client, fEyeAngles);

    fEyeAngles[0] = 0.0;

    Handle trace = TR_TraceRayFilterEx(fEyePos, fEyeAngles, CONTENTS_SOLID, RayType_Infinite, bFilterNothing);

    if(TR_DidHit(trace))
    {
        float fEnd[3];
        TR_GetEndPosition(fEnd, trace);

        if(GetVectorDistance(fEyePos, fEnd) <= distance)
        {
            float fHullMin[3] = {-16.0, -16.0, 0.0};
            float fHullMax[3] = {16.0, 16.0, 90.0};

            if(gG_GameEngine == Game_CSS)
            {
                fHullMax[2] = 72.0;
            }

            Handle hullTrace = TR_TraceHullEx(fEyePos, fEnd, fHullMin, fHullMax, CONTENTS_SOLID);

            if(TR_DidHit(hullTrace))
            {
                TR_GetEndPosition(fEnd, hullTrace);

                if(GetVectorDistance(fEyePos, fEnd) <= distance)
                {
                    bLookingAtWall = true;
                }
            }

            delete hullTrace;
        }
    }

    CloseHandle(trace);

    return !bLookingAtWall;
}

// returns true if hit the target
public bool ShootFlame(int client, int target, float distance)
{
    if(GetEngineTime() - gLR_SpecialCooldown[client] < 0.50)
    {
        return false;
    }

    gLR_SpecialCooldown[client] = GetEngineTime();

    // borrowed from https://forums.alliedmods.net/showthread.php?p=701086
    float fClientOrigin[3];
    GetClientAbsOrigin(client, fClientOrigin);

    float fEyeOrigin[3];
    GetClientEyePosition(client, fEyeOrigin);

    float fEyeAngles[3];
    GetClientEyeAngles(client, fEyeAngles);

    float fAdd[3];
    GetAngleVectors(fEyeAngles, fAdd, NULL_VECTOR, NULL_VECTOR);

    float fFlameOrigin[3];
    fFlameOrigin[0] = fClientOrigin[0] + (fAdd[0] * distance);
    fFlameOrigin[1] = fClientOrigin[1] + (fAdd[1] * distance);
    fFlameOrigin[2] = fClientOrigin[2] + (fAdd[2] * distance);

    char[] sColor = new char[16];

    if(GetClientTeam(client) == CS_TEAM_T)
    {
        FormatEx(sColor, 16, "214 104 41");
    }

    else
    {
        FormatEx(sColor, 16, "41 206 214");
    }

    char[] sTarget = new char[32];
    Format(sTarget, 32, "target%d", client);
    DispatchKeyValue(client, "targetname", sTarget);

    char[] sFlameName = new char[32];
    FormatEx(sFlameName, 32, "flame%d", client);

    int iFlameEnt = CreateEntityByName("env_steam");
    DispatchKeyValue(iFlameEnt, "targetname", sFlameName);
    DispatchKeyValue(iFlameEnt, "parentname", sTarget);
    DispatchKeyValue(iFlameEnt, "SpawnFlags", "1");
    DispatchKeyValue(iFlameEnt, "Type", "0");
    DispatchKeyValue(iFlameEnt, "InitialState", "1");
    DispatchKeyValue(iFlameEnt, "Spreadspeed", "10");
    DispatchKeyValue(iFlameEnt, "Speed", "800");
    DispatchKeyValue(iFlameEnt, "Startsize", "10");
    DispatchKeyValue(iFlameEnt, "EndSize", "250");
    DispatchKeyValue(iFlameEnt, "Rate", "15");
    DispatchKeyValue(iFlameEnt, "JetLength", "400");
    DispatchKeyValue(iFlameEnt, "RenderColor", sColor);
    DispatchKeyValue(iFlameEnt, "RenderAmt", "180");
    DispatchSpawn(iFlameEnt);
    TeleportEntity(iFlameEnt, fClientOrigin, fAdd, NULL_VECTOR);
    SetVariantString(sTarget);
    AcceptEntityInput(iFlameEnt, "SetParent", iFlameEnt, iFlameEnt, 0);
    SetVariantString("forward");
    AcceptEntityInput(iFlameEnt, "SetParentAttachment", iFlameEnt, iFlameEnt, 0);
    AcceptEntityInput(iFlameEnt, "TurnOn");

    char[] sFlame2Name = new char[32];
    FormatEx(sFlame2Name, 32, "flame2%d", client);

    int iFlameEnt2 = CreateEntityByName("env_steam");
    DispatchKeyValue(iFlameEnt2, "targetname", sFlame2Name);
    DispatchKeyValue(iFlameEnt2, "parentname", sTarget);
    DispatchKeyValue(iFlameEnt2, "SpawnFlags", "1");
    DispatchKeyValue(iFlameEnt2, "Type", "1");
    DispatchKeyValue(iFlameEnt2, "InitialState", "1");
    DispatchKeyValue(iFlameEnt2, "Spreadspeed", "10");
    DispatchKeyValue(iFlameEnt2, "Speed", "600");
    DispatchKeyValue(iFlameEnt2, "Startsize", "50");
    DispatchKeyValue(iFlameEnt2, "EndSize", "400");
    DispatchKeyValue(iFlameEnt2, "Rate", "10");
    DispatchKeyValue(iFlameEnt2, "JetLength", "500");
    DispatchSpawn(iFlameEnt2);
    TeleportEntity(iFlameEnt2, fClientOrigin, fAdd, NULL_VECTOR);
    SetVariantString(sTarget);
    AcceptEntityInput(iFlameEnt2, "SetParent", iFlameEnt2, iFlameEnt2, 0);
    SetVariantString("forward");
    AcceptEntityInput(iFlameEnt2, "SetParentAttachment", iFlameEnt2, iFlameEnt2, 0);
    AcceptEntityInput(iFlameEnt2, "TurnOn");

    DataPack dp = new DataPack();
    dp.WriteCell(EntIndexToEntRef(iFlameEnt));
    dp.WriteCell(EntIndexToEntRef(iFlameEnt2));
    CreateTimer(1.50, Timer_KillFlames, dp, TIMER_FLAG_NO_MAPCHANGE);

    float fTargetOrigin[3];
    GetClientAbsOrigin(target, fTargetOrigin);

    if(GetVectorDistance(fFlameOrigin, fTargetOrigin) <= 120.00)
    {
        return true;
    }

    return false;
}

public Action Timer_KillFlames(Handle Timer, any data)
{
    ResetPack(data);

    for(int i = 1; i <= 2; i++)
    {
        int iFlameEnt = EntRefToEntIndex(ReadPackCell(data));
        AcceptEntityInput(iFlameEnt, "TurnOff");

        if(IsValidEntity(iFlameEnt))
        {
            RemoveEdict(iFlameEnt);
        }
    }

    CloseHandle(data);

    return Plugin_Stop;
}

public void ShootMonitor(int client)
{
    if(GetEngineTime() - gLR_SpecialCooldown[client] < 0.75)
    {
        return;
    }

    gLR_SpecialCooldown[client] = GetEngineTime();

    // borrowed from https://github.com/LeGone/Entcontrol/blob/master/scripting/entcontrol/weapons.sp
    float fEyeOrigin[3];
    GetClientEyePosition(client, fEyeOrigin);

    float fEyeAngles[3];
    GetClientEyeAngles(client, fEyeAngles);

    float fDirection[3];
    GetAngleVectors(fEyeAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

    float fResult[3];
    AddVectors(fEyeOrigin, fDirection, fResult);
    ScaleVector(fDirection, 2000.00);

    int iEntity = CreateEntityByName("hegrenade_projectile");
    SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", client);
    SetEntPropFloat(iEntity, Prop_Send, "m_flDamage", GetRandomFloat(20.0, 30.0));

    DispatchSpawn(iEntity);

    float fHitbox[3] = {1.5, 1.5, 1.5};
    SetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", fHitbox);
    NegateVector(fHitbox);
    SetEntPropVector(iEntity, Prop_Send, "m_vecMins", fHitbox);

    TeleportEntity(iEntity, fResult, fEyeAngles, fDirection);

    SetEntityModel(iEntity, gSLR_MonitorModel);

    float fColor[3];

    if(GetClientTeam(client) == CS_TEAM_CT)
    {
        fColor = view_as<float>({0.000, 0.251, 0.250});
    }

    else
    {
        fColor = view_as<float>({0.041, 0.206, 0.214});
    }

    int iGasCloud = CreateEntityByName("env_rockettrail");
    DispatchKeyValueVector(iGasCloud, "Origin", fResult);
    DispatchKeyValueVector(iGasCloud, "Angles", fEyeAngles);
    SetEntPropVector(iGasCloud, Prop_Send, "m_StartColor", fColor);
    SetEntPropVector(iGasCloud, Prop_Send, "m_EndColor", fColor);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_Opacity", 0.5);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_SpawnRate", 100.0);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_ParticleLifetime", 0.5);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_StartSize", 5.0);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_EndSize", 30.0);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_SpawnRadius", 0.0);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_MinSpeed", 0.0);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_MaxSpeed", 10.0);
    SetEntPropFloat(iGasCloud, Prop_Send, "m_flFlareScale", 1.0);
    DispatchSpawn(iGasCloud);

    char[] sIndex = new char[16];
    IntToString(iEntity, sIndex, 16);
    DispatchKeyValue(iEntity, "targetname", sIndex);
    SetVariantString(sIndex);
    AcceptEntityInput(iGasCloud, "SetParent");

    SetEntPropEnt(iEntity, Prop_Send, "m_hEffectEntity", EntIndexToEntRef(iGasCloud));

    SDKHook(iEntity, SDKHook_StartTouch, Monitor_StartTouch);
    SDKHook(iEntity, SDKHook_OnTakeDamage, Monitor_OnTakeDamage);

    EmitSoundToAllAny("javit/lr_hax.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL);
}

public int GetLRPartner(int client)
{
    if(GetClientTeam(client) == CS_TEAM_CT)
    {
        return gLR_Players[LR_Prisoner];
    }

    return gLR_Players[LR_Guard];
}

public Action Monitor_StartTouch(int entity, int other)
{
    char[] sEntity = new char[64];
    GetEntityClassname(other, sEntity, 64);

    if(other != 0 && (other == GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") || (!StrEqual(sEntity, "player") && StrContains(sEntity, "func_") != -1 && StrContains(sEntity, "prop") != -1 && StrContains(sEntity, "physics") != -1 && StrContains(sEntity, "brush") != -1)))
    {
        return Plugin_Continue;
    }

    Explode(entity, other);

    return Plugin_Continue;
}

public Action Monitor_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    Explode(victim, 0);

    return Plugin_Continue;
}

public void Explode(int entity, int target)
{
    SDKUnhook(entity, SDKHook_StartTouch, Monitor_StartTouch);
    SDKUnhook(entity, SDKHook_OnTakeDamage, Monitor_OnTakeDamage);

    int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");

    float fEntityPosition[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fEntityPosition);

    int iGasCloud = EntRefToEntIndex(GetEntPropEnt(entity, Prop_Send, "m_hEffectEntity"));

    if(iGasCloud != INVALID_ENT_REFERENCE)
    {
        AcceptEntityInput(entity, "kill");

        int iExplosion = CreateEntityByName("env_explosion");
        DispatchKeyValueVector(iExplosion, "Origin", fEntityPosition);
        DispatchKeyValue(iExplosion, "iMagnitude", "60");
        DispatchKeyValue(iExplosion, "classname", "HAX");
        DispatchSpawn(iExplosion);
        SetEntPropEnt(iExplosion, Prop_Data, "m_hInflictor", client);

        AcceptEntityInput(iExplosion, "Explode");
        AcceptEntityInput(iExplosion, "Kill");
    }

    AcceptEntityInput(entity, "kill");
}

public int Native_GetClientLR(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);

    if(client != gLR_Players[LR_Prisoner] && client != gLR_Players[LR_Guard])
    {
        return view_as<int>(LR_None);
    }

    return view_as<int>(gLR_Current);
}

public int Native_GetLRName(Handle plugin, int numParams)
{
    LRTypes lr = view_as<LRTypes>(GetNativeCell(1));

    return SetNativeString(2, gS_LRNames[lr], GetNativeCell(3), true);
}

public int Native_GetClientPartner(Handle plugin, int numParams)
{
    return GetLRPartner(GetNativeCell(1));
}

stock bool IsValidClient(int client, bool bAlive = true)
{
    return (IsClientConnected(client) && IsClientInGame(client) && (!bAlive || IsPlayerAlive(client)));
}
