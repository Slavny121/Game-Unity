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

    -- NEW: Advanced Parry Logic Settings
    SmartParry = {
        HistoryBufferSize = 30,               -- How many ticks of data to store for each ball.
        AccelerationDetectionThreshold = 1.2, -- Trigger acceleration mode if speed increases by 20% over the average.
        CurveDetectionThreshold = 0.98,       -- Dot product threshold to detect a curve. Lower = more sensitive.
        AdaptiveReactionMultiplier = 1.1,     -- Multiplier for reaction time based on ball behavior.
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
--[[                                          [ MAIN LOOP ]                                         ]]
--================================================================================================--

RunService.Heartbeat:Connect(function()
    local char = Player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")

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
--[[                                         [ SIMPLE UI ]                                        ]]
--================================================================================================--
local function CreateUI()
    local ScreenGui = Instance.new("ScreenGui")
    local MainFrame = Instance.new("Frame")
    local TitleLabel = Instance.new("TextLabel")
    local ToggleButton = Instance.new("TextButton")

    ScreenGui.Parent = Player:WaitForChild("PlayerGui")
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    MainFrame.BorderColor3 = Color3.fromRGB(100, 100, 100)
    MainFrame.BorderSizePixel = 2
    MainFrame.Position = UDim2.new(0.5, -150, 0.5, -200)
    MainFrame.Size = UDim2.new(0, 300, 0, 400)
    MainFrame.Draggable = true
    MainFrame.Active = true

    TitleLabel.Name = "TitleLabel"
    TitleLabel.Parent = MainFrame
    TitleLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    TitleLabel.Size = UDim2.new(1, 0, 0, 30)
    TitleLabel.Font = Enum.Font.SourceSansBold
    TitleLabel.Text = "IMBA SCRIPT v1.0"
    TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    TitleLabel.TextSize = 18

    ToggleButton.Name = "ToggleButton"
    ToggleButton.Parent = MainFrame
    ToggleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    ToggleButton.Position = UDim2.new(0.05, 0, 0.1, 0)
    ToggleButton.Size = UDim2.new(0.9, 0, 0, 30)
    ToggleButton.Font = Enum.Font.SourceSans
    ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ToggleButton.TextSize = 16
    ToggleButton.Text = "Toggle Script: ON"

    ToggleButton.MouseButton1Click:Connect(function()
        Enabled = not Enabled
        ToggleButton.Text = "Toggle Script: " .. (Enabled and "ON" or "OFF")
    end)

    -- Function to create a simple toggle button
    local function CreateToggleButton(name, yPos, configTable, configKey)
        local button = ToggleButton:Clone()
        button.Name = name
        button.Parent = MainFrame
        button.Position = UDim2.new(0.05, 0, yPos, 0)
        button.Text = name .. ": " .. (configTable[configKey] and "ON" or "OFF")

        button.MouseButton1Click:Connect(function()
            configTable[configKey] = not configTable[configKey]
            button.Text = name .. ": " .. (configTable[configKey] and "ON" or "OFF")
        end)
        return button
    end

    -- Create buttons for each feature
    CreateToggleButton("ESP", 0.2, CONFIG.ESP, "Enabled")
    CreateToggleButton("WalkSpeed", 0.3, CONFIG.WalkSpeed, "Enabled")
    CreateToggleButton("JumpPower", 0.4, CONFIG.JumpPower, "Enabled")
end

CreateUI()
