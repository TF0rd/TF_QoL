-- ════════════════════════════════════════════════════════════════════════════════════
-- Theme: Color palette and layout constants (Catppuccin Mocha)
--
-- Background depth layers (darkest → lightest):
--   Crust → Mantle → Base → Surface0 → Surface1 → Surface2
--   frame    sidebar  content  cards     borders    hover
--            cards    areas    headers   (visible)
--
-- ════════════════════════════════════════════════════════════════════════════════════

local _, addon = ...
local type = type

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 1: Default Theme Table (Catppuccin Mocha palette + layout)
-- ════════════════════════════════════════════════════════════════════════════════════

local ThemeDefaults = {
    -- ── Backgrounds (depth-based layering) ──────────────────────────────────────────
    bgDark         = { 0.0941, 0.0941, 0.1451, 1 },  -- Mantle    #181825  cards, sidebar, widgets
    bgMedium       = { 0.1176, 0.1176, 0.1804, 1 },  -- Base      #1e1e2e  content areas, toggle off
    bgLight        = { 0.1922, 0.1961, 0.2667, 1 },  -- Surface0  #313244  card headers, elevated controls
    bgHover        = { 0.2706, 0.2784, 0.3529, 1 },  -- Surface1  #45475a  hover states
    bgCrust        = { 0.0667, 0.0667, 0.1059, 1 },  -- Crust     #11111b  outermost frame

    -- ── Borders ─────────────────────────────────────────────────────────────────────
    border         = { 0.2706, 0.2784, 0.3529, 1 },  -- Surface1  #45475a  visible borders
    borderSubtle   = { 0.1922, 0.1961, 0.2667, 1 },  -- Surface0  #313244  subtle dividers

    -- ── Accent Colors ───────────────────────────────────────────────────────────────
    accent         = { 0.7961, 0.6510, 0.9686, 1 },  -- Mauve     #cba6f7  primary interactive
    accentHover    = { 0.7961, 0.6510, 0.9686, 0.25 },
    secondaryAccent= { 0.5804, 0.8863, 0.8353, 1 },  -- Teal      #94e2d5  card titles, headers
    peach          = { 0.9804, 0.7020, 0.5294, 1 },  -- Peach     #fab387  slider fills
    yellow         = { 0.9765, 0.8863, 0.6863, 1 },  -- Yellow    #f9e2af  warnings, test mode
    blue           = { 0.5373, 0.7059, 0.9804, 1 },  -- Blue      #89b4fa  links, buttons
    currencyCap    = { 1.0000, 0.2000, 0.2000, 1 },  -- #ff3333  weekly/season currency cap reached

    -- ── Text Colors ─────────────────────────────────────────────────────────────────
    textPrimary    = { 0.8039, 0.8392, 0.9569, 1 },  -- Text      #cdd6f4  body text, labels
    textSecondary  = { 0.7294, 0.7608, 0.8706, 1 },  -- Subtext1  #bac2de  secondary labels
    textMuted      = { 0.6510, 0.6784, 0.7843, 1 },  -- Subtext0  #a6adc8  disabled text
    textSubtle     = { 0.4235, 0.4392, 0.5255, 1 },  -- Overlay0  #6c7086  very de-emphasized

    -- ── Selection ───────────────────────────────────────────────────────────────────
    selectedBg     = { 0.7961, 0.6510, 0.9686, 0.15 },
    selectedText   = { 0.8039, 0.8392, 0.9569, 1 },  -- Text      #cdd6f4

    -- ── Status ──────────────────────────────────────────────────────────────────────
    error          = { 0.9529, 0.5451, 0.6588, 1 },  -- Red       #f38ba8
    success        = { 0.6510, 0.8902, 0.6314, 1 },  -- Green     #a6e3a1

    -- ── Layout Sizes ────────────────────────────────────────────────────────────────
    headerHeight   = 32,
    footerHeight   = 24,
    sidebarWidth   = 180,
    contentWidth   = 650,
    borderSize     = 1,

    -- ── Padding ─────────────────────────────────────────────────────────────────────
    paddingSmall   = 4,
    paddingMedium  = 8,
    paddingLarge   = 16,
    scrollbarWidth = 14,
    paddingXLarge  = 24,

    -- ── Font ────────────────────────────────────────────────────────────────────────
    fontFace       = "Fonts\\FRIZQT__.TTF",
    fontSizeSmall  = 11,
    fontSizeNormal = 12,
    fontSizeLarge  = 14,
    fontSizeTitle  = 16,
    rowHeight      = 38,
    fontOutline    = "OUTLINE",
    fontShadow     = false,
}

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2: Theme Bootstrapping (Deep-copy colors to avoid reference sharing)
-- ════════════════════════════════════════════════════════════════════════════════════

local function CopyColor(c)
    return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
end

addon.Theme = {}
for k, v in pairs(ThemeDefaults) do
    if type(v) == "table" then addon.Theme[k] = CopyColor(v) else addon.Theme[k] = v end
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 2b: Item Level Tier Colors
-- Band coloring for item level values. Reusable across modules (Equip
-- column, tooltips, etc.). Stored as 6-char hex strings (no '#') so they
-- drop straight into |cff color codes; the |r terminator reverts to the
-- FontString's default color. Bands are upper-inclusive:
-- Midnight Season 2 bands, matching WoWthing's itemLevelQuality table:
--   <266 → gray | 266-278 → white | 279-291 → green
--   292-304 → blue | 305-317 → purple | 318-330 → orange | 331+ → gold
-- Source: ThingEngineering/wowthing-again, data/item-level-quality.ts
-- and components/items/convertible/data.ts (current [Mid] Season 2).
-- Assigned after the CopyColor loop because ilvlTiers is a nested table,
-- not a flat 4-float color (CopyColor would mangle it).
-- ════════════════════════════════════════════════════════════════════════════════════

addon.Theme.ilvlTiers = {
    { max = 265,       hex = "9d9d9d" },  -- gray    <266
    { max = 278,       hex = "eeeeee" },  -- white   266-278
    { max = 291,       hex = "1eff00" },  -- green   279-291
    { max = 304,       hex = "44a3ff" },  -- blue    292-304
    { max = 317,       hex = "b864f2" },  -- purple  305-317
    { max = 330,       hex = "f07800" },  -- orange  318-330
    { max = math.huge, hex = "e6cc80" },  -- gold    331+
}

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 3: ApplyThemeFont (Helper to set font face/size/outline on a FontString)
-- ════════════════════════════════════════════════════════════════════════════════════

function addon:ApplyThemeFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local T = self.Theme
    local fs
    if type(size) == "number" then
        fs = size
    elseif size == "small" then
        fs = T.fontSizeSmall
    elseif size == "large" then
        fs = T.fontSizeLarge
    elseif size == "title" then
        fs = T.fontSizeTitle
    else
        fs = T.fontSizeNormal
    end
    local outline = T.fontOutline
    if TFQoLDB and TFQoLDB.global and TFQoLDB.global.slugRendering == true then
        outline = outline .. ",SLUG"
    end
    fontString:SetFont(T.fontFace, fs, outline)
    fontString:SetShadowOffset(0, 0)
    fontString:SetShadowColor(0, 0, 0, 0)
end

-- ════════════════════════════════════════════════════════════════════════════════════
-- Part 4: IlvlTierHex — pick the hex color band for an item level value
-- Returns a 6-char hex string (no '#') suitable for |cff color codes, or
-- nil for non-positive/non-numeric input (caller renders an em-dash or
-- falls back to the FontString's default color in that case). Reads the
-- ilvlTiers band table on the active Theme.
-- ════════════════════════════════════════════════════════════════════════════════════

function addon:IlvlTierHex(ilvl)
    if type(ilvl) ~= "number" or ilvl <= 0 then return nil end
    local tiers = self.Theme and self.Theme.ilvlTiers
    if not tiers then return nil end
    for _, t in ipairs(tiers) do
        if ilvl <= t.max then return t.hex end
    end
    return tiers[#tiers].hex
end