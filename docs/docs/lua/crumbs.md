---
sidebar_position: 9
---

# Crumbs

The Crumbs API provides **client-side storage** similar to browser cookies. Crumbs are stored locally and can have optional expiration times. They are domain-specific, meaning each GURT domain has its own isolated storage.

Storage location: `%APPDATA%/Flumi/crumbs/[domain].json`

## API Reference

### gurt.crumbs.set(options)

Sets a crumb with the specified name and value.

**Parameters:**
- `options` (table) - Configuration object with the following fields:
  - `name` (string, required) - The crumb name/key
  - `value` (string, required) - The crumb value
  - `lifetime` (number, optional) - Lifetime in seconds. If omitted, the crumb persists indefinitely

```lua
-- Set a permanent crumb
gurt.crumbs.set({
    name = "username",
    value = "gurted_user"
})

-- Set a temporary crumb (expires in 10 seconds)
gurt.crumbs.set({
    name = "session_token", 
    value = "abc123def456",
    lifetime = 10
})

-- Set a short-lived crumb (expires in 30 seconds)
gurt.crumbs.set({
    name = "temp_data",
    value = "temporary_value",
    lifetime = 30
})
```

### gurt.crumbs.get(name)

Retrieves a crumb value by name. Returns `nil` if the crumb doesn't exist or has expired.

**Parameters:**
- `name` (string) - The crumb name to retrieve

**Returns:**
- `string` - The crumb value, or `nil` if not found/expired

```lua
-- Get a crumb value
local username = gurt.crumbs.get("username")
if username then
    trace.log("Welcome back, " .. username .. "!")
else
    trace.log("No username found")
end
```

### gurt.crumbs.delete(name)

Deletes a crumb by name.

**Parameters:**
- `name` (string) - The crumb name to delete

**Returns:**
- `boolean` - `true` if the crumb existed and was deleted, `false` if it didn't exist

```lua
local wasDeleted = gurt.crumbs.delete("session_token")
if wasDeleted then
    trace.log("Session token removed")
else
    trace.log("Session token was not found")
end

gurt.crumbs.delete("temp_data")
```

### gurt.crumbs.getAll()

Retrieves all non-expired crumbs for the current domain.

**Returns:**
- `table` - A table where keys are crumb names and values are crumb objects

Each crumb object contains:
- `name` (string) - The crumb name
- `value` (string) - The crumb value  
- `expiry` (number, optional) - Unix timestamp when the crumb expires (only present for temporary crumbs)

```lua
local allCrumbs = gurt.crumbs.getAll()

for name, crumb in pairs(allCrumbs) do
    trace.log("Crumb: " .. name .. " = " .. crumb.value)
    
    if crumb.expiry then
        local remaining = crumb.expiry - (Time.now() / 1000)
        trace.log("  Expires in " .. math.floor(remaining) .. " seconds")
    else
        trace.log("  Permanent crumb")
    end
end
```

### File Storage Format

Crumbs are stored in JSON files:

```json
{
  "username": {
    "name": "username",
    "value": "alice",
    "created_at": 1672531200.0,
    "lifespan": -1.0
  },
  "session_token": {
    "name": "session_token", 
    "value": "abc123",
    "created_at": 1672531200.0,
    "lifespan": 3600.0
  }
}
```
