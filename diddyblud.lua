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

-- Configuration & Storage Files (Unique per account UserId – more reliable than Name)
local FILENAME = "banned_servers_simple_" .. tostring(LocalPlayer.UserId) .. ".json"
local MIN_PLAYERS = 1
local MAX_PLAYERS_BUFFER = 2

-- Hapless Studios Group Configuration
local GROUP_ID = 5502618 -- Hapless Studios Group ID

local hopping = false

-------------------------------------------------------------------------
-- Universal Dragging Logic (defined early so all panels can use it)
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
        -- Prefer UserId-based file; fall back to old Name-based file for migration
        if isfile and isfile(FILENAME) then
            return readfile(FILENAME)
        end
        local oldNameFile = "banned_servers_simple_" .. LocalPlayer.Name .. ".json"
        if isfile and isfile(oldNameFile) then
            local oldData = readfile(oldNameFile)
            -- One-time migration: copy to new UserId file
            pcall(function() writefile(FILENAME, oldData) end)
            return oldData
        end
        return "[]"
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
-- HTTP helper (tries direct + multiple proxies, GET + POST)
-------------------------------------------------------------------------
local function httpRequest(opts)
    opts = opts or {}
    local originalUrl = opts.Url or opts.url or ""
    local method = string.upper(opts.Method or opts.method or "GET")
    local body = opts.Body or opts.body
    local headers = opts.Headers or opts.headers or {}

    -- Ensure content-type for JSON posts
    if method == "POST" and body and not headers["Content-Type"] and not headers["content-type"] then
        headers["Content-Type"] = "application/json"
    end

    local urlsToTry = { originalUrl }
    if originalUrl:find("roblox%.com") then
        table.insert(urlsToTry, (originalUrl:gsub("roblox%.com", "roproxy.com")))
        table.insert(urlsToTry, (originalUrl:gsub("roblox%.com", "ff-roproxy.com")))
    end

    local reqFunc = (syn and syn.request)
        or (http and http.request)
        or (fluxus and fluxus.request)
        or request
        or http_request

    local lastStatus, lastUrl = 0, originalUrl

    for _, url in ipairs(urlsToTry) do
        lastUrl = url

        -- 1) Executor request function
        if reqFunc then
            local ok, res = pcall(function()
                return reqFunc({
                    Url = url,
                    Method = method,
                    Headers = headers,
                    Body = body
                })
            end)
            if ok and type(res) == "table" then
                local status = tonumber(res.StatusCode or res.Status or res.statusCode or 0) or 0
                local resBody = res.Body or res.body or res.Response or res.response or ""
                lastStatus = status
                if (res.Success == true or (status >= 200 and status < 300)) and type(resBody) == "string" and #resBody > 0 then
                    return { Success = true, StatusCode = status, Body = resBody, Url = url }
                end
            end
        end

        -- 2) game:HttpGet (GET only)
        if method == "GET" then
            local ok, result = pcall(function()
                return game:HttpGet(url, true)
            end)
            if ok and type(result) == "string" and #result > 0 then
                return { Success = true, StatusCode = 200, Body = result, Url = url }
            end
        end

        -- 3) HttpService (works in some environments)
        if method == "POST" and body then
            local ok, result = pcall(function()
                return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
            end)
            if ok and type(result) == "string" and #result > 0 then
                return { Success = true, StatusCode = 200, Body = result, Url = url }
            end
        elseif method == "GET" then
            local ok, result = pcall(function()
                return HttpService:GetAsync(url)
            end)
            if ok and type(result) == "string" and #result > 0 then
                return { Success = true, StatusCode = 200, Body = result, Url = url }
            end
        end
    end

    return { Success = false, StatusCode = lastStatus, Body = "", Url = lastUrl }
end

-------------------------------------------------------------------------
-- 2. Staff List Panel – fixed vanishing text + better look
-------------------------------------------------------------------------
local playerOuterFrame, playerMainFrame, playerTitleLabel, playerContainer, playerTopBar = createPanel(PANEL_WIDTH_STAFF, "Staff (0)", true)
playerOuterFrame.Position = UDim2.new(0, 284, 0, 170)

-- Small button on the Staff panel to open the advanced Online Staff window
local advancedBtn = Instance.new("TextButton")
advancedBtn.Name = "AdvancedStaffBtn"
advancedBtn.Size = UDim2.new(0, 18, 0, 16)
advancedBtn.Position = UDim2.new(1, -22, 0, 4)
advancedBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
advancedBtn.BorderSizePixel = 0
advancedBtn.Text = "…"
advancedBtn.Font = Enum.Font.Code
advancedBtn.TextSize = 12
advancedBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
advancedBtn.AutoButtonColor = true
advancedBtn.Parent = playerMainFrame

local advBtnStroke = Instance.new("UIStroke")
advBtnStroke.Thickness = 1
advBtnStroke.Color = Color3.fromRGB(60, 60, 60)
advBtnStroke.Parent = advancedBtn

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

local function getPlayerRankAndRole(plr)
    local rankOk, rankNum = pcall(function()
        return plr:GetRankInGroup(GROUP_ID)
    end)
    if not rankOk or type(rankNum) ~= "number" then
        rankNum = 0
    end

    local roleName = "Staff"
    if rankNum > 0 then
        local roleOk, role = pcall(function()
            return plr:GetRoleInGroup(GROUP_ID)
        end)
        if roleOk and type(role) == "string" and role ~= "" then
            roleName = role
        end
    end
    return rankNum, roleName
end

local function updatePlayerList()
    if isUpdatingStaff then
        pendingStaffUpdate = true
        return
    end
    isUpdatingStaff = true
    pendingStaffUpdate = false

    task.spawn(function()
        local staffMembers = {}
        
        for _, plr in ipairs(Players:GetPlayers()) do
            local rankNum, roleName = getPlayerRankAndRole(plr)
            if rankNum > 1 then
                table.insert(staffMembers, {
                    Player = plr,
                    Role = roleName,
                    Rank = rankNum
                })
            end
        end

        table.sort(staffMembers, function(a, b)
            if (a.Rank or 0) ~= (b.Rank or 0) then
                return (a.Rank or 0) > (b.Rank or 0)
            end
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
                addPlayerRow(data.Player.Name .. " [" .. data.Role .. " | " .. tostring(data.Rank or "?") .. "]", textColor)
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
    task.delay(1.5, updatePlayerList)
    task.delay(4, updatePlayerList)
end)
Players.PlayerRemoving:Connect(function()
    task.defer(updatePlayerList)
end)

task.spawn(function()
    while task.wait(8) do
        if not hopping then
            updatePlayerList()
        end
    end
end)

-------------------------------------------------------------------------
-- Advanced Online Staff Window (live fetch, no permanent member cache)
-------------------------------------------------------------------------
local advancedWindow = nil
local isFetchingAdvanced = false

local function createAdvancedStaffWindow()
    if advancedWindow and advancedWindow.Parent then
        advancedWindow.Visible = true
        return advancedWindow
    end

    local currentStaffData = {} -- kept only while window is open (not a permanent cache)
    local currentSortMode = "status" -- "status" | "name" | "role"

    local winOuter = Instance.new("Frame")
    winOuter.Name = "AdvancedStaffWindow"
    winOuter.Size = UDim2.new(0, 440, 0, 400)
    winOuter.Position = UDim2.new(0.5, -220, 0.5, -200)
    winOuter.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
    winOuter.BorderSizePixel = 0
    winOuter.Active = true
    winOuter.Parent = screenGui

    local winStroke = Instance.new("UIStroke")
    winStroke.Thickness = 1
    winStroke.Color = Color3.fromRGB(70, 70, 70)
    winStroke.Parent = winOuter

    local winMain = Instance.new("Frame")
    winMain.Size = UDim2.new(1, -10, 1, -10)
    winMain.Position = UDim2.new(0, 5, 0, 5)
    winMain.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    winMain.BorderSizePixel = 1
    winMain.BorderColor3 = Color3.fromRGB(35, 35, 35)
    winMain.Parent = winOuter

    local winTopBar = Instance.new("Frame")
    winTopBar.Size = UDim2.new(1, 0, 0, 2)
    winTopBar.BorderSizePixel = 0
    winTopBar.Parent = winMain
    local winGrad = Instance.new("UIGradient")
    winGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(80, 190, 255)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(160, 100, 255)),
        ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 95, 205)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(225, 205, 75))
    })
    winGrad.Parent = winTopBar

    local winTitle = Instance.new("TextLabel")
    winTitle.Size = UDim2.new(1, -160, 0, 22)
    winTitle.Position = UDim2.new(0, 8, 0, 4)
    winTitle.BackgroundTransparency = 1
    winTitle.Font = Enum.Font.Code
    winTitle.Text = "Online Staff (live)"
    winTitle.TextColor3 = TITLE_COLOR
    winTitle.TextSize = 13
    winTitle.TextXAlignment = Enum.TextXAlignment.Left
    winTitle.Parent = winMain

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 18)
    closeBtn.Position = UDim2.new(1, -28, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.Code
    closeBtn.TextSize = 12
    closeBtn.TextColor3 = Color3.fromRGB(220, 140, 140)
    closeBtn.Parent = winMain
    closeBtn.MouseButton1Click:Connect(function()
        winOuter.Visible = false
    end)

    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 55, 0, 18)
    refreshBtn.Position = UDim2.new(1, -88, 0, 5)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Text = "Refresh"
    refreshBtn.Font = Enum.Font.Code
    refreshBtn.TextSize = 11
    refreshBtn.TextColor3 = Color3.fromRGB(160, 200, 255)
    refreshBtn.Parent = winMain

    -- Sort mode buttons
    local sortStatusBtn = Instance.new("TextButton")
    sortStatusBtn.Size = UDim2.new(0, 48, 0, 16)
    sortStatusBtn.Position = UDim2.new(0, 8, 0, 28)
    sortStatusBtn.BackgroundColor3 = Color3.fromRGB(40, 55, 40)
    sortStatusBtn.BorderSizePixel = 0
    sortStatusBtn.Text = "Status"
    sortStatusBtn.Font = Enum.Font.Code
    sortStatusBtn.TextSize = 10
    sortStatusBtn.TextColor3 = Color3.fromRGB(160, 230, 160)
    sortStatusBtn.Parent = winMain

    local sortNameBtn = Instance.new("TextButton")
    sortNameBtn.Size = UDim2.new(0, 40, 0, 16)
    sortNameBtn.Position = UDim2.new(0, 60, 0, 28)
    sortNameBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    sortNameBtn.BorderSizePixel = 0
    sortNameBtn.Text = "Name"
    sortNameBtn.Font = Enum.Font.Code
    sortNameBtn.TextSize = 10
    sortNameBtn.TextColor3 = Color3.fromRGB(160, 160, 160)
    sortNameBtn.Parent = winMain

    local sortRoleBtn = Instance.new("TextButton")
    sortRoleBtn.Size = UDim2.new(0, 40, 0, 16)
    sortRoleBtn.Position = UDim2.new(0, 104, 0, 28)
    sortRoleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    sortRoleBtn.BorderSizePixel = 0
    sortRoleBtn.Text = "Role"
    sortRoleBtn.Font = Enum.Font.Code
    sortRoleBtn.TextSize = 10
    sortRoleBtn.TextColor3 = Color3.fromRGB(160, 160, 160)
    sortRoleBtn.Parent = winMain

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -160, 0, 16)
    statusLabel.Position = UDim2.new(0, 152, 0, 28)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "Fetching..."
    statusLabel.TextColor3 = Color3.fromRGB(140, 140, 140)
    statusLabel.TextSize = 11
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = winMain

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -52)
    scroll.Position = UDim2.new(0, 6, 0, 48)
    scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = winMain

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = scroll

    makeDraggable(winTitle, winOuter)
    makeDraggable(winTopBar, winOuter)

    advancedWindow = winOuter

    local function clearScroll()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
    end

    local function setSortButtons()
        local active = Color3.fromRGB(40, 55, 40)
        local inactive = Color3.fromRGB(35, 35, 35)
        local activeText = Color3.fromRGB(160, 230, 160)
        local inactiveText = Color3.fromRGB(160, 160, 160)

        sortStatusBtn.BackgroundColor3 = currentSortMode == "status" and active or inactive
        sortStatusBtn.TextColor3 = currentSortMode == "status" and activeText or inactiveText
        sortNameBtn.BackgroundColor3 = currentSortMode == "name" and active or inactive
        sortNameBtn.TextColor3 = currentSortMode == "name" and activeText or inactiveText
        sortRoleBtn.BackgroundColor3 = currentSortMode == "role" and active or inactive
        sortRoleBtn.TextColor3 = currentSortMode == "role" and activeText or inactiveText
    end

    local function sortStaffList(list)
        local statusOrder = {
            InGame = 1,
            InStudio = 2,
            Online = 3,
            Invisible = 4,
            Offline = 5,
            Unknown = 6
        }

        table.sort(list, function(a, b)
            if currentSortMode == "name" then
                return a.username:lower() < b.username:lower()
            elseif currentSortMode == "role" then
                if a.role:lower() ~= b.role:lower() then
                    return a.role:lower() < b.role:lower()
                end
                return a.username:lower() < b.username:lower()
            else -- status (default)
                local oa = statusOrder[a.status] or 9
                local ob = statusOrder[b.status] or 9
                if oa ~= ob then return oa < ob end
                return a.username:lower() < b.username:lower()
            end
        end)
    end

    local function populate(staffData)
        clearScroll()
        local order = 1
        local totalHeight = 0

        if #staffData == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 30)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Code
            empty.Text = "No high-rank staff found"
            empty.TextColor3 = EMPTY_ROW_TEXT_COLOR
            empty.TextSize = 12
            empty.Parent = scroll
            scroll.CanvasSize = UDim2.new(0, 0, 0, 40)
            return
        end

        for _, entry in ipairs(staffData) do
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -4, 0, 78)
            card.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
            card.BorderSizePixel = 0
            card.LayoutOrder = order
            card.Parent = scroll

            local cardStroke = Instance.new("UIStroke")
            cardStroke.Thickness = 1
            cardStroke.Color = Color3.fromRGB(40, 40, 40)
            cardStroke.Parent = card

            -- Colored status dot
            local dot = Instance.new("Frame")
            dot.Size = UDim2.new(0, 8, 0, 8)
            dot.Position = UDim2.new(0, 6, 0, 8)
            dot.BorderSizePixel = 0
            dot.Parent = card
            local dotColor = Color3.fromRGB(90, 90, 90)
            if entry.status == "InGame" then
                dotColor = Color3.fromRGB(80, 220, 120)
            elseif entry.status == "Online" then
                dotColor = Color3.fromRGB(80, 170, 255)
            elseif entry.status == "InStudio" then
                dotColor = Color3.fromRGB(230, 180, 80)
            elseif entry.status == "Invisible" then
                dotColor = Color3.fromRGB(160, 100, 220)
            end
            dot.BackgroundColor3 = dotColor
            local dotCorner = Instance.new("UICorner")
            dotCorner.CornerRadius = UDim.new(1, 0)
            dotCorner.Parent = dot

            -- Name + Role
            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -70, 0, 16)
            nameLbl.Position = UDim2.new(0, 18, 0, 4)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Font = Enum.Font.Code
            nameLbl.Text = entry.username .. "  [" .. entry.role .. "]"
            nameLbl.TextColor3 = PRIMARY_TEXT
            nameLbl.TextSize = 12
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.TextStrokeTransparency = 0.75
            nameLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            nameLbl.Parent = card

            -- UserId (click to copy)
            local idBtn = Instance.new("TextButton")
            idBtn.Size = UDim2.new(1, -12, 0, 14)
            idBtn.Position = UDim2.new(0, 6, 0, 22)
            idBtn.BackgroundTransparency = 1
            idBtn.Text = "UserId: " .. tostring(entry.userId) .. "  (click to copy)"
            idBtn.Font = Enum.Font.Code
            idBtn.TextSize = 11
            idBtn.TextColor3 = SECONDARY_TEXT
            idBtn.TextXAlignment = Enum.TextXAlignment.Left
            idBtn.Parent = card
            idBtn.MouseButton1Click:Connect(function()
                if setclipboard then
                    setclipboard(tostring(entry.userId))
                    idBtn.Text = "UserId: " .. tostring(entry.userId) .. "  (copied!)"
                    task.delay(1.2, function()
                        if idBtn and idBtn.Parent then
                            idBtn.Text = "UserId: " .. tostring(entry.userId) .. "  (click to copy)"
                        end
                    end)
                end
            end)

            -- Status
            local statusColor = Color3.fromRGB(130, 130, 130)
            if entry.status == "InGame" then
                statusColor = Color3.fromRGB(100, 220, 140)
            elseif entry.status == "Online" then
                statusColor = Color3.fromRGB(100, 180, 255)
            elseif entry.status == "InStudio" then
                statusColor = Color3.fromRGB(220, 180, 100)
            elseif entry.status == "Invisible" then
                statusColor = Color3.fromRGB(180, 140, 230)
            end

            local statusLbl = Instance.new("TextLabel")
            statusLbl.Size = UDim2.new(1, -12, 0, 14)
            statusLbl.Position = UDim2.new(0, 6, 0, 38)
            statusLbl.BackgroundTransparency = 1
            statusLbl.Font = Enum.Font.Code
            statusLbl.Text = "Status: " .. (entry.status or "Unknown")
            statusLbl.TextColor3 = statusColor
            statusLbl.TextSize = 11
            statusLbl.TextXAlignment = Enum.TextXAlignment.Left
            statusLbl.Parent = card

            -- Location / Server
            local locLine = "Server: —"
            if entry.gameId and entry.gameId ~= "" then
                locLine = "JobId: " .. tostring(entry.gameId)
            elseif entry.placeId then
                locLine = "PlaceId: " .. tostring(entry.placeId)
            elseif entry.lastLocation and entry.lastLocation ~= "" then
                locLine = tostring(entry.lastLocation)
            end

            local locLbl = Instance.new("TextLabel")
            locLbl.Size = UDim2.new(1, -60, 0, 14)
            locLbl.Position = UDim2.new(0, 6, 0, 54)
            locLbl.BackgroundTransparency = 1
            locLbl.Font = Enum.Font.Code
            locLbl.Text = locLine
            locLbl.TextColor3 = MORE_TEXT
            locLbl.TextSize = 11
            locLbl.TextXAlignment = Enum.TextXAlignment.Left
            locLbl.TextTruncate = Enum.TextTruncate.AtEnd
            locLbl.Parent = card

            -- Join button (only when same place + JobId visible)
            if entry.gameId and entry.placeId and tonumber(entry.placeId) == placeId then
                local joinBtn = Instance.new("TextButton")
                joinBtn.Size = UDim2.new(0, 48, 0, 16)
                joinBtn.Position = UDim2.new(1, -54, 0, 4)
                joinBtn.BackgroundColor3 = Color3.fromRGB(30, 55, 40)
                joinBtn.BorderSizePixel = 0
                joinBtn.Text = "Join"
                joinBtn.Font = Enum.Font.Code
                joinBtn.TextSize = 11
                joinBtn.TextColor3 = Color3.fromRGB(140, 230, 160)
                joinBtn.Parent = card
                joinBtn.MouseButton1Click:Connect(function()
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(placeId, tostring(entry.gameId), LocalPlayer)
                    end)
                end)
            end

            -- Copy username button
            local copyNameBtn = Instance.new("TextButton")
            copyNameBtn.Size = UDim2.new(0, 48, 0, 14)
            copyNameBtn.Position = UDim2.new(1, -54, 0, 54)
            copyNameBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
            copyNameBtn.BorderSizePixel = 0
            copyNameBtn.Text = "Copy"
            copyNameBtn.Font = Enum.Font.Code
            copyNameBtn.TextSize = 10
            copyNameBtn.TextColor3 = Color3.fromRGB(160, 160, 200)
            copyNameBtn.Parent = card
            copyNameBtn.MouseButton1Click:Connect(function()
                if setclipboard then
                    setclipboard(entry.username)
                    copyNameBtn.Text = "OK"
                    task.delay(1, function()
                        if copyNameBtn and copyNameBtn.Parent then
                            copyNameBtn.Text = "Copy"
                        end
                    end)
                end
            end)

            order = order + 1
            totalHeight = totalHeight + 82
        end

        scroll.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 8)
    end

    local function applySortAndPopulate()
        if #currentStaffData == 0 then return end
        sortStaffList(currentStaffData)
        populate(currentStaffData)
        setSortButtons()
    end

    sortStatusBtn.MouseButton1Click:Connect(function()
        currentSortMode = "status"
        applySortAndPopulate()
    end)
    sortNameBtn.MouseButton1Click:Connect(function()
        currentSortMode = "name"
        applySortAndPopulate()
    end)
    sortRoleBtn.MouseButton1Click:Connect(function()
        currentSortMode = "role"
        applySortAndPopulate()
    end)

    local function fetchAndShow()
        if isFetchingAdvanced then return end
        isFetchingAdvanced = true
        statusLabel.Text = "Fetching roles & presence..."
        clearScroll()
        currentStaffData = {}

        task.spawn(function()
            local staffList = {}

            -- 1. Get roles
            local rolesRes = httpRequest({
                Url = "https://groups.roblox.com/v1/groups/" .. GROUP_ID .. "/roles",
                Method = "GET"
            })

            if not rolesRes.Success then
                statusLabel.Text = "Failed roles (HTTP " .. tostring(rolesRes.StatusCode) .. ")"
                warn("[Staff] roles fetch failed:", rolesRes.StatusCode, rolesRes.Url)
                isFetchingAdvanced = false
                return
            end

            local rolesOk, rolesData = pcall(function()
                return HttpService:JSONDecode(rolesRes.Body)
            end)

            if not rolesOk or not rolesData or not rolesData.roles then
                statusLabel.Text = "Bad roles JSON"
                warn("[Staff] roles JSON decode failed. Body starts with:", string.sub(tostring(rolesRes.Body), 1, 120))
                isFetchingAdvanced = false
                return
            end

            local highRoles = {}
            for _, role in ipairs(rolesData.roles) do
                if type(role.rank) == "number" and role.rank > 1 then
                    table.insert(highRoles, role)
                end
            end

            -- 2. Live fetch members (no permanent cache)
            local userIdSet = {}
            for _, role in ipairs(highRoles) do
                local cursor = ""
                repeat
                    local url = "https://groups.roblox.com/v1/groups/" .. GROUP_ID .. "/roles/" .. role.id .. "/users?limit=100&sortOrder=Asc"
                    if cursor ~= "" then
                        url = url .. "&cursor=" .. cursor
                    end

                    local memRes = httpRequest({ Url = url, Method = "GET" })
                    if not memRes.Success then break end

                    local memOk, memData = pcall(function()
                        return HttpService:JSONDecode(memRes.Body)
                    end)
                    if not memOk or not memData or not memData.data then break end

                    for _, user in ipairs(memData.data) do
                        if user.userId and not userIdSet[user.userId] then
                            userIdSet[user.userId] = true
                            table.insert(staffList, {
                                userId = user.userId,
                                username = user.username or ("User" .. user.userId),
                                role = role.name or "Staff",
                                status = "Unknown",
                                placeId = nil,
                                gameId = nil,
                                lastLocation = nil
                            })
                        end
                    end

                    cursor = memData.nextPageCursor or ""
                until cursor == ""
            end

            if #staffList == 0 then
                statusLabel.Text = "No high-rank members found"
                populate({})
                isFetchingAdvanced = false
                return
            end

            statusLabel.Text = "Checking presence (" .. #staffList .. ")..."

            local typeNames = {
                [0] = "Offline",
                [1] = "Online",
                [2] = "InGame",
                [3] = "InStudio",
                [4] = "Invisible"
            }

            local presenceMap = {}

            -- Fast parallel presence (same working methods, concurrent)
            local pending = #staffList
            local doneCount = 0

            local function checkOne(uid)
                local singleBody = HttpService:JSONEncode({ userIds = { uid } })
                local singleRes = httpRequest({
                    Url = "https://presence.roblox.com/v1/presence/users",
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = singleBody
                })
                if singleRes.Success then
                    local ok, data = pcall(function()
                        return HttpService:JSONDecode(singleRes.Body)
                    end)
                    if ok and data and data.userPresences and data.userPresences[1] then
                        presenceMap[uid] = data.userPresences[1]
                        return
                    end
                end

                local oldRes = httpRequest({
                    Url = "https://api.roblox.com/users/" .. tostring(uid) .. "/onlinestatus/",
                    Method = "GET"
                })
                if not oldRes.Success then
                    oldRes = httpRequest({
                        Url = "https://www.roblox.com/presence/userinfo?userId=" .. tostring(uid),
                        Method = "GET"
                    })
                end
                if oldRes.Success then
                    local ok, data = pcall(function()
                        return HttpService:JSONDecode(oldRes.Body)
                    end)
                    if ok and type(data) == "table" then
                        local presenceType = 0
                        if data.IsOnline or data.isOnline then
                            presenceType = 1
                            if data.LocationType == 2 or data.locationType == 2 or data.GameId or data.gameId then
                                presenceType = 2
                            end
                        end
                        presenceMap[uid] = {
                            userPresenceType = presenceType,
                            placeId = data.PlaceId or data.placeId,
                            gameId = data.GameId or data.gameId,
                            lastLocation = data.LastLocation or data.lastLocation or data.LocationName
                        }
                    end
                end
            end

            for _, s in ipairs(staffList) do
                local uid = s.userId
                task.spawn(function()
                    checkOne(uid)
                    doneCount = doneCount + 1
                    statusLabel.Text = "Presence " .. doneCount .. "/" .. pending .. "..."
                end)
            end

            local t0 = os.clock()
            while doneCount < pending and (os.clock() - t0) < 8 do
                task.wait(0.05)
            end

            local counts = { InGame = 0, Online = 0, InStudio = 0, Offline = 0, Invisible = 0, Unknown = 0 }

            for _, s in ipairs(staffList) do
                local p = presenceMap[s.userId]
                if p then
                    s.status = typeNames[p.userPresenceType] or "Unknown"
                    s.placeId = p.placeId
                    s.gameId = p.gameId
                    s.lastLocation = p.lastLocation
                else
                    s.status = "Unknown"
                end
                counts[s.status] = (counts[s.status] or 0) + 1
            end

            currentStaffData = staffList
            sortStaffList(currentStaffData)
            populate(currentStaffData)
            setSortButtons()

            local summary = string.format(
                "%d total  |  %d in-game  %d online  %d offline",
                #staffList,
                counts.InGame or 0,
                counts.Online or 0,
                counts.Offline or 0
            )
            statusLabel.Text = summary
            isFetchingAdvanced = false
        end)
    end

    refreshBtn.MouseButton1Click:Connect(fetchAndShow)
    fetchAndShow()

    return winOuter
end

advancedBtn.MouseButton1Click:Connect(function()
    local win = createAdvancedStaffWindow()
    if win then
        win.Visible = true
    end
end)

-------------------------------------------------------------------------
-- Apply dragging to main panels
-------------------------------------------------------------------------
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

print("serverhop and staff list loaded for " .. LocalPlayer.Name .. " (UserId: " .. LocalPlayer.UserId .. ")")
