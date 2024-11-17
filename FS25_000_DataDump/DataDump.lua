--[[
Dump global functions, tables, classes and variables to a file. The purpose is to better understand the Farming Simulator object model through reverse engineering.

With this a starting point, you can then use the console command 'dtSaveTable' from the mod 'PowerTools: Developer' to write whole Lua tables (and full table hierarchies) to file for further analysis.

Author:     w33zl
Version:    1.1.0
Modified:   2024-11-16

Changelog:

]]

DataDump = Mod:init()

DataDump:source("lib/DevHelper.lua")

local OUTPUT_HEADER = [[
-- This file was automatically generated by the mod FS25 Data Dump (https://github.com/w33zl/FS25_DataDump)
]]

function DataDump:loadMap(filename)
    self.g_powerTools = g_globalMods["FS25_PowerTools"]
    createFolder(g_currentModSettingsDirectory)
end

function DataDump:startMission()
    -- DataDump:consoleCommandDump()
end

function DataDump:consoleCommandDump(visualize, visualizeDepth)

    if self.triggerProcess or self.inProgress or self.isFinalizing then
        Log:warning("Dumping already in progress")
        return
    end

    self.executionTimer = DevHelper.measureStart("Processing global table took %.2f seconds")
    self.chunkTimer = DevHelper.measureStart()
    self.activeTable = self.__g
    self.triggerProcess = true
    self.chunkCount = 0
    self.output = {
        functions = {},
        classes = {},
        tables = {},
        fields = {}
    }
    self.stats = {
        functions = 0,
        classes = 0,
        tables = 0,
        fields = 0,
        total = 0,
    }
    self.visualize = visualize and true
    self.visualizeDepth = tonumber(visualizeDepth) or 2

    Log:debug("Visualize: %s, Depth: %d", tostring(self.visualize), self.visualizeDepth)
end

function DataDump:processChunk()
    --NOTE: Yes, this is over engineered, but it is prepared to handle a large number of tables in a deep structure
    local count = 0
    self.chunkCount = self.chunkCount + 1
    while true do
        count = count + 1
        local index, value = next(self.activeTable, self.last)
        self.last = index

        if self.last ~= nil then
            -- print(self.last)
            self.stats.total = self.stats.total + 1

            if type(value) == "function" then
                -- table.insert(self.output.functions, self.last)
                self.output.functions[self.last] = value
                self.stats.functions = self.stats.functions + 1
            elseif type(value) == "table" then
                local isClass = false
                if self.last == "StringUtil" or "g_splitTypeManager" then --HACK: Dirty solution to prevent callstack "error" due to StringUtil being obsolete
                    isClass = true
                elseif value.isa ~= nil and type(value.isa) == "function" then
                    isClass = value:isa(value) -- Should only be true on the actual class, but not on derived objects
                end

                if isClass then
                    self.output.classes[self.last] = value
                    self.stats.classes = self.stats.classes + 1
                else
                    self.output.tables[self.last] = value
                    self.stats.tables = self.stats.tables + 1
                end
            elseif type(value) == "userdata" then
                --TODO: need special care?
                self.output.fields[self.last] = value
                self.stats.fields = self.stats.fields + 1
            else
                self.output.fields[self.last] = value
                self.stats.fields = self.stats.fields + 1
            end
        end

        if self.last == nil or (self.chunkTimer:elapsed() > 1) or (count >= 5000) then
            count = 0
            self.chunkTimer = DevHelper.measureStart()
            return self.last
        end
    end
end

function DataDump:finalize()
    local basePath = g_currentModSettingsDirectory .. "global"
    local saveTimer = DevHelper.measureStart("Files saved in %.2f seconds")

    local function saveOutputToFile(name, table)
        local filePath = basePath .. name .. ".lua"
        if fileExists(filePath) then
            deleteFile(filePath)
        end
        self.g_powerTools:saveTable("global" .. name, table, filePath, 1, nil, OUTPUT_HEADER)

        if not fileExists(filePath) then
            Log:error("Failed to save '%s' to '%s'", name, filePath)
        end

    end
    saveOutputToFile("Functions", self.output.functions)
    saveOutputToFile("Classes", self.output.classes)
    saveOutputToFile("Tables", self.output.tables)
    saveOutputToFile("Variables", self.output.fields)

    Log:info(saveTimer:stop(true))

    if self.visualize then
        self.g_powerTools:visualizeTable("Output", self.output, self.visualizeDepth)
    end

    self.isFinalizing = false
end

function DataDump:update(dt)
    if self.isFinalizing then
        DataDump:finalize()
        return
    elseif not self.triggerProcess and not self.inProgress then
        return
    end

    self.triggerProcess = false
    self.inProgress = true

    local val = self:processChunk()
    if val == nil then
        self.inProgress = false
        Log:info(self.executionTimer:stop(true))

        Log:info("Found %d functions, %d classes, %d tables and %d fields in %d chunks", self.stats.functions, self.stats.classes, self.stats.tables, self.stats.fields, self.chunkCount)

        if self.g_powerTools == nil then
            Log:warning("g_powerTools was not found, verify that the mod 'Developer PowerTools' is enabled.")
            return
        end

        Log:info("Saving output tables...")

        self.isFinalizing = true

        return
    else
        Log:info("#%d: Reading global table, found %d items so far... ", self.chunkCount, self.stats.total)
    end
end


addConsoleCommand("ddDump", "", "consoleCommandDump", DataDump)


