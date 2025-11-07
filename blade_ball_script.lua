--[[
    ======================================================================================================
    --                         IMBA SCRIPT v8.0 (by Jules) - "PERFECT ANALOG"                           --
    ======================================================================================================
]]

--================================================================================================--
--[[                                        [ CONFIGURATION ]                                       ]]
--================================================================================================--
local CONFIG = {
    ToggleEnabledKey = Enum.KeyCode.F4,
    ToggleMenuKey = Enum.KeyCode.Insert,
    AutoSpamXKey = Enum.KeyCode.X,
    ParryKey = Enum.KeyCode.F,
    -- Aggressive Tuning for "Invincible" Performance
    ParryCooldown = 0.08,          -- Lower cooldown for faster successive parries.
    MinBallClickDelay = 0.15,      -- Allows re-parrying the same ball much faster.
    EmergencyParryDistance = 12,   -- Increased safety distance.
    HumanizationFactor = 0,        -- No artificial delay for machine precision.
    Prediction = {
        -- Reaction times are now extremely low for maximum performance.
        ReactionTime = 0.12,       -- Base reaction time.
        ThreatReactionTime = 0.05, -- Reaction time for high-speed/ability balls.
    }
}

--================================================================================================--
--[[                                           [ SERVICES & STATE ]                                 ]]
--================================================================================================--
local Players, RunService, UserInputService, VirtualInputManager, StatsService, HttpService =
    game:GetService("Players"), game:GetService("RunService"), game:GetService("UserInputService"),
    game:GetService("VirtualInputManager"), game:GetService("Stats"), game:GetService("HttpService")

local Player = Players.LocalPlayer
local Enabled = true
local AutoSpamX = false
local LastParry = 0
local BallMemory = {}
local lastFrameTime = tick()

--================================================================================================--
--[[                                        [ INPUT HANDLERS ]                                      ]]
--================================================================================================--
-- (This part is correct and will be preserved)
--================================================================================================--
--[[                                    [ ADVANCED INPUT HANDLERS ]                                 ]]
--================================================================================================--
local SpamConnection = nil
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if input.KeyCode == CONFIG.AutoSpamXKey and not SpamConnection then
        SpamConnection = RunService.Heartbeat:Connect(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.X, false, game)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.X, false, game)
        end)
    end
    if input.KeyCode == CONFIG.ToggleEnabledKey then
        Enabled = not Enabled
        print("Auto Parry Toggled: " .. (Enabled and "ON" or "OFF"))
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CONFIG.AutoSpamXKey then
        if SpamConnection then
            SpamConnection:Disconnect()
            SpamConnection = nil
        end
    end
end)

--================================================================================================--
--[[                                          [ CORE FUNCTIONS ]                                    ]]
--================================================================================================--
local function SmartParry()
    if CONFIG.HumanizationFactor > 0 then task.wait(math.random() * CONFIG.HumanizationFactor) end
    LastParry = tick()
    VirtualInputManager:SendKeyEvent(true, CONFIG.ParryKey, false, game)
    VirtualInputManager:SendKeyEvent(false, CONFIG.ParryKey, false, game)
end

local function GetPing()
    local stats = StatsService:FindFirstChild("PerformanceStats")
    if stats and stats:FindFirstChild("Ping") then return (tonumber(stats.Ping:GetValueString():match("%d+")) or 50) / 1000 end
    return 0.05
end

local function GetBalls()
    local balls = {}
    if workspace:FindFirstChild("Balls") then
        for _, b in ipairs(workspace.Balls:GetChildren()) do if b:GetAttribute("realBall") then table.insert(balls, b) end end
    end
    return balls
end

--================================================================================================--
--[[                                      [ INVINCIBLE CORE ]                                       ]]
-- This is the new "Invincible" prediction engine. It's more aggressive and adaptive.
-- It tracks acceleration to detect ability usage and uses a threat assessment system.
--================================================================================================--
local InvincibleCore = {}
InvincibleCore.__index = InvincibleCore

function InvincibleCore.new(ball)
    local self = setmetatable({}, InvincibleCore)
    self.Ball = ball
    self.State = "Tracking"
    self.LastParryTime = 0
    self.History = {} -- Stores past velocity and position data
    return self
end

function InvincibleCore:Update(character, ping, fps)
    local now = tick()
    if self.State == "Parried" and now - self.LastParryTime > CONFIG.MinBallClickDelay then
        self.State = "Tracking"
    end
    if self.State == "Parried" then self.Analysis = nil; return end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then self.Analysis = nil; return end

    local ballPos = self.Ball.Position
    local ballVel = self.Ball.Velocity

    -- Store history for acceleration calculation
    table.insert(self.History, {Time = now, Velocity = ballVel})
    if #self.History > 5 then table.remove(self.History, 1) end

    local acceleration = 0
    if #self.History > 1 then
        local first = self.History[1]
        local last = self.History[#self.History]
        local deltaTime = last.Time - first.Time
        if deltaTime > 0 then
            acceleration = (last.Velocity.Magnitude - first.Velocity.Magnitude) / deltaTime
        end
    end

    -- Ping compensation and future position prediction
    local predictedPos = ballPos + (ballVel * ping)
    local timeToImpact = (hrp.Position - predictedPos).Magnitude / (ballVel.Magnitude > 1 and ballVel.Magnitude or 1)

    -- Threat Assessment
    local speedThreat = math.clamp(ballVel.Magnitude / 200, 0, 1) -- Normalize speed to a 0-1 threat score
    local accelThreat = math.clamp(acceleration / 150, 0, 1)    -- Normalize acceleration to a 0-1 threat score
    local proximityThreat = math.clamp(1 - ((hrp.Position - ballPos).Magnitude / 50), 0, 1) -- Normalize distance

    local totalThreat = (speedThreat * 0.5) + (accelThreat * 0.3) + (proximityThreat * 0.2)

    self.Analysis = {
        TimeToImpact = timeToImpact,
        ThreatLevel = totalThreat,
        IsHighSpeed = ballVel.Magnitude > 150 or acceleration > 100,
    }
end

function InvincibleCore:ShouldParry()
    if not self.Analysis or self.State == "Parried" then return false end

    -- Dynamic Reaction Time based on threat
    local baseReaction = self.Analysis.IsHighSpeed and CONFIG.Prediction.ThreatReactionTime or CONFIG.Prediction.ReactionTime
    local dynamicReaction = baseReaction - (self.Analysis.ThreatLevel * 0.05) -- Higher threat = lower reaction time

    local reactionTime = dynamicReaction + GetPing()

    if self.Analysis.TimeToImpact <= reactionTime or (self.Ball.Position - Player.Character.HumanoidRootPart.Position).Magnitude <= CONFIG.EmergencyParryDistance then
        return true
    end
    return false
end

function InvincibleCore:SetParried()
    self.State = "Parried"
    self.LastParryTime = tick()
end


--================================================================================================--
--[[                                          [ MAIN LOGIC V2 ]                                     ]]
--================================================================================================--
local HeartbeatConnection = nil
local function StartMainLogic(character)
    if HeartbeatConnection then HeartbeatConnection:Disconnect() end

    HeartbeatConnection = RunService.Heartbeat:Connect(function()
        local now = tick()
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not (hrp and character:FindFirstChildOfClass("Humanoid")) or not Enabled then return end

        -- Stricter parry cooldown management
        if now - LastParry < CONFIG.ParryCooldown then return end

        local ping = GetPing()
        local fps = 1 / (now - lastFrameTime)
        lastFrameTime = now

        local candidates = {}
        for _, ball in ipairs(GetBalls()) do
            if ball:GetAttribute("target") == Player.Name then
                local intel = BallMemory[ball] or InvincibleCore.new(ball)
                BallMemory[ball] = intel
                intel:Update(character, ping, fps)
                if intel:ShouldParry() then table.insert(candidates, intel) end
            end
        end

        if #candidates == 0 then return end

        -- Prioritize by Threat Level, then Time To Impact
        table.sort(candidates, function(a, b)
            if a.Analysis.ThreatLevel ~= b.Analysis.ThreatLevel then
                return a.Analysis.ThreatLevel > b.Analysis.ThreatLevel
            end
            return a.Analysis.TimeToImpact < b.Analysis.TimeToImpact
        end)

        -- Execute parry for the highest threat
        local topThreat = candidates[1]
        SmartParry()
        topThreat:SetParried()

        -- Multi-parry logic: If a second ball is an immediate threat, parry again with a small delay.
        if #candidates > 1 then
            local secondThreat = candidates[2]
            local timeDiff = math.abs(topThreat.Analysis.TimeToImpact - secondThreat.Analysis.TimeToImpact)
            if timeDiff < 0.15 and secondThreat.Analysis.ThreatLevel > 0.5 then
                task.wait(0.08) -- Minimal delay to avoid game engine issues
                if tick() - LastParry > CONFIG.ParryCooldown then
                    SmartParry()
                    secondThreat:SetParried()
                end
            end
        end
    end)
end

--================================================================================================--
--[[                                    [ GALAXY UI - RAYFIELD ]                                    ]]
--================================================================================================--
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield.lua'))()

local Window = Rayfield:CreateWindow({
    Name = "IMBA SCRIPT v9.0 - INVINCIBLE CORE",
    LoadingTitle = "Loading Invincible Core...",
    LoadingSubtitle = "by Jules",
    ConfigurationSaving = { Enabled = true, FileName = "PerfectAnalogConfig" },
    KeybindSystem = { Enabled = true, KeybindSettings = { ToggleKeybind = CONFIG.ToggleMenuKey, HoldKeybinds = false } }
})

Rayfield:SetTheme({
    Scheme = "Dark",
    Accent = Color3.fromRGB(130, 80, 255), -- Galaxy Purple
})

-- [ Combat Tab ] --
local CombatTab = Window:CreateTab("Combat", 4483362458)
CombatTab:CreateToggle({
    Name = "Enable Auto Parry",
    CurrentValue = Enabled,
    Flag = "AutoParryToggle",
    Callback = function(v) Enabled = v end
})
CombatTab:CreateLabel("Hold 'X' to spam deflect")

-- [ Info Tab ] --
local InfoTab = Window:CreateTab("Info", 4483362458)
local InfoLabel = InfoTab:CreateLabel("Fetching data...")

-- We only want to run the UI update loop when the window is actually visible to save performance.
local uiUpdateConnection = nil
local function manageUiUpdates()
    if Window.Visible and not uiUpdateConnection then
        local lastFrameTimeForUI = tick()
        uiUpdateConnection = RunService.Heartbeat:Connect(function()
            if not Window.Visible then
                uiUpdateConnection:Disconnect()
                uiUpdateConnection = nil
                return
            end
            local now = tick()
            local ping = GetPing() * 1000
            local fps = 1 / (now - lastFrameTimeForUI)
            lastFrameTimeForUI = now
            local region = "N/A"
            pcall(function() region = HttpService:GetServerRegion() end) -- Wrap in pcall for safety
            InfoLabel:Set(string.format("Ping: %.0f ms\nFPS: %.0f\nServer Region: %s", ping, fps, region))
        end)
    elseif not Window.Visible and uiUpdateConnection then
        uiUpdateConnection:Disconnect()
        uiUpdateConnection = nil
    end
end

-- Hook into Rayfield's visibility event to manage the update loop automatically.
Window:GetToggle(manageUiUpdates)
manageUiUpdates() -- Initial call in case the window is already visible on script start.


--================================================================================================--
--[[                                     [ INITIALIZATION ]                                       ]]
--================================================================================================--
if Player.Character then StartMainLogic(Player.Character) end
Player.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid")
    StartMainLogic(character)
end)
