--[[
	WIM_Tabs.lua

	Combines every WIM conversation into ONE window with a tab per conversation.

	How it works
	------------
	Each conversation still has its own frame (WIM_msgFrame<name>), because all of the
	message / edit box / shortcut button logic lives there. What changed is:

	  * all conversation frames are anchored to the same invisible frame (WIM_TabHost),
	    so they sit in exactly the same spot on screen
	  * only one conversation frame is shown at a time (the "active" tab)
	  * a tab strip (WIM_TabFrame) is attached below the active frame, one button per conversation

	Tab controls
	------------
	  Left-click a tab            switch to that conversation
	  Right-click a tab           close that conversation (same as Shift+click on the window's X)
	  X button on the window      hide the whole tabbed window (conversations stay open)

	Notes for Lua 5.0 (WoW 1.12): no # operator, no % operator, no string:method calls
	are relied upon here.
]]--

WIM_Tabs = {};            -- ordered list of user names, one entry per open conversation
WIM_TabActive = nil;      -- user name of the selected tab
WIM_TabSwitching = false; -- true while one conversation frame is being swapped for another
WIM_TabButtons = {};      -- pool of tab buttons (created on demand)
WIM_TabFlashTimer = 0;
WIM_TabFlashOn = false;

-- Layout. Tweak these if the tab strip doesn't line up with your WIM skin.
-- WIM_TAB_WIDTH / WIM_TAB_HEIGHT are only the factory defaults now: the real values come from
-- the "Tabs" page of the options window (WIM_Data.tabs.width / .height).
WIM_TAB_WIDTH = 80;
WIM_TAB_HEIGHT = 22;
WIM_TAB_OFFSET_X = 18;    -- distance from the left edge of the window
WIM_TAB_OFFSET_Y = 4;     -- positive = overlap the bottom edge of the window, negative = gap

--[ Tab appearance settings (stored in WIM_Data.tabs, edited on the options window's "Tabs" page)
WIM_TAB_DEFAULTS = {
	flashEnabled = true,    -- flash tabs that have unread messages
	flashText = true,       -- flash alternates the tab text between its normal and flash colour
	flashBorder = false,    -- flash alternates the tab border between its normal and flash colour
	flashSpeed = 0.5,       -- seconds between flash toggles
	hideSingle = false,     -- hide the tab strip while only one conversation is open
	focusOnSwitch = true,   -- put the keyboard cursor in the message box when the user switches tabs
	width = 80,
	height = 22,
	normalAlpha = 0.75,     -- background opacity of inactive tabs
	colors = {
		active = {
			bg     = { r = 0.15, g = 0.15, b = 0.45 },
			border = { r = 1,    g = 0.82, b = 0 },
			text   = { r = 1,    g = 1,    b = 1 },
		},
		unread = {
			bg     = { r = 0.35, g = 0.15, b = 0 },
			border = { r = 1,    g = 0.5,  b = 0 },
			text   = { r = 1,    g = 1,    b = 1 },
			flash  = { r = 1,    g = 0.6,  b = 0 },
		},
		normal = {
			bg     = { r = 0,    g = 0,    b = 0 },
			border = { r = 0.5,  g = 0.5,  b = 0.5 },
			text   = { r = 0.8,  g = 0.8,  b = 0.8 },
		},
	},
};
WIM_TAB_ACTIVE_ALPHA = 0.95;   -- background opacity of the selected tab and of unread tabs

local function WIM_TabCopy(src)
	if(type(src) ~= "table") then
		return src;
	end
	local dst = {};
	for k, v in pairs(src) do
		dst[k] = WIM_TabCopy(v);
	end
	return dst;
end

-- Fill in anything missing from dst using defaults (deep), so settings saved by an older
-- version - or wiped by /wim reset - always end up complete.
local function WIM_TabMerge(dst, defaults)
	for k, v in pairs(defaults) do
		if(type(v) == "table") then
			if(type(dst[k]) ~= "table") then
				dst[k] = WIM_TabCopy(v);
			else
				WIM_TabMerge(dst[k], v);
			end
		elseif(dst[k] == nil) then
			dst[k] = v;
		end
	end
end

-- Bumped whenever the tab colours / flash options may have changed, so every button is
-- re-coloured on the next refresh. While it is unchanged, a button whose state (active /
-- unread / normal) is the same as last time is left alone.
local WIM_TabStyleVersion = 0;

function WIM_TabsInitSettings()
	if(type(WIM_Data.tabs) ~= "table") then
		WIM_Data.tabs = {};
	end
	WIM_TabMerge(WIM_Data.tabs, WIM_TAB_DEFAULTS);
	WIM_TabStyleVersion = WIM_TabStyleVersion + 1;
end

function WIM_TabsResetSettings()
	WIM_Data.tabs = WIM_TabCopy(WIM_TAB_DEFAULTS);
	WIM_TabStyleVersion = WIM_TabStyleVersion + 1;
end

-- always returns a complete settings table
function WIM_TabSettings()
	if(type(WIM_Data.tabs) ~= "table" or type(WIM_Data.tabs.colors) ~= "table") then
		WIM_TabsInitSettings();
	end
	return WIM_Data.tabs;
end

WIM_L_TABTOOLTIP = WIM_L_TABTOOLTIP or "Left-click: switch to this conversation.\nRight-click: close this conversation.";

--[ Tab list helpers

function WIM_TabIndex(theUser)
	for i=1, table.getn(WIM_Tabs) do
		if(WIM_Tabs[i] == theUser) then
			return i;
		end
	end
	return nil;
end

function WIM_TabAdd(theUser)
	if(not WIM_TabIndex(theUser)) then
		tinsert(WIM_Tabs, theUser);
	end
end

function WIM_TabRemove(theUser)
	local i = WIM_TabIndex(theUser);
	if(i) then
		table.remove(WIM_Tabs, i);
	end
end

function WIM_TabGetFrame(theUser)
	if(theUser and WIM_Windows[theUser]) then
		return getglobal(WIM_Windows[theUser].frame);
	end
	return nil;
end

-- true when the tabbed window is currently open on screen
function WIM_TabWindowShown()
	local f = WIM_TabGetFrame(WIM_TabActive);
	if(f and f:IsShown()) then
		return true;
	end
	return false;
end

--[ Positioning

local function WIM_TabScale()
	local scale = WIM_Data.windowSize;
	if(not scale or scale <= 0) then
		scale = 1;
	end
	return scale;
end

-- WIM_Data.winLoc is stored in UIParent units. The host frame carries the window scale,
-- so its offsets are divided by that scale.
local WIM_TabHostScale, WIM_TabHostLeft, WIM_TabHostTop;
function WIM_TabHost_Place()
	local scale = WIM_TabScale();
	local left, top = WIM_Data.winLoc.left, WIM_Data.winLoc.top;
	if(scale == WIM_TabHostScale and left == WIM_TabHostLeft and top == WIM_TabHostTop) then
		return; -- already there: don't make every anchored conversation frame recompute its position
	end
	WIM_TabHostScale, WIM_TabHostLeft, WIM_TabHostTop = scale, left, top;
	WIM_TabHost:SetScale(scale);
	WIM_TabHost:ClearAllPoints();
	WIM_TabHost:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", WIM_Data.winLoc.left / scale, WIM_Data.winLoc.top / scale);
end

-- Called after the user dragged a conversation frame (StartMoving detaches it from the host).
-- Remember the new location and hook the frame back up to the shared anchor.
function WIM_TabWindowMoved(theWin)
	local left, top = theWin:GetLeft(), theWin:GetTop();
	if(left and top) then
		local scale = theWin:GetScale();
		if(not scale or scale <= 0) then
			scale = 1;
		end
		WIM_Data.winLoc.left = left * scale;
		WIM_Data.winLoc.top = top * scale;
		WIM_TabHost_Place();
		theWin:ClearAllPoints();
		theWin:SetPoint("TOPLEFT", "WIM_TabHost", "TOPLEFT", 0, 0);
	end
	WIM_TabFrame:Raise();
end

local WIM_TabStripAnchor;
local function WIM_TabAnchorStrip(theWin)
	if(WIM_TabStripAnchor == theWin) then
		return;
	end
	WIM_TabStripAnchor = theWin;
	WIM_TabFrame:ClearAllPoints();
	WIM_TabFrame:SetPoint("TOPLEFT", theWin, "BOTTOMLEFT", WIM_TAB_OFFSET_X, WIM_TAB_OFFSET_Y);
end

local WIM_TabStripScale, WIM_TabStripAlpha;
function WIM_TabFrame_SetProps()
	local scale = WIM_TabScale();
	if(scale ~= WIM_TabStripScale) then
		WIM_TabStripScale = scale;
		WIM_TabFrame:SetScale(scale);
	end
	local alpha = WIM_Data.windowAlpha;
	if(alpha ~= WIM_TabStripAlpha) then
		WIM_TabStripAlpha = alpha;
		WIM_TabFrame:SetAlpha(alpha);
	end
	WIM_TabsRefresh();
end

--[ Selection

-- Make a conversation the visible tab (opens the tabbed window if it was hidden).
function WIM_TabSelect(theUser)
	local f = WIM_TabGetFrame(theUser);
	if(not f) then
		return;
	end
	if(f:IsShown()) then
		WIM_TabOnShow(theUser);
	else
		f:Show(); -- the frame's OnShow handler calls WIM_TabOnShow
	end
end

-- Switch tabs because the user asked to (tab click, icon menu, "next unread"), then - if the
-- "focus on switch" option is on - put the keyboard cursor in that conversation's message box.
-- Automatic switches (closing a tab, incoming messages) deliberately don't go through here,
-- so they never steal the keyboard while you're typing.
function WIM_TabSwitchTo(theUser)
	if(not theUser or not WIM_Windows[theUser]) then
		return;
	end
	WIM_TabSelect(theUser);
	if(WIM_TabSettings().focusOnSwitch) then
		local box = getglobal(WIM_Windows[theUser].frame.."MsgBox");
		if(box) then
			box:SetFocus();
		end
	end
end

-- Called from the conversation frame's OnShow.
function WIM_TabOnShow(theUser)
	if(not WIM_Windows[theUser]) then
		return;
	end

	-- only one conversation may be visible: hide whichever one was showing before
	WIM_TabSwitching = true;
	for user, info in pairs(WIM_Windows) do
		if(user ~= theUser) then
			local other = getglobal(info.frame);
			if(other and other:IsShown()) then
				other:Hide();
			end
		end
	end
	WIM_TabSwitching = false;

	WIM_TabActive = theUser;
	WIM_Windows[theUser].newMSG = false;

	local f = getglobal(WIM_Windows[theUser].frame);
	WIM_TabAnchorStrip(f);
	-- (with "hide single tab" on and one conversation, the strip stays hidden)
	if(not WIM_TabFrame:IsShown() and not (WIM_TabSettings().hideSingle and table.getn(WIM_Tabs) <= 1)) then
		WIM_TabFrame:Show();
	end
	WIM_TabFrame:Raise();
	WIM_TabsRefresh();
end

-- Called from the conversation frame's OnHide.
function WIM_TabOnHide(theUser)
	if(WIM_TabSwitching) then
		return; -- just being swapped for another tab
	end
	if(WIM_TabActive == theUser) then
		WIM_TabFrame:Hide(); -- the whole tabbed window was closed/hidden
	end
end

--[ Tab buttons
--
-- Performance notes: switching tabs, an incoming message and every flash tick all end up
-- here, so nothing below touches a widget unless the value really changed. Each button
-- remembers what it currently shows (size, position, label, colour state) and text fitting
-- - which needs the expensive SetText + GetStringWidth round trip - is cached per name.

local WIM_TabFitCache = {};      -- [maxWidth][name] = text that fits
local WIM_TabFitCacheCount = 0;

-- first n bytes of name (moved back to a character boundary so a multi-byte UTF-8
-- character is never split) followed by ".."
local function WIM_TabPrefix(name, n)
	local cut = n;
	while(cut > 0) do
		local b = string.byte(name, cut + 1);
		if(b == nil or b < 128 or b >= 192) then
			break;
		end
		cut = cut - 1;
	end
	return string.sub(name, 1, cut).."..";
end

local function WIM_TabFitText(fontString, name, maxWidth)
	local byWidth = WIM_TabFitCache[maxWidth];
	if(not byWidth) then
		byWidth = {};
		WIM_TabFitCache[maxWidth] = byWidth;
	end
	local fitted = byWidth[name];
	if(fitted) then
		fontString:SetText(fitted);
		return;
	end

	fitted = name;
	fontString:SetText(name);
	local hi = string.len(name) - 1;
	if(hi >= 1 and fontString:GetStringWidth() > maxWidth) then
		-- binary search for the longest prefix that fits
		local lo = 1;
		fitted = WIM_TabPrefix(name, 1); -- fallback when nothing fits
		while(lo <= hi) do
			local mid = math.floor((lo + hi) / 2);
			local candidate = WIM_TabPrefix(name, mid);
			fontString:SetText(candidate);
			if(fontString:GetStringWidth() <= maxWidth) then
				fitted = candidate;
				lo = mid + 1;
			else
				hi = mid - 1;
			end
		end
		fontString:SetText(fitted);
	end

	if(WIM_TabFitCacheCount >= 300) then
		WIM_TabFitCache = {};
		WIM_TabFitCacheCount = 0;
		byWidth = {};
		WIM_TabFitCache[maxWidth] = byWidth;
	end
	byWidth[name] = fitted;
	WIM_TabFitCacheCount = WIM_TabFitCacheCount + 1;
end

-- 1 = active, 2 = unread, 3 = unread (flash phase), 4 = normal
local function WIM_TabStyleState(theUser, cfg)
	if(theUser == WIM_TabActive) then
		return 1;
	end
	local info = WIM_Windows[theUser];
	if(info and info.newMSG) then
		if(cfg.flashEnabled and WIM_TabFlashOn) then
			return 3;
		end
		return 2;
	end
	return 4;
end

local function WIM_TabApplyStyle(btn, theUser, cfg)
	local state = WIM_TabStyleState(theUser, cfg);
	if(btn.styleState == state and btn.styleVersion == WIM_TabStyleVersion) then
		return; -- already looks right
	end
	btn.styleState = state;
	btn.styleVersion = WIM_TabStyleVersion;

	local c = cfg.colors;
	if(state == 1) then
		local s = c.active;
		btn:SetBackdropColor(s.bg.r, s.bg.g, s.bg.b, WIM_TAB_ACTIVE_ALPHA);
		btn:SetBackdropBorderColor(s.border.r, s.border.g, s.border.b, 1);
		btn.text:SetTextColor(s.text.r, s.text.g, s.text.b);
	elseif(state == 4) then
		local s = c.normal;
		btn:SetBackdropColor(s.bg.r, s.bg.g, s.bg.b, cfg.normalAlpha);
		btn:SetBackdropBorderColor(s.border.r, s.border.g, s.border.b, 1);
		btn.text:SetTextColor(s.text.r, s.text.g, s.text.b);
	else
		local s = c.unread;
		local flashing = (state == 3);
		btn:SetBackdropColor(s.bg.r, s.bg.g, s.bg.b, WIM_TAB_ACTIVE_ALPHA);
		if(flashing and cfg.flashBorder) then
			btn:SetBackdropBorderColor(s.flash.r, s.flash.g, s.flash.b, 1);
		else
			btn:SetBackdropBorderColor(s.border.r, s.border.g, s.border.b, 1);
		end
		if(flashing and cfg.flashText) then
			btn.text:SetTextColor(s.flash.r, s.flash.g, s.flash.b);
		else
			btn.text:SetTextColor(s.text.r, s.text.g, s.text.b);
		end
	end
end

function WIM_TabButton_OnClick(btn, mouseButton)
	local user = btn.user;
	if(not user or not WIM_Windows[user]) then
		return;
	end
	if(mouseButton == "RightButton") then
		WIM_CloseConvo(user);
	else
		local hadUnread = WIM_Windows[user].newMSG;
		WIM_TabSwitchTo(user);
		if(hadUnread) then
			-- the conversation has now been read: stop the minimap icon flashing for it
			WIM_Icon_DropDown_Update();
		end
	end
end

-- shared by every tab button
local WIM_TabBackdrop = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
};

local function WIM_TabButton_OnClickScript()
	WIM_TabButton_OnClick(this, arg1);
end

local function WIM_TabButton_OnEnterScript()
	if(WIM_Data.showToolTips == true and this.user) then
		GameTooltip:SetOwner(this, "ANCHOR_TOP");
		GameTooltip:SetText(WIM_GetAlias(this.user));
		GameTooltip:AddLine(WIM_L_TABTOOLTIP, 1, 1, 1, 1);
		GameTooltip:Show();
	end
end

local function WIM_TabButton_OnLeaveScript()
	GameTooltip:Hide();
end

local function WIM_TabCreateButton(index)
	local btn = CreateFrame("Button", "WIM_TabFrameTab"..index, WIM_TabFrame);
	btn:SetBackdrop(WIM_TabBackdrop);
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");

	local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	text:SetPoint("CENTER", btn, "CENTER", 0, 0);
	btn.text = text;

	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	btn:SetScript("OnClick", WIM_TabButton_OnClickScript);
	btn:SetScript("OnEnter", WIM_TabButton_OnEnterScript);
	btn:SetScript("OnLeave", WIM_TabButton_OnLeaveScript);

	WIM_TabButtons[index] = btn;
	return btn;
end

local WIM_TabStripWidth, WIM_TabStripHeight;

-- Bring the tab strip in line with the current list of conversations. Cheap to call:
-- only what actually changed since the last call is sent to the UI.
function WIM_TabsRefresh()
	-- forget tabs whose conversation no longer exists
	local i = 1;
	while(WIM_Tabs[i]) do
		if(WIM_Windows[WIM_Tabs[i]]) then
			i = i + 1;
		else
			table.remove(WIM_Tabs, i);
		end
	end
	if(WIM_TabActive and not WIM_Windows[WIM_TabActive]) then
		WIM_TabActive = nil;
	end

	local n = table.getn(WIM_Tabs);
	local cfg = WIM_TabSettings();
	local tabWidth = cfg.width;
	local tabHeight = cfg.height;

	-- hide unused buttons
	for k=n+1, table.getn(WIM_TabButtons) do
		local btn = WIM_TabButtons[k];
		if(btn.user or btn:IsShown()) then
			btn:Hide();
			btn.user = nil;
		end
	end
	if(n == 0) then
		return;
	end

	-- optionally hide the strip while there is only one conversation
	if(cfg.hideSingle and n <= 1) then
		if(WIM_TabFrame:IsShown()) then
			WIM_TabFrame:Hide();
		end
		return;
	elseif(not WIM_TabFrame:IsShown() and WIM_TabWindowShown()) then
		WIM_TabFrame:Show();
	end

	local avail = WIM_Data.winSize.width - 2 * WIM_TAB_OFFSET_X;
	local perRow = math.floor(avail / tabWidth);
	if(perRow < 1) then
		perRow = 1;
	end
	local rows = math.floor((n - 1) / perRow) + 1;
	local cols = n;
	if(cols > perRow) then
		cols = perRow;
	end
	local stripWidth, stripHeight = cols * tabWidth, rows * tabHeight;
	if(stripWidth ~= WIM_TabStripWidth) then
		WIM_TabStripWidth = stripWidth;
		WIM_TabFrame:SetWidth(stripWidth);
	end
	if(stripHeight ~= WIM_TabStripHeight) then
		WIM_TabStripHeight = stripHeight;
		WIM_TabFrame:SetHeight(stripHeight);
	end

	local fitWidth = tabWidth - 12;
	for k=1, n do
		local user = WIM_Tabs[k];
		local btn = WIM_TabButtons[k] or WIM_TabCreateButton(k);
		btn.user = user;

		if(btn.tabWidth ~= tabWidth) then
			btn.tabWidth = tabWidth;
			btn:SetWidth(tabWidth);
		end
		if(btn.tabHeight ~= tabHeight) then
			btn.tabHeight = tabHeight;
			btn:SetHeight(tabHeight);
		end

		local row = math.floor((k - 1) / perRow);
		local col = (k - 1) - row * perRow;
		local x, y = col * tabWidth, -row * tabHeight;
		if(btn.tabX ~= x or btn.tabY ~= y) then
			btn.tabX = x;
			btn.tabY = y;
			btn:ClearAllPoints();
			btn:SetPoint("TOPLEFT", WIM_TabFrame, "TOPLEFT", x, y);
		end

		local label = WIM_GetAlias(user, true);
		if(btn.label ~= label or btn.fitWidth ~= fitWidth) then
			btn.label = label;
			btn.fitWidth = fitWidth;
			WIM_TabFitText(btn.text, label, fitWidth);
		end

		WIM_TabApplyStyle(btn, user, cfg);
		if(not btn:IsShown()) then
			btn:Show();
		end
	end
end

-- Full refresh: also re-applies the colours of every tab. Call this after a tab setting
-- (colours, flash style, opacity, ...) was changed; use WIM_TabsRefresh() everywhere else.
function WIM_TabsUpdate()
	WIM_TabStyleVersion = WIM_TabStyleVersion + 1;
	WIM_TabsRefresh();
end

--[ Unread-tab flashing (WIM_TabFrame's OnUpdate)

-- Re-colour the tabs only (no layout, no text): all a flash tick needs.
local function WIM_TabsRestyle(cfg)
	for i=1, table.getn(WIM_Tabs) do
		local btn = WIM_TabButtons[i];
		if(btn and btn.user and btn.user == WIM_Tabs[i]) then
			WIM_TabApplyStyle(btn, btn.user, cfg);
		end
	end
end

function WIM_TabFrame_OnUpdate(elapsed)
	local cfg = WIM_TabSettings();
	if(not cfg.flashEnabled) then
		-- flashing switched off: make sure nothing is left stuck in the "on" state
		if(WIM_TabFlashOn) then
			WIM_TabFlashOn = false;
			WIM_TabFlashTimer = 0;
			WIM_TabsRestyle(cfg);
		end
		return;
	end
	local interval = cfg.flashSpeed;
	if(not interval or interval < 0.05) then
		interval = 0.05;
	end
	WIM_TabFlashTimer = WIM_TabFlashTimer + elapsed;
	if(WIM_TabFlashTimer >= interval) then
		WIM_TabFlashTimer = 0;
		WIM_TabFlashOn = not WIM_TabFlashOn;
		WIM_TabsRestyle(cfg); -- only unread tabs change state, the rest are skipped
	end
end
