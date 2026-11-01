-- Luau | mm2_shield_v2.lua | Roblox executor (hookfunction, hookmetamethod, getnamecallmethod, setclipboard optional)
-- run FIRST, before any script you want to check. blocks exfil attempts AND tells you exactly what/where in plain text.
local Players, StarterGui, SoundService, TweenService, Debris =
    game:GetService("Players"), game:GetService("StarterGui"), game:GetService("SoundService"),
    game:GetService("TweenService"), game:GetService("Debris")
local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerName, userId = LP.Name, tostring(LP.UserId)

local Stats = {blocked = 0, caught = {}}

-- ===== on-screen + console report, always both =====
local function console(kind, verdict, url, why, body)
    local line = ("[SHIELD] %-10s %-10s %s"):format(kind, verdict, tostring(url))
    if verdict == "BLOCKED" then warn(line .. (why and ("  <- " .. why) or "")) else print(line) end
    if body and type(body) == "string" and #body > 0 and #body < 1500 then
        print("[SHIELD]   body: " .. body)
    end
end
local function screen_alert(title, message, danger)
    task.spawn(function()
        pcall(function()
            local s = Instance.new("Sound", SoundService)
            s.SoundId = "rbxasset://sounds/bell.wav"; s.Volume = 1; s:Play(); Debris:AddItem(s, 3)
        end)
        pcall(function()
            StarterGui:SetCore("SendNotification", {Title = title, Text = message, Duration = 6})
        end)
        pcall(function()
            local pg = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui", 4)
            if not pg then return end
            local old = pg:FindFirstChild("ShieldAlert"); if old then old:Destroy() end
            local gui = Instance.new("ScreenGui", pg)
            gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "ShieldAlert", false, true, 999999
            local card = Instance.new("Frame", gui)
            card.Size, card.Position = UDim2.fromOffset(440, 86), UDim2.new(0.5, -220, 0, -120)
            card.BackgroundColor3, card.BorderSizePixel = Color3.fromRGB(16, 16, 22), 0
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
            local stroke = Instance.new("UIStroke", card)
            stroke.Color = danger and Color3.fromRGB(250, 60, 60) or Color3.fromRGB(40, 200, 95)
            stroke.Thickness = 2
            local t = Instance.new("TextLabel", card)
            t.Size, t.Position, t.BackgroundTransparency = UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 10), 1
            t.Font, t.TextSize, t.TextColor3, t.TextXAlignment = Enum.Font.GothamBold, 15, stroke.Color, Enum.TextXAlignment.Left
            t.Text = title
            local d = Instance.new("TextLabel", card)
            d.Size, d.Position, d.BackgroundTransparency = UDim2.new(1, -24, 0, 44), UDim2.fromOffset(12, 36), 1
            d.Font, d.TextSize, d.TextColor3 = Enum.Font.Gotham, 12, Color3.fromRGB(230, 230, 240)
            d.TextWrapped, d.TextXAlignment, d.TextYAlignment = true, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
            d.Text = message
            TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                {Position = UDim2.new(0.5, -220, 0, 46)}):Play()
            task.delay(6, function()
                if card.Parent then
                    local tw = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
                        {Position = UDim2.new(0.5, -220, 0, -120)})
                    tw:Play(); tw.Completed:Connect(function() gui:Destroy() end)
                end
            end)
        end)
    end)
end

-- ===== detection =====
local SAFE_DOMAINS = {"roblox.com", "roproxy.com", "rbxcdn.com", "github.com", "githubusercontent.com", "gitlab.com"}
local BAD_HINTS = {
    "discord.com/api/webhooks", "discordapp.com/api/webhooks", "webhook", "iplogger", "grabber",
    "2no.co", "blasze", "webhook.site", "pipedream.net", "telegram.org/bot", "requestbin", "ngrok"
}
local INVENTORY_WORDS = {"inventory", "godly", "ancient", "chroma", "vintage", "harvester", "corrupt",
    "candleflame", "swirly", "knife", "gun", "weapons", "iceflake"}

local function host_of(url)
    local h = string.match(string.lower(url or ""), "^%a+://([^/]+)") or string.match(string.lower(url or ""), "^([^/]+)")
    return h and (string.match(h, "^([^:]+)") or h) or ""
end
local function is_safe(url)
    local h = host_of(url)
    for _, d in ipairs(SAFE_DOMAINS) do
        if h == d or h:sub(-#d - 1) == "." .. d then return true end
    end
    return false
end
local function clean_webhook(s)
    local u = (s or ""):gsub("\\/", "/")
    local dom, id, tok = u:match("(discord[%w%.]*/api/webhooks)/(%d+)/([^%s\"'%&<>]+)")
    if dom and id and tok and #tok >= 10 then return "https://" .. dom .. "/" .. id .. "/" .. tok end
end

-- judge(url, body) -> blocked:boolean, reason:string|nil, webhook:string|nil
local function judge(url, body)
    local lurl = string.lower(url or "")
    local lbody = type(body) == "string" and string.lower(body) or ""
    local wh = clean_webhook(url) or clean_webhook(body)

    for _, h in ipairs(BAD_HINTS) do
        if lurl:find(h, 1, true) then return true, "Discord/C2 webhook pattern in URL", wh end
    end
    if is_safe(url) then return false end
    for _, h in ipairs(BAD_HINTS) do
        if lbody:find(h, 1, true) then return true, "Discord/C2 webhook pattern in body", wh end
    end
    local hay = lurl .. " " .. lbody
    local has_identity = hay:find(string.lower(playerName), 1, true) or hay:find(userId, 1, true)
    if has_identity then
        for _, kw in ipairs(INVENTORY_WORDS) do
            if hay:find(kw, 1, true) then return true, "your name/UserId sent together with inventory keyword '" .. kw .. "'", wh end
        end
    end
    return false
end

local function handle(kind, url, body)
    local blocked, reason, wh = judge(url, body)
    if blocked then
        Stats.blocked += 1
        if wh and not Stats.caught[wh] then
            Stats.caught[wh] = true
            console(kind, "BLOCKED", url, reason, body)
            warn("[SHIELD] >>> WEBHOOK URL: " .. wh)
            if setclipboard then pcall(setclipboard, wh); print("[SHIELD] copied webhook to clipboard") end
            screen_alert("🚨 Stealer caught: " .. kind, "Reason: " .. reason .. "\nWebhook copied to clipboard.", true)
        else
            console(kind, "BLOCKED", url, reason, body)
            screen_alert("🚨 Stealer caught: " .. kind, "Reason: " .. reason, true)
        end
        return true
    end
    console(kind, is_safe(url) and "safe" or "unknown", url, nil, nil)
    return false
end

-- ===== hooks: every path a stealer can realistically use =====
local hooked = {}

local raw = request or http_request or (syn and syn.request) or (http and http.request)
if raw and hookfunction then
    local orig
    orig = hookfunction(raw, newcclosure and newcclosure(function(data, ...)
        if type(data) == "table" and handle("request", data.Url or data.url or data.URL, data.Body or data.body) then
            return {StatusCode = 200, StatusMessage = "OK", Success = true, Body = '{"status":"blocked"}'}
        end
        return orig(data, ...)
    end) or function(data, ...)
        if type(data) == "table" and handle("request", data.Url or data.url or data.URL, data.Body or data.body) then
            return {StatusCode = 200, StatusMessage = "OK", Success = true, Body = '{"status":"blocked"}'}
        end
        return orig(data, ...)
    end)
    getgenv().request = orig and function(data, ...)
        if type(data) == "table" and handle("request", data.Url or data.url or data.URL, data.Body or data.body) then
            return {StatusCode = 200, StatusMessage = "OK", Success = true, Body = '{"status":"blocked"}'}
        end
        return orig(data, ...)
    end or request
    getgenv().http_request = getgenv().request
    hooked.request = true
end

pcall(function()
    local orig = game.HttpGet
    hookfunction(orig, function(self, url, ...)
        if handle("HttpGet", url, nil) then return "" end
        return orig(self, url, ...)
    end)
    hooked.HttpGet = true
end)
pcall(function()
    local HttpService = game:GetService("HttpService")
    local orig = HttpService.PostAsync
    hookfunction(orig, function(self, url, body, ...)
        if handle("PostAsync", url, body) then return "" end
        return orig(self, url, body, ...)
    end)
    hooked.PostAsync = true
end)
pcall(function()
    local HttpService = game:GetService("HttpService")
    local orig = HttpService.RequestAsync
    hookfunction(orig, function(self, opts, ...)
        if type(opts) == "table" and handle("RequestAsync", opts.Url, opts.Body) then
            return {Success = true, StatusCode = 200, Body = '{"status":"blocked"}'}
        end
        return orig(self, opts, ...)
    end)
    hooked.RequestAsync = true
end)
pcall(function()
    local ws = WebSocket and WebSocket.connect
    if ws then
        hookfunction(ws, function(url, ...)
            if handle("WebSocket", url, nil) then return nil end
            return ws(url, ...)
        end)
        hooked.WebSocket = true
    end
end)

-- optional: also block MM2 trade remotes firing without a recent click (same idea as the original @lattescripts shield)
local lastClick = 0
pcall(function()
    local UIS = game:GetService("UserInputService")
    UIS.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            lastClick = os.clock()
        end
    end)
end)
local TRADE_WORDS = {"offeritem", "additem", "accepttrade", "confirmtrade", "dropitem"}
local lastAccept = 0
if hookmetamethod then
    pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(function(self, ...)
            local m = getnamecallmethod()
            if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
                local n = string.lower(self.Name)
                for _, w in ipairs(TRADE_WORDS) do
                    if n:find(w, 1, true) then
                        if n:find("confirmtrade", 1, true) and os.clock() - lastAccept < 2.5 then
                            Stats.blocked += 1
                            console("Trade", "BLOCKED", self:GetFullName(), "ConfirmTrade fired <2.5s after Accept (bot)", nil)
                            screen_alert("🚨 Trade-bot caught", "Instant ConfirmTrade blocked — too fast for a human.", true)
                            return nil
                        end
                        if n:find("accepttrade", 1, true) then lastAccept = os.clock() end
                        if os.clock() - lastClick > 3 then
                            Stats.blocked += 1
                            console("Trade", "BLOCKED", self:GetFullName(), "fired with no recent click", nil)
                            screen_alert("🚨 Hidden trade call blocked", self.Name .. " fired without you clicking anything.", true)
                            return nil
                        end
                    end
                end
            end
            return old(self, ...)
        end) or function(self, ...)
            local m = getnamecallmethod()
            if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
                local n = string.lower(self.Name)
                for _, w in ipairs(TRADE_WORDS) do
                    if n:find(w, 1, true) and os.clock() - lastClick > 3 then
                        Stats.blocked += 1
                        console("Trade", "BLOCKED", self:GetFullName(), "fired with no recent click", nil)
                        return nil
                    end
                end
            end
            return old(self, ...)
        end)
    end)
end

getgenv().ShieldStats = function()
    print(("[SHIELD] blocked total: %d | webhooks caught: %d"):format(Stats.blocked, (function()
        local n = 0; for _ in pairs(Stats.caught) do n += 1 end; return n
    end)()))
    for wh in pairs(Stats.caught) do print("[SHIELD]   " .. wh) end
end

local n = 0
for _, v in pairs(hooked) do if v then n += 1 end end
print(("[SHIELD] armed: %d/5 hooks active (%s)"):format(n, table.concat((function()
    local t = {}
    for k, v in pairs(hooked) do if v then t[#t + 1] = k end end
    return t
end)(), ", ")))
screen_alert("🛡️ Shield active", "Now run the script you want to check. Every outbound call is logged.", false)
