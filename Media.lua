-- ════════════════════════════════════════════════════════════════
-- Part 2: Media Registration
-- (Registers custom fonts and sounds with LibSharedMedia-3.0)
-- ════════════════════════════════════════════════════════════════

local _, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

if not LSM then return end

-- ── Fonts ─────────────────────────────────────────────────────

LSM:Register("font", "PT Sans Narrow", [[Interface\AddOns\TF_QoL\Media\Fonts\PTSansNarrow-Bold.ttf]])

-- ── Sounds ────────────────────────────────────────────────────

LSM:Register("sound", "Air Horn", [[Interface\AddOns\TF_QoL\Media\Sounds\AirHorn.ogg]])
LSM:Register("sound", "Brass", [[Interface\AddOns\TF_QoL\Media\Sounds\Brass.mp3]])
LSM:Register("sound", "Glass", [[Interface\AddOns\TF_QoL\Media\Sounds\Glass.mp3]])
LSM:Register("sound", "Oh No", [[Interface\AddOns\TF_QoL\Media\Sounds\OhNo.ogg]])
LSM:Register("sound", "Tada Fanfare", [[Interface\AddOns\TF_QoL\Media\Sounds\TadaFanfare.ogg]])
LSM:Register("sound", "Water Drop", [[Interface\AddOns\TF_QoL\Media\Sounds\WaterDrop.ogg]])
LSM:Register("sound", "Kaching", [[Interface\AddOns\TF_QoL\Media\Sounds\kaching.ogg]])
LSM:Register("sound", "Hiccup", [[Interface\AddOns\TF_QoL\Media\Sounds\hic3.ogg]])
LSM:Register("sound", "Apotheosis", [[Interface\AddOns\TF_QoL\Media\Sounds\apotheosis.ogg]])
LSM:Register("sound", "Ascendance", [[Interface\AddOns\TF_QoL\Media\Sounds\ascendance.ogg]])
LSM:Register("sound", "Aura Mastery", [[Interface\AddOns\TF_QoL\Media\Sounds\aura-mastery.ogg]])
LSM:Register("sound", "Avenging Wrath", [[Interface\AddOns\TF_QoL\Media\Sounds\avenging-wrath.ogg]])
LSM:Register("sound", "Barrier", [[Interface\AddOns\TF_QoL\Media\Sounds\barrier.ogg]])
LSM:Register("sound", "Bloodlust", [[Interface\AddOns\TF_QoL\Media\Sounds\bloodlust.ogg]])
LSM:Register("sound", "Bop", [[Interface\AddOns\TF_QoL\Media\Sounds\bop.ogg]])
LSM:Register("sound", "Bubble", [[Interface\AddOns\TF_QoL\Media\Sounds\bubble.ogg]])
LSM:Register("sound", "Celestial Conduit", [[Interface\AddOns\TF_QoL\Media\Sounds\celestial-conduit.ogg]])
LSM:Register("sound", "Chi-Ji", [[Interface\AddOns\TF_QoL\Media\Sounds\chi-ji.ogg]])
LSM:Register("sound", "Convoke", [[Interface\AddOns\TF_QoL\Media\Sounds\convoke.ogg]])
LSM:Register("sound", "Dispel", [[Interface\AddOns\TF_QoL\Media\Sounds\dispel.ogg]])
LSM:Register("sound", "Divine Hymn", [[Interface\AddOns\TF_QoL\Media\Sounds\divine-hymn.ogg]])
LSM:Register("sound", "Divine Toll", [[Interface\AddOns\TF_QoL\Media\Sounds\divine-toll.ogg]])
LSM:Register("sound", "Dream Flight", [[Interface\AddOns\TF_QoL\Media\Sounds\dream-flight.ogg]])
LSM:Register("sound", "Evangelism", [[Interface\AddOns\TF_QoL\Media\Sounds\evangelism.ogg]])
LSM:Register("sound", "Grip", [[Interface\AddOns\TF_QoL\Media\Sounds\grip.ogg]])
LSM:Register("sound", "Halo", [[Interface\AddOns\TF_QoL\Media\Sounds\halo.ogg]])
LSM:Register("sound", "Healing Tide", [[Interface\AddOns\TF_QoL\Media\Sounds\healing-tide.ogg]])
LSM:Register("sound", "Health Pot", [[Interface\AddOns\TF_QoL\Media\Sounds\health-pot.ogg]])
LSM:Register("sound", "Healthstone", [[Interface\AddOns\TF_QoL\Media\Sounds\healthstone.ogg]])
LSM:Register("sound", "Incarn", [[Interface\AddOns\TF_QoL\Media\Sounds\incarn.ogg]])
LSM:Register("sound", "Innervate", [[Interface\AddOns\TF_QoL\Media\Sounds\innervate.ogg]])
LSM:Register("sound", "Ironbark", [[Interface\AddOns\TF_QoL\Media\Sounds\ironbark.ogg]])
LSM:Register("sound", "Life Cocoon", [[Interface\AddOns\TF_QoL\Media\Sounds\life-cocoon.ogg]])
LSM:Register("sound", "Pain Sup", [[Interface\AddOns\TF_QoL\Media\Sounds\pain-sup.ogg]])
LSM:Register("sound", "Potion", [[Interface\AddOns\TF_QoL\Media\Sounds\potion.ogg]])
LSM:Register("sound", "Power Infusion", [[Interface\AddOns\TF_QoL\Media\Sounds\power-infusion.ogg]])
LSM:Register("sound", "Rescue", [[Interface\AddOns\TF_QoL\Media\Sounds\rescue.ogg]])
LSM:Register("sound", "Revival", [[Interface\AddOns\TF_QoL\Media\Sounds\revival.ogg]])
LSM:Register("sound", "Rewind", [[Interface\AddOns\TF_QoL\Media\Sounds\rewind.ogg]])
LSM:Register("sound", "Sac", [[Interface\AddOns\TF_QoL\Media\Sounds\sac.ogg]])
LSM:Register("sound", "Spatial", [[Interface\AddOns\TF_QoL\Media\Sounds\spatial.ogg]])
LSM:Register("sound", "Spellwarding", [[Interface\AddOns\TF_QoL\Media\Sounds\spellwarding.ogg]])
LSM:Register("sound", "Spirit Link", [[Interface\AddOns\TF_QoL\Media\Sounds\spirit-link.ogg]])
LSM:Register("sound", "Stampeding Roar", [[Interface\AddOns\TF_QoL\Media\Sounds\stampeding-roar.ogg]])
LSM:Register("sound", "Stasis", [[Interface\AddOns\TF_QoL\Media\Sounds\stasis.ogg]])
LSM:Register("sound", "T D", [[Interface\AddOns\TF_QoL\Media\Sounds\t-d.ogg]])
LSM:Register("sound", "Time Spiral", [[Interface\AddOns\TF_QoL\Media\Sounds\time-spiral.ogg]])
LSM:Register("sound", "Tranquility", [[Interface\AddOns\TF_QoL\Media\Sounds\tranquility.ogg]])
LSM:Register("sound", "Trinket", [[Interface\AddOns\TF_QoL\Media\Sounds\trinket.ogg]])
LSM:Register("sound", "Ultimate Penitence", [[Interface\AddOns\TF_QoL\Media\Sounds\ultimate-penitence.ogg]])
LSM:Register("sound", "Wind Rush", [[Interface\AddOns\TF_QoL\Media\Sounds\wind-rush.ogg]])
LSM:Register("sound", "Yu'lon", [[Interface\AddOns\TF_QoL\Media\Sounds\yu'lon.ogg]])

-- ── Status Bars ───────────────────────────────────────────────

LSM:Register("statusbar", "Better Blizzard", [[Interface\AddOns\TF_QoL\Media\StatusBar\BetterBlizzard.blp]])