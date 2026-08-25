-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Progress ring of the mod, an arc filling clockwise over a track
RMS_ProgressRing = {}
RMS_ProgressRing.modDirectory = g_currentModDirectory
RMS_ProgressRing.RADIUS = 107 / 256
RMS_ProgressRing.DOT = 32 / 256
RMS_ProgressRing.SEGMENTS = 90
RMS_ProgressRing.PERCENT_TEXT_SHARE = 0.22

---Loads the ring atlas and its overlays
function RMS_ProgressRing.register()
    g_overlayManager:addTextureConfigFile(RMS_ProgressRing.modDirectory .. "hud/rms_progressRing.xml", "rms_ProgressRing")
    RMS_ProgressRing.track = g_overlayManager:createOverlay("rms_ProgressRing.ring", 0, 0, 0, 0)
    RMS_ProgressRing.dot = g_overlayManager:createOverlay("rms_ProgressRing.dot", 0, 0, 0, 0)
end

---Draws the ring with its arc filled to the given ratio and its percentage inside
-- @param float centerX horizontal center in screen space
-- @param float centerY vertical center in screen space
-- @param float width ring width in screen space
-- @param float height ring height in screen space
-- @param float ratio progress between 0 and 1
function RMS_ProgressRing.render(centerX, centerY, width, height, ratio)
    local grey = Dashboard.COLORS.GREY
    local green = HUD.COLOR.ACTIVE
    local track = RMS_ProgressRing.track

    track:setDimension(width, height)
    track:setPosition(centerX - width * 0.5, centerY - height * 0.5)
    track:setColor(grey[1], grey[2], grey[3], grey[4])
    track:render()

    local dotWidth, dotHeight = width * RMS_ProgressRing.DOT, height * RMS_ProgressRing.DOT
    local radiusX, radiusY = width * RMS_ProgressRing.RADIUS, height * RMS_ProgressRing.RADIUS
    local dot = RMS_ProgressRing.dot

    dot:setDimension(dotWidth, dotHeight)
    dot:setColor(green[1], green[2], green[3], green[4])

    local sweep = math.clamp(ratio, 0, 1) * 2 * math.pi
    local step = (2 * math.pi) / RMS_ProgressRing.SEGMENTS
    local angle = 0

    while angle < sweep do
        dot:setPosition(centerX + math.sin(angle) * radiusX - dotWidth * 0.5, centerY + math.cos(angle) * radiusY - dotHeight * 0.5)
        dot:render()
        angle = angle + step
    end

    dot:setPosition(centerX + math.sin(sweep) * radiusX - dotWidth * 0.5, centerY + math.cos(sweep) * radiusY - dotHeight * 0.5)
    dot:render()

    local percentSize = height * RMS_ProgressRing.PERCENT_TEXT_SHARE

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(centerX, centerY - percentSize * 0.4, percentSize, string.format("%d%%", math.floor(ratio * 100)))
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end
