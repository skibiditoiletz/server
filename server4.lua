--[================================================================]--
-- Advanced Anti-VoteKick / Serverban Hop Script (Transparent Outlined UI)
--[================================================================]--

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local placeId = game.PlaceId
local currentJobId = game.JobId

-- Configuration & Storage Files
local FILENAME = "banned_servers_v3.json"
local BANNED_EXPIRY_SECONDS = 7200 -- 2 hours auto-expiry
local MIN_PLAYERS = 1
local MAX_PLAYERS_BUFFER = 2

local hopping = false

-------------------------------------------------------------------------
-- Persistent Storage Management
-------------------------------------------------------------------------
local function loadBannedServers()
    if not (readfile and writefile) then return {} end
    local success, result = pcall(function()
        if isfile and not isfile(FILENAME) then return "{}" end
        return readfile(FILENAME)
    end)
    
    if success and result then
        local decoded = pcall(function() return HttpService:JSONDecode(result) end)
        if decoded and type(decoded) == "table" then
            local cleaned = {}
            local currentTime = os.time()
            for jobId, timestamp in pairs(decoded) do
                if type(timestamp) == "number" and (currentTime - timestamp) < BANNED_EXPIRY_SECONDS then
                    cleaned[jobId] = timestamp
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

local function addBannedServer(jobId)
    if not jobId or jobId == "" then return end
    bannedServers[jobId] = os.time()
    saveBannedServers()
end

-------------------------------------------------------------------------
-- UI Elements Creation (Completely transparent background, outlined text)
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

-- Completely invisible/transparent main container
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 360, 0, 220)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Active = false
mainFrame.Draggable = false
mainFrame.Parent = screenGui

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, 0, 1, 0)
scrollFrame.Position = UDim2.new(0, 0, 0, 0)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 4
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Active = true
scrollFrame.Parent = mainFrame

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Padding = UDim.new(0, 4)
uiListLayout.Parent = scrollFrame

local function updateUIList()
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local layoutOrderCounter = 1

    local function addRow(text, color)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Code
        lbl.Text = text
        lbl.TextColor3 = color
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.LayoutOrder = layoutOrderCounter
        lbl.Parent = scrollFrame

        -- Added UIStroke to text label for clear legibility without a background box
        local textStroke = Instance.new("UIStroke")
        textStroke.Color = Color3.fromRGB(0, 0, 0)
        textStroke.Thickness = 1.5
        textStroke.Transparency = 0.1
        textStroke.Parent = lbl

        layoutOrderCounter = layoutOrderCounter + 1
    end

    -- Current JobId (Green with outline)
    addRow(currentJobId, Color3.fromRGB(80, 255, 120))

    -- Banned JobIds (Red with outline, stacked underneath)
    for jobId, _ in pairs(bannedServers) do
        addRow(jobId, Color3.fromRGB(255, 90, 90))
    end

    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, layoutOrderCounter * 24)
end

updateUIList()

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
        customMessage = "[Connection Notice]: Client disconnected due to session consensus update (vk)."
    elseif reasonType == "serverbanned" then
        customMessage = "[Connection Notice]: Client access revoked by host policy filter (sb)."
    else
        customMessage = "[Connection Notice]: Session instance terminated."
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
                    if jobId ~= currentJobId and not bannedServers[jobId] then
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

if bannedServers[currentJobId] then
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

print("[ServerHop Manager] Loaded with transparent background and outlined JobID text.")
