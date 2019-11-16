--- Unit base module for all units in the game
-- @module gameon.engine.Unit

local thispackage = (...):match("(.-)[^%.]+$")

local pltablex = require "pl.tablex"
local Sprite = require (thispackage..".sprite")
local Animation = require (thispackage..".animation")
local MissionIdle = require (thispackage..".mission.idle")
local MissionMove = require (thispackage..".mission.move")
local PLAYER_COLOR = require (thispackage..".enums").PLAYER_COLOR
local HexMap = require "gameon.engine.algo.hexmap"

local Game = require "gameon.game"

--- Base Unit table
-- @table Unit
local Unit = setmetatable({
    speed = 1, -- number of seconds to move from one tile to another
    health = 100, -- the amount of health
    attack = 0, -- the amount health will be taken from enemy per hit
    shield = 0 -- the amount of attack to be reduced by the enemy
}, Sprite)
Unit.__index = Unit

function Unit.new(player, typename)
    local o = setmetatable(Sprite.new{
        color = player.color,
        player = player,
        typename = typename,
        action = "Idle",
    }, Unit)
    o.mission = MissionIdle.new{unit = o}
    return o
end

function Unit:setPos(x, y)
    assert(self:isAlive(), "Can't setPos death unit")
    local previousTile = self.tile
    Sprite.setPos(self, x, y)
    if previousTile ~= self.tile then
        if previousTile then
            self.map:removeUnitFromTile(self, previousTile)
        end
        self.map:addUnitToTile(self, self.tile)
    end
end

function Unit:isAlive()
    return self.health > 0
end

function Unit:setMission(mission)
    self.mission:abort()
    self.mission = mission
end

function Unit:attackUnit(enemy)
    assert(self:isAlive(), "Can't attackUnit death unit")
    self:setAction("Attacking")
    self.enemy = enemy
    self.attackAtCycle = nil
    self:lookAtTile(enemy.tile)
end

function Unit:isNearBy(other)
    return other:isAlive() and self:getDistanceTo(other.tile) == 1
end

function Unit:lookAtTile(tile)
    if self.tile.x ~= tile.x then
        self.flipped = tile.x < self.tile.x
    end
end

function Unit:setAction(action)
    Sprite.setAction(self, action)

    if action ~= "Attacking" then
        self.enemy = nil
    end

    assert(self.health > 0 or self.action == "Dying", "Invalid action "..self.action.." with health = "..self.health)
end

function Unit:stop()
    if self:isAlive() then
        self:setMission(MissionIdle.new{ unit = self })
        self:setAction("Idle")
    end
end

function Unit:onFrameChanged(cycle, prevFrame, nextFrame)
    if self.enemy and self.enemy:isAlive() and self.action == "Attacking" then
        if not self.attackAtCycle or self.attackAtCycle ~= cycle then
            local attack_hit_frame = self.spriteSheet.frames.Attacking.attack_hit_frame
            if prevFrame <= attack_hit_frame and nextFrame >= attack_hit_frame then
                self.attackAtCycle = cycle
                -- is the enemy still in range to hit?
                if self:isNearBy(self.enemy) then
                    self.enemy:hit(self)
                else
                    self.enemy:miss(self)
                end
            end
        end
    end
end

function Unit:onAnimationFinished()
    if self.action == "Dying" then
        self:destroy()
    elseif self.action == "Attacking" then
        if not self.enemy:isAlive() then
            self:setAction("Idle")
        end
    end
end

function Unit:isFriendly(unit)
    return self.player.team == unit.player.team
end

function Unit:update(dt)
    Sprite.update(self, dt)
    if self:isAlive() then
        self.mission:update(dt)
    else
        assert(self.action == "Dying", "Not alive can't be in other action than Dying")
    end
end

function Unit:onSelected(selected)
    Sprite.onSelected(self, selected)
    if self.mission then
        self.mission:onSelected(selected)
    end
end

function Unit:getDistanceTo(tile)
    return HexMap.offset_distance(self.tile, tile)
end

function Unit:canStepOnTile(tile)
    return self.map:getTileMovingPoints(tile) >= 0
end

function Unit:moveTo(x, y)
    assert(self:isAlive(), "Can't moveTo death unit")

    local tileto = self.map:getTileAtPixel(x, y)
    local followUnit = self.map:getUnitAtTile(tileto)
    if followUnit then
        tileto = nil
    end
    self:setMission(MissionMove.new{
        unit = self,
        followUnit = followUnit,
        tileto = tileto
    })
    -- force showing patroling flag
    self.mission:onSelected(self:isSelected())
end

function Unit:patrolTo(x, y)
    assert(self:isAlive(), "Can't patrolTo death unit")

    local tileto = self.map:getTileAtPixel(x, y)
    if getmetatable(self.mission)._NAME == "MissionMove" then
        self.mission:togglePatrolTile(tileto)
        return
    end
    self:setMission(MissionMove.new{
        unit = self,
        tileto = tileto
    })
    -- force showing the patrol point
    self.mission:onSelected(self:isSelected())
end

function Unit:die()
    self.mission:abort()
    self.mission = nil
    self.health = 0
    self:setAction("Dying")
    self:stop()
    if self.tile then
        self.map:removeUnitFromTile(self, self.tile)
    end
    self.eventBox:triggerEvent("die")
end

function Unit:destroy()
    if self.health > 0 then
        self:die()
    end
    Sprite.destroy(self)
end

-- this unit has been hit by another unit
function Unit:hit(otherUnit)
    assert(self:isAlive(), "Can't hit death unit")
    local damage = math.max(0, otherUnit.attack - self.shield)
    self.health = math.max(0, self.health - damage)
    self.map:addFloatingTextAtTile(self.tile, tostring(-damage), PLAYER_COLOR[self.color])
    if self.health == 0 then
        self:die()
    end
end

-- this unit has been attempted to be hit but missed
function Unit:miss(otherUnit)
    assert(self:isAlive(), "Can't miss death unit")
    self.map:addFloatingTextAtTile(self.tile, "miss", PLAYER_COLOR[self.color])
end

return Unit
