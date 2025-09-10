# GitHub Copilot Instructions for TeamManager SourcePawn Plugin

## Repository Overview

This repository contains **TeamManager**, a SourcePawn plugin for SourceMod that manages team assignments and warmup rounds in Source engine games. The plugin provides intelligent team balancing, configurable warmup systems, and special integration with zombie-themed game modes.

### Key Features
- **Warmup System**: Configurable warmup rounds with player ratio requirements and dynamic timing
- **Team Management**: Automatic team assignment (CT/T) based on game mode and conditions
- **ZombieReloaded Integration**: Special handling for zombie survival game modes
- **Dynamic Warmup**: Map size-based warmup duration adjustment
- **Native API**: Provides functions for other plugins to interact with warmup states

## Development Environment

### Required Tools
- **SourceMod 1.12+**: Latest stable release required
- **SourceKnight 0.2**: Python-based build system for SourceMod plugins (exact version specified in sourceknight.yaml)
- **Python 3.x**: Required for sourceknight build tool

### Dependencies (Managed by SourceKnight)
```yaml
# From sourceknight.yaml
- sourcemod: 1.11.0-git6934 (build dependency)
- zombiereloaded: GitHub integration for zombie game modes
- utilshelper: Utility functions library
- multicolors: Enhanced chat color support
```

## Project Structure

```
addons/sourcemod/
├── scripting/
│   ├── TeamManager.sp           # Main plugin file (443 lines)
│   └── include/
│       └── TeamManager.inc      # Native functions API (44 lines)
sourceknight.yaml                # Build configuration
.github/
├── workflows/ci.yml             # CI/CD pipeline
└── dependabot.yml              # Dependency updates
```

## SourcePawn Coding Standards

### Style Guide (Enforced in this codebase)
```sourcepawn
#pragma semicolon 1              // Always used
#pragma newdecls required        // Modern syntax required

// Variable naming conventions
bool g_bWarmup = false;          // Global boolean: g_b prefix
int g_iWarmup = 0;               // Global integer: g_i prefix  
Handle g_hWarmupEndFwd;          // Global handle: g_h prefix
ConVar g_cvWarmup;               // Global ConVar: g_cv prefix

// Function naming
public void OnPluginStart()      // PascalCase for public functions
stock void EndWarmUp()           // PascalCase for stock functions
int ClientsNeeded = RoundToCeil  // PascalCase for local variables
```

### Memory Management Patterns
```sourcepawn
// Proper StringMap usage (follows repository conventions)
StringMap g_hEntitiesListToKill;

// Initialization
g_hEntitiesListToKill = new StringMap();

// Cleanup (no null check needed before delete)
delete g_hEntitiesListToKill;
g_hEntitiesListToKill = new StringMap(); // Create new after delete

// NEVER use .Clear() - creates memory leaks
// ALWAYS use delete + new StringMap()
```

### Event-Based Programming Patterns
```sourcepawn
// Standard event hooks used in this plugin
HookEvent("round_start", OnRoundStart, EventHookMode_Pre);
HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

// Command listeners
AddCommandListener(OnJoinTeamCommand, "jointeam");

// ConVar change hooks
g_cvWarmup.AddChangeHook(WarmupSystem);

// Timers with proper flags
CreateTimer(1.0, OnWarmupTimer, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
```

## Build System (SourceKnight)

### Build Commands
```bash
# Install sourceknight (exact version from sourceknight.yaml)
pip install sourceknight==0.2

# Build plugin
sourceknight build

# Output location
addons/sourcemod/plugins/TeamManager.smx
```

### Build Configuration Validation
```bash
# Verify configuration is valid
cat sourceknight.yaml

# Check target plugin exists
ls -la addons/sourcemod/scripting/TeamManager.sp

# Validate dependencies are correctly specified
grep -A 20 "dependencies:" sourceknight.yaml
```

### CI/CD Pipeline
- **Trigger**: Push to main/master, PRs, tags
- **Build**: Ubuntu 24.04 with sourceknight
- **Artifacts**: Packaged plugin files
- **Release**: Automatic releases on tags and latest on main/master

## Key Plugin Architecture

### Main Plugin Lifecycle
```sourcepawn
// Core initialization functions
public APLRes AskPluginLoad2()    // Native registration, forwards
public void OnPluginStart()      // Event hooks, ConVars, commands
public void OnPluginEnd()        // Cleanup StringMaps
public void OnMapStart()         // Initialize warmup system
public void OnMapEnd()           // Clean temporary entities
```

### Warmup System Flow
1. **Initialization**: `InitWarmup()` sets up timers and variables
2. **Timer Loop**: `OnWarmupTimer()` manages countdown and player checks
3. **End Warmup**: `EndWarmUp()` triggers cleanup and round restart
4. **Forward Call**: `TeamManager_WarmupEnd()` notifies other plugins

### Team Management Logic
```sourcepawn
// Team assignment based on game mode
if(g_bZombieReloaded) {
    // Zombie mode: Humans = CT, Zombies = T
    if(!g_bZombieSpawned && NewTeam == CS_TEAM_T)
        NewTeam = CS_TEAM_CT;
} else {
    // Standard mode: Players = T
    if(NewTeam == CS_TEAM_CT)
        NewTeam = CS_TEAM_T;
}
```

## Integration Points

### ZombieReloaded Plugin Integration
```sourcepawn
#tryinclude <zombiereloaded>  // Optional dependency

// Conditional compilation
#if defined _zr_included
public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, ...)
public Action ZR_OnClientRespawn(int &client, ZR_RespawnCondition& condition)
#endif

// Runtime detection
g_bZombieReloaded = LibraryExists("zombiereloaded");
```

### Native API for Other Plugins
```sourcepawn
// Exported functions (see TeamManager.inc)
native bool TeamManager_HasWarmup();   // Check if warmup is enabled
native bool TeamManager_InWarmup();    // Check current warmup status
forward void TeamManager_WarmupEnd();  // Called when warmup ends
```

## Common Development Tasks

### Adding New ConVars
```sourcepawn
// In OnPluginStart()
ConVar g_cvNewFeature = CreateConVar(
    "sm_teammanager_newfeature", 
    "1", 
    "Description of new feature", 
    0, true, 0.0, true, 1.0
);

// Add change hook if needed
g_cvNewFeature.AddChangeHook(OnNewFeatureChanged);

// Don't forget AutoExecConfig(true) at end of OnPluginStart()
```

### Modifying Team Logic
- **Location**: `OnJoinTeamCommand()` function
- **Key Variables**: `CurrentTeam`, `NewTeam`, `g_bZombieReloaded`, `g_bZombieSpawned`
- **Testing**: Ensure compatibility with both ZR and standard CS modes

### Adding Temporary Entities for Cleanup
```sourcepawn
// In InitStringMap() function
char sSafeEntitiesToKill[][] = {
    "your_entity_classname",
    // ... existing entities
};

// System automatically cleans these during warmup end
```

## Testing and Validation

### Manual Testing Checklist
- [ ] Warmup timer functions correctly
- [ ] Team assignment works in both ZR and standard modes
- [ ] Player ratio requirements enforced
- [ ] Dynamic warmup timing based on map size
- [ ] Entity cleanup during warmup end
- [ ] Native functions accessible to other plugins

### Build Validation
```bash
# Check compilation
sourceknight build

# Verify output
ls -la addons/sourcemod/plugins/TeamManager.smx

# Check file size (should be reasonable, not empty)
stat addons/sourcemod/plugins/TeamManager.smx
```

## Troubleshooting Common Issues

### Build Failures
- **Missing dependencies**: Check sourceknight.yaml dependency versions
- **Syntax errors**: Ensure `#pragma semicolon 1` and `#pragma newdecls required`
- **Include issues**: Verify all `#include` statements resolve correctly

### Runtime Issues
- **Team switching problems**: Check `g_cvForceTeam` and `g_cvAliveTeamChange` settings
- **Warmup not starting**: Verify `g_cvWarmup`, `g_cvWarmuptime`, and player ratios
- **Memory leaks**: Ensure StringMap cleanup in `OnPluginEnd()` and `OnMapEnd()`

### Integration Issues
- **ZombieReloaded conflicts**: Check `g_bZombieReloaded` detection and conditional compilation
- **Native function errors**: Verify `RegPluginLibrary("TeamManager")` is called

## Performance Considerations

### Optimization Guidelines
- **Timer frequency**: 1-second intervals for warmup (avoid sub-second for UI updates)
- **Entity iteration**: Limited to warmup end cleanup only
- **String operations**: Minimal in frequently called functions
- **Team checks**: Cached boolean states (`g_bZombieSpawned`, `g_bRoundEnded`)

### Memory Management
- **StringMap lifecycle**: Create once, delete + recreate instead of Clear()
- **Timer cleanup**: Automatic with `TIMER_FLAG_NO_MAPCHANGE`
- **Handle management**: All handles properly closed in cleanup functions

## Version Management

- **Current Version**: 2.3.0 (see plugin info block)
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Release Process**: Automatic via GitHub Actions on tags
- **Compatibility**: SourceMod 1.12+ required (check sourceknight.yaml for exact versions)

---

## Quick Reference Commands

```bash
# Build plugin
sourceknight build

# Development dependencies
pip install sourceknight

# Plugin output
./addons/sourcemod/plugins/TeamManager.smx

# Include file for other plugins
./addons/sourcemod/scripting/include/TeamManager.inc
```

This plugin is production-ready and follows established SourcePawn conventions. When making changes, prioritize backward compatibility and thorough testing with both zombie and standard game modes.