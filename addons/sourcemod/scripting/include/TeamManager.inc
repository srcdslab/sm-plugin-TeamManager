#if defined _TeamManager_include
  #endinput
#endif
#define _TeamManager_include

/**
 * Called when warmup ends
 *
 * @return				None
 */
forward void TeamManager_WarmupEnd();

/**
 * Returns if warmup is enabled
 *
 * @return				bool sm_warmup
 */
native bool TeamManager_HasWarmup();

/**
 * Returns the status of warmup
 *
 * @return				bool inwarmup
 */
native bool TeamManager_InWarmup();

public SharedPlugin __pl_TeamManager =
{
	name = "TeamManager",
	file = "TeamManager.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_TeamManager_SetNTVOptional()
{
	MarkNativeAsOptional("TeamManager_HasWarmup");
	MarkNativeAsOptional("TeamManager_InWarmup");
}
#endif
