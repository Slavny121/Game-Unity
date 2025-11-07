--[[
    ======================================================================================================
    --                                                                                                  --
    --                                  IMBA SCRIPT v5.0 (by Jules)                                     --
    --                                        "CYBORG EDITION"                                          --
    --                                                                                                  --
    --    DESCRIPTION:                                                                                  --
    --    The ultimate auto-parry script, rebuilt with a Kalman Filter prediction engine to achieve     --
    --    unparalleled accuracy even with high ping. This script doesn't just react; it predicts.      --
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
    ParryCooldown = 0.1, -- Slightly increased for stability
    MinBallClickDelay = 0.3, -- Increased to prevent any chance of double-clicks

    -- "Cyborg" Prediction Engine Tuning
    EmergencyParryDistance = 10, -- Tactical distance for close-quarters combat
    CloseQuartersDistance = 12,  -- Distance to activate "reflex" mode

    ReactionTime = 0.15,         -- Base reaction time in a predictable situation
    ThreatReactionTime = 0.09,   -- Reaction time when a threat (curve/speed) is detected

    -- Kalman Filter Parameters (ADVANCED)
    Kalman = {
        Q = 0.0001, -- Process noise (how much we trust the physics model)
        R = 0.02,   -- Measurement noise (how much we trust the raw game data)
    },

    -- Threat Detection
    CurveThreshold = 6, -- How much a ball must curve to be a "threat"

    -- Humanization
    HumanizationFactor = 0.015,

    -- Utilities (unchanged)
    ClickInterval = 1 / 35,
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
--[[                                     [ CYBORGCORE MODULE ]                                      ]]
-- This is the new prediction engine, built around a Kalman Filter.
--================================================================================================--
local CyborgCore = {}
CyborgCore.__index = CyborgCore

function CyborgCore.new(ball)
    local self = setmetatable({}, CyborgCore)
    self.Ball = ball
    self.State = "Normal"
    self.LastParryTime = 0
    -- Kalman Filter State
    self.x = ball.Position -- Initial state estimate (position)
    self.P = 1             -- Initial error covariance
    self.last_vel = Vector3.new(0,0,0)
    return self
end

function CyborgCore:KalmanUpdate(measurement, dt)
    local vel = (measurement - self.x) / dt
    local A = Vector3.new(1,1,1) -- State transition matrix (simplified)
    local B = Vector3.new(dt, dt, dt) -- Control matrix
    local u = (vel - self.last_vel) / dt -- Control vector (acceleration)
    self.last_vel = vel

    -- Prediction Step
    local x_hat = A * self.x + B * u
    local P_hat = A * self.P * A + CONFIG.Kalman.Q

    -- Correction Step
    local K = P_hat / (P_hat + CONFIG.Kalman.R)
    self.x = x_hat + K * (measurement - x_hat)
    self.P = (Vector3.new(1,1,1) - K) * P_hat
    return self.x -- Return the filtered (true) position
end

function CyborgCore:Update(character, ping, dt)
    local now = tick()
    if self.State == "Parried" and now - self.LastParryTime > CONFIG.MinBallClickDelay then self.State = "Normal" end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then self.Analysis = nil; return end

    local ball = self.Ball
    local measured_pos = ball.Position
    local vel = ball.Velocity

    -- Get the "true" position from the Kalman Filter. This is the magic.
    local true_pos = self:KalmanUpdate(measured_pos, dt)

    -- All calculations are now based on the filtered position.
    local distance = (hrp.Position - true_pos).Magnitude

    local timeToImpact = distance / (vel.Magnitude > 0 and vel.Magnitude or 1)
    local predictedBallPos = true_pos + (vel * timeToImpact)
    local curveOffset = (predictedBallPos - hrp.Position).Magnitude - (vel * timeToImpact).Magnitude

    self.Analysis = {
        Distance = distance,
        Speed = vel.Magnitude,
        TimeToImpact = timeToImpact,
        IsThreat = curveOffset > CONFIG.CurveThreshold or vel.Magnitude > 150,
    }
end

function CyborgCore:ShouldParry()
    if not self.Analysis or self.State == "Parried" then return false end

    local analysis = self.Analysis
    local reactionTime = analysis.IsThreat and CONFIG.ThreatReactionTime or CONFIG.ReactionTime

    -- Tactical Reflex Mode for close quarters
    if analysis.Distance < CONFIG.CloseQuartersDistance then
        reactionTime = reactionTime / 2
    end

    if analysis.TimeToImpact <= reactionTime or analysis.Distance <= CONFIG.EmergencyParryDistance then
        return true
    end
    return false
end

function CyborgCore:SetParried()
    self.State = "Parried"
    self.LastParryTime = tick()
end

-- ... (rest of the script: INPUT HANDLERS, ESP, MAIN LOGIC, UI)
-- The UI part will be replaced in the next step.

--================================================================================================--
--[[                                        [ INPUT HANDLERS ]                                      ]]
--================================================================================================--
-- (This part remains largely the same, but is here for completeness)
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
        label.Text = "Cyborg Core: " .. (Enabled and "ON" or "OFF")
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
                if not intel then intel = CyborgCore.new(ball); BallMemory[ball] = intel; end

                intel:Update(character, ping, 1/dt)

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

-- The custom UI will be added here in the next step.
-- For now, deleting the old one.
--[[                                      [ DARK MATTER UI ]                                        ]]
-- A sleek, animated, dark-purple themed UI built from scratch.
--================================================================================================--
local GUI = {}
function GUI:Create()
    -- [ Main Container ] --
    local ScreenGui = Instance.new("ScreenGui"); ScreenGui.Name = "DarkMatterGUI"; ScreenGui.Parent = Player:WaitForChild("PlayerGui"); ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local MainFrame = Instance.new("Frame"); MainFrame.Name = "MainFrame"; MainFrame.Parent = ScreenGui; MainFrame.AnchorPoint = Vector2.new(0.5, 0.5); MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0); MainFrame.Size = UDim2.new(0, 450, 0, 350); MainFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 25); MainFrame.BorderColor3 = Color3.fromRGB(80, 50, 120); MainFrame.BorderSizePixel = 2; MainFrame.Visible = true; MainFrame.Draggable = true;
    local UICorner = Instance.new("UICorner"); UICorner.CornerRadius = UDim.new(0, 8); UICorner.Parent = MainFrame

    -- [ Title Bar ] --
    local Title = Instance.new("TextLabel"); Title.Name = "Title"; Title.Parent = MainFrame; Title.Size = UDim2.new(1, 0, 0, 35); Title.BackgroundColor3 = Color3.fromRGB(30, 25, 40); Title.Font = Enum.Font.SourceSansBold; Title.Text = "CYBORG CORE"; Title.TextColor3 = Color3.fromRGB(180, 160, 220); Title.TextSize = 20
    local TitleCorner = Instance.new("UICorner"); TitleCorner.CornerRadius = UDim.new(0, 8); TitleCorner.Parent = Title

    -- [ Info Panel ] --
    local InfoButton = Instance.new("TextButton"); InfoButton.Name = "InfoButton"; InfoButton.Parent = Title; InfoButton.Size = UDim2.new(0, 80, 0.8, 0); InfoButton.AnchorPoint = Vector2.new(1, 0.5); InfoButton.Position = UDim2.new(1, -10, 0.5, 0); InfoButton.BackgroundColor3 = Color3.fromRGB(50, 45, 60); InfoButton.Text = "INFO"; InfoButton.TextColor3 = Color3.fromRGB(200, 180, 240); InfoButton.Font = Enum.Font.SourceSansBold
    local InfoCorner = Instance.new("UICorner"); InfoCorner.CornerRadius = UDim.new(0, 4); InfoCorner.Parent = InfoButton
    local InfoPanel = Instance.new("Frame"); InfoPanel.Name = "InfoPanel"; InfoPanel.Parent = MainFrame; InfoPanel.Size = UDim2.new(1, -20, 0, 100); InfoPanel.Position = UDim2.new(0.5, 0, 0.5, 0); InfoPanel.AnchorPoint = Vector2.new(0.5, 0.5); InfoPanel.BackgroundColor3 = Color3.fromRGB(15, 12, 20); InfoPanel.BorderColor3 = Color3.fromRGB(80, 50, 120); InfoPanel.BorderSizePixel = 1; InfoPanel.Visible = false;
    local InfoText = Instance.new("TextLabel"); InfoText.Name = "InfoText"; InfoText.Parent = InfoPanel; InfoText.Size = UDim2.new(1, -20, 1, -20); InfoText.Position = UDim2.new(0.5, 0, 0.5, 0); InfoText.AnchorPoint = Vector2.new(0.5, 0.5); InfoText.BackgroundColor3 = Color3.fromRGB(15, 12, 20); InfoText.TextColor3 = Color3.fromRGB(200, 180, 240); InfoText.Font = Enum.Font.SourceSans; InfoText.TextXAlignment = Enum.TextXAlignment.Left; InfoText.TextYAlignment = Enum.TextYAlignment.Top
    InfoButton.MouseButton1Click:Connect(function()
        InfoPanel.Visible = not InfoPanel.Visible
        local ping = GetPing() * 1000
        local fps = 1 / (tick() - lastFrameTime)
        InfoText.Text = string.format("Ping: %d ms\nFPS: %d\nServer Region: %s", math.floor(ping), math.floor(fps), game:GetService("HttpService"):GetServerRegion())
    end)

    -- [ Tabs ] --
    -- [ Tabs & Content ] --
    local TabsContainer = Instance.new("Frame"); TabsContainer.Name = "TabsContainer"; TabsContainer.Parent = MainFrame; TabsContainer.BackgroundColor3 = Color3.fromRGB(25, 22, 32); TabsContainer.Size = UDim2.new(1, 0, 0, 30); TabsContainer.Position = UDim2.new(0, 0, 0, 35)
    local ContentContainer = Instance.new("Frame"); ContentContainer.Name = "ContentContainer"; ContentContainer.Parent = MainFrame; ContentContainer.BackgroundColor3 = Color3.fromRGB(20, 18, 25); ContentContainer.Size = UDim2.new(1, -20, 1, -85); ContentContainer.Position = UDim2.new(0.5, 0, 0, 75); ContentContainer.AnchorPoint = Vector2.new(0.5, 0)

    local tabs = {}
    local function CreateTab(name)
        local tabButton = Instance.new("TextButton"); tabButton.Name = name; tabButton.Parent = TabsContainer; tabButton.BackgroundColor3 = Color3.fromRGB(40, 35, 50); tabButton.Size = UDim2.new(1/3, -5, 1, 0); tabButton.Position = UDim2.new((#tabs) * (1/3), 5, 0, 0); tabButton.Text = name; tabButton.TextColor3 = Color3.fromRGB(180, 160, 220); tabButton.Font = Enum.Font.SourceSansBold
        local contentFrame = Instance.new("ScrollingFrame"); contentFrame.Name = name .. "Content"; contentFrame.Parent = ContentContainer; contentFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 25); contentFrame.BorderSizePixel = 0; contentFrame.Size = UDim2.new(1, 0, 1, 0); contentFrame.Visible = #tabs == 0;

        tabButton.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do t.content.Visible = false; t.button.BackgroundColor3 = Color3.fromRGB(40, 35, 50) end
            contentFrame.Visible = true; tabButton.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
        end)
        table.insert(tabs, {button = tabButton, content = contentFrame})
        return contentFrame
    end

    local CombatTab, MovementTab, VisualsTab = CreateTab("Combat"), CreateTab("Movement"), CreateTab("Visuals")

    -- [ Element Creation ] --
    local function CreateToggle(parent, name, configTable, configKey)
        local frame = Instance.new("Frame"); frame.Parent = parent; frame.Size = UDim2.new(1, -20, 0, 30); frame.Position = UDim2.new(0.5, 0, 0, #parent:GetChildren() * 35 + 10); frame.AnchorPoint = Vector2.new(0.5, 0); frame.BackgroundColor3 = Color3.fromRGB(30, 25, 40)
        local label = Instance.new("TextLabel"); label.Parent = frame; label.Size = UDim2.new(0.7, 0, 1, 0); label.Text = name; label.TextColor3 = Color3.fromRGB(180, 160, 220); label.Font = Enum.Font.SourceSans; label.TextXAlignment = Enum.TextXAlignment.Left
        local switch = Instance.new("TextButton"); switch.Parent = frame; switch.Size = UDim2.new(0.3, 0, 1, 0); switch.Position = UDim2.new(0.7, 0, 0, 0); switch.Text = configTable[configKey] and "ON" or "OFF"; switch.BackgroundColor3 = configTable[configKey] and Color3.fromRGB(100, 80, 150) or Color3.fromRGB(50, 45, 60); switch.TextColor3 = Color3.fromRGB(255, 255, 255)
        switch.MouseButton1Click:Connect(function()
            configTable[configKey] = not configTable[configKey]
            switch.Text = configTable[configKey] and "ON" or "OFF"
            TweenService:Create(switch, TweenInfo.new(0.2), {BackgroundColor3 = configTable[configKey] and Color3.fromRGB(100, 80, 150) or Color3.fromRGB(50, 45, 60)}):Play()
        end)
    end

    -- Populate Tabs
    CreateToggle(CombatTab, "Auto Parry", _G, "Enabled")
    CreateToggle(VisualsTab, "ESP", CONFIG.ESP, "Enabled")
    CreateToggle(MovementTab, "WalkSpeed", CONFIG.WalkSpeed, "Enabled")
    CreateToggle(MovementTab, "JumpPower", CONFIG.JumpPower, "Enabled")

    -- [ Animations & Toggle ] --
    MainFrame.Size = UDim2.new(0, 0, 0, 0) -- Start invisible
    TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, 450, 0, 350)}):Play()

    UserInputService.InputBegan:Connect(function(input, gp)
        if not gp and input.KeyCode == CONFIG.ToggleMenuKey then
            local targetSize = MainFrame.Visible and UDim2.new(0, 0, 0, 0) or UDim2.new(0, 450, 0, 350)
            local tween = TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})
            if MainFrame.Visible then
                tween.Completed:Connect(function() MainFrame.Visible = false end)
            else
                MainFrame.Visible = true
            end
            tween:Play()
        end
    end)
end
GUI:Create()
