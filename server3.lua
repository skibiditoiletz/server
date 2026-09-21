local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local placeId = game.PlaceId
local currentJobId = game.JobId

local CUSTOM_MESSAGE = "vk"
local hopping = false

local function kickThenHop()
    if hopping then return end
    hopping = true

    pcall(function()
        game.Players.LocalPlayer:kick(CUSTOM_MESSAGE)
    end)

    task.wait(0.35)

    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
        ))
    end)

    if success and servers and servers.data then
        for _, server in ipairs(servers.data) do
            local jobId = tostring(server.id)
            if jobId ~= currentJobId and server.playing < server.maxPlayers and server.playing > 0 then
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                end)
                task.wait(0.25)
            end
        end
    end

    for i = 1, 6 do
        pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)
        task.wait(0.2)
    end
end

-- VoteKickGui check
local function checkVoteKickGui(gui)
    if not gui or not gui.Enabled then return end

    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if string.find(string.lower(obj.Text or ""), string.lower(LocalPlayer.Name)) then
                print("VoteKick detected")
                kickThenHop()
                return
            end
        end
    end
end

-- Check for real "player is currently serverbanned" kick message
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

    if string.find(msg, "player is currently serverbanned") or string.find(msg, "serverbanned") then
        print("Serverbanned kick detected")
        kickThenHop()
        return true
    end

    return false
end

-- Check once on execution
checkServerBanned()

-- VoteKickGui already exists?
local existing = PlayerGui:FindFirstChild("VoteKickGui")
if existing then
    checkVoteKickGui(existing)
end

-- VoteKickGui added
PlayerGui.ChildAdded:Connect(function(child)
    if child.Name == "VoteKickGui" then
        task.wait(0.2)
        checkVoteKickGui(child)

        child:GetPropertyChangedSignal("Enabled"):Connect(function()
            if child.Enabled then
                checkVoteKickGui(child)
            end
        end)
    end
end)

-- Check serverban every 1 second + VoteKickGui
task.spawn(function()
    while task.wait(1) do
        checkServerBanned() -- ← checks the real kick message every second

        local gui = PlayerGui:FindFirstChild("VoteKickGui")
        if gui and gui.Enabled then
            checkVoteKickGui(gui)
        end
    end
end)

print("Serverhop loaded (VoteKick + Serverbanned every 1s)")
