--[[
    ======================================================================================================
    --                                                                                                  --
    --                                  IMBA SCRIPT v6.0 (by Jules)                                     --
    --                                        "PHOENIX EDITION"                                         --
    --                                                                                                  --
    --    DESCRIPTION:                                                                                  --
    --    A complete rewrite focusing on raw performance, reliability, and a professional UI.           --
    --    This version uses a simple, aggressive, and proven prediction model and integrates the        --
    --    standard Rayfield UI library for a flawless experience. No more failed experiments.           --
    --                                                                                                  --
    ======================================================================================================
]]

--================================================================================================--
--[[                                        [ CONFIGURATION ]                                       ]]
--================================================================================================--
local CONFIG = {
    -- Keybinds
    ToggleEnabledKey = Enum.KeyCode.F4,
    ToggleMenuKey = Enum.KeyCode.Insert,
    AutoClickKey = Enum.KeyCode.V,
    AutoSpamXKey = Enum.KeyCode.X,

    -- Parry Settings
    ParryKey = Enum.KeyCode.F,
    ParryCooldown = 0.09,
    MinBallClickDelay = 0.25,

    -- Aggressive Prediction Engine
    EmergencyParryDistance = 11,
    ReactionTime = 0.17,
    ThreatReactionTime = 0.10,
    CurveThreshold = 6,
    HumanizationFactor = 0.01,

    -- Utilities
    ClickInterval = 1 / 40, -- Faster spam
    WalkSpeed = { Enabled = false, Speed = 32 },
    JumpPower = { Enabled = false, Power = 75 },
    ESP = { Enabled = false, Players = { Enabled = true, Color = Color3.fromRGB(255, 0, 0) }, Ball = { Enabled = true, Color = Color3.fromRGB(255, 255, 0) } },
}

--================================================================================================--
--[[                                           [ SERVICES ]                                         ]]
--================================================================================================--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StatsService = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

--================================================================================================--
--[[                                        [ SCRIPT STATE ]                                        ]]
--================================================================================================--
local Player = Player or Players.LocalPlayer
local Enabled = true
local AutoSpamClick = false
local AutoSpamX = false
local LastClick = 0
local LastParry = 0
local BallMemory = {}

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
    if stats and stats:FindFirstChild("Ping") then
        return (tonumber(stats.Ping:GetValueString():match("%d+")) or 50) / 1000
    end
    return 0.05
end

local function GetBalls()
    local balls = {}
    if workspace:FindFirstChild("Balls") then
        for _, b in ipairs(workspace.Balls:GetChildren()) do
            if b:GetAttribute("realBall") and b:IsA("BasePart") then table.insert(balls, b) end
        end
    end
    return balls
end

--================================================================================================--
--[[                                     [ INVINCIBLE CORE V2 ]                                     ]]
-- A simple, aggressive, and reliable prediction engine. No more over-engineered failures.
--================================================================================================--
local InvincibleCore = {}
InvincibleCore.__index = InvincibleCore

function InvincibleCore.new(ball)
    local self = setmetatable({}, InvincibleCore)
    self.Ball = ball
    self.State = "Normal"
    self.LastParryTime = 0
    self.History = {}
    return self
end

function InvincibleCore:Update(character, ping, dt)
    local now = tick()
    if self.State == "Parried" and now - self.LastParryTime > CONFIG.MinBallClickDelay then self.State = "Normal" end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then self.Analysis = nil; return end

    local ball = self.Ball
    local vel = ball.Velocity
    local pos = ball.Position

    table.insert(self.History, {pos = pos, time = now})
    if #self.History > 10 then table.remove(self.History, 1) end
    if #self.History < 2 then self.Analysis = nil; return end

    local realPos = pos + (vel * ping)
    local distance = (hrp.Position - realPos).Magnitude

    local timeToImpact = distance / (vel.Magnitude > 0 and vel.Magnitude or 1)

    local predictedBallPos = realPos + (vel * timeToImpact)
    local curveOffset = (predictedBallPos - hrp.Position).Magnitude - (vel * timeToImpact).Magnitude

    self.Analysis = {
        Distance = distance,
        TimeToImpact = timeToImpact,
        IsThreat = curveOffset > CONFIG.CurveThreshold or vel.Magnitude > 140 or (vel.Y > 10 and vel.Magnitude > 90),
    }
end

function InvincibleCore:ShouldParry()
    if not self.Analysis or self.State == "Parried" then return false end

    local analysis = self.Analysis
    local reactionTime = (analysis.IsThreat and CONFIG.ThreatReactionTime or CONFIG.ReactionTime) + GetPing()

    if analysis.TimeToImpact <= reactionTime or analysis.Distance <= CONFIG.EmergencyParryDistance then
        return true
    end
    return false
end

function InvincibleCore:SetParried()
    self.State = "Parried"
    self.LastParryTime = tick()
end

--================================================================================================--
--[[                                        [ INPUT HANDLERS ]                                      ]]
--================================================================================================--
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if input.KeyCode == CONFIG.AutoClickKey then AutoSpamClick = true end
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
        local notifGui = Instance.new("ScreenGui", Player.PlayerGui)
        local label = Instance.new("TextLabel", notifGui)
        label.Size = UDim2.new(0.2, 0, 0.1, 0); label.Position = UDim2.new(0.4, 0, 0, 0)
        label.BackgroundColor3 = Color3.fromRGB(20, 20, 20); label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.SourceSansBold; label.TextSize = 24
        label.Text = "Core: " .. (Enabled and "ON" or "OFF")
        TweenService:Create(label, TweenInfo.new(2), {TextTransparency = 1, BackgroundTransparency = 1}):Play()
        Debris:AddItem(notifGui, 2.1)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CONFIG.AutoClickKey then AutoSpamClick = false end
    if input.KeyCode == CONFIG.AutoSpamXKey then AutoSpamX = false end
end)

--================================================================================================--
--[[                                          [ ESP LOGIC ]                                         ]]
--================================================================================================--
local ESP_CONTAINER = Instance.new("Folder", workspace)
ESP_CONTAINER.Name = "ESP_CONTAINER_" .. tostring(math.random(1, 1000))
local function UpdateESP()
    for _, v in ipairs(ESP_CONTAINER:GetChildren()) do v:Destroy() end
    if not CONFIG.ESP.Enabled then return end
    if CONFIG.ESP.Players.Enabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= Player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local box = Instance.new("BoxHandleAdornment")
                box.Adornee = player.Character.HumanoidRootPart; box.Size = player.Character:GetExtentsSize() + Vector3.new(1, 1, 1)
                box.Color3 = CONFIG.ESP.Players.Color; box.AlwaysOnTop = true; box.Parent = ESP_CONTAINER
            end
        end
    end
    if CONFIG.ESP.Ball.Enabled then
        for _, ball in ipairs(GetBalls()) do
             local box = Instance.new("BoxHandleAdornment")
             box.Adornee = ball; box.Size = ball.Size + Vector3.new(1, 1, 1)
             box.Color3 = CONFIG.ESP.Ball.Color; box.AlwaysOnTop = true; box.Parent = ESP_CONTAINER
        end
    end
end

--================================================================================================--
--[[                                          [ MAIN LOGIC ]                                        ]]
--================================================================================================--
local HeartbeatConnection = nil
local lastFrameTime = tick()

local function StartMainLogic(character)
    if HeartbeatConnection then HeartbeatConnection:Disconnect(); HeartbeatConnection = nil; end

    HeartbeatConnection = RunService.Heartbeat:Connect(function()
        local now = tick()
        local dt = now - lastFrameTime
        lastFrameTime = now

        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not (hrp and humanoid) then return end

        UpdateESP()
        if CONFIG.WalkSpeed.Enabled then humanoid.WalkSpeed = CONFIG.WalkSpeed.Speed end
        if CONFIG.JumpPower.Enabled then humanoid.JumpPower = CONFIG.JumpPower.Power end
        if AutoSpamClick and now - LastClick >= CONFIG.ClickInterval then
            LastClick = now
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end

        if not Enabled or now - LastParry < CONFIG.ParryCooldown then return end

        local ping = GetPing()
        local candidates = {}

        for _, ball in ipairs(GetBalls()) do
            if ball:GetAttribute("target") == Player.Name then
                local intel = BallMemory[ball]
                if not intel then intel = InvincibleCore.new(ball); BallMemory[ball] = intel; end

                intel:Update(character, ping, dt)

                if intel:ShouldParry() then
                    table.insert(candidates, intel)
                end
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
--[[                                     [ INITIALIZATION ]                                       ]]
--================================================================================================--
if Player.Character then StartMainLogic(Player.Character) end
Player.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid")
    StartMainLogic(character)
end)

--================================================================================================--
--[[                                        [ GALAXY UI ]                                           ]]
--  Powered by Rayfield - the standard for premium script UIs.
--================================================================================================--
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/UI-Interface/CustomFIeld/main/RayField.lua'))()

local Window = Rayfield:CreateWindow({
    Name = "IMBA SCRIPT v6.0 - PHOENIX",
    LoadingTitle = "Loading Phoenix Core...",
    LoadingSubtitle = "by Jules",
    ConfigurationSaving = { Enabled = true, FileName = "PhoenixConfig" },
    KeybindSystem = { Enabled = true, KeybindSettings = { ToggleKeybind = CONFIG.ToggleMenuKey, HoldKeybinds = false } }
})
Rayfield:SetTheme({
    Scheme = "Dark",
    Accent = Color3.fromRGB(120, 40, 255), -- Deep Purple Accent
})

-- [ Combat Tab ] --
local CombatTab = Window:CreateTab("Combat")
CombatTab:CreateToggle({ Name = "Enable Auto Parry", CurrentValue = Enabled, Flag = "AutoParryToggle", Callback = function(v) Enabled = v end })
CombatTab:CreateButton({ Name = "Spam 'X' (Hold Key)", Callback = function() end }) -- Informational
CombatTab:CreateButton({ Name = "Auto Click (Hold Key)", Callback = function() end }) -- Informational

-- [ Movement Tab ] --
local MovementTab = Window:CreateTab("Movement")
MovementTab:CreateToggle({ Name = "Enable WalkSpeed", CurrentValue = CONFIG.WalkSpeed.Enabled, Flag = "WalkSpeedToggle", Callback = function(v) CONFIG.WalkSpeed.Enabled = v end })
MovementTab:CreateSlider({ Name = "Speed", Range = {16, 120}, CurrentValue = CONFIG.WalkSpeed.Speed, Flag = "WalkSpeedSlider", Callback = function(v) CONFIG.WalkSpeed.Speed = v end })
MovementTab:CreateToggle({ Name = "Enable JumpPower", CurrentValue = CONFIG.JumpPower.Enabled, Flag = "JumpPowerToggle", Callback = function(v) CONFIG.JumpPower.Enabled = v end })
MovementTab:CreateSlider({ Name = "Power", Range = {50, 250}, CurrentValue = CONFIG.JumpPower.Power, Flag = "JumpPowerSlider", Callback = function(v) CONFIG.JumpPower.Power = v end })

-- [ Visuals Tab ] --
local VisualsTab = Window:CreateTab("Visuals")
VisualsTab:CreateToggle({ Name = "Enable ESP", CurrentValue = CONFIG.ESP.Enabled, Flag = "ESPToggle", Callback = function(v) CONFIG.ESP.Enabled = v end })
VisualsTab:CreateToggle({ Name = "Player ESP", CurrentValue = CONFIG.ESP.Players.Enabled, Flag = "PlayerESPToggle", Callback = function(v) CONFIG.ESP.Players.Enabled = v end })
VisualsTab:CreateToggle({ Name = "Ball ESP", CurrentValue = CONFIG.ESP.Ball.Enabled, Flag = "BallESPToggle", Callback = function(v) CONFIG.ESP.Ball.Enabled = v end })

-- [ Info Tab ] --
local InfoTab = Window:CreateTab("Info")
local InfoLabel = InfoTab:CreateLabel("Fetching data...")
RunService.Heartbeat:Connect(function()
    local ping = GetPing() * 1000
    local fps = 1 / (tick() - lastFrameTime)
    InfoLabel:Set(string.format("Ping: %d ms\nFPS: %d\nServer Region: %s", math.floor(ping), math.floor(fps), HttpService:GetServerRegion()))
end)
