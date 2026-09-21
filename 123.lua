--[================================================================]--
-- Simple Server Hopper (Matching Keybinds UI Style)
--[================================================================]--

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local placeId = game.PlaceId
local currentJobId = game.JobId

-- Configuration & Storage Files (Unique per account name)
local FILENAME = "banned_servers_simple_" .. LocalPlayer.Name .. ".json"
local MIN_PLAYERS = 1
local MAX_PLAYERS_BUFFER = 2

local hopping = false

-------------------------------------------------------------------------
-- Persistent Storage Management
-------------------------------------------------------------------------
local function loadBannedServers()
    if not (readfile and writefile) then return {} end
    local success, result = pcall(function()
        if isfile and not isfile(FILENAME) then return "[]" end
        return readfile(FILENAME)
    end)
    
    if success and result then
        local decSuccess, decoded = pcall(function()
            return HttpService:JSONDecode(result)
        end)
        
        if decSuccess and type(decoded) == "table" then
            local cleaned = {}
            if #decoded > 0 or (next(decoded) ~= nil and type(next(decoded)) == "number") then
                for _, jobId in ipairs(decoded) do
                    if type(jobId) == "string" and jobId ~= "" then
                        table.insert(cleaned, jobId)
                    end
                end
            else
                for jobId, _ in pairs(decoded) do
                    if type(jobId) == "string" and jobId ~= "" then
                        table.insert(cleaned, jobId)
                    end
                end
            end
            return cleaned
        end
    end
    return {}
end

local bannedServers = loadBannedServers()

local function saveBannedServers()
    if not writefile then return end
    pcall(function()
        writefile(FILENAME, HttpService:JSONEncode(bannedServers))
    end)
end

local function isServerBanned(jobId)
    for _, savedId in ipairs(bannedServers) do
        if savedId == jobId then
            return true
        end
    end
    return false
end

local function addBannedServer(jobId)
    if not jobId or jobId == "" then return end
    if isServerBanned(jobId) then return end
    
    table.insert(bannedServers, jobId)
    saveBannedServers()
end

-------------------------------------------------------------------------
-- UI Elements Creation (Exact Keybinds Color/Border Match)
-------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ServerHopManagerGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local successParent = pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(screenGui)
        screenGui.Parent = CoreGui
    elseif gethui then
        screenGui.Parent = gethui()
    else
        screenGui.Parent = CoreGui
    end
end)
if not successParent then
    screenGui.Parent = PlayerGui
end

-- 1. Outer Frame (Slightly smaller margin/thickness: inset reduced from 6 to 5)
local outerFrame = Instance.new("Frame")
outerFrame.Size = UDim2.new(0, 244, 0, 132)
outerFrame.Position = UDim2.new(0, 30, 0, 170)
outerFrame.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
outerFrame.BorderSizePixel = 0
outerFrame.Active = true
outerFrame.Parent = screenGui

-- Outer Outline Edge
local outerStroke = Instance.new("UIStroke")
outerStroke.Thickness = 1
outerStroke.Color = Color3.fromRGB(65, 65, 65)
outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
outerStroke.Parent = outerFrame

-- 2. Inner Main Frame (Adjusted position and size to match 5px inset)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(1, -10, 1, -10)
mainFrame.Position = UDim2.new(0, 5, 0, 5)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
mainFrame.BorderSizePixel = 1
mainFrame.BorderColor3 = Color3.fromRGB(35, 35, 35)
mainFrame.Parent = outerFrame

-- 3. Top Spectrum Gradient Bar (Edge-to-edge inside inner frame)
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 2)
topBar.Position = UDim2.new(0, 0, 0, 0)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame

local topBarGradient = Instance.new("UIGradient")
topBarGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(80, 190, 255)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(160, 100, 255)),
    ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 95, 205)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(225, 205, 75))
})
topBarGradient.Parent = topBar

-- 4. Title Label ("jobids")
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 20)
titleLabel.Position = UDim2.new(0, 0, 0, 3)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.Code
titleLabel.Text = "jobids"
titleLabel.TextColor3 = Color3.fromRGB(215, 215, 215)
titleLabel.TextSize = 13
titleLabel.Parent = mainFrame

-- 5. Thin Horizontal Divider Line
local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -12, 0, 1)
divider.Position = UDim2.new(0, 6, 0, 23)
divider.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
divider.BorderSizePixel = 0
divider.Parent = mainFrame

-- 6. Content Container Layout
local contentContainer = Instance.new("Frame")
contentContainer.Size = UDim2.new(1, -12, 1, -27)
contentContainer.Position = UDim2.new(0, 6, 0, 26)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = mainFrame

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Padding = UDim.new(0, 2)
uiListLayout.Parent = contentContainer

local function updateUIList()
    for _, child in ipairs(contentContainer:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local layoutOrderCounter = 1

    local function addRow(text, color)
        local rowFrame = Instance.new("Frame")
        rowFrame.Size = UDim2.new(1, 0, 0, 18)
        rowFrame.BackgroundTransparency = 1
        rowFrame.LayoutOrder = layoutOrderCounter
        rowFrame.Parent = contentContainer

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Code
        lbl.Text = text
        lbl.TextColor3 = color
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = rowFrame

        layoutOrderCounter = layoutOrderCounter + 1
    end

    -- Current Session Row (Pure white)
    addRow(currentJobId, Color3.fromRGB(240, 240, 240))

    -- Banned Sessions Rows (Softened greyer tone)
    local maxDisplay = 3
    local totalBanned = #bannedServers
    
    for i = 1, math.min(totalBanned, maxDisplay) do
        addRow(bannedServers[i], Color3.fromRGB(155, 155, 155))
    end

    if totalBanned > maxDisplay then
        addRow("and " .. (totalBanned - maxDisplay) .. " more", Color3.fromRGB(120, 120, 120))
    end
end

updateUIList()

-------------------------------------------------------------------------
-- Ultra-Smooth UserInputService Dragging Logic
-------------------------------------------------------------------------
local dragging = false
local dragInput, dragStart, startPos

titleLabel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = outerFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = outerFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        outerFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-------------------------------------------------------------------------
-- Server Hopping Logic
-------------------------------------------------------------------------
local function kickAndHop(reasonType)
    if hopping then return end
    hopping = true

    addBannedServer(currentJobId)
    updateUIList()

    local customMessage = ""
    if reasonType == "votekick" then
        customMessage = "votekicked, hopping servers..."
    elseif reasonType == "serverbanned" then
        customMessage = "server banned, hopping servers..."
    else
        customMessage = "switching servers..."
    end

    pcall(function()
        LocalPlayer:Kick(customMessage)
    end)

    task.wait(0.4)

    local function fetchAndHop()
        local cursor = ""
        while true do
            local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
            if cursor ~= "" then
                url = url .. "&cursor=" .. cursor
            end

            local success, result = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            if success and result and result.data then
                for _, server in ipairs(result.data) do
                    local jobId = tostring(server.id)
                    if jobId ~= currentJobId and not isServerBanned(jobId) then
                        if server.playing >= MIN_PLAYERS and server.playing <= (server.maxPlayers - MAX_PLAYERS_BUFFER) then
                            pcall(function()
                                TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                            end)
                            task.wait(1.5)
                        end
                    end
                end
                
                if result.nextPageCursor then
                    cursor = result.nextPageCursor
                else
                    break
                end
            else
                break
            end
            task.wait(0.2)
        end

        for i = 1, 5 do
            pcall(function()
                TeleportService:Teleport(placeId, LocalPlayer)
            end)
            task.wait(1)
        end
    end

    task.spawn(fetchAndHop)
end

if isServerBanned(currentJobId) then
    task.spawn(function()
        task.wait(1)
        addBannedServer(currentJobId)
        currentJobId = "" 
        kickAndHop("serverbanned")
    end)
end

-------------------------------------------------------------------------
-- Detection Listeners
-------------------------------------------------------------------------
local function checkVoteKickGui(gui)
    if not gui or not gui.Enabled then return end

    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if string.find(string.lower(obj.Text or ""), string.lower(LocalPlayer.Name)) then
                kickAndHop("votekick")
                return
            end
        end
    end
end

local function checkServerBanned()
    local msg = ""
    pcall(function()
        if GuiService.GetErrorMessage then
            msg = tostring(GuiService:GetErrorMessage() or "")
        end
    end)
    pcall(function()
        if GuiService.GetUiMessage then
            msg = msg .. " " .. tostring(GuiService:GetUiMessage() or "")
        end
    end)

    msg = string.lower(msg)
    if string.find(msg, "player is currently serverbanned") or string.find(msg, "serverbanned") or string.find(msg, "banned from this server") then
        kickAndHop("serverbanned")
        return true
    end
    return false
end

checkServerBanned()
local existingGui = PlayerGui:FindFirstChild("VoteKickGui")
if existingGui then
    checkVoteKickGui(existingGui)
end

PlayerGui.ChildAdded:Connect(function(child)
    if child.Name == "VoteKickGui" then
        task.wait(0.1)
        checkVoteKickGui(child)
        child:GetPropertyChangedSignal("Enabled"):Connect(function()
            if child.Enabled then
                checkVoteKickGui(child)
            end
        end)
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        if hopping then break end
        checkServerBanned()

        local gui = PlayerGui:FindFirstChild("VoteKickGui")
        if gui and gui.Enabled then
            checkVoteKickGui(gui)
        end
    end
end)

print("serverhop loaded for " .. LocalPlayer.Name)
