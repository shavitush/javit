#if defined _jailbreak_addons_v2_included_
  #endinput
#endif
#define _jailbreak_addons_v2_included_

// API

/**
 * Sets VIP status for a player.
 *
 * @param client  					Client index.
 * @param status					VIP or not?
 * @noreturn
 */
native void Javit_SetVIP(int client, bool status);

public SharedPlugin __pl_jailbreak_addons_v2 =
{
	name = "jailbreak_addons_v2",
	file = "jailbreak_addons_v2.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_jailbreak_addons_v2_SetNTVOptional()
{
	MarkNativeAsOptional("Javit_SetVIP");
}
#endif
