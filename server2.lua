local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
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

    task.wait(0.4)

    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
        ))
    end)

    if success and servers and servers.data then
        for _, server in ipairs(servers.data) do
            local jobId = tostring(server.id)
            -- High players but not full + not current server
            if jobId ~= currentJobId and server.playing < server.maxPlayers and server.playing > 0 then
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                end)
                task.wait(0.3)
            end
        end
    end

    -- Fallback
    for i = 1, 5 do
        pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)
        task.wait(0.25)
    end
end

local function checkVoteKickGui(gui)
    if not gui or not gui.Enabled then return end

    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if string.find(string.lower(obj.Text or ""), string.lower(LocalPlayer.Name)) then
                print("found")
                kickThenHop()
                return
            end
        end
    end
end

local existing = PlayerGui:FindFirstChild("VoteKickGui")
if existing then
    checkVoteKickGui(existing)
end

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

task.spawn(function()
    while task.wait(0.5) do
        local gui = PlayerGui:FindFirstChild("VoteKickGui")
        if gui and gui.Enabled then
            checkVoteKickGui(gui)
        end
    end
end)

print("I")
