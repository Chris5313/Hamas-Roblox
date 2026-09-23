# HamasClient — Roblox

Fluent-based script suite: Hamas green/black theme, pooled Drawing ESP engine, debug console, SaveManager configs.

## Loadstring

**AOT Revolution**
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/AOTRevolution.lua", true))()
```

**Island Tribes**
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/IslandTribes.lua", true))()
```

Works on any executor with `loadstring` + `game:HttpGet` (tested on Synapse Z).
If the module files already exist in the executor workspace they're used as-is; otherwise they're fetched from this repo and cached locally.

## Layout

| File | What it is |
|---|---|
| `loader.lua` | Module resolver (workspace readfile → GitHub raw fallback) |
| `HamasBase.lua` | Window + Hamas theme + tabs + logo + debug console + SaveManager |
| `HamasESP.lua` | Game-agnostic Drawing ESP engine (category registry, per-class pool, zombie sweep, Panic) |
| `HamasDebug.lua` | In-menu console tab (logs, Lua exec, copy-log) |
| `AOTRevolution.lua` / `IslandTribes.lua` | Game scripts |
| `assets/` | Logo images |

## Dev workflow

Source of truth is the organized tree (`../scripts/`). To publish changes:
```bash
bash ../sync_and_push.sh   # mirrors to this flat layout and pushes to main
```
