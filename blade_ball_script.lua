--[[
    BLADE BALL AUTO PARRY SCRIPT
    Last Updated: 2024-XX-XX

    DESCRIPTION:
    This script provides auto-parry functionality for the Roblox game Blade Ball.
    It also includes an auto-spam feature for mouse clicks and a new 'X' key spam.

    FEATURES:
    - Smart Auto-Parry: Predicts ball trajectory based on speed, distance, and player ping.
    - Auto-Clicker: Spams mouse clicks when a key is held.
    - X-Spam: Spams the 'X' key when a key is held.
    - Customizable: All keybinds and timings can be adjusted in the CONFIG section.
]]

--================================================================================================--
--[[                                        [ CONFIGURATION ]                                       ]]
--================================================================================================--
local CONFIG = {
    -- Keybinds
    ToggleEnabledKey = Enum.KeyCode.F4,      -- Press to toggle the entire script on/off
    AutoClickKey = Enum.KeyCode.V,            -- Hold to spam mouse clicks
    AutoSpamXKey = Enum.KeyCode.X,            -- Hold to spam the 'X' key for abilities

    -- Auto Parry Settings
    ParryKey = Enum.KeyCode.F,                -- The key used for parrying
    ParryCooldown = 0.09,                     -- Minimum time between parry attempts (seconds)
    MinBallClickDelay = 0.15,                 -- Minimum time before trying to parry the same ball again
    MaxParryChain = 2,                        -- Max number of balls to parry in quick succession

    -- Prediction Tuning (ADJUST THESE IF PARRY IS INACCURATE)
    EmergencyParryDistance = 11,              -- Parries if the ball is this close, regardless of prediction.

    -- Base reaction time for different ball trajectories. Lower values = parry sooner.
    ReactionTime = {
        Normal = 0.26,                        -- Default reaction time for normal balls.
        UpwardSpin = 0.20,                    -- Reaction time for balls with upward spin (which are often faster).
    },
    -- Reaction time when the ball is accelerating rapidly (e.g., after a clash).
    -- These values are lower because we need to react faster.
    AcceleratingReactionTime = {
        Normal = 0.17,
        UpwardSpin = 0.12,
    },

    -- This section defines what counts as a "rapidly accelerating" ball.
    AccelerationThresholds = {
        DeltaSpeed = 30,                      -- Trigger if speed increases by this much in one frame.
        AvgSpeedMultiplier = 1.35,            -- Trigger if current speed is this much higher than recent average speed.
        TravelDistance = 14,                  -- Trigger if the ball travels this far in a single frame.
    },

    -- Performance Settings
    FPSTarget = 60,                           -- The script adjusts timings based on this FPS target.
                                              -- If your FPS is lower than this, it will try to compensate by reacting slightly earlier.

    -- Auto Clicker Settings
    ClickInterval = 1 / 35,                   -- Time between clicks for the auto-clicker (35 clicks per second)

    -- X-Spam Settings
    XSpamInterval = 1 / 10,                   -- Time between 'X' key presses (10 presses per second)
}

--================================================================================================--
--[[                                           [ SERVICES ]                                         ]]
--================================================================================================--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StatsService = game:GetService("Stats")

--================================================================================================--
--[[                                        [ SCRIPT STATE ]                                        ]]
--================================================================================================--
local Player = Players.LocalPlayer
local AutoSpamClick = false
local AutoSpamX = false
local Enabled = true

local LastClick = 0
local LastParry = 0
local LastSuccessfulParry = 0
local LastXSpam = 0

local BallMemory = {}
local BallLastParryTime = {}

--================================================================================================--
--[[                                          [ FUNCTIONS ]                                         ]]
--================================================================================================--

-- Function to simulate a key press for parrying
local function SmartParry()
    LastParry = tick()
    VirtualInputManager:SendKeyEvent(true, CONFIG.ParryKey, false, game)
    VirtualInputManager:SendKeyEvent(false, CONFIG.ParryKey, false, game)
end

-- Function to get the player's current ping
local function GetPing()
    local stats = StatsService:FindFirstChild("PerformanceStats")
    if stats and stats:FindFirstChild("Ping") then
        local pingValue = stats.Ping:GetValueString():match("%d+")
        return tonumber(pingValue) or 50
    end
    return 50
end

-- Function to get all active balls on the map
local function GetBalls()
    local balls = {}
    if workspace:FindFirstChild("Balls") then
        for _, b in ipairs(workspace.Balls:GetChildren()) do
            if b:GetAttribute("realBall") and b:IsA("BasePart") then
                table.insert(balls, b)
            end
        end
    end
    return balls
end

--================================================================================================--
--[[                                        [ INPUT HANDLERS ]                                      ]]
--================================================================================================--

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end

    if input.KeyCode == CONFIG.AutoClickKey then AutoSpamClick = true end
    if input.KeyCode == CONFIG.AutoSpamXKey then AutoSpamX = true end
    if input.KeyCode == CONFIG.ToggleEnabledKey then Enabled = not Enabled end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CONFIG.AutoClickKey then AutoSpamClick = false end
    if input.KeyCode == CONFIG.AutoSpamXKey then AutoSpamX = false end
end)


--================================================================================================--
--[[                                          [ MAIN LOOP ]                                         ]]
--================================================================================================--

RunService.Heartbeat:Connect(function()
    local char = Player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hrp and Enabled) then return end

    local now = tick()

    -- Auto-Clicker Logic
    if AutoSpamClick and now - LastClick >= CONFIG.ClickInterval then
        LastClick = now
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end

    -- Auto-X-Spam Logic
    if AutoSpamX and now - LastXSpam >= CONFIG.XSpamInterval then
        LastXSpam = now
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.X, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.X, false, game)
    end

    -- Auto-Parry Logic
    local ping = GetPing() / 1000
    local fps = math.floor(workspace:GetRealPhysicsFPS())
    local fpsFactor = math.clamp(1 - (fps < CONFIG.FPSTarget and (CONFIG.FPSTarget - fps) / 100 or 0), 0.8, 1)

    local candidates = {}

    for _, ball in ipairs(GetBalls()) do
        if ball:GetAttribute("target") ~= Player.Name then continue end

        local pos = ball.Position
        local vel = (ball:FindFirstChild("zoomies") and ball.zoomies.VectorVelocity) or ball.Velocity
        local speed = vel.Magnitude
        local upwardSpin = vel.Y > 10
        local toPlayer = hrp.Position - pos
        local distance = toPlayer.Magnitude
        local dir = toPlayer.Unit
        local dot = vel.Unit:Dot(dir)

        if dot < 0.3 then continue end

        local mem = BallMemory[ball] or {
            lastVelocity = speed,
            lastPos = pos,
            history = {},
            lastTime = now,
        }

        table.insert(mem.history, speed)
        if #mem.history > 20 then table.remove(mem.history, 1) end

        local avgSpeed = 0
        for _, v in ipairs(mem.history) do avgSpeed += v end
        avgSpeed /= #mem.history

        local deltaSpeed = speed - mem.lastVelocity
        local travel = (pos - mem.lastPos).Magnitude

        mem.lastVelocity = speed
        mem.lastPos = pos
        mem.lastTime = now
        BallMemory[ball] = mem

        local isAccelerating = deltaSpeed > CONFIG.AccelerationThresholds.DeltaSpeed or
                               speed > avgSpeed * CONFIG.AccelerationThresholds.AvgSpeedMultiplier or
                               travel > CONFIG.AccelerationThresholds.TravelDistance

        local reactTime
        if isAccelerating then
            reactTime = (upwardSpin and CONFIG.AcceleratingReactionTime.UpwardSpin or CONFIG.AcceleratingReactionTime.Normal) * fpsFactor + ping
        else
            reactTime = (upwardSpin and CONFIG.ReactionTime.UpwardSpin or CONFIG.ReactionTime.Normal) * fpsFactor + ping
        end

        local predictedTime = distance / (speed + 1)

        local last = BallLastParryTime[ball] or 0
        local ready = now - last >= CONFIG.MinBallClickDelay and now - LastParry >= CONFIG.ParryCooldown

        if ready and (distance <= CONFIG.EmergencyParryDistance or predictedTime <= reactTime) then
            table.insert(candidates, {
                ball = ball,
                priority = predictedTime,
                distance = distance,
            })
        end
    end

    if #candidates > 0 then
        table.sort(candidates, function(a, b)
            return a.priority < b.priority
        end)

        local didParry = false

        for i, data in ipairs(candidates) do
            if i > CONFIG.MaxParryChain then break end

            local ball = data.ball
            local now = tick()

            if BallLastParryTime[ball] and now - BallLastParryTime[ball] < CONFIG.MinBallClickDelay then
                continue
            end

            if i == 2 then
                local distBetweenBalls = (candidates[1].ball.Position - candidates[2].ball.Position).Magnitude
                if distBetweenBalls <= 10 then
                    task.wait(0.03)
                end
            end

            if now - LastParry >= CONFIG.ParryCooldown and now - LastSuccessfulParry >= 0.1 then
                SmartParry()
                LastSuccessfulParry = now
                BallLastParryTime[ball] = now
                didParry = true
            end
        end

        if didParry then
            LastParry = tick()
        end
    end
end)
