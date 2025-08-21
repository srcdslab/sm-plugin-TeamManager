#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <utilshelper>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <zombiereloaded>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define MIN_PLAYERS 2

Handle g_hWarmupEndFwd = INVALID_HANDLE;

ConVar g_cvWarmup, g_cvWarmuptime, g_cvWarmupMaxTime, g_cvForceTeam, g_cvPlayersRatio, g_cvCleanOnWarmupEnd, g_cvAliveTeamChange;
ConVar g_cvDynamic, g_cvDynamicRatio, g_cvDynamicTime;

bool g_bWarmup = false;
bool g_bRoundEnded = false;
bool g_bZombieSpawned = false;
bool g_bBlockRespawn = false;
bool g_bZombieReloaded = false;

int g_iWarmup = 0;
int g_iDynamicWarmupTime = 0;
int g_TeamChangeQueue[MAXPLAYERS + 1] = { -1, ... };

StringMap g_hEntitiesListToKill;

public Plugin myinfo =
{
	name = "TeamManager",
	author = "BotoX + maxime1907, .Rushaway",
	description = "Adds a warmup round, makes every human a ct and every zombie a t",
	version = "2.3.0",
	url = "https://github.com/srcdslab/sm-plugin-TeamManager"
};

public APLRes AskPluginLoad2(Handle hThis, bool bLate, char[] err, int iErrLen)
{
	g_hWarmupEndFwd = CreateGlobalForward("TeamManager_WarmupEnd", ET_Ignore);

	CreateNative("TeamManager_HasWarmup", Native_HasWarmup);
	CreateNative("TeamManager_InWarmup", Native_InWarmup);

	RegPluginLibrary("TeamManager");

	return APLRes_Success;
}

public void OnPluginStart()
{
	InitStringMap();

	AddCommandListener(OnJoinTeamCommand, "jointeam");
	HookEvent("round_start", OnRoundStart, EventHookMode_Pre);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

	/* Global */
	g_cvWarmup = CreateConVar("sm_warmup", "1", "Enables the warmup system", 0, true, 0.0, true, 1.0);
	g_cvWarmuptime = CreateConVar("sm_warmuptime", "10", "Warmup timer.", 0, true, 0.0);
	g_cvWarmupMaxTime = CreateConVar("sm_warmuptime_max", "-1", "Maximum warmup timer [-1 = Disabled]");
	g_cvForceTeam = CreateConVar("sm_warmupteam", "1", "Force the player to join the counterterrorist team", 0, true, 0.0, true, 1.0);
	g_cvPlayersRatio = CreateConVar("sm_warmupratio", "0.60", "Ratio of connected players that need to be in game to start warmup timer.", 0, true, 0.0, true, 1.0);
	g_cvCleanOnWarmupEnd = CreateConVar("sm_warmup_slay", "0", "Slay all players at the end of the warmup round. [0 = Disabled | 1 = Enabled | 2 = Enabled + Clean temporary entities]", 0, true, 0.0, true, 2.0);
	g_cvAliveTeamChange = CreateConVar("sm_teammanager_aliveteamchange", "1", "Determines if players are allowed to change teams while they're alive. [0 = Dissalow | 1 = Allow]", 0, true, 0.0, true, 1.0);

	/* Dynamic based on map size*/
	g_cvDynamic = CreateConVar("sm_warmuptime_dynamic", "0", "Dynamic warmup timer based on map size. [0 Disabled | 1 = Enabled]", 0, true, 0.0, true, 1.0);
	g_cvDynamicRatio = CreateConVar("sm_warmup_dynamic_ratio", "50", "Ratio per Megabyte (MiB) based on map size.", 0, true, 1.0);
	g_cvDynamicTime = CreateConVar("sm_warmuptime_dynamic_ratio_time", "5", "Additional time in seconds to add to the dynamic warmup timer. [Based on the dynamic ratio]");

	g_cvWarmup.AddChangeHook(WarmupSystem);
	AutoExecConfig(true);
}

public void OnPluginEnd()
{
	if (g_hEntitiesListToKill != null)
		delete g_hEntitiesListToKill;
}

public void OnAllPluginsLoaded()
{
	g_bZombieReloaded = LibraryExists("zombiereloaded");
}

public void OnLibraryAdded(const char[] szName)
{
	if (strcmp(szName, "zombiereloaded") == 0)
		g_bZombieReloaded = true;
}

public void OnLibraryRemoved(const char[] szName)
{
	if (strcmp(szName, "zombiereloaded") == 0)
		g_bZombieReloaded = false;
}

public void WarmupSystem(ConVar convar, const char[] oldValue, const char[] newValue)
{
	InitWarmup();
}

public void InitWarmup()
{
	g_iWarmup = 0;
	g_bWarmup = false;
	g_bRoundEnded = false;
	g_bBlockRespawn = false;
	g_bZombieSpawned = false;

	if (g_cvDynamic.IntValue > 0)
	{
		// Convert the map size fromn bytes to megabytes.
		int iMapSize = (GetCurrentMapSize() / 1048576);
		if (iMapSize < 1)
			g_cvDynamic.IntValue = 0; // Invalid map size, disable dynamic warmup.
		else
		{
			// Ensure the dynamic ratio is between 1 and map size.
			if (g_cvDynamicRatio.IntValue < 1)
				g_cvDynamicRatio.IntValue = 1;
		
			if (g_cvDynamicRatio.IntValue > iMapSize)
				g_cvDynamicRatio.IntValue = iMapSize;

			// Ratio of additional warmup time per Megabyte (MiB) based on map size.
			int iDynamicTime = iMapSize / g_cvDynamicRatio.IntValue;

			// Additional time in seconds to add to the dynamic warmup timer. [Based on the dynamic ratio]
			g_iDynamicWarmupTime = iDynamicTime * g_cvDynamicTime.IntValue;
		}
	}

	// Prevent the warmup timer from being longer than the maximum warmup time.
	if (g_cvWarmupMaxTime.IntValue >= 0 && g_cvWarmuptime.IntValue > g_cvWarmupMaxTime.IntValue)
		g_cvWarmuptime.IntValue = g_cvWarmupMaxTime.IntValue;

	// Prevent the dynamic warmup timer from being shorter than the default warmup time.
	if (g_iDynamicWarmupTime < g_cvWarmuptime.IntValue)
		g_iDynamicWarmupTime = g_cvWarmuptime.IntValue;

	// Prevent surpassing the maximum warm-up time
	if (g_cvWarmupMaxTime.IntValue >= 0 && g_iDynamicWarmupTime > g_cvWarmupMaxTime.IntValue)
		g_iDynamicWarmupTime = g_cvWarmupMaxTime.IntValue;

	if (g_cvWarmup.BoolValue && (g_cvWarmuptime.IntValue > 0 || g_cvPlayersRatio.FloatValue > 0.0 || g_cvDynamic.IntValue > 0))
	{
		g_bWarmup = true;
		CreateTimer(1.0, OnWarmupTimer, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnMapStart()
{
	InitWarmup();
}

public void OnMapEnd()
{
	if (g_hEntitiesListToKill != null)
		delete g_hEntitiesListToKill;

	g_hEntitiesListToKill = new StringMap();
}

public Action OnWarmupTimer(Handle timer)
{
	if (!g_bWarmup)
		return Plugin_Stop;


	if (g_cvPlayersRatio.FloatValue > 0.0)
	{
		int ClientsConnected = GetClientCount(false);
		int ClientsInGame = GetClientCount(true);
		int ClientsNeeded = RoundToCeil(float(ClientsConnected) * g_cvPlayersRatio.FloatValue);
		ClientsNeeded = ClientsNeeded > MIN_PLAYERS ? ClientsNeeded : MIN_PLAYERS;

		if(ClientsInGame < ClientsNeeded)
		{
			g_iWarmup = 0;
			PrintCenterTextAll("Warmup: Waiting for %d more players to join.", ClientsNeeded - ClientsInGame);
			return Plugin_Continue;
		}
	}

	int iTime = (g_cvDynamic.IntValue != 0) ? g_iDynamicWarmupTime : g_cvWarmuptime.IntValue;

	if (g_iWarmup >= iTime)
	{
		EndWarmUp();
		return Plugin_Stop;
	}

	PrintCenterTextAll("Warmup: %d", iTime - g_iWarmup);
	g_iWarmup++;

	return Plugin_Continue;
}

stock void EndWarmUp()
{
	g_iWarmup = 0;
	g_bWarmup = false;
	float fDelay = 3.0;

	int iCleanMode = g_cvCleanOnWarmupEnd.IntValue;

	if (iCleanMode == 2)
	{
		bool dummy;
		char sClassname[64];
		int iMaxEntities = GetMaxEntities();

		for (int entities = 0; entities <= iMaxEntities; entities++)
		{
			if (!IsValidEntity(entities))
				continue;

			GetEntityClassname(entities, sClassname, sizeof(sClassname));

			if (g_hEntitiesListToKill != null && g_hEntitiesListToKill.GetValue(sClassname, dummy))
				AcceptEntityInput(entities, "Kill");
		}
	}

	if (iCleanMode >= 1)
		CreateTimer(0.3, Timer_ForceSuicide, _, TIMER_FLAG_NO_MAPCHANGE);

	CS_TerminateRound(fDelay, CSRoundEnd_GameStart, false);
	SetTeamScore(CS_TEAM_CT, 0);
	CS_SetTeamScore(CS_TEAM_CT, 0);
	SetTeamScore(CS_TEAM_T, 0);
	CS_SetTeamScore(CS_TEAM_T, 0);
	CreateTimer(fDelay, Timer_FireForward, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ForceSuicide(Handle timer)
{
	g_bBlockRespawn = true;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
			ForcePlayerSuicide(i);
	}
	g_bBlockRespawn = false;

	return Plugin_Handled;
}

public Action Timer_FireForward(Handle hThis)
{
	Call_StartForward(g_hWarmupEndFwd);
	Call_Finish();
	return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
	g_TeamChangeQueue[client] = -1;
}

public Action OnJoinTeamCommand(int client, const char[] command, int argc)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !g_cvForceTeam.BoolValue)
		return Plugin_Continue;

	int CurrentTeam = GetClientTeam(client);

	if(strcmp(command, "joingame", false) == 0)
	{
		if(CurrentTeam != CS_TEAM_NONE)
			return Plugin_Continue;

		ShowVGUIPanel(client, "team");
		return Plugin_Handled;
	}

	char sArg[8];
	GetCmdArg(1, sArg, sizeof(sArg));
	int NewTeam = StringToInt(sArg);

	if(NewTeam < CS_TEAM_NONE || NewTeam > CS_TEAM_CT)
		return Plugin_Handled;

	if(g_bRoundEnded)
	{
		if(NewTeam == CS_TEAM_T || NewTeam == CS_TEAM_NONE)
			NewTeam = CS_TEAM_CT;

		if(NewTeam == CurrentTeam)
		{
			if(g_TeamChangeQueue[client] != -1)
			{
				g_TeamChangeQueue[client] = -1;
				PrintCenterText(client, "Team change request canceled.");
			}
			return Plugin_Handled;
		}

		g_TeamChangeQueue[client] = NewTeam;
		PrintCenterText(client, "You will be placed in the selected team shortly.");
		return Plugin_Handled;
	}

	if(g_bZombieReloaded)
	{
		if(!g_bZombieSpawned && NewTeam == CS_TEAM_T || NewTeam == CS_TEAM_NONE)
			NewTeam = CS_TEAM_CT;

		else if(g_bZombieSpawned && NewTeam == CS_TEAM_SPECTATOR)
			return Plugin_Handled;
	}
	else if(NewTeam == CS_TEAM_CT || NewTeam == CS_TEAM_NONE)
		NewTeam = CS_TEAM_T;

	if(NewTeam == CurrentTeam)
		return Plugin_Handled;

	// Prevent players from changing team if they are already in a team (CT or T)
	if(!g_cvAliveTeamChange.BoolValue && IsPlayerAlive(client) && NewTeam >= 0 && (CurrentTeam == CS_TEAM_T || CurrentTeam == CS_TEAM_CT))
		return Plugin_Handled;

	ChangeClientTeam(client, NewTeam);

	return Plugin_Handled;
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = false;
	g_bZombieSpawned = false;

	if (!g_cvForceTeam.BoolValue)
		return;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client))
			continue;

		int CurrentTeam = GetClientTeam(client);
		int NewTeam = CS_TEAM_CT;

		if(g_TeamChangeQueue[client] != -1)
		{
			NewTeam = g_TeamChangeQueue[client];
			g_TeamChangeQueue[client] = -1;
		}
		else if(CurrentTeam <= CS_TEAM_SPECTATOR)
			continue;

		if(NewTeam == CurrentTeam)
			continue;

		if(NewTeam >= CS_TEAM_T)
			CS_SwitchTeam(client, NewTeam);
		else
			ChangeClientTeam(client, NewTeam);

		if(NewTeam >= CS_TEAM_T && !IsPlayerAlive(client))
			CS_RespawnPlayer(client);
	}
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = true;
	g_bBlockRespawn = false;
	g_bZombieSpawned = false;
}

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	if(g_bWarmup && g_cvWarmup.BoolValue)
		return Plugin_Handled;

	return Plugin_Continue;
}

#if defined _zr_included
public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
	if (motherInfect)
		g_bZombieSpawned = true;
}

public Action ZR_OnClientRespawn(int &client, ZR_RespawnCondition& condition)
{
	if(g_bBlockRespawn)
	{
		CPrintToChat(client, "Warmup: Warmup is ending. You will respawn shortly.");
		return Plugin_Handled;
	}

	return Plugin_Continue;
}
#endif

public int Native_HasWarmup(Handle hPlugin, int numParams)
{
	return g_cvWarmup.BoolValue;
}

public int Native_InWarmup(Handle hPlugin, int numParams)
{
	return g_bWarmup;
}

stock void InitStringMap()
{
	char sSafeEntitiesToKill[][] = {
		"env_beam", "env_entity_maker", "env_explosion", "env_fade", "env_shake", "env_spark", "env_sprite",
		"func_breakable", "func_button", "func_door", "func_door_rotating", "func_movelinear", "func_physbox", "func_physbox_multiplayer", "func_reflective_glass", "func_rotating",
		"game_text",
		"info_particle_system", "info_teleport_destination",
		"phys_keepupright", "phys_thruster",
		"point_hurt", "point_spotlight", "point_teleport",
		"prop_dynamic", "prop_dynamic_override", "prop_physics", "prop_physics_multiplayer", "prop_physics_override",
		"trigger_hurt", "trigger_multiple", "trigger_once", "trigger_push", "trigger_teleport",
		"weapon_glock", "weapon_usp", "weapon_deagle", "weapon_elite", "weapon_p228", "weapon_fiveseven",
		"weapon_m3", "weapon_xm1014",
		"weapon_mac10", "weapon_tmp", "weapon_mp5navy", "weapon_ump45", "weapon_p90",
		"weapon_galil", "weapon_famas", "weapon_ak47", "weapon_m4a1", "weapon_sg552", "weapon_aug",
		"weapon_scout", "weapon_sg550", "weapon_g3sg1", "weapon_awp",
		"weapon_m249", "weapon_knife", "weapon_c4", 
		"weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade", "item_nvgs", "item_kevlar"
	};

	if (g_hEntitiesListToKill == null)
		g_hEntitiesListToKill = new StringMap();

	for (int i = 0; i < sizeof(sSafeEntitiesToKill); i++)
	{
		g_hEntitiesListToKill.SetValue(sSafeEntitiesToKill[i], true);
	}
}
