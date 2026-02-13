-- Enhanced Mario-like 2D prototype with sprite + sound support
-- Controls: ←/A and →/D to move, Z/Space to jump, X or LShift to run, R to restart

local TILE = 32
local GRAVITY = 1600

local player = {}
local level = {}
local camera = {x = 0, y = 0}

local blocks = {}      -- question blocks, bricks
local mushrooms = {}   -- active power-ups
local enemies = {}
local coins = {}
local piranha_plants = {}
local bullets = {}
local boss = nil -- Will hold the single boss object
local spikes = {}
local endPipe = nil
local smoke_particles = {}

local hud = {score = 0, coins = 0, lives = 3, totalCoins = 0}

local assets = {}

local gameState = "playing" -- "playing", "win", "pipe_transition"
local transition = {active = false, timer = 0, duration = 1.5, alpha = 0, onComplete = nil}


-- safe asset loader: returns nil if missing
local function tryLoadImage(path)
    if love.filesystem.getInfo(path) then
        return love.graphics.newImage(path)
    end
    return nil
end
local function tryLoadSource(path, mode)
    if love.filesystem.getInfo(path) then
        return love.audio.newSource(path, mode)
    end
    return nil
end

-- helpers to add world objects
function addQuestionBlock(tx, ty, content)
    table.insert(blocks, {type="question", tx=tx, ty=ty, used=false, content = content or "item"})
end
function addBrick(tx, ty)
    table.insert(blocks, {type="brick", tx=tx, ty=ty, used=false, broken=false})
end
function addCoin(tx, ty)
    table.insert(coins, {tx=tx, ty=ty, taken=false})
end
function addSpike(tx, ty)
    table.insert(spikes, {tx=tx, ty=ty})
end
function addEnemy(x,y)
    table.insert(enemies, {x=x, y=y, w=32, h=24, dir=-1, speed=60, alive=true, vy=0})
end
function addPiranhaPlant(tx, ty)
    -- state: 0=down, 1=rising, 2=up, 3=sinking. timer controls state changes.
    table.insert(piranha_plants, {tx=tx, ty=ty, w=24, h=32, state=0, timer=math.random(2,4), y_offset=32})
end
function addBoss(x, y)
    boss = {x=x, y=y, w=64, h=64, vx=0, vy=0, dir=-1, speed=80, hp=5, max_hp=5, alive=true, patrol_left=181*TILE, patrol_right=199*TILE, is_boss=true}
end

function love.load()
    math.randomseed(os.time())

    -- try to load assets (place your files into `assets/` folder)
    assets.player = tryLoadImage("assets/player.png") -- the sprite you attached
    assets.background = tryLoadImage("assets/background.png")
    assets.music = tryLoadSource("assets/music.ogg", "stream") -- looped background music
    assets.sfx_jump = tryLoadSource("assets/jump.wav", "static")
    assets.sfx_coin = tryLoadSource("assets/coin.wav", "static")
    assets.sfx_block = tryLoadSource("assets/block.wav", "static")
    assets.enemy = tryLoadImage("assets/enemy.png")
    assets.mushroom_red = tryLoadImage("assets/mushroom_red.png")
    assets.piranha_plant = tryLoadImage("assets/piranha_plant.png")
    assets.gun = tryLoadImage("assets/gun.png")
    assets.boss = tryLoadImage("assets/boss.png")
    assets.mushroom_green = tryLoadImage("assets/mushroom_green.png")

    if assets.music then
        -- handle smoother looping by disabling builtin loop and using crossfade between two sources
        assets.music:setLooping(false)
        assets.music:setVolume(0.6)
        assets.music:play()
        assets.musicAlt = tryLoadSource("assets/music.ogg", "stream")
        if assets.musicAlt then
            assets.musicAlt:setLooping(false)
            assets.musicAlt:setVolume(0)
        end
        assets.musicFadeTime = 0.8
        assets.musicCrossfading = false
        assets.musicCurrent = assets.music
        assets.musicNext = assets.musicAlt
    else
        print("[info] assets/music.ogg not found. Add your background music file to assets/ if you want music.")
    end

    -- If assets are missing, synthesize simple fallback music and SFX so the game has audio.
    local function makeSoundData(durationSeconds, sampleRate)
        sampleRate = sampleRate or 44100
        local samples = math.floor(durationSeconds * sampleRate)
        return love.sound.newSoundData(samples, sampleRate, 16, 1)
    end

    local function appendWave(sd, startSample, freq, dur, volume, waveType)
        local sr = sd:getSampleRate()
        local samples = math.floor(dur * sr)
        for i=0,samples-1 do
            local t = i / sr
            local v = 0
            local phase = 2 * math.pi * freq * t
            if waveType == 'square' then
                v = (math.sin(phase) >= 0) and 1 or -1
            else
                v = math.sin(phase)
            end
            sd:setSample(startSample + i, v * volume)
        end
    end

    -- create simple chiptune loop if music missing
    if not assets.music then
        -- generate a longer 24-second chiptune loop
        local sd = makeSoundData(24) -- 24 second loop
        local sr = sd:getSampleRate()
        local totalSamples = sd:getSampleCount()
        
        -- extended chiptune pattern: longer melodic progression
        local notes = {
            -- section 1: main theme
            {freq=523.25, dur=0.5},  -- C5
            {freq=659.25, dur=0.5},  -- E5
            {freq=783.99, dur=0.5},  -- G5
            {freq=987.77, dur=0.5},  -- B5
            {freq=783.99, dur=0.5},  -- G5
            {freq=659.25, dur=0.5},  -- E5
            {freq=587.33, dur=0.5},  -- D5
            {freq=523.25, dur=1.0},  -- C5
            -- section 2: variation A
            {freq=587.33, dur=0.5},  -- D5
            {freq=739.99, dur=0.5},  -- F#5
            {freq=880.00, dur=0.5},  -- A5
            {freq=987.77, dur=0.5},  -- B5
            {freq=880.00, dur=0.5},  -- A5
            {freq=739.99, dur=0.5},  -- F#5
            {freq=587.33, dur=0.5},  -- D5
            {freq=659.25, dur=1.0},  -- E5
            -- section 3: lower register
            {freq=392.00, dur=0.5},  -- G4
            {freq=440.00, dur=0.5},  -- A4
            {freq=493.88, dur=0.5},  -- B4
            {freq=523.25, dur=0.5},  -- C5
            {freq=493.88, dur=0.5},  -- B4
            {freq=440.00, dur=0.5},  -- A4
            {freq=392.00, dur=0.5},  -- G4
            {freq=349.23, dur=1.0},  -- F4
            -- section 4: ascending climax
            {freq=523.25, dur=0.25}, -- C5
            {freq=587.33, dur=0.25}, -- D5
            {freq=659.25, dur=0.25}, -- E5
            {freq=739.99, dur=0.25}, -- F#5
            {freq=830.61, dur=0.25}, -- G#5
            {freq=987.77, dur=0.25}, -- B5
            {freq=1046.50, dur=0.5}, -- C6
            {freq=987.77, dur=0.5},  -- B5
            -- section 5: descending outro
            {freq=880.00, dur=0.5},  -- A5
            {freq=783.99, dur=0.5},  -- G5
            {freq=659.25, dur=0.5},  -- E5
            {freq=587.33, dur=0.5},  -- D5
            {freq=523.25, dur=0.5},  -- C5
            {freq=440.00, dur=0.5},  -- A4
            {freq=392.00, dur=1.0},  -- G4
            {freq=349.23, dur=1.0},  -- F4
        }
        
        local samplePos = 0
        for _, note in ipairs(notes) do
            local noteSamples = math.floor(note.dur * sr)
            -- only write if we have room
            if samplePos + noteSamples <= totalSamples then
                appendWave(sd, samplePos, note.freq, note.dur, 0.15, 'square')
                samplePos = samplePos + noteSamples
            end
        end
        
        local src = love.audio.newSource(sd, 'static')
        src:setLooping(false)
        src:setVolume(0.5)
        assets.music = src
        assets.music:play()
        -- create alternate copy from same SoundData for crossfade
        local src2 = love.audio.newSource(sd, 'static')
        src2:setLooping(false)
        src2:setVolume(0)
        assets.musicAlt = src2
        assets.musicFadeTime = 0.8
        assets.musicCrossfading = false
        assets.musicCurrent = assets.music
        assets.musicNext = assets.musicAlt
    end

    -- create small blip SFX if missing
    if not assets.sfx_jump then
        local sd = makeSoundData(0.25)
        appendWave(sd, 0, 880, 0.15, 0.6, 'square')
        assets.sfx_jump = love.audio.newSource(sd, 'static')
    end
    if not assets.sfx_coin then
        local sd = makeSoundData(0.18)
        appendWave(sd, 0, 1100, 0.12, 0.6, 'square')
        assets.sfx_coin = love.audio.newSource(sd, 'static')
    end
    if not assets.sfx_block then
        local sd = makeSoundData(0.2)
        appendWave(sd, 0, 660, 0.12, 0.5, 'square')
        assets.sfx_block = love.audio.newSource(sd, 'static')
    end

    -- if player sprite missing, create a simple pixel-art fallback (approximate)
    if not assets.player then
        local w,h = 32,48
        local img = love.image.newImageData(w,h)
        -- fill transparent
        for yy=0,h-1 do for xx=0,w-1 do img:setPixel(xx,yy,0,0,0,0) end end
        local function px(x,y,r,g,b,a)
            img:setPixel(x,y,r/255,g/255,b/255,a/255)
        end
        -- hat (red)
        for yy=2,7 do for xx=6,25 do px(xx,yy,200,20,20,255) end end
        -- head (skin)
        for yy=8,18 do for xx=8,20 do px(xx,yy,245,205,160,255) end end
        -- hair (brown)
        for yy=10,13 do for xx=5,8 do px(xx,yy,120,60,20,255) end end
        -- shirt (red)
        for yy=19,28 do for xx=6,26 do px(xx,yy,200,20,20,255) end end
        -- overalls (blue)
        for yy=26,40 do for xx=8,24 do px(xx,yy,50,60,200,255) end end
        -- boots (brown)
        for yy=40,46 do for xx=6,12 do px(xx,yy,100,50,20,255) end end
        for yy=40,46 do for xx=18,24 do px(xx,yy,100,50,20,255) end end
        assets.player = love.graphics.newImage(img)
    end

    -- if enemy sprite missing, create a simple pixel-art Goomba-like fallback
    if not assets.enemy then
        local w,h = 20,20
        local img = love.image.newImageData(w,h)
        -- fill transparent
        for yy=0,h-1 do for xx=0,w-1 do img:setPixel(xx,yy,0,0,0,0) end end
        local function px(x,y,r,g,b,a)
            if x >= 0 and x < w and y >= 0 and y < h then
                img:setPixel(x,y,r/255,g/255,b/255,a/255)
            end
        end
        -- Head (brown)
        for yy=3,10 do for xx=2,17 do px(xx,yy,139,69,19,255) end end
        for yy=4,5 do for xx=3,16 do px(xx,yy,160,82,45,255) end end
        -- Body (beige)
        for yy=11,17 do for xx=4,15 do px(xx,yy,245,222,179,255) end end
        -- Eyes (black with white)
        px(6,8,0,0,0,255); px(7,8,0,0,0,255); px(8,8,255,255,255,255)
        px(11,8,255,255,255,255); px(12,8,0,0,0,255); px(13,8,0,0,0,255)
        -- Feet (dark brown)
        for yy=18,19 do for xx=3,7 do px(xx,yy,0x8B,57,42,255) end end
        for yy=18,19 do for xx=12,16 do px(xx,yy,0x8B,57,42,255) end end
        assets.enemy = love.graphics.newImage(img)
    end

    -- if mushroom sprites missing, create simple pixel-art fallbacks
    local function createMushroomSprite(r,g,b)
        local w,h = 16,16
        local img = love.image.newImageData(w,h)
        -- fill transparent
        for yy=0,h-1 do for xx=0,w-1 do img:setPixel(xx,yy,0,0,0,0) end end
        local function px(x,y,cr,cg,cb,ca)
            if x >= 0 and x < w and y >= 0 and y < h then
                img:setPixel(x,y,cr/255,cg/255,cb/255,ca/255)
            end
        end
        -- Stalk (beige)
        for yy=7,15 do for xx=4,11 do px(xx,yy,245,222,179,255) end end
        -- Eyes (black)
        px(6,10,0,0,0,255); px(9,10,0,0,0,255)
        -- Cap (main color)
        px(4,1,r,g,b,255); px(5,1,r,g,b,255); px(6,1,r,g,b,255); px(7,1,r,g,b,255); px(8,1,r,g,b,255); px(9,1,r,g,b,255); px(10,1,r,g,b,255); px(11,1,r,g,b,255)
        px(2,2,r,g,b,255); px(3,2,r,g,b,255); for xx=4,11 do px(xx,2,r,g,b,255) end; px(12,2,r,g,b,255); px(13,2,r,g,b,255)
        px(1,3,r,g,b,255); for xx=2,13 do px(xx,3,r,g,b,255) end; px(14,3,r,g,b,255)
        px(1,4,r,g,b,255); for xx=2,13 do px(xx,4,r,g,b,255) end; px(14,4,r,g,b,255)
        px(1,5,r,g,b,255); for xx=2,13 do px(xx,5,r,g,b,255) end; px(14,5,r,g,b,255)
        px(1,6,r,g,b,255); for xx=2,13 do px(xx,6,r,g,b,255) end; px(14,6,r,g,b,255)
        px(2,7,r,g,b,255); px(3,7,r,g,b,255); px(12,7,r,g,b,255); px(13,7,r,g,b,255)
        -- Spots (white)
        px(8,2,255,255,255,255)
        px(4,3,255,255,255,255); px(11,3,255,255,255,255)
        px(7,5,255,255,255,255)
        return love.graphics.newImage(img)
    end

    if not assets.mushroom_red then
        assets.mushroom_red = createMushroomSprite(200, 20, 20) -- red
    end
    if not assets.mushroom_green then
        assets.mushroom_green = createMushroomSprite(30, 180, 30) -- green
    end

    -- if piranha plant sprite missing, create a simple pixel-art fallback
    if not assets.piranha_plant then
        local w,h = 24,32
        local img = love.image.newImageData(w,h)
        -- fill transparent
        for yy=0,h-1 do for xx=0,w-1 do img:setPixel(xx,yy,0,0,0,0) end end
        local function px(x,y,r,g,b,a)
            if x >= 0 and x < w and y >= 0 and y < h then
                img:setPixel(x,y,r/255,g/255,b/255,a/255)
            end
        end
        -- Head (red)
        for yy=0,10 do for xx=2,21 do px(xx,yy,255,0,0,255) end end
        -- Lips (white)
        for yy=11,13 do for xx=0,23 do px(xx,yy,255,255,255,255) end end
        -- Teeth (black lines on lips)
        px(3,11,0,0,0,255); px(7,11,0,0,0,255); px(11,11,0,0,0,255); px(15,11,0,0,0,255); px(19,11,0,0,0,255)
        -- Stem (green)
        for yy=14,20 do for xx=8,15 do px(xx,yy,0,220,0,255) end end
        -- Leaves
        for yy=16,18 do for xx=4,7 do px(xx,yy,0,220,0,255) end end
        for yy=16,18 do for xx=16,19 do px(xx,yy,0,220,0,255) end end
        assets.piranha_plant = love.graphics.newImage(img)
    end

    -- if boss sprite missing, create a simple pixel-art fallback
    if not assets.boss then
        local w,h = 64,64
        local img = love.image.newImageData(w,h)
        -- fill transparent
        for yy=0,h-1 do for xx=0,w-1 do img:setPixel(xx,yy,0,0,0,0) end end
        local function px(x,y,r,g,b,a)
            if x >= 0 and x < w and y >= 0 and y < h then
                img:setPixel(x,y,r/255,g/255,b/255,a/255)
            end
        end
        -- Body (dark green)
        for yy=10,50 do for xx=5,59 do px(xx,yy,20,100,20,255) end end
        -- Big spikes on back (yellow)
        for i=0,4 do
            local spike_y = 12 + i * 8
            px(5, spike_y+2, 255,255,0,255); px(4, spike_y+2, 255,255,0,255)
            px(3, spike_y+1, 255,255,0,255); px(2, spike_y, 255,255,0,255)
        end
        -- Eyes (red on yellow)
        for yy=15,20 do for xx=45,55 do px(xx,yy,255,255,0,255) end end
        for yy=16,19 do for xx=48,52 do px(xx,yy,255,0,0,255) end end
        -- Feet (dark grey)
        for yy=51,60 do for xx=10,25 do px(xx,yy,80,80,80,255) end end
        for yy=51,60 do for xx=40,55 do px(xx,yy,80,80,80,255) end end
        assets.boss = love.graphics.newImage(img)
    end

    -- if gun sprite missing, create a simple pixel-art fallback
    if not assets.gun then
        local w,h = 24,16
        local img = love.image.newImageData(w,h)
        -- fill transparent
        for yy=0,h-1 do for xx=0,w-1 do img:setPixel(xx,yy,0,0,0,0) end end
        local function px(x,y,r,g,b,a)
            if x >= 0 and x < w and y >= 0 and y < h then
                img:setPixel(x,y,r/255,g/255,b/255,a/255)
            end
        end
        -- Body (dark grey)
        for yy=4,10 do for xx=2,20 do px(xx,yy,80,80,80,255) end end
        -- Handle (brown)
        for yy=11,14 do for xx=8,12 do px(xx,yy,139,69,19,255) end end
        -- Barrel (light grey)
        for yy=5,7 do for xx=21,23 do px(xx,yy,150,150,150,255) end end
        assets.gun = love.graphics.newImage(img)
    end

    -- nicer physics/controls
    player.x = 64
    player.y = 300
    player.w = 20
    player.h = 28
    player.vx = 0
    player.vy = 0
    player.accel = 2200
    player.friction = 12
    player.maxSpeed = 220
    player.runMultiplier = 1.5
    player.jumpPower = -760 -- increased jump power for a taller jump
    player.speedBoostActive = false
    player.speedBoostTimer = 0
    player.speedBoostDuration = 8 -- 8 seconds of speed boost from mushroom
    player.greenTimer = 0
    player.greenDuration = 10 -- green (big) lasts 10 seconds
    -- stacking counters for mushrooms
    player.redCount = 0    -- number of red (speed) mushrooms collected (stacks up to 3)
    player.greenCount = 0  -- number of green (size) mushrooms collected (stacks up to 2 -> 3x)
    player.baseW = 20
    player.baseH = 28
    -- jump tuning: buffer/coyote/variable jump
    player.jumpBufferTime = 0.16 -- seconds to buffer jump input
    player.coyoteTime = 0.16 -- seconds after leaving ground where jump still allowed
    player.jumpBuffer = 0
    player.timeSinceGround = 1
    player.onGround = false
    player.big = false
    player.hasGun = false
    player.shootTimer = 0
    player.facing = 1 -- 1 for right, -1 for left
    player.checkpoint = nil -- Will store {x, y} for respawning

    -- tile map: larger level
    local cols = 240 -- increased for longer level
    local rows = 14
    level.cols = cols
    level.rows = rows
    level.tiles = {}
    for y=1,rows do
        level.tiles[y] = {}
        for x=1,cols do
            if y >= 12 then
                level.tiles[y][x] = 1 -- ground
            else
                level.tiles[y][x] = 0
            end
        end
    end

    -- add some floating platforms for variation
    for x=50,60 do level.tiles[9][x] = 1 end
    for x=70,75 do level.tiles[8][x] = 1 end
    for x=85,95 do level.tiles[7][x] = 1 end
    for x=110,120 do level.tiles[9][x] = 1 end
    for x=130,140 do level.tiles[8][x] = 1 end
    for x=155,165 do level.tiles[7][x] = 1 end

    -- level objects: more blocks, coins, enemies
    addQuestionBlock(8, 9)
    addQuestionBlock(12, 9)
    addBrick(16, 9)
    addCoin(20, 8)
    addPiranhaPlant(22, 10)
    addSpike(25, 11)
    addEnemy(30 * TILE, (11 * TILE) - 24)
    for i=0,6 do addQuestionBlock(40 + i*2, 8) end
    
    -- section 2: more platforms
    addQuestionBlock(55, 8)
    addQuestionBlock(58, 8)
    addCoin(56, 7)
    addCoin(59, 7)
    addEnemy(52 * TILE, (9 * TILE) - 24)
    addPiranhaPlant(62, 10)
    addSpike(65, 11)
    addSpike(67, 11)
    
    -- section 3: higher platforms
    addQuestionBlock(72, 7)
    addQuestionBlock(75, 7)
    addBrick(78, 7)
    addCoin(73, 6)
    addCoin(76, 6)
    addEnemy(70 * TILE, (8 * TILE) - 24)
    addPiranhaPlant(80, 10)
    
    -- section 4: challenging sequence
    addQuestionBlock(88, 6)
    addQuestionBlock(92, 6)
    addBrick(96, 6)
    for i=0,3 do addCoin(87 + i*2, 5) end
    addSpike(90, 11)
    addSpike(94, 11)
    addEnemy(85 * TILE, (7 * TILE) - 24)
    addEnemy(98 * TILE, (7 * TILE) - 24)
    
    -- section 5: mid-level
    addQuestionBlock(115, 8)
    addQuestionBlock(118, 8)
    addCoin(116, 7)
    addPiranhaPlant(125, 10)
    -- addEnemy(112 * TILE, (9 * TILE) - 24) -- Moved to underground
    
    -- section 6: higher challenge
    addQuestionBlock(138, 7)
    addQuestionBlock(142, 7)
    addBrick(146, 7)
    for i=0,2 do addCoin(137 + i*2, 6) end
    addSpike(135, 11)
    addPiranhaPlant(140, 10)
    addSpike(148, 11)
    -- addEnemy(135 * TILE, (8 * TILE) - 24) -- Moved to underground
    -- addEnemy(145 * TILE, (8 * TILE) - 24) -- Moved to underground
    
    -- section 7: final stretch with tall platforms
    addQuestionBlock(160, 6)
    addQuestionBlock(165, 6)
    addBrick(170, 6)
    for i=0,3 do addCoin(159 + i*2, 5) end
    addSpike(155, 11)
    addPiranhaPlant(172, 10)
    addSpike(175, 11)
    -- addEnemy(158 * TILE, (7 * TILE) - 24) -- Moved to underground
    -- addEnemy(168 * TILE, (7 * TILE) - 24) -- Moved to underground
    
    -- final boss area
    addQuestionBlock(185, 8)
    addQuestionBlock(190, 8)
    addBrick(195, 8)
    for i=0,4 do addCoin(184 + i*2, 7) end
    addSpike(182, 11)
    addPiranhaPlant(188, 10)
    addSpike(198, 11)
    -- addEnemy(182 * TILE, (9 * TILE) - 24) -- Moved to underground
    -- addEnemy(192 * TILE, (9 * TILE) - 24) -- Moved to underground

    -- Add a block for the gun before the boss
    addQuestionBlock(180, 8, "gun")

    -- Add the boss at the end of the level
    addBoss(190 * TILE, 10 * TILE)
end

function createUndergroundLevel()
    local start_y = level.rows + 1
    local new_rows = 20
    level.rows = level.rows + new_rows

    -- Extend tiles table
    for y = start_y, level.rows do
        level.tiles[y] = {}
        for x = 1, level.cols do
            level.tiles[y][x] = 0
        end
    end

    -- Create ceiling and floor for the underground area
    for x = 1, level.cols do
        level.tiles[start_y][x] = 1
        level.tiles[level.rows][x] = 3 -- New tile type for lava
    end

    -- Create a fixed starting platform
    local first_platform_y = start_y + 13
    for x = 10, 15 do
        level.tiles[first_platform_y][x] = 1
    end

    -- 2nd Platform (Fixed)
    local second_platform_y = start_y + 11
    for x = 18, 23 do
        level.tiles[second_platform_y][x] = 1
    end

    -- 3rd Platform (Fixed, Lower)
    local third_platform_y = start_y + 14 -- Lower than 2nd
    for x = 30, 35 do
        level.tiles[third_platform_y][x] = 1
    end

    -- Add some challenging platforms and hazards
    local current_y = third_platform_y
    local x = 39 -- Start after fixed platforms
    local platform_length = 4
    local gap = 3

    while x < 100 do
        -- Vary platform height
        current_y = current_y + math.random(-1, 1)
        current_y = math.max(start_y + 10, math.min(level.rows - 4, current_y))

        -- Uniform platforms
        for i = 0, platform_length - 1 do
            level.tiles[current_y][x + i] = 1
        end

        -- Add hazards
        if math.random() > 0.5 then
            addSpike(x + math.random(0, platform_length - 1), current_y - 1)
        end
        if math.random() > 0.5 then
            addEnemy((x + math.random(0, platform_length - 2)) * TILE, (current_y - 2) * TILE)
        end
        if math.random() > 0.8 then -- Less frequent
            addBrick(x + math.random(0, platform_length - 1), current_y - 3)
        end
        x = x + platform_length + gap
    end

    -- Build stairs up if we are too low, to prepare for the slide
    while current_y > start_y + 6 and x < level.cols - 25 do
        x = x + 1
        current_y = current_y - 1
        if x <= level.cols then
            level.tiles[current_y][x] = 1
            -- Fill underneath
            for fy = current_y + 1, level.rows - 1 do
                level.tiles[fy][x] = 1
            end
        end
    end

    -- Create a "slide" section (descending stairs)
    local slide_start_x = x
    for i = 0, 18 do
        local sx = slide_start_x + i
        local sy = current_y + i
        if sx <= level.cols and sy < level.rows - 1 then
            level.tiles[sy][sx] = 1
            -- Fill underneath to make it solid
            for fy = sy + 1, level.rows - 1 do
                level.tiles[fy][sx] = 1
            end
            addCoin(sx, sy - 1)
        end
    end

    -- Safe platform at the bottom of the slide
    local final_x = slide_start_x + 14
    for i = 0, 6 do
        if final_x + i <= level.cols then level.tiles[level.rows - 2][final_x + i] = 1 end
    end

    -- Set the player's starting position for this level
    player.underground_start_x = 11 * TILE
    player.underground_start_y = (first_platform_y - 1) * TILE - player.h
end

-- tile collision helpers
local function tileAt(tx, ty)
    if ty < 1 or ty > level.rows or tx < 1 or tx > level.cols then return 0 end
    return level.tiles[ty][tx]
end

local function worldToTile(x)
    return math.floor(x / TILE) + 1
end

function spawnEndPipe()
    local pipe_tx = worldToTile(player.x + player.w + TILE)
    local pipe_ty = 11 -- Ground level
    endPipe = {tx = pipe_tx, ty = pipe_ty}
    createUndergroundLevel()
end

function spawnMushroom(x,y,mtype)
    mtype = mtype or (math.random() < 0.5 and "green" or "red")  -- 50% green, 50% red
    table.insert(mushrooms, {x=x, y=y, w=48, h=48, vx=60, vy=0, alive=true, type=mtype})
    if assets.sfx_block then assets.sfx_block:play() end
end

-- basic AABB
local function aabb(a,b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function resolvePlayerWorldCollision(dt)
    player.onGround = false

    -- It's more robust to check for block collisions first, then tile collisions.
    local block_collided_y = false

    -- compute AABB near player
    local left = worldToTile(player.x)
    local right = worldToTile(player.x + player.w - 1)
    local top = math.floor(player.y / TILE) + 1
    local bottom = math.floor((player.y + player.h - 1) / TILE) + 1

    -- Move horizontally
    player.x = player.x + player.vx * dt
    left = worldToTile(player.x)
    right = worldToTile(player.x + player.w - 1)
    for ty = top, bottom do
        for tx = left, right do
            if tileAt(tx, ty) == 1 then
                if player.vx > 0 then
                    player.x = (tx - 1) * TILE - player.w
                elseif player.vx < 0 then
                    player.x = tx * TILE
                end
                player.vx = 0
            end
        end
    end

    -- Move vertically
    player.y = player.y + player.vy * dt
    top = math.floor(player.y / TILE) + 1
    bottom = math.floor((player.y + player.h - 1) / TILE) + 1
    left = worldToTile(player.x)
    right = worldToTile(player.x + player.w - 1)

    -- Check block collisions
    for _,b in ipairs(blocks) do
        if not b.broken then
            local bx = (b.tx - 1) * TILE
            local by = (b.ty - 1) * TILE
            local block = {x=bx, y=by, w=TILE, h=TILE}
            if aabb({x=player.x, y=player.y, w=player.w, h=player.h}, block) and not block_collided_y then
                -- jumping up (vy < 0) hits block from below
                if player.vy < 0 then
                    player.y = by + TILE
                    handleBlockHit(b.tx, b.ty)
                    player.vy = 0
                    block_collided_y = true
                -- falling down (vy > 0) lands on block
                elseif player.vy > 0 then
                    player.y = by - player.h
                    player.onGround = true
                    player.vy = 0
                    block_collided_y = true
                end
            end
        end
    end

    -- Only check for tile collision if we haven't already hit a special block
    if not block_collided_y then
        for ty = top, bottom do
            for tx = left, right do
                if tileAt(tx, ty) == 1 then
                    if player.vy > 0 then
                        player.y = (ty - 1) * TILE - player.h
                        player.onGround = true
                    elseif player.vy < 0 then
                        player.y = ty * TILE
                    end
                    player.vy = 0
                elseif tileAt(tx, ty) == 3 then -- Lava collision
                    -- Treat lava like spikes, instant damage
                    handlePlayerDamageCollision({x=(tx-1)*TILE, y=(ty-1)*TILE, w=TILE, h=TILE})
                end
            end
        end
    end
end

function handleBlockHit(tx, ty)
    for _,b in ipairs(blocks) do
        if b.tx == tx and b.ty == ty then
            if b.type == "question" and not b.used then
                b.used = true
                if b.content == "gun" then
                    player.hasGun = true
                    if assets.sfx_coin then assets.sfx_coin:play() end
                elseif math.random() < 0.25 then
                    spawnMushroom((tx-1)*TILE, (ty-1)*TILE - 16)
                else
                    hud.coins = hud.coins + 1
                    hud.totalCoins = hud.totalCoins + 1
                    hud.score = hud.score + 100
                    if assets.sfx_coin then assets.sfx_coin:play() end
                end
            elseif b.type == "brick" and not b.broken then
                if player.big then
                    b.broken = true
                    hud.score = hud.score + 50
                    if assets.sfx_block then assets.sfx_block:play() end
                else
                    if assets.sfx_block then assets.sfx_block:play() end
                end
            end
            return
        end
    end
end

function updateMushrooms(dt)
    for i=#mushrooms,1,-1 do
        local m = mushrooms[i]
        m.vy = m.vy + GRAVITY * dt * 0.3
        m.x = m.x + m.vx * dt
        m.y = m.y + m.vy * dt

        -- Tile collision for mushrooms so they land on platforms
        local bottom_ty = math.floor((m.y + m.h) / TILE) + 1
        local left_tx = worldToTile(m.x)
        local right_tx = worldToTile(m.x + m.w - 1)
        
        for tx = left_tx, right_tx do
            if tileAt(tx, bottom_ty) == 1 then
                if m.vy > 0 then
                    m.y = (bottom_ty - 1) * TILE - m.h
                    m.vy = 0
                end
            end
        end

        -- Extra check to prevent mushrooms falling through the floor on level 1
        if m.y < 14 * TILE and m.y + m.h > 11 * TILE then
            m.y = 11 * TILE - m.h
            m.vy = 0
        end

        if aabb({x=player.x,y=player.y,w=player.w,h=player.h}, {x=m.x,y=m.y,w=m.w,h=m.h}) then
            if m.type == "green" then
                -- green mushroom: increment greenCount (stacking). 1 -> 2x, 2+ -> 3x (capped)
                player.greenCount = math.min(player.greenCount + 1, 3)
                player.greenTimer = player.greenDuration
                applySize()
                hud.score = hud.score + 300
            else
                -- red mushroom: increment redCount (stacking up to 3) and reset timer
                player.redCount = math.min(player.redCount + 1, 3)
                player.speedBoostTimer = player.speedBoostDuration
                hud.score = hud.score + 500
            end
            if assets.sfx_coin then assets.sfx_coin:play() end
            table.remove(mushrooms, i)
        end
    end
end

function updateEnemies(dt)
    for i=#enemies,1,-1 do
        local e = enemies[i]

        if e.alive then
            -- Apply gravity
            e.vy = e.vy + GRAVITY * dt
            e.y = e.y + e.vy * dt

            -- Vertical collision with ground tiles
            local bottom_ty = math.floor((e.y + e.h) / TILE) + 1
            local left_tx = worldToTile(e.x)
            local right_tx = worldToTile(e.x + e.w - 1)
            local onGround = false
            for tx = left_tx, right_tx do
                if tileAt(tx, bottom_ty) == 1 then
                    if e.vy > 0 then
                        e.y = (bottom_ty - 1) * TILE - e.h
                        e.vy = 0
                        onGround = true
                    end
                end
            end

            -- Horizontal movement and AI (only if on ground)
            if onGround then
                e.x = e.x + e.dir * e.speed * dt

                -- Ledge detection: check tile in front and below
                local check_x = (e.dir == 1) and (e.x + e.w) or (e.x - 1)
                local check_tx = worldToTile(check_x)
                local check_ty = math.floor((e.y + e.h) / TILE) + 1
                if tileAt(check_tx, check_ty) == 0 then
                    e.dir = e.dir * -1 -- Turn around at ledge
                else
                    -- Horizontal collision with walls
                    local next_left_tx = worldToTile(e.x)
                    local next_right_tx = worldToTile(e.x + e.w - 1)
                    local mid_ty = math.floor((e.y + e.h/2) / TILE) + 1
                    if (e.dir == -1 and tileAt(next_left_tx, mid_ty) == 1) or (e.dir == 1 and tileAt(next_right_tx, mid_ty) == 1) then
                        e.dir = e.dir * -1 -- Turn around at wall
                    end
                end
            end

            if aabb({x=player.x,y=player.y,w=player.w,h=player.h}, {x=e.x,y=e.y,w=e.w,h=e.h}) then
                if player.vy > 0 and player.y + player.h < e.y + e.h / 2 then -- Stomp check
                    e.alive = false
                    player.vy = player.jumpPower * 0.5
                    hud.score = hud.score + 200
                else
                    handlePlayerDamageCollision(e)
                end
            end
        -- Do not remove the boss from the enemies table, it's handled separately
        elseif not e.is_boss then
            table.remove(enemies, i)
        end
    end
end

function updatePiranhaPlants(dt)
    for _,p in ipairs(piranha_plants) do
        p.timer = p.timer - dt

        -- State machine for piranha plant
        if p.state == 0 then -- Hiding in pipe
            if p.timer <= 0 then
                -- Check if player is nearby before rising
                local pipe_x = (p.tx - 1) * TILE
                local dist = math.abs((player.x + player.w/2) - (pipe_x + TILE))
                if dist > TILE * 1.5 then
                    p.state = 1 -- Start rising
                    p.timer = 1 -- Time to rise
                else
                    p.timer = 0.5 -- Wait and check again
                end
            end
        elseif p.state == 1 then -- Rising
            p.y_offset = math.max(0, p.y_offset - 60 * dt)
            if p.y_offset == 0 then
                p.state = 2 -- Fully risen
                p.timer = 2 -- Time to wait at top
            end
        elseif p.state == 2 then -- Waiting at top
            if p.timer <= 0 then
                p.state = 3 -- Start sinking
                p.timer = 0.8 -- Time to sink
            end
        elseif p.state == 3 then -- Sinking
            p.y_offset = math.min(32, p.y_offset + 60 * dt)
            if p.y_offset == 32 then
                p.state = 0 -- Fully hidden
                p.timer = math.random(2,4) -- Time to wait in pipe
            end
        end

        -- Collision check only if plant is somewhat visible
        if p.y_offset < 30 then
            local plant_hitbox = {
                x = (p.tx - 1) * TILE + (TILE - p.w)/2,
                y = (p.ty - 1) * TILE + p.y_offset,
                w = p.w,
                h = p.h
            }
            if aabb({x=player.x,y=player.y,w=player.w,h=player.h}, plant_hitbox) then
                handlePlayerDamageCollision(plant_hitbox)
            end
        end
    end
end

function updateBoss(dt)
    if not boss or not boss.alive then return end

    -- Apply gravity
    boss.vy = boss.vy + GRAVITY * dt
    boss.y = boss.y + boss.vy * dt

    -- Vertical collision with ground
    local bottom_ty = math.floor((boss.y + boss.h) / TILE) + 1
    local left_tx = worldToTile(boss.x)
    local right_tx = worldToTile(boss.x + boss.w - 1)
    local onGround = false
    for tx = left_tx, right_tx do
        if tileAt(tx, bottom_ty) == 1 then
            if boss.vy > 0 then
                boss.y = (bottom_ty - 1) * TILE - boss.h
                boss.vy = 0
                onGround = true
            end
        end
    end

    -- Horizontal patrol movement
    if onGround then
        boss.x = boss.x + boss.dir * boss.speed * dt
        if boss.x < boss.patrol_left then
            boss.x = boss.patrol_left
            boss.dir = 1
        elseif boss.x + boss.w > boss.patrol_right then
            boss.x = boss.patrol_right - boss.w
            boss.dir = -1
        end
    end

    -- Collision with player
    if aabb({x=player.x,y=player.y,w=player.w,h=player.h}, boss) then
        -- Stomp check (player must be above the center of the boss)
        if player.vy > 0 and player.y + player.h < boss.y + boss.h / 2 then
            player.vy = player.jumpPower * 0.6 -- bounce off boss
            boss.hp = boss.hp - 1
            hud.score = hud.score + 1000
        else
            -- Player gets hit by boss
            handlePlayerDamageCollision(boss)
        end
    end

    -- Collision with bullets
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        if aabb(b, boss) then
            boss.hp = boss.hp - 1
            hud.score = hud.score + 500
            table.remove(bullets, i) -- remove bullet on hit
        end
    end

    -- Check if boss is defeated
    if boss.hp <= 0 then
        boss.alive = false
        hud.score = hud.score + 5000 -- big bonus for winning
        spawnEndPipe()
    end

end

function updateCoinsAndSpikes()
    for i=#coins,1,-1 do
        local c = coins[i]
        local cx = (c.tx-1)*TILE
        local cy = (c.ty-1)*TILE
        if aabb({x=player.x,y=player.y,w=player.w,h=player.h}, {x=cx,y=cy,w=16,h=16}) then
            hud.coins = hud.coins + 1
            hud.totalCoins = hud.totalCoins + 1
            hud.score = hud.score + 100
            if assets.sfx_coin then assets.sfx_coin:play() end
            table.remove(coins, i)
        end
    end
    for _,s in ipairs(spikes) do
        local sx = (s.tx-1)*TILE
        local sy = (s.ty-1)*TILE
        if aabb({x=player.x,y=player.y,w=player.w,h=player.h}, {x=sx,y=sy,w=TILE,h=TILE}) then
            handlePlayerDamageCollision({x=sx,y=sy,w=TILE,h=TILE})
        end
    end
end

function handlePlayerDamageCollision(collider)
    -- Only process damage if player is not invincible
    if not player.invincible and aabb({x=player.x,y=player.y,w=player.w,h=player.h}, collider) then
        if player.big then
            -- if big, shrink and get short invincibility
            player.greenCount = 0
            applySize()
            player.invincible = true
            player.invincibleTimer = 1.5 -- 1.5 seconds of flashing/invincibility
        else
            -- if small, lose a life
            hud.lives = hud.lives - 1
            player.greenCount = 0
            applySize()
            player.redCount = 0
            player.hasGun = false
            player.speedBoostTimer = 0
            if player.checkpoint then
                player.x, player.y = player.checkpoint.x, player.checkpoint.y
            else
                player.x, player.y = 64, 300
            end
            player.vx, player.vy = 0, 0
            resetBlocks()
            -- Reset the boss when the player dies, unless the game has been won
            if gameState ~= "win" then
                addBoss(190 * TILE, 10 * TILE)
            end
        end
    end
end

function resetBlocks()
    for _,b in ipairs(blocks) do
        b.used = false
        b.broken = false
    end
end

function updateSmoke(dt)
    -- Spawn new particles periodically only when in the underground area
    if player.y > 14 * TILE then
        if math.random() < 0.8 then -- Control spawn rate
            local spawn_x = camera.x + math.random(love.graphics.getWidth())
            local spawn_y = camera.y + love.graphics.getHeight() + math.random(20, 50) -- Start just below the screen over the lava
            
            table.insert(smoke_particles, {
                x = spawn_x,
                y = spawn_y,
                size = math.random(40, 120),
                alpha = math.random(40, 80) / 255, -- Start semi-transparent
                life = math.random(5, 10), -- 5 to 10 seconds lifetime
                max_life = 10,
                vx = math.random(-10, 10), -- Slow horizontal drift
                vy = math.random(-15, -30) -- Slow rise
            })
        end
    end

    -- Update existing particles
    for i = #smoke_particles, 1, -1 do
        local p = smoke_particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(smoke_particles, i)
        else
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            p.alpha = p.alpha * 0.998 -- Slowly fade out over time
        end
    end
end

function applySize()
    -- compute scale from greenCount: 0 -> 1x, 1 -> 2x, 2+ -> 3x
    local scale = 1
    if player.greenCount >= 2 then
        scale = 3
    elseif player.greenCount == 1 then
        scale = 2
    end
    local old_h = player.h
    local old_w = player.w
    player.w = math.max(math.floor(player.baseW * scale), 20)
    player.h = math.max(math.floor(player.baseH * scale), 28)
    -- adjust y so feet remain on same surface
    player.y = player.y - (player.h - old_h)
    player.big = player.greenCount > 0
end

local input = {left=false,right=false,run=false}

function love.keypressed(key)
    if (key == 'z' or key == 'space') then
        -- buffer the jump so it's responsive even if slightly early
        player.jumpBuffer = player.jumpBufferTime
    end
    if key == 'r' then love.event.quit('restart') end
end

function love.keyreleased(key)
    -- variable jump height: cut the jump short when release
    if (key == 'z' or key == 'space') then
        if player.vy < 0 then player.vy = player.vy * 0.5 end
    end
end

function love.update(dt)
    if gameState == "pipe_transition" then
        transition.timer = transition.timer + dt
        local half_duration = transition.duration / 2
        if transition.timer < half_duration then -- Fading out
            transition.alpha = transition.timer / half_duration
        else -- Fading in
            if transition.onComplete then
                transition.onComplete()
                transition.onComplete = nil -- Run only once
            end
            transition.alpha = 1 - ((transition.timer - half_duration) / half_duration)
        end

        if transition.timer >= transition.duration then
            transition.active = false
            gameState = "playing" -- Change state AFTER transition is fully done
        end
        return -- Pause other game updates during transition
    end

    if gameState == "win" then
        -- If we won, don't update anything else
        if love.keyboard.isDown('r') then love.event.quit('restart') end
        return
    end
    if hud.lives <= 0 then
        -- If game over, don't update anything else
        return
    end
    -- input
    input.left = love.keyboard.isDown('left','a')
    input.right = love.keyboard.isDown('right','d')
    input.run = love.keyboard.isDown('x','lshift')

    local targetSpeed = player.maxSpeed * (input.run and player.runMultiplier or 1)
    -- apply stacked red mushroom speed multiplier
    local speedMultiplier = 1
    if player.redCount >= 3 then
        speedMultiplier = 3
    elseif player.redCount == 2 then
        speedMultiplier = 2
    elseif player.redCount == 1 then
        speedMultiplier = 1.8
    end
    targetSpeed = targetSpeed * speedMultiplier
    -- horizontal acceleration toward target
    if input.left then
        player.vx = player.vx - player.accel * dt
        player.facing = -1
    elseif input.right then
        player.vx = player.vx + player.accel * dt
    else
        -- apply friction
        player.vx = player.vx * (1 - math.min(player.friction*dt, 1))
    end

    -- clamp speed
    if player.vx > targetSpeed then player.vx = targetSpeed end
    if player.vx < -targetSpeed then player.vx = -targetSpeed end

    -- gravity
    player.vy = player.vy + GRAVITY * dt

    -- update red mushroom timer (clears stacked speed boost when it expires)
    if player.redCount > 0 then
        player.speedBoostTimer = player.speedBoostTimer - dt
        if player.speedBoostTimer <= 0 then
            player.redCount = 0
            player.speedBoostTimer = 0
        end
    end

    -- update green (big) timer: clear green stacks when it expires
    if player.greenCount > 0 then
        player.greenTimer = player.greenTimer - dt
        if player.greenTimer <= 0 then
            player.greenCount = 0
            player.greenTimer = 0
            applySize()
        end
    end

    -- update timers for coyote time and jump buffer
    if player.onGround then
        player.timeSinceGround = 0
    else
        player.timeSinceGround = player.timeSinceGround + dt
    end
    if player.jumpBuffer > 0 then player.jumpBuffer = player.jumpBuffer - dt end

    -- perform jump if buffered and within coyote time or on ground
    if player.jumpBuffer > 0 and (player.onGround or player.timeSinceGround <= player.coyoteTime) then
        player.vy = player.jumpPower
        player.onGround = false
        player.jumpBuffer = 0
        if assets.sfx_jump then assets.sfx_jump:play() end
    end

    -- Auto-shoot if player has gun
    if player.hasGun then
        player.shootTimer = player.shootTimer - dt
        if player.shootTimer <= 0 then
            player.shootTimer = 0.5 -- Fire every 0.5 seconds
            local bullet_x = player.facing == 1 and player.x + player.w or player.x
            local bullet_y = player.y + player.h / 2 - 2
            table.insert(bullets, {x=bullet_x, y=bullet_y, w=8, h=4, vx = 800 * player.facing})
        end
    end

    -- Update invincibility timer
    if player.invincible then
        player.invincibleTimer = player.invincibleTimer - dt
        if player.invincibleTimer <= 0 then player.invincible = false end
    end

    -- Update bullets
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        b.x = b.x + b.vx * dt
        -- remove bullets that go off-screen
        if b.x < camera.x or b.x > camera.x + love.graphics.getWidth() then
            table.remove(bullets, i)
        end
    end

    -- Check for entering the end pipe
    if endPipe then
        local pipe_x = (endPipe.tx - 1) * TILE
        local pipe_y = (endPipe.ty - 1) * TILE
        local pipe_opening = {x = pipe_x, y = pipe_y, w = TILE, h = TILE / 2}

        -- Check if player is centered and moving down into the pipe
        if player.vy > 0 and math.abs((player.x + player.w/2) - (pipe_x + TILE/2)) < TILE/4 and aabb({x=player.x, y=player.y, w=player.w, h=player.h}, pipe_opening) then
            gameState = "pipe_transition"
            transition.active = true
            transition.timer = 0
            transition.duration = 1.5 -- 0.75s fade out, 0.75s fade in
            transition.alpha = 0
            transition.onComplete = function()
                -- This code runs at the midpoint of the transition (fully black screen)
                player.x = player.underground_start_x
                player.y = player.underground_start_y
                player.hasGun = false
                player.vy = 0
                -- Set the checkpoint to the start of the underground level
                -- and give the player 5 lives for this new section.
                hud.lives = 5
                player.checkpoint = {x = player.underground_start_x, y = player.underground_start_y}
                -- Immediately snap camera to the new position
                camera.x = math.max(0, player.x - love.graphics.getWidth() / 2) -- Follow player X
                camera.y = player.y - love.graphics.getHeight() / 2 -- Center on player Y
            end
        end
    end

    resolvePlayerWorldCollision(dt)
    updateMushrooms(dt)
    updateEnemies(dt)

    updateSmoke(dt)
    updatePiranhaPlants(dt)
    updateBoss(dt)
    updateCoinsAndSpikes()

    -- camera (only update if not in a special state like minecart ride)
    if gameState == "playing" then
        camera.x = math.max(0, player.x - love.graphics.getWidth() / 2)
        -- Smoothly follow player's y position
        local target_y = player.y - love.graphics.getHeight() / 2
        camera.y = camera.y + (target_y - camera.y) * 0.1
    end

    -- music crossfade looping: if musicCurrent and musicNext are available, crossfade near end
    if assets.musicCurrent and assets.musicNext and assets.musicCurrent:getDuration() and assets.musicCurrent:getDuration() > 0 then
        local cur = assets.musicCurrent
        local dur = cur:getDuration()
        if dur and dur > 0 then
            local pos = cur:tell() or 0
            local timeLeft = dur - pos
            local fadeT = assets.musicFadeTime or 0.8
            if timeLeft <= fadeT and not assets.musicCrossfading and assets.musicNext then
                -- start next source and begin crossfade
                assets.musicNext:stop()
                assets.musicNext:play()
                assets.musicNext:setVolume(0)
                assets.musicCrossfading = true
                assets.musicFadeTimer = 0
            end
            if assets.musicCrossfading then
                assets.musicFadeTimer = (assets.musicFadeTimer or 0) + dt
                local t = math.min(assets.musicFadeTimer / fadeT, 1)
                cur:setVolume(0.6 * (1 - t))
                assets.musicNext:setVolume(0.6 * t)
                if t >= 1 then
                    cur:stop()
                    -- swap current and next
                    assets.musicCurrent, assets.musicNext = assets.musicNext, assets.musicCurrent
                    assets.musicCrossfading = false
                    assets.musicFadeTimer = 0
                end
            end
        end
    end
end

function drawParallax()
    -- Check if player is in the underground area (y > 14 tiles)
    if player.y > 14 * TILE then
        -- Underground: Draw a solid black background that fills the screen
        local w, h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle('fill', camera.x, camera.y, w, h)
    else
        -- Overworld: Draw the parallax sky
        if assets.background then
            local bx = - (camera.x * 0.2)
            love.graphics.draw(assets.background, bx % assets.background:getWidth(), camera.y)
            love.graphics.draw(assets.background, bx % assets.background:getWidth() + assets.background:getWidth(), camera.y)
        else
            -- fallback background gradient
            local w,h = love.graphics.getDimensions()
            for i=0,h,20 do
                love.graphics.setColor(0.6 - (i/h)*0.4, 0.8 - (i/h)*0.4, 1)
                love.graphics.rectangle('fill', camera.x, camera.y + i, w, 20)
            end
        end
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)

    -- background
    love.graphics.push()
    drawParallax()
    love.graphics.pop()

    -- Lava animation values
    local time = love.timer.getTime()
    local pulse = (math.sin(time * 4) + 1) / 2 -- A value that smoothly goes from 0 to 1 and back
    local lava_g = 0.4 + pulse * 0.2 -- Varies green between 0.4 and 0.6

    -- ground tiles
    for y=1,level.rows do
        for x=1,level.cols do
            local t = level.tiles[y][x]
            if t == 1 then
                if y > 14 then -- Underground tiles
                    love.graphics.setColor(0.4,0.25,0.1) -- Brown for "mine"
                else -- Overworld tiles
                    love.graphics.setColor(0.3,0.7,0.3)
                end
                love.graphics.rectangle('fill', (x-1)*TILE, (y-1)*TILE, TILE, TILE)
                love.graphics.setColor(1,1,1) -- Reset color
            elseif t == 3 then -- Lava
                love.graphics.setColor(1, lava_g, 0) -- Pulsating orange/yellow

                local tile_x = (x-1) * TILE
                local tile_y = (y-1) * TILE
                local tile_above = tileAt(x, y - 1)

                if tile_above == 0 then -- This is a surface tile, draw with waves
                    for i = 0, TILE - 1 do
                        local wave_height = (math.sin((tile_x + i) * 0.2 + time * 3) + math.sin((tile_x + i) * 0.5 + time * 1.5)) * 3
                        love.graphics.rectangle('fill', tile_x + i, tile_y + wave_height, 1, TILE - wave_height)
                    end
                else -- This is a subsurface tile, draw as a solid block
                    love.graphics.rectangle('fill', tile_x, tile_y, TILE, TILE)
                end
            end
        end
    end

    -- smoke particles (drawn after tiles, before other objects)
    for _,p in ipairs(smoke_particles) do
        -- Use a dark grey for smoke
        love.graphics.setColor(0.3, 0.3, 0.3, p.alpha)
        love.graphics.circle('fill', p.x, p.y, p.size)
    end
    love.graphics.setColor(1,1,1) -- Reset color

    -- blocks
    for _,b in ipairs(blocks) do
        local bx = (b.tx-1)*TILE
        local by = (b.ty-1)*TILE
        if b.type == 'question' then
            if b.used then love.graphics.setColor(0.6,0.6,0.6) else love.graphics.setColor(1,0.9,0) end
            love.graphics.rectangle('fill', bx, by, TILE, TILE)
            love.graphics.setColor(0,0,0)
            love.graphics.rectangle('line', bx, by, TILE, TILE)
            -- draw question mark on the block
            if not b.used then
                love.graphics.setColor(0,0,0)
                love.graphics.printf("?", bx + 4, by + 6, TILE - 8, 'center')
            end
        elseif b.type == 'brick' and not b.broken then
            love.graphics.setColor(0.6,0.3,0.2)
            love.graphics.rectangle('fill', bx, by, TILE, TILE)
        end
    end

    -- coins
    love.graphics.setColor(1,0.9,0)
    for _,c in ipairs(coins) do
        local cx = (c.tx-1)*TILE + TILE/4
        local cy = (c.ty-1)*TILE + TILE/4
        love.graphics.circle('fill', cx+8, cy+8, 6)
    end

    -- spikes
    love.graphics.setColor(0.8,0.2,0.2)
    for _,s in ipairs(spikes) do
        local sx = (s.tx-1)*TILE
        local sy = (s.ty-1)*TILE
        love.graphics.polygon('fill', sx, sy+TILE, sx+TILE/2, sy, sx+TILE, sy+TILE)
    end

    -- end pipe
    if endPipe then
        local pipe_x = (endPipe.tx - 1) * TILE
        local pipe_y = (endPipe.ty - 1) * TILE
        -- draw pipe
        love.graphics.setColor(0.1, 0.8, 0.1)
        love.graphics.rectangle('fill', pipe_x, pipe_y, TILE, TILE*2)
        love.graphics.rectangle('fill', pipe_x - 4, pipe_y, TILE + 8, TILE/3)
        love.graphics.setColor(0,0,0)
        love.graphics.rectangle('line', pipe_x, pipe_y, TILE, TILE*2)
        love.graphics.rectangle('line', pipe_x - 4, pipe_y, TILE + 8, TILE/3)
    end

    -- piranha plants (and their pipes)
    for _,p in ipairs(piranha_plants) do
        local pipe_x = (p.tx - 1) * TILE
        local pipe_y = (p.ty - 1) * TILE
        -- draw pipe
        love.graphics.setColor(0.1, 0.8, 0.1)
        love.graphics.rectangle('fill', pipe_x, pipe_y, TILE, TILE*2)
        love.graphics.rectangle('fill', pipe_x - 4, pipe_y, TILE + 8, TILE/3)
        love.graphics.setColor(0,0,0)
        love.graphics.rectangle('line', pipe_x, pipe_y, TILE, TILE*2)
        love.graphics.rectangle('line', pipe_x - 4, pipe_y, TILE + 8, TILE/3)

        -- draw plant
        if assets.piranha_plant then
            love.graphics.draw(assets.piranha_plant, pipe_x + (TILE - p.w)/2, pipe_y + p.y_offset)
        end
    end

    -- bullets
    love.graphics.setColor(1, 1, 0)
    for _,b in ipairs(bullets) do
        love.graphics.rectangle('fill', b.x, b.y, b.w, b.h)
    end

    -- mushrooms
    love.graphics.setColor(1,1,1)
    for _,m in ipairs(mushrooms) do
        local asset = nil
        if m.type == "green" then asset = assets.mushroom_green end
        if m.type == "red" then asset = assets.mushroom_red end

        if asset then
            local iw, ih = asset:getDimensions()
            local sx = m.w / iw
            local sy = m.h / ih
            love.graphics.draw(asset, m.x, m.y, 0, sx, sy)
        else -- fallback to rectangles if sprites are missing
            if m.type == "green" then love.graphics.setColor(0.2,0.8,0.2) else love.graphics.setColor(1,0.2,0.2) end
            love.graphics.rectangle('fill', m.x, m.y, m.w, m.h)
        end
    end

    -- enemies
    if assets.enemy then
        love.graphics.setColor(1,1,1)
        for _,e in ipairs(enemies) do
            local iw, ih = assets.enemy:getDimensions()
            local sx = e.w / iw
            local sy = e.h / ih
            love.graphics.draw(assets.enemy, e.x, e.y, 0, sx, sy)
        end
    else
        love.graphics.setColor(0.5,0.2,0.2)
        for _,e in ipairs(enemies) do
            love.graphics.rectangle('fill', e.x, e.y, e.w, e.h)
        end
    end

    -- boss
    if boss and boss.alive then
        if assets.boss then
            love.graphics.setColor(1,1,1)
            local bdir = boss.dir > 0 and 1 or -1
            love.graphics.draw(assets.boss, boss.x + (bdir == -1 and boss.w or 0), boss.y, 0, bdir, 1)
        else
            love.graphics.setColor(0.1, 0.5, 0.1)
            love.graphics.rectangle('fill', boss.x, boss.y, boss.w, boss.h)
        end

        -- Draw health bar above the boss
        local bar_w = boss.w
        local bar_h = 8
        local bar_x = boss.x
        local bar_y = boss.y - bar_h - 4 -- 4 pixels above the boss

        -- Health bar background (red)
        love.graphics.setColor(1, 0.2, 0.2)
        love.graphics.rectangle('fill', bar_x, bar_y, bar_w, bar_h)
        -- Current health (green)
        love.graphics.setColor(0.2, 1, 0.2)
        love.graphics.rectangle('fill', bar_x, bar_y, bar_w * (boss.hp / boss.max_hp), bar_h)
        love.graphics.setColor(1,1,1) -- Reset color to white after drawing health bar
    end

    -- player (sprite if available)
    if assets.player then
        -- scale the provided sprite to roughly match player.w/h
        local iw,ih = assets.player:getDimensions()
        local sx = player.w / iw
        local sy = player.h / ih
        -- Flashing effect when invincible
        if player.invincible and math.floor(love.timer.getTime() * 10) % 2 == 0 then
            love.graphics.setColor(1,1,1,0.5)
        end
        love.graphics.draw(assets.player, player.x + (player.facing == -1 and player.w or 0), player.y, 0, sx * player.facing, sy)
    else
        if player.big then love.graphics.setColor(0.2,0.4,1) else love.graphics.setColor(0.8,0.2,0.2) end
        love.graphics.rectangle('fill', player.x, player.y, player.w, player.h)
    end

    -- Draw gun on player if they have it
    if player.hasGun and assets.gun then
        local gun_x = player.facing == 1 and player.x + player.w - 8 or player.x - 16
        local gun_y = player.y + player.h/2 - 8
        love.graphics.draw(assets.gun, gun_x, gun_y)
    end

    love.graphics.pop()

    -- Draw transition overlay
    if transition.active then
        local w, h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, transition.alpha)
        love.graphics.rectangle('fill', 0, 0, w, h)
        love.graphics.setColor(1,1,1) -- Reset color
    end

    -- HUD
    love.graphics.setColor(1,1,1)
    love.graphics.print(string.format("Score: %d  Coins: %d/%d  Lives: %d", hud.score, hud.coins, hud.totalCoins, hud.lives), 8, 8)
    -- display speed multiplier and remaining time if any
    if hud.lives <= 0 then
        love.graphics.setColor(1,0,0)
        love.graphics.printf("GAME OVER", 0, 200, love.graphics.getWidth(), 'center')
        love.graphics.setColor(1,1,1)
        love.graphics.printf("Press R to Restart", 0, 240, love.graphics.getWidth(), 'center')
        return
    end
    if gameState == "win" then
        love.graphics.setColor(0,1,0)
        love.graphics.printf("YOU WIN!", 0, 200, love.graphics.getWidth(), 'center')
        love.graphics.setColor(1,1,1)
        love.graphics.printf("Final Score: " .. hud.score, 0, 240, love.graphics.getWidth(), 'center')
        love.graphics.printf("Press R to Restart", 0, 280, love.graphics.getWidth(), 'center')
    end
    local speedMultiplier = 1
    if player.redCount >= 3 then speedMultiplier = 3 elseif player.redCount == 2 then speedMultiplier = 2 elseif player.redCount == 1 then speedMultiplier = 1.8 end
    local speedStatus = player.redCount > 0 and string.format(" [SPEED x%.1f: %.1fs]", speedMultiplier, player.speedBoostTimer) or ""
    local sizeMult = 1
    if player.greenCount >= 2 then sizeMult = 3 elseif player.greenCount == 1 then sizeMult = 2 end
    local sizeStatus = ""
    if player.greenCount > 0 then
        sizeStatus = string.format(" [BIG x%d: %.1fs]", sizeMult, player.greenTimer)
    end
    love.graphics.print("Controls: ←/A →/D move, Z/Space jump, X run, R restart" .. speedStatus .. sizeStatus, 8, 28)
end
