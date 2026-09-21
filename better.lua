--[================================================================]--
-- Simple Server Hopper & Staff List Manager
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

-- Hapless Studios Group Configuration
local GROUP_ID = 5502618 -- Hapless Studios Group ID

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
-- UI Elements Creation: ScreenGui Setup
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

-------------------------------------------------------------------------
-- 1. UI Elements Creation: Server Hopper (Jobids) GUI
-------------------------------------------------------------------------
local outerFrame = Instance.new("Frame")
outerFrame.Size = UDim2.new(0, 244, 0, 132)
outerFrame.Position = UDim2.new(0, 30, 0, 170)
outerFrame.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
outerFrame.BorderSizePixel = 0
outerFrame.Active = true
outerFrame.Parent = screenGui

local outerStroke = Instance.new("UIStroke")
outerStroke.Thickness = 1
outerStroke.Color = Color3.fromRGB(65, 65, 65)
outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
outerStroke.Parent = outerFrame

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(1, -10, 1, -10)
mainFrame.Position = UDim2.new(0, 5, 0, 5)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
mainFrame.BorderSizePixel = 1
mainFrame.BorderColor3 = Color3.fromRGB(35, 35, 35) -- Exact subtle inner grid border line
mainFrame.Parent = outerFrame

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

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 20)
titleLabel.Position = UDim2.new(0, 0, 0, 3)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.Code
titleLabel.Text = "Jobids"
titleLabel.TextColor3 = Color3.fromRGB(215, 215, 215)
titleLabel.TextSize = 13
titleLabel.Parent = mainFrame

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -12, 0, 1)
divider.Position = UDim2.new(0, 6, 0, 23)
divider.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
divider.BorderSizePixel = 0
divider.Parent = mainFrame

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
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = rowFrame

        layoutOrderCounter = layoutOrderCounter + 1
    end

    addRow(currentJobId, Color3.fromRGB(240, 240, 240))

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
-- 2. UI Elements Creation: Staff List GUI
-------------------------------------------------------------------------
local playerOuterFrame = Instance.new("Frame")
playerOuterFrame.Size = UDim2.new(0, 220, 0, 48)
playerOuterFrame.Position = UDim2.new(0, 284, 0, 170)
playerOuterFrame.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
playerOuterFrame.BorderSizePixel = 0
playerOuterFrame.Active = true
playerOuterFrame.Parent = screenGui

local playerOuterStroke = Instance.new("UIStroke")
playerOuterStroke.Thickness = 1
playerOuterStroke.Color = Color3.fromRGB(65, 65, 65)
playerOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
playerOuterStroke.Parent = playerOuterFrame

local playerMainFrame = Instance.new("Frame")
playerMainFrame.Size = UDim2.new(1, -10, 1, -10)
playerMainFrame.Position = UDim2.new(0, 5, 0, 5)
playerMainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
playerMainFrame.BorderSizePixel = 1
playerMainFrame.BorderColor3 = Color3.fromRGB(35, 35, 35) -- Exact subtle inner grid border line
playerMainFrame.Parent = playerOuterFrame

local playerTopBar = Instance.new("Frame")
playerTopBar.Size = UDim2.new(1, 0, 0, 2)
playerTopBar.Position = UDim2.new(0, 0, 0, 0)
playerTopBar.BorderSizePixel = 0
playerTopBar.Parent = playerMainFrame

local playerTopBarGradient = Instance.new("UIGradient")
playerTopBarGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(225, 205, 75)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 95, 205)),
    ColorSequenceKeypoint.new(0.66, Color3.fromRGB(160, 100, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(80, 190, 255))
})
playerTopBarGradient.Parent = playerTopBar

local playerTitleLabel = Instance.new("TextLabel")
playerTitleLabel.Size = UDim2.new(1, 0, 0, 20)
playerTitleLabel.Position = UDim2.new(0, 0, 0, 3)
playerTitleLabel.BackgroundTransparency = 1
playerTitleLabel.Font = Enum.Font.Code
playerTitleLabel.Text = "Staff (0)"
playerTitleLabel.TextColor3 = Color3.fromRGB(215, 215, 215)
playerTitleLabel.TextSize = 13
playerTitleLabel.Parent = playerMainFrame

local playerDivider = Instance.new("Frame")
playerDivider.Size = UDim2.new(1, -12, 0, 1)
playerDivider.Position = UDim2.new(0, 6, 0, 23)
playerDivider.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
playerDivider.BorderSizePixel = 0
playerDivider.Parent = playerMainFrame

local playerContainer = Instance.new("Frame")
playerContainer.Size = UDim2.new(1, -12, 1, -27)
playerContainer.Position = UDim2.new(0, 6, 0, 26)
playerContainer.BackgroundTransparency = 1
playerContainer.Parent = playerMainFrame

local playerListLayout = Instance.new("UIListLayout")
playerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
playerListLayout.Padding = UDim.new(0, 2)
playerListLayout.Parent = playerContainer

local isUpdatingStaff = false
local function updatePlayerList()
    if isUpdatingStaff then return end
    isUpdatingStaff = true

    task.defer(function()
        for _, child in ipairs(playerContainer:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        local staffMembers = {}
        
        for _, plr in ipairs(Players:GetPlayers()) do
            local inGroup = pcall(function() return plr:IsInGroup(GROUP_ID) end)
            if inGroup then
                local successRankNum, rankNum = pcall(function()
                    return plr:GetRankInGroup(GROUP_ID)
                end)
                local successRole, rankInGroup = pcall(function()
                    return plr:GetRoleInGroup(GROUP_ID)
                end)

                if successRankNum and rankNum > 1 then
                    table.insert(staffMembers, {
                        Player = plr,
                        Role = successRole and rankInGroup or "Member"
                    })
                end
            end
        end

        playerTitleLabel.Text = "Staff (" .. #staffMembers .. ")"

        local playerOrderCounter = 1

        local function addPlayerRow(text, color)
            local rowFrame = Instance.new("Frame")
            rowFrame.Size = UDim2.new(1, 0, 0, 18)
            rowFrame.BackgroundTransparency = 1
            rowFrame.LayoutOrder = playerOrderCounter
            rowFrame.Parent = playerContainer

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.Code
            lbl.Text = text
            lbl.TextColor3 = color
            lbl.TextSize = 12
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = rowFrame

            playerOrderCounter = playerOrderCounter + 1
        end

        if #staffMembers == 0 then
            addPlayerRow("No staff in server", Color3.fromRGB(130, 130, 130))
        else
            for _, data in ipairs(staffMembers) do
                local textColor = (data.Player == LocalPlayer) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(165, 215, 255)
                addPlayerRow(data.Player.Name .. " [" .. data.Role .. "]", textColor)
            end
        end

        local totalHeight = 26 + (math.max(#staffMembers, 1) * 20) + 6
        playerOuterFrame.Size = UDim2.new(0, 220, 0, totalHeight)
        
        isUpdatingStaff = false
    end)
end

updatePlayerList()

Players.PlayerAdded:Connect(updatePlayerList)
Players.PlayerRemoving:Connect(updatePlayerList)

-------------------------------------------------------------------------
-- Universal Dragging Logic for Both Panels
-------------------------------------------------------------------------
local function makeDraggable(topHandle, targetFrame)
    local dragging = false
    local dragStart, startPos

    topHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = targetFrame.Position

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
            targetFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(titleLabel, outerFrame)
makeDraggable(topBar, outerFrame)
makeDraggable(playerTitleLabel, playerOuterFrame)
makeDraggable(playerTopBar, playerOuterFrame)

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
    if child.Name == "VoteKickGroup" or child.Name == "VoteKickGui" then
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

print("serverhop and staff list loaded for " .. LocalPlayer.Name)
