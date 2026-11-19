local _, ns = ...

-- Each character's mailbox, as seen the last time it was opened, plus what the other characters sent it since:
--   rec.mail = { count =, items = { [itemID] = n }, money =, cod =, expiresAt =, at =, sent = n }
-- `expiresAt` is when the first letter runs out (it goes back to its sender, or is deleted). Mail sent from one
-- character to another is added to the receiver's copy when the game confirms the sending, so the window knows
-- about it before the receiver logs in.
local MAIL_DAYS = 30
local pendingSend

function ns.Mail_Scan()
    if not GetInboxNumItems then return end
    local shown, total = GetInboxNumItems()
    shown, total = ns.Num(shown) or 0, ns.Num(total) or ns.Num(shown) or 0
    local rec = ns.Me()
    local mail = { count = total, items = {}, money = 0, cod = 0, at = ns.Now(), sent = 0 }
    local now = ns.Now()
    for i = 1, shown do
        local _, _, _, _, money, cod, daysLeft, hasItem = GetInboxHeaderInfo(i)
        mail.money = mail.money + (ns.Num(money) or 0)
        mail.cod = mail.cod + (ns.Num(cod) or 0)
        daysLeft = ns.Num(daysLeft)
        if daysLeft then
            local at = now + math.floor(daysLeft * 86400)
            if not mail.expiresAt or at < mail.expiresAt then mail.expiresAt = at end
        end
        if hasItem then
            for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local name, itemID, _, count = GetInboxItem(i, a)
                if itemID then
                    mail.items[itemID] = (mail.items[itemID] or 0) + (ns.Num(count) or 1)
                    ns.Items_Remember(itemID, GetInboxItemLink and GetInboxItemLink(i, a))
                    local entry = ns.db.items[itemID]
                    if entry and not entry.n then entry.n = name end
                end
            end
        end
    end
    -- letters past the 50 the client shows: counted, their contents unknown
    mail.hidden = math.max(0, total - shown)
    rec.mail = mail
end

-- Whether a character has mail waiting that it hasn't read in the game (as far as the addon knows).
function ns.Mail_Has(rec)
    local mail = rec and rec.mail
    return mail ~= nil and ((mail.count or 0) > 0 or (mail.sent or 0) > 0)
end

function ns.Mail_ExpiresIn(rec, now)
    local mail = rec and rec.mail
    if not mail or not mail.expiresAt or (mail.count or 0) + (mail.sent or 0) == 0 then return nil end
    return mail.expiresAt - (now or ns.Now())
end

---------------------------------------------------------------------------------------------------
-- Mail sent to another character of the account: what is attached is noted when SendMail is called and added to
-- the receiver when MAIL_SEND_SUCCESS arrives.
---------------------------------------------------------------------------------------------------
local function noteSend(recipient)
    local key = ns.FindCharByName((recipient or ""):match("^([^%-]+)") or recipient)
    if not key or ns.IsMe(key) then
        pendingSend = nil
        return
    end
    local items = {}
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local _, itemID, _, count = GetSendMailItem(i)
        if itemID then items[itemID] = (items[itemID] or 0) + (ns.Num(count) or 1) end
    end
    pendingSend = { key = key, items = items, money = ns.Num(GetSendMailMoney and GetSendMailMoney()) or 0 }
end

function ns.Mail_Delivered(send)
    send = send or pendingSend
    pendingSend = nil
    if not send then return end
    local rec = ns.GetChar(send.key)
    if not rec then return end
    local mail = rec.mail or { count = 0, items = {}, money = 0, cod = 0 }
    mail.items = mail.items or {}
    for id, n in pairs(send.items) do mail.items[id] = (mail.items[id] or 0) + n end
    mail.money = (mail.money or 0) + send.money
    mail.sent = (mail.sent or 0) + 1
    local expires = ns.Now() + MAIL_DAYS * 86400
    if not mail.expiresAt or expires < mail.expiresAt then mail.expiresAt = expires end
    rec.mail = mail
    ns.Changed("mailSent", send.key, send.items)
end


function ns.Mail_Init()
    ns.On("MAIL_INBOX_UPDATE", function() ns.Debounce("mail", 0.3, function()
        ns.Mail_Scan()
        ns.Changed("mail")
    end) end)
    ns.On("MAIL_CLOSED", function() ns.SafeCall(ns.Mail_Scan) end)
    ns.On("MAIL_SEND_SUCCESS", function() ns.Mail_Delivered() end)
    ns.On("MAIL_FAILED", function() pendingSend = nil end)
    if hooksecurefunc and SendMail then
        hooksecurefunc("SendMail", function(recipient) ns.SafeCall(noteSend, recipient) end)
    end
end

