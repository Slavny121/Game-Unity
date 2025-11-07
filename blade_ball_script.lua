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
    ParryCooldown = 0.1,
    MinBallClickDelay = 0.4,
    EmergencyParryDistance = 10,
    HumanizationFactor = 0.01,
    -- New Prediction Model Config
    Prediction = {
        Gravity = Vector3.new(0, -workspace.Gravity, 0),
        ReactionTime = 0.15,
        ThreatReactionTime = 0.08,
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
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if input.KeyCode == CONFIG.AutoSpamXKey then
        AutoSpamX = true
        coroutine.wrap(function()
            while AutoSpamX do
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.X, false, game)
                task.wait()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.X, false, game)
            end
        end)()
    end
    if input.KeyCode == CONFIG.ToggleEnabledKey then
        Enabled = not Enabled
        -- (Notification logic will be re-added with the UI)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CONFIG.AutoSpamXKey then AutoSpamX = false end
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
--[[                                    [ PERFECT ANALOG CORE ]                                     ]]
-- This is the new prediction engine, based on proven ballistic trajectory equations.
-- Every line is documented to explain exactly how it works.
--================================================================================================--
local PerfectAnalogCore = {}
PerfectAnalogCore.__index = PerfectAnalogCore

--- Creates a new Core object for a ball.
function PerfectAnalogCore.new(ball)
    local self = setmetatable({}, PerfectAnalogCore)
    self.Ball = ball
    self.State = "Tracking" -- States: Tracking, Parried
    self.LastParryTime = 0
    return self
end

--- The main update function, called every frame.
function PerfectAnalogCore:Update(character, ping)
    local now = tick()
    -- Reset state after cooldown to allow re-parrying the same ball later.
    if self.State == "Parried" and now - self.LastParryTime > CONFIG.MinBallClickDelay then self.State = "Tracking" end
    -- If the ball is in a cooldown state, do not perform any calculations.
    if self.State == "Parried" then self.Analysis = nil; return end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then self.Analysis = nil; return end

    -- Get current ball physics properties.
    local ballPos = self.Ball.Position
    local ballVel = self.Ball.Velocity

    -- Compensate for network latency (ping).
    -- We estimate the "real" position of the ball by moving it forward in time by the ping amount.
    local realPos = ballPos + (ballVel * ping)

    -- Vector from ball to player.
    local delta = hrp.Position - realPos

    -- Ballistic Trajectory Calculation (from EgoMoose's tutorials)
    -- This solves for the time it will take for a projectile to hit a target.
    local a = 0.5 * CONFIG.Prediction.Gravity.Y
    local b = ballVel.Y
    local c = -delta.Y

    -- Quadratic formula to find time 't'.
    local discriminant = (b^2) - (4*a*c)
    if discriminant < 0 then self.Analysis = nil; return end -- No real solution, trajectory won't hit.

    -- We choose the positive solution for time.
    local t = (-b - math.sqrt(discriminant)) / (2*a)

    -- If time is negative or invalid, fall back to a simpler linear calculation.
    if t < 0 or t ~= t then
        t = delta.Magnitude / (ballVel.Magnitude > 0 and ballVel.Magnitude or 1)
    end

    -- Store the analysis results.
    self.Analysis = {
        TimeToImpact = t,
        IsThreat = ballVel.Magnitude > 130 or (ballVel.Y > 10 and ballVel.Magnitude > 80),
    }
end

--- The final decision maker.
function PerfectAnalogCore:ShouldParry()
    -- Do not parry if no valid analysis exists or if the ball is on cooldown.
    if not self.Analysis or self.State == "Parried" then return false end

    -- Choose a reaction time based on whether the ball is a threat.
    local reactionTime = (self.Analysis.IsThreat and CONFIG.Prediction.ThreatReactionTime or CONFIG.Prediction.ReactionTime) + GetPing()

    -- Parry if the time to impact is within our reaction window, or if it's an emergency.
    if self.Analysis.TimeToImpact <= reactionTime or (self.Ball.Position - Player.Character.HumanoidRootPart.Position).Magnitude <= CONFIG.EmergencyParryDistance then
        return true
    end
    return false
end

--- Sets the ball's state to "Parried" to start its cooldown.
function PerfectAnalogCore:SetParried()
    self.State = "Parried"
    self.LastParryTime = tick()
end

--================================================================================================--
--[[                                          [ MAIN LOGIC ]                                        ]]
--================================================================================================--
local HeartbeatConnection = nil
local function StartMainLogic(character)
    if HeartbeatConnection then HeartbeatConnection:Disconnect() end
    HeartbeatConnection = RunService.Heartbeat:Connect(function()
        local now = tick()
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not (hrp and character:FindFirstChildOfClass("Humanoid")) then return end
        if not Enabled or now - LastParry < CONFIG.ParryCooldown then return end

        local ping = GetPing()
        local candidates = {}

        for _, ball in ipairs(GetBalls()) do
            if ball:GetAttribute("target") == Player.Name then
                local intel = BallMemory[ball] or PerfectAnalogCore.new(ball)
                BallMemory[ball] = intel
                intel:Update(character, ping)
                if intel:ShouldParry() then table.insert(candidates, intel) end
            end
        end

        if #candidates > 0 then
            table.sort(candidates, function(a, b) return a.Analysis.TimeToImpact < b.Analysis.TimeToImpact end)
            local topThreat = candidates[1]
            SmartParry()
            topThreat:SetParried()
        end
    end)
end

--================================================================================================--
--[[                                    [ GALAXY UI - RAYFIELD ]                                    ]]
--================================================================================================--
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield.lua'))()

local Window = Rayfield:CreateWindow({
    Name = "IMBA SCRIPT v8.0 - PERFECT ANALOG",
    LoadingTitle = "Loading Perfect Analog Core...",
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
