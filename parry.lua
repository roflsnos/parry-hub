local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Balls = workspace:WaitForChild("Balls", 9e9)

local Theme = {
    Accent = Color3.fromRGB(0, 140, 255),
    Current = "Royal Blue"
}

local ParryConfig = { Enabled = false, Threshold = 0.30, Notify = true }
local CameraConfig = { FOV = 70, DefaultFOV = 70 }

do
    if Camera then CameraConfig.DefaultFOV = Camera.FieldOfView end
end

local TargetConfig = {
    Offset = Vector3.new(0, 0, 5), Height = 0, FollowSpeed = 1,
    BindToggle = Enum.KeyCode.F,
    BindNext = Enum.KeyCode.G,
    BindPrev = Enum.KeyCode.B,
}

local TargetState = {
    Active = false, Conn = nil,
    Target = nil, TargetIndex = 0, PlayerList = {},
}

local ConfigSystem = {
    Folder = "ParryHub_Configs",
    AutoSave = true,
    AutoSaveTimer = 0,
    AutoSaveInterval = 30,
    HasFileAPI = false,
}

do
    ConfigSystem.HasFileAPI = (writefile and readfile and isfile and listfiles and makefolder) ~= nil
    if ConfigSystem.HasFileAPI then
        local folderPath = "./" .. ConfigSystem.Folder
        if not isfolder(folderPath) then
            pcall(function() makefolder(folderPath) end)
        end
    end
end

local function GetConfigPath(name)
    return "./" .. ConfigSystem.Folder .. "/" .. name .. ".json"
end

local function SaveConfigToFile(name, data)
    if not ConfigSystem.HasFileAPI then return false end
    local ok, err = pcall(function()
        writefile(GetConfigPath(name), HttpService:JSONEncode(data))
    end)
    return ok, err
end

local function LoadConfigFromFile(name)
    if not ConfigSystem.HasFileAPI then return nil end
    local path = GetConfigPath(name)
    if not isfile(path) then return nil end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if ok then return decoded end
    return nil
end

local function ListConfigFiles()
    if not ConfigSystem.HasFileAPI then return {} end
    local result = {}
    local path = "./" .. ConfigSystem.Folder
    local ok, files = pcall(function() return listfiles(path) end)
    if ok and files then
        for _, f in ipairs(files) do
            local name = f:match("([^/\\]+)%.json$")
            if name then table.insert(result, name) end
        end
    end
    return result
end

local function CollectConfig()
    return {
        AccentColor = tostring(Theme.Accent),
        ThemeName = Theme.Current,
        FOV = CameraConfig.FOV,
        ParryEnabled = ParryConfig.Enabled,
        ParryThreshold = ParryConfig.Threshold,
        ParryNotify = ParryConfig.Notify,
        TargetOffset = {TargetConfig.Offset.X, TargetConfig.Offset.Y, TargetConfig.Offset.Z},
        TargetHeight = TargetConfig.Height,
        TargetFollowSpeed = TargetConfig.FollowSpeed,
    }
end

local function ApplyConfig(data)
    if not data then return end
    if data.FOV then 
        CameraConfig.FOV = data.FOV 
        if Camera then Camera.FieldOfView = data.FOV end
    end
    if data.ParryThreshold then ParryConfig.Threshold = data.ParryThreshold end
    if data.ParryNotify ~= nil then ParryConfig.Notify = data.ParryNotify end
    if data.TargetOffset then
        TargetConfig.Offset = Vector3.new(data.TargetOffset[1], data.TargetOffset[2], data.TargetOffset[3])
    end
    if data.TargetHeight then TargetConfig.Height = data.TargetHeight end
    if data.TargetFollowSpeed then TargetConfig.FollowSpeed = data.TargetFollowSpeed end
end

local ColorThemes = {
    ["Royal Blue"] = Color3.fromRGB(0, 140, 255),
    ["Pink Gradient"] = Color3.fromRGB(255, 105, 180),
    ["Purple Neon"] = Color3.fromRGB(168, 85, 247),
    ["Cyan Glow"] = Color3.fromRGB(6, 182, 212),
    ["Emerald Green"] = Color3.fromRGB(34, 197, 94),
    ["Crimson Red"] = Color3.fromRGB(239, 68, 68),
    ["Orange Fire"] = Color3.fromRGB(255, 140, 0),
    ["Golden"] = Color3.fromRGB(255, 215, 0),
}

local function GetBall()
    for _, Ball in ipairs(Balls:GetChildren()) do
        if Ball:GetAttribute("realBall") == true then return Ball end
    end
    return nil
end

local IsParried = false
local LastParryTime = 0
local MinParryInterval = 0.1
local LastNotifTime = 0

local function ShowParryNotif(distance, speed, time)
    if not ParryConfig.Notify then return end
    local now = tick()
    if now - LastNotifTime < 0.3 then return end
    LastNotifTime = now
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Parry",
            Text = string.format("d=%.1f s=%.0f t=%.3f", distance, speed, time),
            Duration = 2,
        })
    end)
end

local LastClickTime = 0
local function Click()
    local vp = Camera.ViewportSize
    local x, y = vp.X / 2, vp.Y / 2
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

RunService.PreSimulation:Connect(function()
    if not ParryConfig.Enabled then return end
    local Ball = GetBall()
    if not Ball then
        IsParried = false
        return
    end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if Ball:GetAttribute("target") ~= LocalPlayer.Name then
        IsParried = false
        return
    end
    if IsParried then return end
    if Ball:GetAttribute("parried") == true then return end

    local zoomies = Ball:FindFirstChild("zoomies")
    if not zoomies then return end
    local Speed = zoomies.VectorVelocity.Magnitude
    if Speed < 5 then return end

    local Distance = (hrp.Position - Ball.Position).Magnitude
    local timeToImpact = Distance / Speed

    if timeToImpact <= ParryConfig.Threshold and timeToImpact > -0.05 then
        local now = tick()
        if now - LastParryTime < MinParryInterval then return end
        LastParryTime = now

        Click()
        IsParried = true
        ShowParryNotif(Distance, Speed, timeToImpact)
    end
end)

local function RefreshTargetList()
    TargetState.PlayerList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then table.insert(TargetState.PlayerList, p) end
        end
    end
end

local function GetNextTarget()
    RefreshTargetList()
    if #TargetState.PlayerList == 0 then TargetState.Target = nil return end
    TargetState.TargetIndex = TargetState.TargetIndex + 1
    if TargetState.TargetIndex > #TargetState.PlayerList then TargetState.TargetIndex = 1 end
    TargetState.Target = TargetState.PlayerList[TargetState.TargetIndex]
end

local function GetPrevTarget()
    RefreshTargetList()
    if #TargetState.PlayerList == 0 then TargetState.Target = nil return end
    TargetState.TargetIndex = TargetState.TargetIndex - 1
    if TargetState.TargetIndex < 1 then TargetState.TargetIndex = #TargetState.PlayerList end
    TargetState.Target = TargetState.PlayerList[TargetState.TargetIndex]
end

local function StartTarget()
    if TargetState.Active then return end
    TargetState.Active = true
    if not TargetState.Target then GetNextTarget() end

    TargetState.Conn = RunService.Heartbeat:Connect(function()
        if not TargetState.Active then return end
        if not TargetState.Target or not TargetState.Target.Character then return end
        local targetHrp = TargetState.Target.Character:FindFirstChild("HumanoidRootPart")
        if not targetHrp then return end
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local myHrp = myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end

        local offsetCFrame = targetHrp.CFrame * CFrame.new(TargetConfig.Offset)
        local finalPos = offsetCFrame.Position + Vector3.new(0, TargetConfig.Height, 0)
        local lookCFrame = CFrame.new(finalPos, targetHrp.Position + Vector3.new(0, TargetConfig.Height, 0))

        if TargetConfig.FollowSpeed >= 1 then
            myHrp.CFrame = lookCFrame
        else
            myHrp.CFrame = myHrp.CFrame:Lerp(lookCFrame, TargetConfig.FollowSpeed)
        end
    end)
end

local function StopTarget()
    TargetState.Active = false
    if TargetState.Conn then TargetState.Conn:Disconnect(); TargetState.Conn = nil end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ParryHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parentContainer = (gethui and gethui()) or (syn and syn.protect_gui and CoreGui) or Players.LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.Parent = parentContainer

local MiniGui = Instance.new("ScreenGui")
MiniGui.Name = "ParryHubMini"
MiniGui.ResetOnSpawn = false
MiniGui.Parent = parentContainer

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, -220, 0.5, -160)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
MainFrame.BackgroundTransparency = 0.05
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.Accent
MainStroke.Thickness = 1
MainStroke.Transparency = 0.5
MainStroke.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
Header.BackgroundTransparency = 0.3
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local HeaderCover = Instance.new("Frame")
HeaderCover.Size = UDim2.new(1, 0, 0, 12)
HeaderCover.Position = UDim2.new(0, 0, 1, -12)
HeaderCover.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
HeaderCover.BackgroundTransparency = 0.3
HeaderCover.BorderSizePixel = 0
HeaderCover.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 1, 0)
Title.Position = UDim2.new(0, 16, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "PARRY HUB"
Title.TextColor3 = Color3.fromRGB(230, 230, 240)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -32, 0.5, -12)
CloseBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(200, 60, 60)}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(40, 40, 50)}):Play()
end)

local dragging, dragStart, startPos
Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)
Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(0, 120, 1, -55)
TabBar.Position = UDim2.new(0, 10, 0, 48)
TabBar.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
TabBar.BackgroundTransparency = 0.3
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local TabBarCorner = Instance.new("UICorner")
TabBarCorner.CornerRadius = UDim.new(0, 8)
TabBarCorner.Parent = TabBar

local TabList = Instance.new("UIListLayout")
TabList.SortOrder = Enum.SortOrder.LayoutOrder
TabList.Padding = UDim.new(0, 6)
TabList.Parent = TabBar

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingTop = UDim.new(0, 8)
TabPadding.PaddingLeft = UDim.new(0, 8)
TabPadding.PaddingRight = UDim.new(0, 8)
TabPadding.Parent = TabBar

local PagesContainer = Instance.new("Frame")
PagesContainer.Size = UDim2.new(1, -145, 1, -55)
PagesContainer.Position = UDim2.new(0, 135, 0, 48)
PagesContainer.BackgroundTransparency = 1
PagesContainer.Parent = MainFrame

local Tabs = {}
local ActiveTab = nil
local AccentElements = {}

local function RegisterAccent(element, property)
    table.insert(AccentElements, {Element = element, Property = property or "BackgroundColor3"})
end

local function UpdateAccent()
    for _, item in ipairs(AccentElements) do
        pcall(function()
            item.Element[item.Property] = Theme.Accent
        end)
    end
    MainStroke.Color = Theme.Accent
end

function CreateTab(name)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(1, 0, 0, 32)
    TabBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
    TabBtn.BackgroundTransparency = 0.3
    TabBtn.Text = name
    TabBtn.TextColor3 = Color3.fromRGB(180, 180, 195)
    TabBtn.Font = Enum.Font.GothamMedium
    TabBtn.TextSize = 13
    TabBtn.BorderSizePixel = 0
    TabBtn.Parent = TabBar

    local TabCorner = Instance.new("UICorner")
    TabCorner.CornerRadius = UDim.new(0, 6)
    TabCorner.Parent = TabBtn

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, 0, 1, 0)
    Page.BackgroundTransparency = 1
    Page.Visible = false
    Page.ScrollBarThickness = 3
    Page.ScrollBarImageColor3 = Theme.Accent
    Page.Parent = PagesContainer

    local PageLayout = Instance.new("UIListLayout")
    PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    PageLayout.Padding = UDim.new(0, 8)
    PageLayout.Parent = Page

    local Tab = { Button = TabBtn, Page = Page, Name = name }

    function Tab:Select()
        for _, t in pairs(Tabs) do
            t.Page.Visible = false
            TweenService:Create(t.Button, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(25, 25, 34),
                TextColor3 = Color3.fromRGB(180, 180, 195)
            }):Play()
        end
        ActiveTab = Tab
        Page.Visible = true
        TweenService:Create(TabBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Theme.Accent,
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
    end

    TabBtn.MouseButton1Click:Connect(function() Tab:Select() end)

    table.insert(Tabs, Tab)
    if #Tabs == 1 then Tab:Select() end
    return Tab
end

local function AddToggle(parent, label, default, callback)
    local state = default or false
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, -8, 0, 38)
    Frame.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    Frame.BorderSizePixel = 0
    Frame.Parent = parent

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -60, 1, 0)
    Label.Position = UDim2.new(0, 14, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Color3.fromRGB(210, 210, 225)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 13
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame

    local Switch = Instance.new("Frame")
    Switch.Size = UDim2.new(0, 38, 0, 20)
    Switch.Position = UDim2.new(1, -50, 0.5, -10)
    Switch.BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(40, 40, 50)
    Switch.BorderSizePixel = 0
    Switch.Parent = Frame

    local SwitchCorner = Instance.new("UICorner")
    SwitchCorner.CornerRadius = UDim.new(1, 0)
    SwitchCorner.Parent = Switch

    local Dot = Instance.new("Frame")
    Dot.Size = UDim2.new(0, 16, 0, 16)
    Dot.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    Dot.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
    Dot.BorderSizePixel = 0
    Dot.Parent = Switch

    local DotCorner = Instance.new("UICorner")
    DotCorner.CornerRadius = UDim.new(1, 0)
    DotCorner.Parent = Dot

    local Click = Instance.new("TextButton")
    Click.Size = UDim2.new(1, 0, 1, 0)
    Click.BackgroundTransparency = 1
    Click.Text = ""
    Click.Parent = Frame

    local function setState(v)
        state = v
        TweenService:Create(Switch, TweenInfo.new(0.2), {
            BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(40, 40, 50)
        }):Play()
        TweenService:Create(Dot, TweenInfo.new(0.2), {
            Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
    end

    Click.MouseButton1Click:Connect(function()
        setState(not state)
        if callback then callback(state) end
    end)

    RegisterAccent(Switch, "BackgroundColor3")
    Switch.BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(40, 40, 50)

    return {
        SetState = setState,
        GetState = function() return state end
    }
end

local function AddSlider(parent, label, minVal, maxVal, default, callback)
    local current = default or minVal
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, -8, 0, 52)
    Frame.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    Frame.BorderSizePixel = 0
    Frame.Parent = parent

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -90, 0, 18)
    Label.Position = UDim2.new(0, 14, 0, 6)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Color3.fromRGB(210, 210, 225)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 13
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame

    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Size = UDim2.new(0, 70, 0, 18)
    ValueLabel.Position = UDim2.new(1, -82, 0, 6)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Text = tostring(current)
    ValueLabel.TextColor3 = Theme.Accent
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.TextSize = 13
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
    ValueLabel.Parent = Frame

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, -28, 0, 6)
    Track.Position = UDim2.new(0, 14, 0, 34)
    Track.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    Track.BorderSizePixel = 0
    Track.Parent = Frame

    local TrackCorner = Instance.new("UICorner")
    TrackCorner.CornerRadius = UDim.new(1, 0)
    TrackCorner.Parent = Track

    local rel = (current - minVal) / (maxVal - minVal)
    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.new(rel, 0, 1, 0)
    Fill.BackgroundColor3 = Theme.Accent
    Fill.BorderSizePixel = 0
    Fill.Parent = Track

    local FillCorner = Instance.new("UICorner")
    FillCorner.CornerRadius = UDim.new(1, 0)
    FillCorner.Parent = Fill

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 14, 0, 14)
    Knob.Position = UDim2.new(rel, -7, 0.5, -7)
    Knob.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
    Knob.BorderSizePixel = 0
    Knob.Parent = Track

    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = Knob

    local Click = Instance.new("TextButton")
    Click.Size = UDim2.new(1, 0, 1, 0)
    Click.BackgroundTransparency = 1
    Click.Text = ""
    Click.Parent = Track

    local dragging = false

    local function updateFromX(x)
        local r = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        local val = math.floor(minVal + r * (maxVal - minVal) + 0.5)
        current = val
        Fill.Size = UDim2.new(r, 0, 1, 0)
        Knob.Position = UDim2.new(r, -7, 0.5, -7)
        ValueLabel.Text = tostring(val)
        if callback then callback(val) end
    end

    Click.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    RegisterAccent(Fill, "BackgroundColor3")
    RegisterAccent(ValueLabel, "TextColor3")

    return {
        SetValue = function(v)
            current = math.clamp(v, minVal, maxVal)
            local r = (current - minVal) / (maxVal - minVal)
            Fill.Size = UDim2.new(r, 0, 1, 0)
            Knob.Position = UDim2.new(r, -7, 0.5, -7)
            ValueLabel.Text = tostring(current)
            if callback then callback(current) end
        end,
        GetValue = function() return current end
    }
end

local function AddButton(parent, label, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, -8, 0, 34)
    Btn.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
    Btn.Text = label
    Btn.TextColor3 = Color3.fromRGB(210, 210, 220)
    Btn.Font = Enum.Font.GothamMedium
    Btn.TextSize = 13
    Btn.BorderSizePixel = 0
    Btn.Parent = parent

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Btn

    Btn.MouseEnter:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(32, 32, 42)}):Play()
    end)
    Btn.MouseLeave:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(25, 25, 34)}):Play()
    end)
    Btn.MouseButton1Click:Connect(function() if callback then callback() end end)
end

local GeneralTab = CreateTab("Главная")
AddToggle(GeneralTab.Page, "Авто-парирование", false, function(v)
    ParryConfig.Enabled = v
end)
AddToggle(GeneralTab.Page, "Уведомления", true, function(v)
    ParryConfig.Notify = v
end)
AddSlider(GeneralTab.Page, "Порог парри (x100)", 5, 50, 30, function(v)
    ParryConfig.Threshold = v / 100
end)
AddSlider(GeneralTab.Page, "FOV", 70, 120, CameraConfig.FOV, function(v)
    CameraConfig.FOV = v
    if Camera then Camera.FieldOfView = v end
end)

local TargetTab = CreateTab("Таргет")
AddToggle(TargetTab.Page, "Лететь за целью", false, function(v)
    if v then StartTarget() else StopTarget() end
end)
AddButton(TargetTab.Page, "Следующая цель", function() GetNextTarget() end)
AddButton(TargetTab.Page, "Предыдущая цель", function() GetPrevTarget() end)
AddButton(TargetTab.Page, "Обновить список", function() RefreshTargetList() end)

local SettingTab = CreateTab("Настройки")

local ThemeDropdown = Instance.new("TextButton")
ThemeDropdown.Size = UDim2.new(1, -8, 0, 36)
ThemeDropdown.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
ThemeDropdown.Text = "Тема: Royal Blue ▼"
ThemeDropdown.TextColor3 = Color3.fromRGB(210, 210, 225)
ThemeDropdown.Font = Enum.Font.Gotham
ThemeDropdown.TextSize = 13
ThemeDropdown.BorderSizePixel = 0
ThemeDropdown.Parent = SettingTab.Page

local TdCorner = Instance.new("UICorner")
TdCorner.CornerRadius = UDim.new(0, 6)
TdCorner.Parent = ThemeDropdown

local ThemeList = Instance.new("Frame")
ThemeList.Size = UDim2.new(1, -8, 0, 0)
ThemeList.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
ThemeList.BorderSizePixel = 0
ThemeList.ClipsDescendants = true
ThemeList.Parent = SettingTab.Page

local TlCorner = Instance.new("UICorner")
TlCorner.CornerRadius = UDim.new(0, 6)
TlCorner.Parent = ThemeList

local TlLayout = Instance.new("UIListLayout")
TlLayout.Padding = UDim.new(0, 4)
TlLayout.Parent = ThemeList

local ThemeExpanded = false

for name, color in pairs(ColorThemes) do
    local OptBtn = Instance.new("TextButton")
    OptBtn.Size = UDim2.new(1, -8, 0, 30)
    OptBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
    OptBtn.Text = "  " .. name
    OptBtn.TextColor3 = color
    OptBtn.Font = Enum.Font.GothamMedium
    OptBtn.TextSize = 12
    OptBtn.BorderSizePixel = 0
    OptBtn.Parent = ThemeList

    local OptCorner = Instance.new("UICorner")
    OptCorner.CornerRadius = UDim.new(0, 4)
    OptCorner.Parent = OptBtn

    OptBtn.MouseButton1Click:Connect(function()
        Theme.Accent = color
        Theme.Current = name
        UpdateAccent()
        ThemeDropdown.Text = "Тема: " .. name .. " ▼"
        ThemeExpanded = false
        TweenService:Create(ThemeList, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, -8, 0, 0)}):Play()
    end)
end

local ThemeOptCount = 0
for _ in pairs(ColorThemes) do ThemeOptCount = ThemeOptCount + 1 end

ThemeDropdown.MouseButton1Click:Connect(function()
    ThemeExpanded = not ThemeExpanded
    local h = ThemeExpanded and (ThemeOptCount * 34 + 8) or 0
    TweenService:Create(ThemeList, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, -8, 0, h)}):Play()
end)

local saveNameBox = Instance.new("TextBox")
saveNameBox.Size = UDim2.new(1, -8, 0, 32)
saveNameBox.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
saveNameBox.TextColor3 = Color3.fromRGB(240, 240, 250)
saveNameBox.PlaceholderText = "Имя конфига..."
saveNameBox.PlaceholderColor3 = Color3.fromRGB(110, 110, 130)
saveNameBox.Font = Enum.Font.Gotham
saveNameBox.TextSize = 12
saveNameBox.ClearTextOnFocus = false
saveNameBox.BorderSizePixel = 0
saveNameBox.Parent = SettingTab.Page

local SnCorner = Instance.new("UICorner")
SnCorner.CornerRadius = UDim.new(0, 6)
SnCorner.Parent = saveNameBox

AddButton(SettingTab.Page, "Сохранить конфиг", function()
    local name = saveNameBox.Text
    if name == "" then name = "config_" .. os.time() end
    SaveConfigToFile(name, CollectConfig())
    saveNameBox.Text = ""
end)

AddButton(SettingTab.Page, "Загрузить автocохранение", function()
    local data = LoadConfigFromFile("autosave")
    if data then ApplyConfig(data) end
end)

AddButton(SettingTab.Page, "Выгрузить скрипт", function()
    if ConfigSystem.HasFileAPI then
        SaveConfigToFile("autosave", CollectConfig())
    end
    ScreenGui:Destroy()
    MiniGui:Destroy()
    StopTarget()
    ParryConfig.Enabled = false
end)

local MiniFrame = Instance.new("Frame")
MiniFrame.Size = UDim2.new(0, 160, 0, 80)
MiniFrame.Position = UDim2.new(0, 20, 0, 20)
MiniFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
MiniFrame.BackgroundTransparency = 0.1
MiniFrame.BorderSizePixel = 0
MiniFrame.Visible = false
MiniFrame.Parent = MiniGui

local MiniCorner = Instance.new("UICorner")
MiniCorner.CornerRadius = UDim.new(0, 10)
MiniCorner.Parent = MiniFrame

local MiniStroke = Instance.new("UIStroke")
MiniStroke.Color = Theme.Accent
MiniStroke.Thickness = 1
MiniStroke.Transparency = 0.5
MiniStroke.Parent = MiniFrame

local MiniTitle = Instance.new("TextLabel")
MiniTitle.Size = UDim2.new(1, -20, 0, 20)
MiniTitle.Position = UDim2.new(0, 10, 0, 6)
MiniTitle.BackgroundTransparency = 1
MiniTitle.Text = "PARRY HUB"
MiniTitle.TextColor3 = Theme.Accent
MiniTitle.Font = Enum.Font.GothamBold
MiniTitle.TextSize = 11
MiniTitle.TextXAlignment = Enum.TextXAlignment.Left
MiniTitle.Parent = MiniFrame

local PingLabel = Instance.new("TextLabel")
PingLabel.Size = UDim2.new(1, -20, 0, 18)
PingLabel.Position = UDim2.new(0, 10, 0, 28)
PingLabel.BackgroundTransparency = 1
PingLabel.Text = "Ping: -- ms"
PingLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
PingLabel.Font = Enum.Font.Gotham
PingLabel.TextSize = 12
PingLabel.TextXAlignment = Enum.TextXAlignment.Left
PingLabel.Parent = MiniFrame

local FpsLabel = Instance.new("TextLabel")
FpsLabel.Size = UDim2.new(1, -20, 0, 18)
FpsLabel.Position = UDim2.new(0, 10, 0, 48)
FpsLabel.BackgroundTransparency = 1
FpsLabel.Text = "FPS: --"
FpsLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
FpsLabel.Font = Enum.Font.Gotham
FpsLabel.TextSize = 12
FpsLabel.TextXAlignment = Enum.TextXAlignment.Left
FpsLabel.Parent = MiniFrame

task.spawn(function()
    local frames = 0
    local lastTime = tick()
    RunService.RenderStepped:Connect(function()
        frames = frames + 1
        local now = tick()
        if now - lastTime >= 1 then
            local fps = math.floor(frames / (now - lastTime))
            FpsLabel.Text = "FPS: " .. fps
            frames = 0
            lastTime = now
        end
    end)
end)

task.spawn(function()
    while task.wait(1) do
        local ok, ping = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and ping then
            PingLabel.Text = string.format("Ping: %d ms", math.floor(ping))
        else
            PingLabel.Text = "Ping: -- ms"
        end
    end
end)

local MiniDragging, MiniDragStart, MiniStartPos
MiniFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        MiniDragging = true
        MiniDragStart = input.Position
        MiniStartPos = MiniFrame.Position
    end
end)
MiniFrame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then MiniDragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and MiniDragging then
        local delta = input.Position - MiniDragStart
        MiniFrame.Position = UDim2.new(MiniStartPos.X.Scale, MiniStartPos.X.Offset + delta.X, MiniStartPos.Y.Scale, MiniStartPos.Y.Offset + delta.Y)
    end
end)

MiniFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local clickTime = tick()
        task.delay(0.3, function()
            if tick() - clickTime >= 0.28 then return end
            local wasDragging = MiniDragging
            if not wasDragging then
                MainFrame.Visible = true
                MiniFrame.Visible = false
                MainFrame.Size = UDim2.new(0, 0, 0, 0)
                TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Size = UDim2.new(0, 440, 0, 320)
                }):Play()
            end
        end)
    end
end)

local isOpen = false
local function ToggleGUI()
    isOpen = not isOpen
    if isOpen then
        MainFrame.Visible = true
        MiniFrame.Visible = false
        MainFrame.Size = UDim2.new(0, 0, 0, 0)
        TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 440, 0, 320)
        }):Play()
    else
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 0, 0, 0)
        }):Play()
        task.delay(0.25, function()
            MainFrame.Visible = false
            MiniFrame.Visible = true
        end)
    end
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        ToggleGUI()
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == TargetConfig.BindToggle then
        if TargetState.Active then StopTarget() else StartTarget() end
    elseif input.KeyCode == TargetConfig.BindNext then
        GetNextTarget()
    elseif input.KeyCode == TargetConfig.BindPrev then
        GetPrevTarget()
    end
end)

MiniFrame.Visible = false
MainFrame.Visible = true
MainFrame.Size = UDim2.new(0, 440, 0, 320)
isOpen = true

print("[ParryHub] Loaded. Press Insert to toggle.")