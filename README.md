# Celeste-Style Platformer Engine

## Folder Structure

```
celeste_game/
├── main.lua           -- Entry point, handles game loop & scaling
├── conf.lua           -- LÖVE configuration (window, vsync)
├── run.bat            -- Windows launcher
│
├── src/
│   ├── core/
│   │   ├── game.lua   -- Main game logic, physics, transitions
│   │   └── input.lua  -- Input handling with buffering
│   │
│   ├── world/
│   │   └── map.lua    -- Room/tile management, serialization
│   │
│   ├── editor/
│   │   └── editor.lua -- Level editor
│   │
│   └── ui/
│       └── menu.lua   -- Main menu & settings
│
└── assets/            -- (add your tilesets/sprites here)
    ├── tilesets/
    └── sprites/
```

## Key Fixes

### 1. Stuttering Fixed
- Proper accumulator-based fixed timestep (no more `love.timer.sleep()`)
- Player position interpolation for smooth rendering
- VSync enabled (works WITH fixed timestep, not against it)

### 2. Room Transitions
- **Fade out → teleport → fade in** instead of smooth camera pan
- No auto-walk during transitions
- Instant and clean

### 3. Camera for Small Rooms
- Small rooms are centered in camera view
- Never shows void/out-of-bounds
- Scissor clipping ensures only room area is drawn

### 4. Collision
- Pixel-by-pixel movement (Celeste-accurate)
- Depenetration if stuck
- Subpixel remainder tracking

## Controls

| Key | Action |
|-----|--------|
| Arrow Keys / WASD | Move |
| Z / Space | Jump |
| C / Ctrl | Grab (climb walls) |
| Down / S | Crouch |
| TAB | Toggle Editor |
| ESC | Menu |

## Editor Controls

| Key | Action |
|-----|--------|
| 1-4 | Select tool (Select/Tile/Spawn/Hazard) |
| Q/E | Cycle tile type |
| R | Cycle hazard type |
| N | New room at cursor |
| Delete | Delete selected room |
| F5 | Save world |
| F9 | Load world |
| RMB/MMB | Pan camera |
| Scroll | Zoom |

## Why These Changes?

### Previous Stuttering Cause
The old code used `love.timer.sleep()` to cap framerate, which:
- Is imprecise (OS scheduler variance)
- Fights with vsync
- Causes frame timing jitter

### New Approach
```lua
-- Accumulator collects real time
accumulator = accumulator + dt

-- Physics runs at fixed 60Hz regardless of render rate
while accumulator >= FIXED_DT do
    -- Update physics
    accumulator = accumulator - FIXED_DT
end

-- Render with interpolation for smoothness
local alpha = accumulator / FIXED_DT
drawX = prevX + (currentX - prevX) * alpha
```

This is the industry-standard "Fix Your Timestep" approach.
