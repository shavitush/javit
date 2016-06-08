#if defined _javit_included_
  #endinput
#endif
#define _javit_included_

#define LR_Prisoner 0
#define LR_Guard 1

#define STOPLR_NOTHING ""
#define PLACEHOLDER ""

char gS_CSSPistols[][] =
{
    "weapon_glock",
    "weapon_usp",
    "weapon_p228",
    "weapon_deagle",
    "weapon_fiveseven",
    "weapon_elite"
};

char gS_CSSPistolNames[][] =
{
    "9×19mm Sidearm (Glock 18)",
    "H&K USP45 Tactical (USP)",
    "228 Compact (P228)",
    "Night Hawk .50C (Desert Eagle.50 AE)",
    "FN Five-seveN",
    ".40 Dual Elites (Dual Berettas)"
};

char gS_CSGOPistols[][] =
{
    "weapon_deagle",
    "weapon_revolver",
    "weapon_glock",
    "weapon_fiveseven",
    "weapon_usp_silencer",
    "weapon_p250",
    "weapon_cz75a",
    "weapon_tec9",
    "weapon_hkp2000",
    "weapon_elite"
};

char gS_CSGOPistolNames[][] =
{
    "Night Hawk .50C (Desert Eagle)",
    "R8 Revolver",
    "9×19mm Sidearm (Glock 18)",
    "FN Five-seveN",
    "H&K USP45 Tactical (USP-S)",
    "P250",
    "CZ75-Auto",
    "Tec-9",
    "P2000",
    ".40 Dual Elites (Dual Berettas)"
};

char gS_CSSPrimaries[][] =
{
    "weapon_m3",
    "weapon_xm1014",
    "weapon_mp5",
    "weapon_mac10",
    "weapon_p90",
    "weapon_tmp",
    "weapon_ump45",
    "weapon_ak47",
    "weapon_aug",
    "weapon_famas",
    "weapon_galil",
    "weapon_sg552",
    "weapon_m4a1",
    "weapon_scout",
    "weapon_awp",
    "weapon_g3sg1",
    "weapon_sg550",
    "weapon_m249"
};

char gS_CSSPrimaryNames[][] =
{
    "Leone 12 Gauge Super (M3)",
    "Leone YG1265 Auto Shotgun (XM1014)",
    "K&M Sub-Machine Gun (MP5)",
    "MAC-10",
    "ES C90 (P90)",
    "Schmidt Machine Pistol (TMP)",
    "KM UMP45 (UMP-45)",
    "CV-47 (AK-47)",
    "Bullpup (AUG)",
    "Clarion 5.56 (FAMAS)",
    "IDF Defender (Galil)",
    "SG 552 (Krieg 552)",
    "Maverick M4A1 Carbine (M4)",
    "Steyr Scout (Schmidt Scout)",
    "Magnum Sniper Rifle (AWP)",
    "D3/AU-1 (G3SG1)",
    "Krieg 550 Commando (SG 550)",
    "FN M249 Para (M249)"
};

char gS_CSGOPrimaries[][] =
{
    "weapon_nova",
    "weapon_xm1014",
    "weapon_mag7",
    "weapon_sawedoff",
    "weapon_mac10",
    "weapon_p90",
    "weapon_ump45",
    "weapon_mp7",
    "weapon_mp9",
    "weapon_bizon",
    "weapon_ak47",
    "weapon_aug",
    "weapon_famas",
    "weapon_galilar",
    "weapon_m4a1_silencer",
    "weapon_m4a1",
    "weapon_sg556",
    "weapon_awp",
    "weapon_g3sg1",
    "weapon_scar20",
    "weapon_ssg08",
    "weapon_m249",
    "weapon_negev"
};

char gS_CSGOPrimaryNames[][] =
{
    "Nova",
    "Leone YG1265 Auto Shotgun (XM1014)",
    "MAG-7M1 (MAG-7)",
    "Remington 870 AOW (Sawed-Off)",
    "MAC-10",
    "ES C90 (P90)",
    "KM UMP45 (UMP-45)",
    "MP7",
    "MP9",
    "ПП-19 Бизон (PP-Bizon)",
    "CV-47 (AK-47)",
    "Bullpup (AUG)",
    "Clarion 5.56 (FAMAS)",
    "IDF Defender (Galil AR)",
    "Colt M4A1 Carbine (M4A1-S)",
    "M4A1 SOPMOD (M4A4)",
    "SG 553",
    "Magnum Sniper Rifle (AWP)",
    "D3/AU-1 (G3SG1)",
    "SCAR-20",
    "SSG 08 (Scout)",
    "FN M249 Para (M249)",
    "Negev"
};

char gS_CSSSnipers[][] =
{
    "weapon_scout",
    "weapon_awp",
    "weapon_g3sg1",
    "weapon_sg550"
};

char gS_CSSSniperNames[][] =
{
    "Steyr Scout (Schmidt Scout)",
    "Magnum Sniper Rifle (AWP)",
    "D3/AU-1 (G3SG1)",
    "Krieg 550 Commando (SG 550)"
};

char gS_CSGOSnipers[][] =
{
    "weapon_awp",
    "weapon_g3sg1",
    "weapon_scar20",
    "weapon_ssg08"
};

char gS_CSGOSniperNames[][] =
{
    "Magnum Sniper Rifle (AWP)",
    "D3/AU-1 (G3SG1)",
    "SCAR-20",
    "SSG 08 (Scout)"
};

enum GameEngines(+=1)
{
    Game_CSS = 0,
    Game_CSGO,
    Game_Unknown
};

enum LRTypes(+=1)
{
    LR_None = 0,
    LR_RandomLR,
    LR_Dodgeball,
    LR_Shot4Shot,
    LR_Randomization,
    LR_NoScopeBattle,
    LR_NadeFight,
    LR_Backstabs,
    LR_Pro90,
    LR_Headshots,
    LR_Jumpshots,
    LR_RussianRoulette,
    LR_VintageKnifeFight,
    LR_Flamethrower,
    LR_DRHax,
    LR_DeagleToss,
    LR_ShotgunFight,
    LR_Rebel
};

char gS_LRNames[][] =
{
    PLACEHOLDER,
    "Random LR",
    "Dodgeball",
    "Shot4Shot",
    "???",
    "NoScope Battle",
    "Nade Fight",
    "Backstabs!",
    "Pro90",
    "Headshots!",
    "Jumpshots!",
    "Russian Roulette",
    "Vintage Knife Fight",
    "Flamethrower",
    "Dr. HAX!",
    "Deagle Toss",
    "Shotgun Fight",
    "Rebel!"
};

// API

/**
 * Called when an LR is about to start and there's a prisoner/guard.
 *
 * @param type  					The LR that ended.
 * @param prisoner					Client index of LR winner.
 * @param guard 					Client index of LR loser.
 * @return                          False to stop the LR from starting.
 */
forward bool Javit_OnLRStart(LRTypes type, int prisoner, int guard);

/**
 * Called when an LR finishes and there's a winner/loser.
 *
 * @param type  					The LR that ended.
 * @param winner					Client index of LR winner.
 * @param loser 					Client index of LR loser.
 * @noreturn
 */
forward void Javit_OnLRFinish(LRTypes type, int winner, int loser);

/**
 * Gets the current LR the player is in right now.
 *
 * @param client    Client index.
 * @return          LR_None if not in LR right now, otherwise - the LR type.
 */
native LRTypes Javit_GetClientLR(int client);

/**
 * Gets the current LR the player is in right now.
 *
 * @param lr        LR type
 * @param buffer    String buffer
 * @param maxlen    Size of buffer
 * @noreturn
 */
native void Javit_GetLRName(LRTypes lr, char[] buffer);

/**
 * Gets the player's LR partner.
 *
 * @param client    Client index.
 * @return          Client index of the LR partner.
 */
native int Javit_GetClientPartner(int client);

public SharedPlugin __pl_javit =
{
	name = "javit",
	file = "javit.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_javit_SetNTVOptional()
{
	MarkNativeAsOptional("Javit_GetClientLR");
	MarkNativeAsOptional("Javit_GetLRName");
	MarkNativeAsOptional("Javit_GetClientPartner");
}
#endif
