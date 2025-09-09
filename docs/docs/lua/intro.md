---
sidebar_position: 3
---

# Intro

Gurted provides a Lua API that enables dynamic web development with client-side scripting. The Lua runtime is integrated into the browser engine and provides access to DOM manipulation, network requests, animations, and more.

## Global: gurt

The main global object for DOM manipulation and core functionality.

### gurt.select(selector)

Selects the first element matching the CSS selector.

```lua
local element = gurt.select('#my-id')
local firstButton = gurt.select('button')
local classElement = gurt.select('.my-class')
```

### gurt.selectAll(selector)

Selects all elements matching the CSS selector, returns an array.

```lua
local allButtons = gurt.selectAll('button')
local listItems = gurt.selectAll('li')

-- Iterate through results
for i = 1, #allButtons do
    local button = allButtons[i]
    button.text = 'Button ' .. i
end
```

### gurt.create(tagName, options)

Creates a new HTML element.

```lua
-- Basic element
local div = gurt.create('div')

-- Element with attributes and content
local button = gurt.create('button', {
    text = 'Click me!',
    style = 'bg-blue-500 text-white px-4 py-2 rounded',
    id = 'my-button'
})
```

### gurt.body

Reference to the document body element.

```lua
-- Add event listeners to body
gurt.body:on('keydown', function(event)
    trace.log('Key pressed: ' .. event.key)
end)

-- Append elements to body
local newDiv = gurt.create('div', { text = 'Hello World!' })
gurt.body:append(newDiv)
```

### gurt.location

Browser location and navigation control.

### gurt.location.href

Gets the current URL.

```lua
local currentUrl = gurt.location.href
trace.log('Current URL: ' .. currentUrl)
```

### gurt.location.reload()

Reloads the current page.

```lua
gurt.location.reload()
```

### gurt.location.goto(url)

Navigates to a new URL.

```lua
gurt.location.goto('gurt://example.com/page')
gurt.location.goto('https://external-site.com')
```

### gurt.location.query

Query parameter access.

```lua
-- Get a specific parameter
local userId = gurt.location.query.get('user_id')

-- Check if parameter exists
if gurt.location.query.has('debug') then
    trace.log('Debug mode enabled')
end

-- Get all values for a parameter (for repeated params)
local tags = gurt.location.query.getAll('tag')
```

### gurt.width()

Gets the available width of the site page viewport in pixels.

```lua
local pageWidth = gurt.width()
trace.log('Page width: ' .. pageWidth .. ' pixels')
```

### gurt.height()

Gets the available height of the site page viewport in pixels.

```lua
local pageHeight = gurt.height()
trace.log('Page height: ' .. pageHeight .. ' pixels')
```

## Global: trace

The global trace table for logging messages to the console.

### trace.log(message)
Identical to `print()`, logs a message to the console.

```lua
trace.log('Hello from Lua!')
```

### trace.warn(message)
Logs a warning message to the console.

```lua
trace.warn('This is a warning!')
```

### trace.error(message)
Logs an error message to the console.

```lua
trace.error('This is an error!')
```

## Time API

### Time.now()

Gets current Unix timestamp.

```lua
local timestamp = Time.now()
trace.log('Current time: ' .. timestamp)
```

### Time.format(timestamp, format)

Formats a timestamp using format strings.

```lua
local now = Time.now()
local formatted = Time.format(now, '%Y-%m-%d %H:%M:%S')
trace.log('Formatted: ' .. formatted)

-- Format strings
-- %Y - Full year (2024)
-- %y - Two-digit year (24)
-- %m - Month (01-12)
-- %d - Day (01-31)
-- %H - Hour 24-format (00-23)
-- %I - Hour 12-format (01-12)
-- %M - Minute (00-59)
-- %S - Second (00-59)
-- %p - AM/PM
-- %A - Full weekday name
-- %a - Abbreviated weekday name
-- %B - Full month name
-- %b - Abbreviated month name
```

### Time.date(timestamp)

Gets date components as a table.

```lua
local now = Time.now()
local date = Time.date(now)

trace.log('Year: ' .. date.year)
trace.log('Month: ' .. date.month)
trace.log('Day: ' .. date.day)
trace.log('Hour: ' .. date.hour)
trace.log('Minute: ' .. date.minute)
trace.log('Second: ' .. date.second)
trace.log('Weekday: ' .. date.weekday)  -- 0=Sunday, 6=Saturday
```

### Time.sleep(seconds)

Pauses execution for a specified duration.

```lua
trace.log('Starting...')
Time.sleep(2.0)  -- Wait 2 seconds
trace.log('Done waiting!')
```

:::note
This blocks the entire Lua thread. Use with caution, we recommend using `setTimeout()` for non-blocking delays.
:::

### Time.benchmark(function)

Measures function execution time.

```lua
local elapsed, result = Time.benchmark(function()
    -- Some complex calculation
    local sum = 0
    for i = 1, 1000000 do
        sum = sum + i
    end
    return sum
end)

trace.log('Function took ' .. elapsed .. ' seconds')
trace.log('Result: ' .. result)
```

### Time.timer()

Creates a timer object for measuring intervals.

```lua
local timer = Time.timer()

-- Do some work...
Time.sleep(1.5)

local elapsed = timer:elapsed()
trace.log('Elapsed: ' .. elapsed .. ' seconds')

timer:reset()  -- Reset timer
```

### Time.delay(seconds)

Creates a delay object for non-blocking waits.

```lua
local delay = Time.delay(3.0)

-- Check if delay is complete
if delay:complete() then
    trace.log('Delay finished!')
end

-- Get remaining time
local remaining = delay:remaining()
trace.log('Time left: ' .. remaining .. ' seconds')
```

## Timeout and Interval Functions

### setTimeout(callback, milliseconds)

Executes a function after a delay.

```lua
local timeoutId = setTimeout(function()
    trace.log('This runs after 2 seconds')
end, 2000)

-- Cancel the timeout
-- clearTimeout(timeoutId)
```

### setInterval(callback, milliseconds)

Executes a function repeatedly at intervals.

```lua
local intervalId = setInterval(function()
    trace.log('This runs every second')
end, 1000)

setTimeout(function()
    clearInterval(intervalId)
    trace.log('Interval stopped')
end, 5000)
```

### clearTimeout(timeoutId) / clearInterval(intervalId)

Cancels scheduled timeouts or intervals.

```lua
local id = setTimeout(function()
    trace.log('This will not run')
end, 1000)

clearTimeout(id)
```

## Clipboard API

Write to the system clipboard.

```lua
Clipboard.write('Hello clipboard!')
```