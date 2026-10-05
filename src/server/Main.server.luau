--!strict
-- Server entry point: build the course, start its mechanics, then track players.

local CourseBuilder = require(script.Parent.CourseBuilder)
local Mechanics = require(script.Parent.Mechanics)
local Progress = require(script.Parent.Progress)

local course = CourseBuilder.build()
Mechanics.start()
Progress.start(course)
