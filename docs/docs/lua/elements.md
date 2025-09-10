# Elements

Elements returned by `gurt.select()`, `gurt.create()`, etc. have the following properties and methods:

## Properties

### element.text

Gets or sets the text content of an element.

```lua
local p = gurt.select('p')
p.text = 'New paragraph content'
local currentText = p.text
```

### element.value

Gets or sets the value of form elements.

```lua
local input = gurt.select('#username')
input.value = 'john_doe'
local username = input.value

local checkbox = gurt.select('#agree')
checkbox.value = true  -- Check the checkbox
```

### element.visible

Gets or sets element visibility.

```lua
local modal = gurt.select('#modal')
modal.visible = false  -- Hide element
modal.visible = true   -- Show element

if modal.visible then
    trace.log('Element is visible')
end
```

### element.children

Gets an array of child elements.

```lua
local container = gurt.select('.container')
local children = container.children

for i = 1, #children do
    local child = children[i]
    trace.log('Child ' .. i .. ': ' .. child.text)
end
```

### element.size

Gets the size of an element in pixels.

```lua
local box = gurt.select('#my-box')
local size = box.size

trace.log('Width: ' .. size.width .. 'px')
trace.log('Height: ' .. size.height .. 'px')

if size.width == size.height then
    trace.log('Element is square')
end
```

### element.position

Gets the position of an element relative to its parent.

```lua
local element = gurt.select('#positioned-element')
local pos = element.position

trace.log('X position: ' .. pos.x .. 'px')
trace.log('Y position: ' .. pos.y .. 'px')

-- Check if element is at origin
if pos.x == 0 and pos.y == 0 then
    trace.log('Element is at origin')
end
```

## DOM Traversal

### element.parent

Gets the parent element.

```lua
local button = gurt.select('#my-button')
local container = button.parent
```

### element.nextSibling / element.previousSibling

Gets adjacent sibling elements.

```lua
local current = gurt.select('#current-item')
local next = current.nextSibling
local prev = current.previousSibling
```

### element.firstChild / element.lastChild

Gets first or last child element.

```lua
local list = gurt.select('ul')
local firstItem = list.firstChild
local lastItem = list.lastChild
```

## Methods

### element:on(eventName, callback)

Adds an event listener. Returns a subscription object.

```lua
local button = gurt.select('#my-button')

-- Click event
local subscription = button:on('click', function(event)
    trace.log('Button clicked at: ' .. event.x .. ', ' .. event.y)
end)

-- Mouse events
button:on('mousedown', function(event)
    trace.log('Mouse down at: ' .. event.x .. ', ' .. event.y)
end)

button:on('mouseup', function(event)
    trace.log('Mouse up at: ' .. event.x .. ', ' .. event.y)
end)

button:on('mouseenter', function()
    button.classList:add('hover-effect')
end)

button:on('mouseexit', function()
    button.classList:remove('hover-effect')
end)

-- Input events (for form elements)
local input = gurt.select('#username')
input:on('change', function(event)
    trace.log('Input changed to: ' .. event.value)
end)

-- Focus events
input:on('focusin', function()
    trace.log('Input focused')
end)

input:on('focusout', function()
    trace.log('Input lost focus')
end)

-- Unsubscribe from event
subscription:unsubscribe()
```

#### Mouse Event Positioning

Mouse events (`click`, `mousedown`, `mouseup`) provide position information relative to the element:

```lua
local element = gurt.select('#interactive-element')

element:on('click', function(event)
    -- event.x and event.y are relative to the element's top-left corner
    local elementX = event.x
    local elementY = event.y
    
    trace.log('Clicked at (' .. elementX .. ', ' .. elementY .. ') within element')
    
    local size = element.size
    local pos = element.position
    
    local xPercent = (elementX / size.width) * 100
    local yPercent = (elementY / size.height) * 100
    
    trace.log('Clicked at ' .. xPercent .. '% horizontally, ' .. yPercent .. '% vertically')
end)
```

### element:append(childElement)

Adds a child element.

```lua
local container = gurt.select('.container')
local newDiv = gurt.create('div', { text = 'New content' })
container:append(newDiv)
```

### element:remove()

Removes the element from the DOM.

```lua
local elementToRemove = gurt.select('#temporary')
elementToRemove:remove()
```

### element:insertBefore(newElement, referenceElement)

Inserts an element before another element.

```lua
local container = gurt.select('.container')
local newElement = gurt.create('div', { text = 'Inserted' })
local reference = gurt.select('#reference')
container:insertBefore(newElement, reference)
```

### element:insertAfter(newElement, referenceElement)

Inserts an element after another element.

```lua
local container = gurt.select('.container')
local newElement = gurt.create('div', { text = 'Inserted' })
local reference = gurt.select('#reference')
container:insertAfter(newElement, reference)
```

### element:replace(oldElement, newElement)

Replaces a child element with a new element.

```lua
local container = gurt.select('.container')
local oldElement = gurt.select('#old')
local newElement = gurt.create('div', { text = 'Replacement' })
container:replace(oldElement, newElement)
```

### element:clone(deep)

Creates a copy of the element.

```lua
-- Shallow clone (element only)
local copy = element:clone(false)

-- Deep clone (element and all children)
local deepCopy = element:clone(true)
```

### element:getAttribute(name) / element:setAttribute(name, value)

Gets or sets element attributes.

```lua
local img = gurt.select('img')
local src = img:getAttribute('src')
img:setAttribute('alt', 'Description text')

-- Remove attribute by setting empty value
img:setAttribute('title', '')
```

### element:show() / element:hide()

Shows or hides an element.

```lua
local modal = gurt.select('#modal')
modal:show()   -- Makes element visible
modal:hide()   -- Hides element
```

### element:focus() / element:unfocus()

Sets or removes focus from an element.

```lua
local input = gurt.select('#search')
input:focus()    -- Focus the input
input:unfocus()  -- Remove focus
```

## Class List Management

### element.classList

Provides methods for managing CSS classes.

```lua
local button = gurt.select('#my-button')

-- Add classes
button.classList:add('active')
button.classList:add('btn-primary')

-- Remove classes
button.classList:remove('disabled')

-- Toggle classes
button.classList:toggle('selected')

-- Check if class exists
if button.classList:contains('active') then
    trace.log('Button is active')
end

-- Get specific class by index (1-based)
local firstClass = button.classList:item(1)

-- Get number of classes
local classCount = button.classList.length
```

## Animations

### element:createTween()

Creates a tween animation for the element.

```lua
local box = gurt.select('#animated-box')

-- Fade out
box:createTween()
   :to('opacity', 0)
   :duration(1.0)
   :easing('out')
   :transition('linear')
   :play()

-- Move and scale
box:createTween()
   :to('x', 200)
   :to('y', 100)
   :to('scale', 1.5)
   :duration(2.0)
   :easing('inout')
   :transition('cubic')
   :play()

-- Color animation
box:createTween()
   :to('backgroundColor', '#ff0000')
   :duration(1.5)
   :easing('out')
   :transition('quad')
   :play()

-- Rotation
box:createTween()
   :to('rotation', 360)
   :duration(3.0)
   :easing('inout')
   :transition('sine')
   :play()
```

**Available Tween Properties:**
- `opacity` - Element transparency (0-1)
- `backgroundColor` - Background color (hex format)
- `scale` - Element scale (1.0 = normal size)
- `rotation` - Rotation in degrees
- `x`, `y` - Position offset

**Easing Types:** `'in'`, `'out'`, `'inout'`, `'outin'`

**Transition Types:** `'linear'`, `'quad'`, `'cubic'`, `'quart'`, `'quint'`, `'sine'`, `'expo'`, `'circ'`, `'elastic'`, `'back'`, `'bounce'`

![CRT effect](../../static/img/docs/tween.png)
Resource: [Reddit](https://www.reddit.com/r/godot/comments/frqzup/godot_tweening_cheat_sheet/)