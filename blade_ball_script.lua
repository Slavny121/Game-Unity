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
    ToggleEnabledKey = Enum.KeyCode.F4,      -- Press to toggle the auto parry ON/OFF
    ToggleMenuKey = Enum.KeyCode.Insert,     -- Press to show/hide the menu
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
        Normal = 0.22,                        -- Default reaction time for normal balls. (LOWERED FOR FASTER REACTION)
        UpwardSpin = 0.17,                    -- Reaction time for balls with upward spin (which are often faster). (LOWERED)
    },
    -- Reaction time when the ball is accelerating rapidly (e.g., after a clash).
    -- These values are lower because we need to react faster.
    AcceleratingReactionTime = {
        Normal = 0.14,                        -- (LOWERED)
        UpwardSpin = 0.09,                    -- (LOWERED)
    },

    -- This section defines what counts as a "rapidly accelerating" ball.
    AccelerationThresholds = {
        DeltaSpeed = 25,                      -- Trigger if speed increases by this much in one frame. (LOWERED)
        AvgSpeedMultiplier = 1.3,             -- Trigger if current speed is this much higher than recent average speed. (LOWERED)
        TravelDistance = 12,                  -- Trigger if the ball travels this far in a single frame. (LOWERED)
    },

    -- NEW: Advanced Parry Logic Settings
    SmartParry = {
        HistoryBufferSize = 35,               -- How many ticks of data to store for each ball. (INCREASED)
        AccelerationDetectionThreshold = 1.15, -- Trigger acceleration mode if speed increases by 15% over the average. (LOWERED)
        CurveDetectionThreshold = 0.97,       -- Dot product threshold to detect a curve. Lower = more sensitive. (LOWERED)
        AdaptiveReactionMultiplier = 1.3,     -- Multiplier for reaction time based on ball behavior. (INCREASED)
    },

    -- Performance Settings
    FPSTarget = 60,                           -- The script adjusts timings based on this FPS target.
                                              -- If your FPS is lower than this, it will try to compensate by reacting slightly earlier.

    -- Auto Clicker Settings
    ClickInterval = 1 / 35,                   -- Time between clicks for the auto-clicker (35 clicks per second)

    -- NEW: Player Modifications
    WalkSpeed = {
        Enabled = false,
        Speed = 32 -- Default is 16
    },
    JumpPower = {
        Enabled = false,
        Power = 75 -- Default is 50
    },

    -- NEW: ESP (Wallhack)
    ESP = {
        Enabled = false,
        Players = {
            Enabled = true,
            Color = Color3.fromRGB(255, 0, 0)
        },
        Ball = {
            Enabled = true,
            Color = Color3.fromRGB(255, 255, 0)
        }
    },
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

    if input.KeyCode == CONFIG.AutoClickKey then
        AutoSpamClick = true
    end
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
    if input.KeyCode == CONFIG.ToggleEnabledKey then
        Enabled = not Enabled
        print("Auto Parry: " .. (Enabled and "ON" or "OFF"))
        -- Optional: Add a simple on-screen notification as well, as console might not always be visible.
        local notifGui = Instance.new("ScreenGui", Player.PlayerGui)
        notifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local label = Instance.new("TextLabel", notifGui)
        label.Size = UDim2.new(0.2, 0, 0.1, 0)
        label.Position = UDim2.new(0.4, 0, 0, 0)
        label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.SourceSansBold
        label.TextSize = 24
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
--================================================================================================--
local ESP_CONTAINER = Instance.new("Folder", workspace) -- A container to hold our ESP elements for easy cleanup.
ESP_CONTAINER.Name = "ESP_CONTAINER_" .. tostring(math.random(1, 1000))

local function UpdateESP()
    -- Clear previous ESP elements
    for _, v in ipairs(ESP_CONTAINER:GetChildren()) do
        v:Destroy()
    end

    if not CONFIG.ESP.Enabled then return end

    -- Player ESP
    if CONFIG.ESP.Players.Enabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if player == Player then continue end
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local box = Instance.new("BoxHandleAdornment")
                box.Adornee = char.HumanoidRootPart
                box.Size = char:GetExtentsSize() + Vector3.new(1, 1, 1)
                box.Color3 = CONFIG.ESP.Players.Color
                box.AlwaysOnTop = true
                box.ZIndex = 1
                box.Parent = ESP_CONTAINER
            end
        end
    end

    -- Ball ESP
    if CONFIG.ESP.Ball.Enabled then
        for _, ball in ipairs(GetBalls()) do
             local box = Instance.new("BoxHandleAdornment")
             box.Adornee = ball
             box.Size = ball.Size + Vector3.new(1, 1, 1)
             box.Color3 = CONFIG.ESP.Ball.Color
             box.AlwaysOnTop = true
             box.ZIndex = 2
             box.Parent = ESP_CONTAINER
        end
    end
end


--================================================================================================--
--[[                                          [ MAIN LOGIC ]                                        ]]
--================================================================================================--

local HeartbeatConnection = nil

local function StartMainLogic(character)
    if HeartbeatConnection then
        HeartbeatConnection:Disconnect()
        HeartbeatConnection = nil
    end

    HeartbeatConnection = RunService.Heartbeat:Connect(function()
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if not (hrp and Enabled and humanoid) then return end

    -- Update ESP
    UpdateESP()

    -- Apply Player Modifications
    if CONFIG.WalkSpeed.Enabled then
        humanoid.WalkSpeed = CONFIG.WalkSpeed.Speed
    end
    if CONFIG.JumpPower.Enabled then
        humanoid.JumpPower = CONFIG.JumpPower.Power
    end

    local now = tick()

    -- Auto-Clicker Logic
    if AutoSpamClick and now - LastClick >= CONFIG.ClickInterval then
        LastClick = now
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end

    --================================================================================================--
    --[[                                      [ ADVANCED AUTO PARRY ]                                   ]]
    --================================================================================================--
    local ping = GetPing() / 1000
    local fps = math.floor(workspace:GetRealPhysicsFPS())
    local fpsFactor = math.clamp(1 - (fps < CONFIG.FPSTarget and (CONFIG.FPSTarget - fps) / 100 or 0), 0.8, 1)

    local candidates = {}

    for _, ball in ipairs(GetBalls()) do
        if ball:GetAttribute("target") ~= Player.Name then continue end

        local pos = ball.Position
        local vel = (ball:FindFirstChild("zoomies") and ball.zoomies.VectorVelocity) or ball.Velocity
        local speed = vel.Magnitude
        local toPlayer = hrp.Position - pos
        local distance = toPlayer.Magnitude

        -- Initialize memory for new balls
        local mem = BallMemory[ball] or {
            history = {},
            lastDirection = vel.Unit,
        }
        BallMemory[ball] = mem

        -- Record history
        table.insert(mem.history, {position = pos, velocity = vel, time = now})
        if #mem.history > CONFIG.SmartParry.HistoryBufferSize then
            table.remove(mem.history, 1)
        end

        -- Analyze ball behavior from history
        local avgSpeed = 0
        local isCurving = false
        if #mem.history > 1 then
            for _, data in ipairs(mem.history) do
                avgSpeed += data.velocity.Magnitude
            end
            avgSpeed /= #mem.history

            local dotProduct = vel.Unit:Dot(mem.lastDirection)
            if dotProduct < CONFIG.SmartParry.CurveDetectionThreshold then
                isCurving = true
            end
        end
        mem.lastDirection = vel.Unit

        local isAccelerating = speed > avgSpeed * CONFIG.SmartParry.AccelerationDetectionThreshold
        local upwardSpin = vel.Y > 10

        -- Determine reaction time based on behavior
        local baseReactTime
        if isAccelerating or isCurving then
            baseReactTime = (upwardSpin and CONFIG.AcceleratingReactionTime.UpwardSpin or CONFIG.AcceleratingReactionTime.Normal)
        else
            baseReactTime = (upwardSpin and CONFIG.ReactionTime.UpwardSpin or CONFIG.ReactionTime.Normal)
        end

        local reactTime = baseReactTime * fpsFactor + ping
        if isAccelerating or isCurving then
             reactTime /= CONFIG.SmartParry.AdaptiveReactionMultiplier
        end

        local predictedTime = distance / (speed + 1)

        local last = BallLastParryTime[ball] or 0
        local ready = now - last >= CONFIG.MinBallClickDelay and now - LastParry >= CONFIG.ParryCooldown

        if ready and (distance <= CONFIG.EmergencyParryDistance or predictedTime <= reactTime) then
            table.insert(candidates, {
                ball = ball,
                priority = predictedTime,
            })
        end
    end

    -- Parry logic (same as before, but now with smarter candidates)
    if #candidates > 0 then
        table.sort(candidates, function(a, b)
            return a.priority < b.priority
        end)

        for i, data in ipairs(candidates) do
            if i > CONFIG.MaxParryChain then break end

            local ball = data.ball
            if BallLastParryTime[ball] and tick() - BallLastParryTime[ball] < CONFIG.MinBallClickDelay then
                continue
            end

            if i == 2 then
                local distBetweenBalls = (candidates[1].ball.Position - candidates[2].ball.Position).Magnitude
                if distBetweenBalls <= 10 then
                    task.wait(0.03)
                end
            end

            if tick() - LastParry >= CONFIG.ParryCooldown and tick() - LastSuccessfulParry >= 0.1 then
                SmartParry()
                LastSuccessfulParry = tick()
                BallLastParryTime[ball] = tick()
                LastParry = tick()
                break -- Parry one ball at a time for precision
            end
        end
    end
end)

--================================================================================================--
--================================================================================================--
--[[                                     [ INITIALIZATION ]                                       ]]
--================================================================================================--

-- Start the script for the first time
if Player.Character then
    StartMainLogic(Player.Character)
end

-- Restart the script every time the player respawns
Player.CharacterAdded:Connect(function(character)
    -- Wait for the humanoid to be created
    character:WaitForChild("Humanoid")
    StartMainLogic(character)
end)

--================================================================================================--
--[[                                        [ PREMIUM UI ]                                        ]]
--================================================================================================--
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/UI-Interface/CustomFIeld/main/RayField.lua'))()

local Window = Rayfield:CreateWindow({
    Name = "IMBA SCRIPT v2.0",
    LoadingTitle = "Loading Your Imba Script...",
    LoadingSubtitle = "by Jules",
    ConfigurationSaving = {
        Enabled = true,
        FileName = "ImbaScriptConfig"
    },
    KeybindSystem = {
        Enabled = true,
        KeybindSettings = {
            -- hide the menu when you press the keybind
            ToggleKeybind = CONFIG.ToggleMenuKey,
            -- when you press the keybind, it will be executed
            HoldKeybinds = false,
        }
    }
})

-- Combat Tab
local CombatTab = Window:CreateTab("Combat")

CombatTab:CreateToggle({
    Name = "Auto Parry",
    CurrentValue = Enabled,
    Flag = "AutoParryToggle",
    Callback = function(Value)
        Enabled = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Auto Click",
    CurrentValue = AutoSpamClick,
    Flag = "AutoClickToggle",
    Callback = function(Value)
        AutoSpamClick = Value -- Note: this requires holding the key as well
    end,
})

CombatTab:CreateToggle({
    Name = "Auto 'X' Spam",
    CurrentValue = AutoSpamX,
    Flag = "AutoXSpamToggle",
    Callback = function(Value)
        AutoSpamX = Value -- Note: this requires holding the key as well
    end,
})

-- Movement Tab
local MovementTab = Window:CreateTab("Movement")

MovementTab:CreateToggle({
    Name = "Enable WalkSpeed",
    CurrentValue = CONFIG.WalkSpeed.Enabled,
    Flag = "WalkSpeedToggle",
    Callback = function(Value)
        CONFIG.WalkSpeed.Enabled = Value
        if not Value then
            Player.Character.Humanoid.WalkSpeed = 16 -- Reset to default
        end
    end,
})

MovementTab:CreateSlider({
    Name = "Speed",
    Range = {16, 100},
    Increment = 1,
    Suffix = "studs/s",
    CurrentValue = CONFIG.WalkSpeed.Speed,
    Flag = "WalkSpeedSlider",
    Callback = function(Value)
        CONFIG.WalkSpeed.Speed = Value
    end,
})

MovementTab:CreateToggle({
    Name = "Enable JumpPower",
    CurrentValue = CONFIG.JumpPower.Enabled,
    Flag = "JumpPowerToggle",
    Callback = function(Value)
        CONFIG.JumpPower.Enabled = Value
        if not Value then
            Player.Character.Humanoid.JumpPower = 50 -- Reset to default
        end
    end,
})

MovementTab:CreateSlider({
    Name = "Power",
    Range = {50, 200},
    Increment = 1,
    Suffix = "power",
    CurrentValue = CONFIG.JumpPower.Power,
    Flag = "JumpPowerSlider",
    Callback = function(Value)
        CONFIG.JumpPower.Power = Value
    end,
})

-- Visuals Tab
local VisualsTab = Window:CreateTab("Visuals")

VisualsTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = CONFIG.ESP.Enabled,
    Flag = "ESPToggle",
    Callback = function(Value)
        CONFIG.ESP.Enabled = Value
    end,
})

VisualsTab:CreateToggle({
    Name = "Player ESP",
    CurrentValue = CONFIG.ESP.Players.Enabled,
    Flag = "PlayerESPToggle",
    Callback = function(Value)
        CONFIG.ESP.Players.Enabled = Value
    end,
})

VisualsTab:CreateToggle({
    Name = "Ball ESP",
    CurrentValue = CONFIG.ESP.Ball.Enabled,
    Flag = "BallESPToggle",
    Callback = function(Value)
        CONFIG.ESP.Ball.Enabled = Value
    end,
})
