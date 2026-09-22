--[================================================================]--
-- Simple Server Hopper & Staff List Manager (Improved UI v2)
-- Fixed: staff text vanishing, better outline, cleaner text
--[================================================================]--

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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

-- UI Constants (matched to Keybinds style for 1:1 consistency)
local PANEL_WIDTH_JOBIDS = 244
local PANEL_WIDTH_STAFF = 220
local ROW_HEIGHT = 18
local TITLE_HEIGHT = 22
local DIVIDER_Y = 23
local CONTENT_TOP = 26
local OUTER_PADDING = 5
local MAX_DISPLAY_ROWS = 4 -- current/job + up to 3 more, or staff rows
local EMPTY_ROW_TEXT_COLOR = Color3.fromRGB(130, 130, 130)
local TITLE_COLOR = Color3.fromRGB(215, 215, 215)
local PRIMARY_TEXT = Color3.fromRGB(240, 240, 240)
local SECONDARY_TEXT = Color3.fromRGB(155, 155, 155)
local MORE_TEXT = Color3.fromRGB(120, 120, 120)
local STAFF_TEXT = Color3.fromRGB(165, 215, 255)

-------------------------------------------------------------------------
-- Persistent Storage Management (bans expire after 24 hours)
-------------------------------------------------------------------------
local BAN_DURATION = 24 * 60 * 60 -- 1 day in seconds

-- bannedServers is now a list of {id = string, bannedAt = number (os.time)}
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
            local now = os.time()

            -- Support both old format (array of strings) and new format (array of objects)
            for _, entry in ipairs(decoded) do
                if type(entry) == "string" and entry ~= "" then
                    -- Migrate old permanent bans → treat as banned just now (still valid for 24h)
                    table.insert(cleaned, {id = entry, bannedAt = now})
                elseif type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "" then
                    local bannedAt = tonumber(entry.bannedAt) or now
                    if (now - bannedAt) < BAN_DURATION then
                        table.insert(cleaned, {id = entry.id, bannedAt = bannedAt})
                    end
                    -- else expired → drop it
                end
            end

            -- Also handle old dictionary-style saves just in case
            if #cleaned == 0 then
                for jobId, val in pairs(decoded) do
                    if type(jobId) == "string" and jobId ~= "" then
                        local bannedAt = (type(val) == "number" and val) or now
                        if (now - bannedAt) < BAN_DURATION then
                            table.insert(cleaned, {id = jobId, bannedAt = bannedAt})
                        end
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

local function cleanExpiredBans()
    local now = os.time()
    local kept = {}
    for _, entry in ipairs(bannedServers) do
        if type(entry) == "table" and entry.id and (now - (entry.bannedAt or 0)) < BAN_DURATION then
            table.insert(kept, entry)
        end
    end
    if #kept ~= #bannedServers then
        bannedServers = kept
        saveBannedServers()
        return true -- changed
    end
    return false
end

local function isServerBanned(jobId)
    if not jobId or jobId == "" then return false end
    local now = os.time()
    for _, entry in ipairs(bannedServers) do
        if entry.id == jobId and (now - (entry.bannedAt or 0)) < BAN_DURATION then
            return true
        end
    end
    return false
end

local function addBannedServer(jobId)
    if not jobId or jobId == "" then return end
    if isServerBanned(jobId) then return end
    
    table.insert(bannedServers, {
        id = jobId,
        bannedAt = os.time()
    })
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
-- Helper: Create consistent panel (outer + main + top gradient + title + divider)
-- Matches Keybinds visual style + guaranteed outer stroke/outline on both
-------------------------------------------------------------------------
local function createPanel(width, titleText, gradientReversed)
    local outer = Instance.new("Frame")
    outer.Size = UDim2.new(0, width, 0, 48) -- start compact like Keybinds
    outer.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
    outer.BorderSizePixel = 0
    outer.Active = true
    outer.Parent = screenGui

    -- Outer layer outline (always present and visible on both panels)
    local outerStroke = Instance.new("UIStroke")
    outerStroke.Name = "OuterOutline"
    outerStroke.Thickness = 1
    outerStroke.Color = Color3.fromRGB(70, 70, 70) -- slightly brighter for visibility
    outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outerStroke.LineJoinMode = Enum.LineJoinMode.Miter
    outerStroke.Parent = outer

    local main = Instance.new("Frame")
    main.Size = UDim2.new(1, -10, 1, -10)
    main.Position = UDim2.new(0, 5, 0, 5)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    main.BorderSizePixel = 1
    main.BorderColor3 = Color3.fromRGB(35, 35, 35)
    main.Parent = outer

    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, 0, 0, 2)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    topBar.BorderSizePixel = 0
    topBar.Parent = main

    local topBarGradient = Instance.new("UIGradient")
    if gradientReversed then
        topBarGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(225, 205, 75)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 95, 205)),
            ColorSequenceKeypoint.new(0.66, Color3.fromRGB(160, 100, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(80, 190, 255))
        })
    else
        topBarGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(80, 190, 255)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(160, 100, 255)),
            ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 95, 205)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(225, 205, 75))
        })
    end
    topBarGradient.Parent = topBar

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 20)
    title.Position = UDim2.new(0, 0, 0, 3)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.Text = titleText
    title.TextColor3 = TITLE_COLOR
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = main

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -12, 0, 1)
    divider.Position = UDim2.new(0, 6, 0, DIVIDER_Y)
    divider.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
    divider.BorderSizePixel = 0
    divider.Parent = main

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -12, 1, -27)
    content.Position = UDim2.new(0, 6, 0, CONTENT_TOP)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = false -- turned OFF to stop text vanishing / clipping issues
    content.Parent = main

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = content

    return outer, main, title, content, topBar
end

-------------------------------------------------------------------------
-- 1. Jobids Panel
-------------------------------------------------------------------------
local outerFrame, mainFrame, titleLabel, contentContainer, topBar = createPanel(PANEL_WIDTH_JOBIDS, "Jobids", false)
outerFrame.Position = UDim2.new(0, 30, 0, 170)

local function updateUIList()
    -- Clear safely
    for _, child in ipairs(contentContainer:GetChildren()) do
        if child:IsA("Frame") then
            child.Parent = nil
            child:Destroy()
        end
    end

    local layoutOrderCounter = 1
    local visibleRows = 0

    local function addRow(text, color)
        local rowFrame = Instance.new("Frame")
        rowFrame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
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
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        -- Subtle stroke so text stays readable and doesn't "disappear" against dark bg
        lbl.TextStrokeTransparency = 0.75
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.Parent = rowFrame

        layoutOrderCounter = layoutOrderCounter + 1
        visibleRows = visibleRows + 1
    end

    -- Always show current job id
    if currentJobId and currentJobId ~= "" then
        addRow(currentJobId, PRIMARY_TEXT)
    else
        addRow("(no jobid)", EMPTY_ROW_TEXT_COLOR)
    end

    -- Drop any bans that have aged past 24h before displaying
    cleanExpiredBans()

    local totalBanned = #bannedServers
    local maxBannedShow = MAX_DISPLAY_ROWS - 1

    for i = 1, math.min(totalBanned, maxBannedShow) do
        local entry = bannedServers[i]
        local id = (type(entry) == "table" and entry.id) or tostring(entry)
        addRow(id, SECONDARY_TEXT)
    end

    if totalBanned > maxBannedShow then
        addRow("and " .. (totalBanned - maxBannedShow) .. " more", MORE_TEXT)
    end

    -- Slightly more generous height so nothing ever clips
    local contentHeight = math.max(visibleRows, 1) * (ROW_HEIGHT + 2)
    local totalHeight = 10 + CONTENT_TOP + contentHeight + 8  -- outer padding + content + bottom breathing room
    outerFrame.Size = UDim2.new(0, PANEL_WIDTH_JOBIDS, 0, totalHeight)
end

updateUIList()

-------------------------------------------------------------------------
-- 2. Staff List Panel – fixed vanishing text + better look
-------------------------------------------------------------------------
local playerOuterFrame, playerMainFrame, playerTitleLabel, playerContainer, playerTopBar = createPanel(PANEL_WIDTH_STAFF, "Staff (0)", true)
playerOuterFrame.Position = UDim2.new(0, 284, 0, 170)

local isUpdatingStaff = false
local lastStaffSignature = ""
local pendingStaffUpdate = false

local function getStaffSignature(staffMembers)
    local parts = {}
    for _, data in ipairs(staffMembers) do
        table.insert(parts, data.Player.Name .. ":" .. (data.Role or ""))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function updatePlayerList()
    if isUpdatingStaff then
        pendingStaffUpdate = true
        return
    end
    isUpdatingStaff = true
    pendingStaffUpdate = false

    task.spawn(function()
        -- Collect staff first (outside of UI mutation)
        local staffMembers = {}
        
        for _, plr in ipairs(Players:GetPlayers()) do
            local ok, inGroup = pcall(function()
                return plr:IsInGroup(GROUP_ID)
            end)
            
            if ok and inGroup then
                local successRankNum, rankNum = pcall(function()
                    return plr:GetRankInGroup(GROUP_ID)
                end)
                local successRole, roleName = pcall(function()
                    return plr:GetRoleInGroup(GROUP_ID)
                end)

                if successRankNum and type(rankNum) == "number" and rankNum > 1 then
                    table.insert(staffMembers, {
                        Player = plr,
                        Role = (successRole and roleName) or "Staff"
                    })
                end
            end
        end

        table.sort(staffMembers, function(a, b)
            return a.Player.Name:lower() < b.Player.Name:lower()
        end)

        local signature = getStaffSignature(staffMembers)
        local count = #staffMembers

        -- Skip full rebuild if nothing actually changed (prevents flicker / vanishing)
        if signature == lastStaffSignature and playerTitleLabel.Text == ("Staff (" .. count .. ")") then
            isUpdatingStaff = false
            if pendingStaffUpdate then
                task.defer(updatePlayerList)
            end
            return
        end
        lastStaffSignature = signature

        -- Wait one frame so any previous destroy has fully processed
        RunService.Heartbeat:Wait()

        -- Clear previous rows safely
        for _, child in ipairs(playerContainer:GetChildren()) do
            if child:IsA("Frame") then
                child.Parent = nil
                child:Destroy()
            end
        end

        -- Another frame after clear helps Roblox UI engine not drop text
        RunService.Heartbeat:Wait()

        playerTitleLabel.Text = "Staff (" .. count .. ")"

        local playerOrderCounter = 1
        local visibleRows = 0

        local function addPlayerRow(text, color)
            local rowFrame = Instance.new("Frame")
            rowFrame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
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
            lbl.TextYAlignment = Enum.TextYAlignment.Center
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            -- Subtle black stroke = text stays crisp and never "vanishes"
            lbl.TextStrokeTransparency = 0.75
            lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            lbl.Parent = rowFrame

            playerOrderCounter = playerOrderCounter + 1
            visibleRows = visibleRows + 1
        end

        if count == 0 then
            addPlayerRow("No staff in server", EMPTY_ROW_TEXT_COLOR)
        else
            local maxShow = MAX_DISPLAY_ROWS
            for i = 1, math.min(count, maxShow) do
                local data = staffMembers[i]
                local textColor = (data.Player == LocalPlayer) and PRIMARY_TEXT or STAFF_TEXT
                addPlayerRow(data.Player.Name .. " [" .. data.Role .. "]", textColor)
            end
            if count > maxShow then
                addPlayerRow("and " .. (count - maxShow) .. " more", MORE_TEXT)
            end
        end

        -- Generous height so last row never gets clipped
        local contentHeight = math.max(visibleRows, 1) * (ROW_HEIGHT + 2)
        local totalHeight = 10 + CONTENT_TOP + contentHeight + 8
        playerOuterFrame.Size = UDim2.new(0, PANEL_WIDTH_STAFF, 0, totalHeight)

        isUpdatingStaff = false

        -- If another update came in while we were working, run it now
        if pendingStaffUpdate then
            task.defer(updatePlayerList)
        end
    end)
end

updatePlayerList()

Players.PlayerAdded:Connect(function()
    task.defer(updatePlayerList)
end)
Players.PlayerRemoving:Connect(function()
    task.defer(updatePlayerList)
end)

-- Light periodic refresh only if ranks might have changed (rare)
task.spawn(function()
    while task.wait(12) do
        if not hopping then
            updatePlayerList()
        end
    end
end)

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
