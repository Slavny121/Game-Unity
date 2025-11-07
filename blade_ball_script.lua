--[[
    ======================================================================================================
    --                                                                                                  --
    --                                  IMBA SCRIPT v4.0 (by Jules)                                     --
    --                                                                                                  --
    --    DESCRIPTION:                                                                                  --
    --    This is the ultimate auto-parry and utility script for Blade Ball, rebuilt from the ground    --
    --    up for maximum performance, accuracy, and security. It features an intelligent prediction     --
    --    engine that behaves like a top-tier player, making tactical decisions in real-time.           --
    --                                                                                                  --
    --    FEATURES:                                                                                     --
    --    - INTELLECTUAL AUTO-PARRY: A state-of-the-art prediction core that analyzes ball physics,      --
    --      detects complex trajectories (curves, acceleration), and makes human-like decisions.        --
    --    - TACTICAL THREAT ASSESSMENT: Intelligently prioritizes the most dangerous ball when faced    --
    --      with multiple threats.                                                                      --
    --    - HUMANIZATION: Actions are slightly randomized to mimic a real player, reducing detection risk.--
    --    - UTILITIES: ESP, WalkSpeed/JumpPower control, and powerful key-spam features.                --
    --    - CUSTOM PREMIUM UI: A sleek, custom-built UI for controlling all features.                   --
    --                                                                                                  --
    ======================================================================================================
]]

--================================================================================================--
--[[                                        [ CONFIGURATION ]                                       ]]
--  This is the central control panel for the script. Adjust these values to fine-tune performance.
--================================================================================================--
local CONFIG = {
    -- [ Keybinds ] --
    -- Define the keys to control the script's functions.
    ToggleEnabledKey = Enum.KeyCode.F4,      -- Press to toggle the auto parry ON/OFF.
    ToggleMenuKey = Enum.KeyCode.Insert,     -- Press to show/hide the menu.
    AutoClickKey = Enum.KeyCode.V,            -- Hold to spam left mouse clicks.
    AutoSpamXKey = Enum.KeyCode.X,            -- Hold to spam the 'X' key.

    -- [ Auto Parry Settings ] --
    -- Core settings for the parry mechanic.
    ParryKey = Enum.KeyCode.F,                -- The keybind for parrying in-game.
    ParryCooldown = 0.09,                     -- (Seconds) A global cooldown after any parry attempt to prevent spam.
    MinBallClickDelay = 0.25,                 -- (Seconds) A specific cooldown for EACH ball to prevent double-clicking the same ball.

    -- [ Prediction Engine Tuning ] --
    -- These values control the "brain" of the auto-parry. Lower reaction times = parry sooner.
    EmergencyParryDistance = 12,              -- (Studs) Parries any ball within this distance, regardless of prediction. A failsafe.

    -- Base reaction time for "normal" situations.
    ReactionTime = {
        Normal = 0.18,                        -- Reaction time for a standard, predictable ball.
        UpwardSpin = 0.14,                    -- Reaction time for balls with upward momentum.
    },
    -- Reaction time for "threat" situations (high speed, curves).
    AcceleratingReactionTime = {
        Normal = 0.11,                        -- Faster reaction time for accelerating balls.
        UpwardSpin = 0.07,                    -- Fastest reaction time for accelerating, spinning balls.
    },

    -- [ Threat Detection Thresholds ] --
    -- How the script defines a "dangerous" ball.
    AccelerationThresholds = {
        DeltaSpeed = 20,                      -- Speed increase required to be considered "accelerating".
    },

    -- [ Ball Intelligence Settings ] --
    -- Parameters for the `BallIntelligence` module.
    SmartParry = {
        HistoryBufferSize = 40,               -- How many past frames of data to analyze for each ball.
        CurveDetectionThreshold = 5,          -- (Studs) How far the ball must deviate from a straight path to be considered "curved".
        HumanizationFactor = 0.02,            -- (Seconds) Adds a tiny random delay to parries to look more human. Set to 0 to disable.
    },

    -- [ Performance Settings ] --
    -- Helps the script adapt to your computer's performance.
    FPSTarget = 60,                           -- The script will adjust timings to try and match this FPS target.

    -- [ Utility Settings ] --
    -- Settings for other script features.
    ClickInterval = 1 / 35,                   -- (Seconds) Delay between clicks for the auto-clicker.
    WalkSpeed = {
        Enabled = false,
        Speed = 32 -- Default is 16
    },
    JumpPower = {
        Enabled = false,
        Power = 75 -- Default is 50
    },
    ESP = {
        Enabled = false,
        Players = { Enabled = true, Color = Color3.fromRGB(255, 0, 0) },
        Ball = { Enabled = true, Color = Color3.fromRGB(255, 255, 0) }
    },
}

--================================================================================================--
--[[                                           [ SERVICES ]                                         ]]
--  Loading essential Roblox services. This is standard practice for clean code.
--================================================================================================--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StatsService = game:GetService("Stats")

--================================================================================================--
--[[                                        [ SCRIPT STATE ]                                        ]]
--  Global variables that track the script's current state.
--================================================================================================--
local Player = Players.LocalPlayer
local AutoSpamClick = false
local AutoSpamX = false
local Enabled = true -- Controls the auto-parry specifically.

local LastClick = 0 -- Timestamp for the auto-clicker.
local LastParry = 0 -- Timestamp for the GLOBAL parry cooldown.

local BallMemory = {} -- Stores the `BallIntelligence` object for each ball.

--================================================================================================--
--[[                                          [ CORE FUNCTIONS ]                                    ]]
--  Essential helper functions used throughout the script.
--================================================================================================--

--[[
    --- @Description
    -- Simulates a key press for the parry action. Includes a humanization delay.
]]
local function SmartParry()
    if CONFIG.SmartParry.HumanizationFactor > 0 then
        task.wait(math.random() * CONFIG.SmartParry.HumanizationFactor)
    end
    LastParry = tick()
    VirtualInputManager:SendKeyEvent(true, CONFIG.ParryKey, false, game)
    VirtualInputManager:SendKeyEvent(false, CONFIG.ParryKey, false, game)
end

--[[
    --- @Description
    -- Retrieves the player's current ping. Critical for accurate prediction.
]]
local function GetPing()
    local stats = StatsService:FindFirstChild("PerformanceStats")
    if stats and stats:FindFirstChild("Ping") then
        local pingValue = stats.Ping:GetValueString():match("%d+")
        return tonumber(pingValue) or 50
    end
    return 50
end

--[[
    --- @Description
    -- Finds and returns all active "real" balls in the workspace.
]]
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
--[[                                    [ BALL INTELLIGENCE MODULE ]                                ]]
--  This is the brain of the auto-parry. It analyzes ball behavior to make smart decisions.
--================================================================================================--
local BallIntelligence = {}
BallIntelligence.__index = BallIntelligence

--[[
    --- @Description
    -- Creates a new "intelligence" object for a specific ball.
]]
function BallIntelligence.new(ball)
    local self = setmetatable({}, BallIntelligence)
    self.Ball = ball
    self.History = {}
    self.State = "Normal" -- States: Normal, Parried, HighSpeed, Curved
    self.LastParryTime = 0
    return self
end

--[[
    --- @Description
    -- Updates the ball's state and runs all physical calculations.
]]
function BallIntelligence:Update(character, ping, fps)
    local now = tick()
    -- Transition out of "Parried" state after the cooldown to prevent double-clicks.
    if self.State == "Parried" and now - self.LastParryTime > CONFIG.MinBallClickDelay then
        self.State = "Normal"
    end

    -- Update history with current data.
    local ball = self.Ball
    local vel = (ball:FindFirstChild("zoomies") and ball.zoomies.VectorVelocity) or ball.Velocity
    local pos = ball.Position
    table.insert(self.History, { Time = now, Position = pos, Velocity = vel })
    if #self.History > CONFIG.SmartParry.HistoryBufferSize then
        table.remove(self.History, 1)
    end

    -- Exit if we don't have enough data to analyze.
    if #self.History < 2 then
        self.Analysis = nil
        return
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- Physics Calculations
    local latest = self.History[#self.History]
    local previous = self.History[#self.History - 1]
    local deltaTime = latest.Time - previous.Time
    if deltaTime == 0 then return end

    local realPos = latest.Position + (latest.Velocity * ping) -- Compensate for ping
    local distance = (hrp.Position - realPos).Magnitude
    local acceleration = (latest.Velocity.Magnitude - previous.Velocity.Magnitude) / deltaTime

    -- Advanced Curve Detection: Predict where the ball and player will be and measure the offset.
    local playerVel = hrp.Velocity
    local relativeVel = latest.Velocity - playerVel
    local timeToImpact = distance / (relativeVel.Magnitude > 0 and relativeVel.Magnitude or 1)

    local predictedBallPos = realPos + (latest.Velocity * timeToImpact)
    local predictedPlayerPos = hrp.Position + (playerVel * timeToImpact)
    local curveOffset = (predictedBallPos - predictedPlayerPos).Magnitude

    -- Update the ball's state based on the analysis.
    if self.State ~= "Parried" then
        if acceleration > CONFIG.AccelerationThresholds.DeltaSpeed or latest.Velocity.Magnitude > 150 then
            self.State = "HighSpeed"
        elseif curveOffset > CONFIG.SmartParry.CurveDetectionThreshold then
            self.State = "Curved"
        else
            self.State = "Normal"
        end
    end

    -- Store the results for other functions to use.
    self.Analysis = {
        Distance = distance,
        Speed = latest.Velocity.Magnitude,
        Acceleration = acceleration,
        TimeToImpact = timeToImpact,
        CurveOffset = curveOffset,
        Ping = ping,
        FPSFactor = math.clamp(1 - (fps < CONFIG.FPSTarget and (CONFIG.FPSTarget - fps) / 100 or 0), 0.8, 1),
    }
end

--[[
    --- @Description
    -- Calculates a "threat score" for the ball to prioritize targets.
]]
function BallIntelligence:GetThreatLevel()
    if not self.Analysis then return 0 end
    local analysis = self.Analysis
    -- A formula that weighs speed and curve higher than distance.
    local threat = (analysis.Speed * 1.5) + (analysis.CurveOffset * 0.8) - (analysis.Distance * 0.7)
    if self.State == "HighSpeed" or self.State == "Curved" then
        threat = threat * 1.5 -- Threats are more dangerous.
    end
    return threat
end

--[[
    --- @Description
    -- The final decision maker. Decides if it's the perfect moment to parry.
]]
function BallIntelligence:ShouldParry()
    -- Don't parry if we have no analysis or if the ball was just parried.
    if not self.Analysis or self.State == "Parried" then return false end

    local analysis = self.Analysis
    -- Use faster reaction times for threats.
    local baseReactionTime = (self.State == "HighSpeed" or self.State == "Curved") and CONFIG.AcceleratingReactionTime.Normal or CONFIG.ReactionTime.Normal

    -- Adjust for performance and network.
    local reactionTime = (baseReactionTime * analysis.FPSFactor) + analysis.Ping

    -- Final Decision: Parry if time-to-impact is less than our reaction time, or if it's an emergency.
    if analysis.TimeToImpact <= reactionTime or analysis.Distance <= CONFIG.EmergencyParryDistance then
        return true
    end
    return false
end

--[[
    --- @Description
    -- Sets the ball's state to "Parried" to activate its internal cooldown.
]]
function BallIntelligence:SetParried()
    self.State = "Parried"
    self.LastParryTime = tick()
end


--================================================================================================--
--[[                                        [ INPUT HANDLERS ]                                      ]]
--  Manages all player keyboard inputs.
--================================================================================================--
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    -- Ignore inputs if the player is typing in chat.
    if gameProcessedEvent then return end

    -- Handle Auto-Click
    if input.KeyCode == CONFIG.AutoClickKey then
        AutoSpamClick = true
    end
    -- Handle 'X' Spam
    if input.KeyCode == CONFIG.AutoSpamXKey then
        AutoSpamX = true
        coroutine.wrap(function()
            while AutoSpamX do
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.X, false, game)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.X, false, game)
                task.wait()
            end
        end)()
    end
    -- Handle Auto-Parry Toggle
    if input.KeyCode == CONFIG.ToggleEnabledKey then
        Enabled = not Enabled
        -- Display an on-screen notification.
        local notifGui = Instance.new("ScreenGui", Player.PlayerGui)
        notifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local label = Instance.new("TextLabel", notifGui)
        label.Size = UDim2.new(0.2, 0, 0.1, 0); label.Position = UDim2.new(0.4, 0, 0, 0)
        label.BackgroundColor3 = Color3.fromRGB(20, 20, 20); label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.SourceSansBold; label.TextSize = 24
        label.Text = "Auto Parry: " .. (Enabled and "ON" or "OFF")
        game:GetService("TweenService"):Create(label, TweenInfo.new(2), {TextTransparency = 1, BackgroundTransparency = 1}):Play()
        game:GetService("Debris"):AddItem(notifGui, 2.1)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CONFIG.AutoClickKey then AutoSpamClick = false end
    if input.KeyCode == CONFIG.AutoSpamXKey then AutoSpamX = false end
end)

--================================================================================================--
--[[                                          [ ESP LOGIC ]                                         ]]
--  Handles the drawing of visual aids (ESP).
--================================================================================================--
local ESP_CONTAINER = Instance.new("Folder", workspace)
ESP_CONTAINER.Name = "ESP_CONTAINER_" .. tostring(math.random(1, 1000))

--[[
    --- @Description
    -- Updates and redraws all ESP elements on the screen.
]]
local function UpdateESP()
    -- Clear previous visuals to prevent clutter.
    for _, v in ipairs(ESP_CONTAINER:GetChildren()) do v:Destroy() end
    if not CONFIG.ESP.Enabled then return end

    -- Draw player ESP if enabled.
    if CONFIG.ESP.Players.Enabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if player == Player then continue end
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local box = Instance.new("BoxHandleAdornment")
                box.Adornee = char.HumanoidRootPart; box.Size = char:GetExtentsSize() + Vector3.new(1, 1, 1)
                box.Color3 = CONFIG.ESP.Players.Color; box.AlwaysOnTop = true
                box.ZIndex = 1; box.Parent = ESP_CONTAINER
            end
        end
    end
    -- Draw ball ESP if enabled.
    if CONFIG.ESP.Ball.Enabled then
        for _, ball in ipairs(GetBalls()) do
             local box = Instance.new("BoxHandleAdornment")
             box.Adornee = ball; box.Size = ball.Size + Vector3.new(1, 1, 1)
             box.Color3 = CONFIG.ESP.Ball.Color; box.AlwaysOnTop = true
             box.ZIndex = 2; box.Parent = ESP_CONTAINER
        end
    end
end

--================================================================================================--
--[[                                          [ MAIN LOGIC ]                                        ]]
--  This is the core loop that runs every frame.
--================================================================================================--
local HeartbeatConnection = nil

--[[
    --- @Description
    -- The main function that contains the script's core loop (Heartbeat).
    -- It's wrapped in a function so it can be restarted on respawn.
]]
local function StartMainLogic(character)
    -- Disconnect the old loop if it exists, to prevent multiple loops running.
    if HeartbeatConnection then HeartbeatConnection:Disconnect(); HeartbeatConnection = nil; end

    HeartbeatConnection = RunService.Heartbeat:Connect(function()
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not (hrp and humanoid) then return end

        -- Run utility functions.
        UpdateESP()
        if CONFIG.WalkSpeed.Enabled then humanoid.WalkSpeed = CONFIG.WalkSpeed.Speed end
        if CONFIG.JumpPower.Enabled then humanoid.JumpPower = CONFIG.JumpPower.Power end
        if AutoSpamClick and tick() - LastClick >= CONFIG.ClickInterval then
            LastClick = tick()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end

        -- Core Parry Logic starts here. Only run if enabled.
        if not Enabled then return end
        if tick() - LastParry < CONFIG.ParryCooldown then return end -- Respect global cooldown.

        local ping = GetPing() / 1000
        local fps = workspace:GetRealPhysicsFPS()
        local candidates = {}

        -- 1. Analyze all balls and identify potential threats.
        for _, ball in ipairs(GetBalls()) do
            if ball:GetAttribute("target") ~= Player.Name then continue end

            -- Get or create the intelligence object for this ball.
            local intel = BallMemory[ball]
            if not intel then intel = BallIntelligence.new(ball); BallMemory[ball] = intel; end

            intel:Update(character, ping, fps)

            if intel:ShouldParry() then
                table.insert(candidates, intel)
            end
        end

        -- 2. If there are threats, decide which one to parry.
        if #candidates > 0 then
            -- Sort threats by their calculated threat level.
            table.sort(candidates, function(a, b) return a:GetThreatLevel() > b:GetThreatLevel() end)

            -- 3. Execute the parry on the most dangerous ball.
            local topThreat = candidates[1]
            SmartParry()
            topThreat:SetParried() -- Set the ball's state to "Parried".
        end
    end)
end

--================================================================================================--
--[[                                     [ INITIALIZATION ]                                       ]]
--  Sets up the script when it's first injected.
--================================================================================================--
-- Start the main logic when the script loads.
if Player.Character then
    StartMainLogic(Player.Character)
end
-- Restart the main logic every time the player respawns to ensure stability.
Player.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid")
    StartMainLogic(character)
end)

--================================================================================================--
--[[                                      [ CUSTOM PREMIUM UI ]                                     ]]
--  Creates the custom graphical user interface from scratch.
--================================================================================================--
local GUI = {}
function GUI:Create()
    -- Create all the UI elements (frames, buttons, etc.).
    local ScreenGui = Instance.new("ScreenGui"); ScreenGui.Name = "ImbaScriptGUI"; ScreenGui.Parent = Player:WaitForChild("PlayerGui"); ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local MainFrame = Instance.new("Frame"); MainFrame.Name = "MainFrame"; MainFrame.Parent = ScreenGui; MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25); MainFrame.BorderColor3 = Color3.fromRGB(80, 80, 80); MainFrame.BorderSizePixel = 2; MainFrame.Position = UDim2.new(0.5, -200, 0.5, -150); MainFrame.Size = UDim2.new(0, 400, 0, 300); MainFrame.Draggable = true; MainFrame.Visible = true
    local Title = Instance.new("TextLabel"); Title.Name = "Title"; Title.Parent = MainFrame; Title.BackgroundColor3 = Color3.fromRGB(35, 35, 35); Title.Size = UDim2.new(1, 0, 0, 30); Title.Font = Enum.Font.SourceSansBold; Title.Text = "IMBA SCRIPT v4.0"; Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.TextSize = 18
    local TabsContainer = Instance.new("Frame"); TabsContainer.Name = "TabsContainer"; TabsContainer.Parent = MainFrame; TabsContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30); TabsContainer.Position = UDim2.new(0, 0, 0, 30); TabsContainer.Size = UDim2.new(1, 0, 0, 30)
    local ContentContainer = Instance.new("Frame"); ContentContainer.Name = "ContentContainer"; ContentContainer.Parent = MainFrame; ContentContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40); ContentContainer.Position = UDim2.new(0, 0, 0, 60); ContentContainer.Size = UDim2.new(1, 0, 1, -60)

    -- Logic for creating and managing tabs.
    local tabs = {}
    local function CreateTab(name)
        local tabButton = Instance.new("TextButton"); tabButton.Name = name; tabButton.Parent = TabsContainer; tabButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45); tabButton.Size = UDim2.new(1 / 3, 0, 1, 0); tabButton.Position = UDim2.new((#tabs) * (1/3), 0, 0, 0); tabButton.Font = Enum.Font.SourceSans; tabButton.Text = name; tabButton.TextColor3 = Color3.fromRGB(200, 200, 200); tabButton.TextSize = 16
        local contentFrame = Instance.new("Frame"); contentFrame.Name = name .. "Content"; contentFrame.Parent = ContentContainer; contentFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40); contentFrame.Size = UDim2.new(1, 0, 1, 0); contentFrame.Visible = #tabs == 0
        tabButton.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do t.content.Visible = false; t.button.BackgroundColor3 = Color3.fromRGB(45, 45, 45); end
            contentFrame.Visible = true; tabButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60);
        end)
        table.insert(tabs, {button = tabButton, content = contentFrame})
        return contentFrame
    end
    local CombatTab = CreateTab("Combat")
    local MovementTab = CreateTab("Movement")
    local VisualsTab = CreateTab("Visuals")

    -- Handle showing/hiding the menu.
    UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
        if not gameProcessedEvent and input.KeyCode == CONFIG.ToggleMenuKey then
            MainFrame.Visible = not MainFrame.Visible
        end
    end)

    -- Logic for creating toggle switches.
    local verticalOffset = 15
    local function CreateToggle(parent, name, configTable, configKey)
        local toggleFrame = Instance.new("Frame"); toggleFrame.Name = name .. "Toggle"; toggleFrame.Parent = parent; toggleFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50); toggleFrame.Size = UDim2.new(0, 150, 0, 25); toggleFrame.Position = UDim2.new(0.05, 0, 0, verticalOffset)
        local label = Instance.new("TextLabel"); label.Parent = toggleFrame; label.Size = UDim2.new(1, -30, 1, 0); label.BackgroundColor3 = Color3.fromRGB(50, 50, 50); label.Font = Enum.Font.SourceSans; label.Text = name; label.TextColor3 = Color3.fromRGB(220, 220, 220)
        local switch = Instance.new("TextButton"); switch.Parent = toggleFrame; switch.Size = UDim2.new(0, 25, 1, 0); switch.Position = UDim2.new(1, -25, 0, 0); switch.BackgroundColor3 = configTable[configKey] and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100); switch.Text = ""
        switch.MouseButton1Click:Connect(function()
            configTable[configKey] = not configTable[configKey]
            game:GetService("TweenService"):Create(switch, TweenInfo.new(0.2), {BackgroundColor3 = configTable[configKey] and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)}):Play()
        end)
        verticalOffset = verticalOffset + 35
    end

    -- Add the controls to the UI tabs.
    CreateToggle(CombatTab, "Auto Parry", _G, "Enabled")
    CreateToggle(VisualsTab, "ESP", CONFIG.ESP, "Enabled")
    CreateToggle(MovementTab, "WalkSpeed", CONFIG.WalkSpeed, "Enabled")
    CreateToggle(MovementTab, "JumpPower", CONFIG.JumpPower, "Enabled")
end
GUI:Create()
