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
--[[                                    [ BALL PREDICTOR MODULE ]                                   ]]
--================================================================================================--
local BallPredictor = {}
BallPredictor.__index = BallPredictor

--[[
    Creates a new Ball Predictor object.
    Each ball in the game will have its own predictor to track its state.
]]
function BallPredictor.new(ball)
    local self = setmetatable({}, BallPredictor)
    self.Ball = ball
    self.History = {} -- Stores past positions, velocities, and times
    return self
end

--[[
    Updates the predictor with the latest data for the ball.
    This function will be called every frame (Heartbeat).
]]
function BallPredictor:Update(character, ping, fps)
    local now = tick()
    local ball = self.Ball
    local vel = (ball:FindFirstChild("zoomies") and ball.zoomies.VectorVelocity) or ball.Velocity
    local pos = ball.Position

    -- Store current state
    table.insert(self.History, {
        Time = now,
        Position = pos,
        Velocity = vel,
    })

    -- Keep history buffer at a fixed size
    if #self.History > CONFIG.SmartParry.HistoryBufferSize then
        table.remove(self.History, 1)
    end

    -- Not enough data to analyze, exit early
    if #self.History < 2 then
        self.Analysis = nil
        return
    end

    -- Analyze the collected data
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local latest = self.History[#self.History]
    local previous = self.History[#self.History - 1]

    local deltaTime = latest.Time - previous.Time
    if deltaTime == 0 then return end

    -- Ping Compensation: Estimate the ball's "real" position
    local estimatedRealPos = latest.Position + (latest.Velocity * ping)
    local distance = (hrp.Position - estimatedRealPos).Magnitude

    -- Acceleration Analysis
    local acceleration = (latest.Velocity.Magnitude - previous.Velocity.Magnitude) / deltaTime

    -- Curve Analysis
    local dotProduct = latest.Velocity.Unit:Dot(previous.Velocity.Unit)
    local isCurving = dotProduct < CONFIG.SmartParry.CurveDetectionThreshold

    -- FPS Compensation Factor
    local fpsFactor = math.clamp(1 - (fps < CONFIG.FPSTarget and (CONFIG.FPSTarget - fps) / 100 or 0), 0.8, 1)

    self.Analysis = {
        Distance = distance,
        Speed = latest.Velocity.Magnitude,
        Acceleration = acceleration,
        IsCurving = isCurving,
        Ping = ping,
        FPSFactor = fpsFactor,
    }
end

--[[
    The core function. Determines if a parry is needed based on the analysis.
    This function will use the physical model to predict the future.
]]
function BallPredictor:ShouldParry()
    if not self.Analysis then return false end

    local analysis = self.Analysis
    local speed = analysis.Speed
    if speed == 0 then return false end

    -- Time To Collision (TTC) - fundamental calculation
    local timeToCollision = analysis.Distance / speed

    -- Calculate base reaction time
    local baseReactionTime
    if analysis.Acceleration > CONFIG.AccelerationThresholds.DeltaSpeed or analysis.IsCurving then
        baseReactionTime = CONFIG.AcceleratingReactionTime.Normal -- Use the faster reaction times
    else
        baseReactionTime = CONFIG.ReactionTime.Normal
    end

    -- Adjust reaction time based on ping and FPS
    local reactionTime = (baseReactionTime * analysis.FPSFactor) + analysis.Ping

    -- Make reaction time even faster if the ball is behaving erratically
    if analysis.Acceleration > CONFIG.AccelerationThresholds.DeltaSpeed or analysis.IsCurving then
        reactionTime = reactionTime / CONFIG.SmartParry.AdaptiveReactionMultiplier
    end

    -- The final decision
    if timeToCollision <= reactionTime or analysis.Distance <= CONFIG.EmergencyParryDistance then
        return true
    end

    return false
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

        -- New Parry Logic
        local ping = GetPing() / 1000
        local fps = workspace:GetRealPhysicsFPS()

        for _, ball in ipairs(GetBalls()) do
            if ball:GetAttribute("target") ~= Player.Name then continue end

            local predictor = BallMemory[ball]
            if not predictor then
                predictor = BallPredictor.new(ball)
                BallMemory[ball] = predictor
            end

            predictor:Update(character, ping, fps)

            if predictor:ShouldParry() then
                 if now - LastParry >= CONFIG.ParryCooldown then
                    SmartParry()
                    LastParry = now
                    break -- Parry one ball at a time
                end
            end
        end
    end)
end

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
--[[                                      [ CUSTOM PREMIUM UI ]                                     ]]
--================================================================================================--
local GUI = {}

function GUI:Create()
    -- Main Container
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "ImbaScriptGUI"
    ScreenGui.Parent = Player:WaitForChild("PlayerGui")
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    MainFrame.BorderColor3 = Color3.fromRGB(80, 80, 80)
    MainFrame.BorderSizePixel = 2
    MainFrame.Position = UDim2.new(0.5, -200, 0.5, -150)
    MainFrame.Size = UDim2.new(0, 400, 0, 300)
    MainFrame.Draggable = true
    MainFrame.Visible = true

    -- Title
    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Parent = MainFrame
    Title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    Title.Size = UDim2.new(1, 0, 0, 30)
    Title.Font = Enum.Font.SourceSansBold
    Title.Text = "IMBA SCRIPT v3.0"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.TextSize = 18

    -- Tabs Container
    local TabsContainer = Instance.new("Frame")
    TabsContainer.Name = "TabsContainer"
    TabsContainer.Parent = MainFrame
    TabsContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    TabsContainer.Position = UDim2.new(0, 0, 0, 30)
    TabsContainer.Size = UDim2.new(1, 0, 0, 30)

    -- Content Container
    local ContentContainer = Instance.new("Frame")
    ContentContainer.Name = "ContentContainer"
    ContentContainer.Parent = MainFrame
    ContentContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    ContentContainer.Position = UDim2.new(0, 0, 0, 60)
    ContentContainer.Size = UDim2.new(1, 0, 1, -60)

    -- Tab Creation Logic
    local tabs = {}
    local function CreateTab(name)
        local tabButton = Instance.new("TextButton")
        tabButton.Name = name
        tabButton.Parent = TabsContainer
        tabButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        tabButton.Size = UDim2.new(1 / 3, 0, 1, 0)
        tabButton.Position = UDim2.new((#tabs) * (1/3), 0, 0, 0)
        tabButton.Font = Enum.Font.SourceSans
        tabButton.Text = name
        tabButton.TextColor3 = Color3.fromRGB(200, 200, 200)
        tabButton.TextSize = 16

        local contentFrame = Instance.new("Frame")
        contentFrame.Name = name .. "Content"
        contentFrame.Parent = ContentContainer
        contentFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        contentFrame.Size = UDim2.new(1, 0, 1, 0)
        contentFrame.Visible = #tabs == 0

        tabButton.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do
                t.content.Visible = false
                t.button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            end
            contentFrame.Visible = true
            tabButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        end)

        table.insert(tabs, {button = tabButton, content = contentFrame})
        return contentFrame
    end

    local CombatTab = CreateTab("Combat")
    local MovementTab = CreateTab("Movement")
    local VisualsTab = CreateTab("Visuals")

    -- Toggle UI visibility
    UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
        if not gameProcessedEvent and input.KeyCode == CONFIG.ToggleMenuKey then
            MainFrame.Visible = not MainFrame.Visible
        end
    end)

    -- Element Creation
    local verticalOffset = 15
    local function CreateToggle(parent, name, configTable, configKey)
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Name = name .. "Toggle"
        toggleFrame.Parent = parent
        toggleFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        toggleFrame.Size = UDim2.new(0, 150, 0, 25)
        toggleFrame.Position = UDim2.new(0.05, 0, 0, verticalOffset)

        local label = Instance.new("TextLabel")
        label.Parent = toggleFrame
        label.Size = UDim2.new(1, -30, 1, 0)
        label.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        label.Font = Enum.Font.SourceSans
        label.Text = name
        label.TextColor3 = Color3.fromRGB(220, 220, 220)

        local switch = Instance.new("TextButton")
        switch.Parent = toggleFrame
        switch.Size = UDim2.new(0, 25, 1, 0)
        switch.Position = UDim2.new(1, -25, 0, 0)
        switch.BackgroundColor3 = configTable[configKey] and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        switch.Text = ""

        switch.MouseButton1Click:Connect(function()
            configTable[configKey] = not configTable[configKey]
            game:GetService("TweenService"):Create(switch, TweenInfo.new(0.2), {BackgroundColor3 = configTable[configKey] and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)}):Play()
        end)

        verticalOffset = verticalOffset + 35
    end

    -- Populate Tabs
    CreateToggle(CombatTab, "Auto Parry", _G, "Enabled")
    CreateToggle(VisualsTab, "ESP", CONFIG.ESP, "Enabled")
    CreateToggle(MovementTab, "WalkSpeed", CONFIG.WalkSpeed, "Enabled")
    CreateToggle(MovementTab, "JumpPower", CONFIG.JumpPower, "Enabled")

end

GUI:Create()
